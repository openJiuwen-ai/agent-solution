#!/usr/bin/env python3
"""Batch-evaluate whether labeled intents match user query semantics via LLM."""

from __future__ import annotations

import concurrent.futures
import json
import logging
import os
import re
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import pandas as pd
from openai import OpenAI
from tqdm import tqdm

logger = logging.getLogger(__name__)

ROOT_DIR = Path(__file__).resolve().parent.parent
REFS_DIR = ROOT_DIR / "references"
OUTPUT_DIR = ROOT_DIR / "output"

INPUT_FILE = REFS_DIR / "input_samples.xlsx"
OUTPUT_FILE = OUTPUT_DIR / "evaluation_results.xlsx"
MENU_DESC_FILE = REFS_DIR / "menu_desc.xlsx"
PROMPT_TEMPLATE_FILE = REFS_DIR / "intent_match_prompt.txt"

REQUIRED_INPUT_COLUMNS = frozenset({"query", "intent"})
MENU_DESC_SHEET = "Sheet1"
MENU_NAME_COLUMN = "intent_name"
MENU_DESC_COLUMN = "intent_desc"

MAX_WORKERS = 8
LLM_TEMPERATURE = 0.1
LLM_MAX_TOKENS = 2048
LLM_TIMEOUT = 60
LLM_MAX_RETRIES = 3
LLM_RETRY_DELAY_SECONDS = 2

JSON_FENCE_PATTERN = re.compile(r"```(?:json)?\s*([\s\S]*?)\s*```", re.IGNORECASE)


@dataclass(frozen=True)
class LlmRequest:
    content: str
    temperature: float = LLM_TEMPERATURE
    max_tokens: int = LLM_MAX_TOKENS


@dataclass(frozen=True)
class JudgmentRecord:
    query: str
    intent: str
    result: str | int
    reason: str


@dataclass(frozen=True)
class ParseFailure:
    raw_response: str
    error: str


def load_llm_settings() -> dict[str, Any]:
    api_key = os.environ.get("LLM_API_KEY", "").strip()
    if not api_key:
        raise ValueError("Environment variable LLM_API_KEY is required")

    return {
        "api_key": api_key,
        "model": os.environ.get("LLM_MODEL", "glm-5.1"),
        "base_url": os.environ.get(
            "LLM_API_BASE",
            "https://open.bigmodel.cn/api/paas/v4/",
        ),
        "timeout": LLM_TIMEOUT,
    }


def create_llm_client(settings: dict[str, Any]) -> OpenAI:
    return OpenAI(
        api_key=settings["api_key"],
        base_url=settings["base_url"],
        timeout=settings["timeout"],
    )


def load_prompt_template(path: Path = PROMPT_TEMPLATE_FILE) -> str:
    return path.read_text(encoding="utf-8")


def build_prompt(
    query: str,
    intent: str,
    menu_desc: str,
    template: str,
) -> str:
    return template.format(query=query, intent=intent, menu_desc=menu_desc)


def load_menu_descriptions(path: Path = MENU_DESC_FILE) -> dict[str, str]:
    menu_df = pd.read_excel(path, sheet_name=MENU_DESC_SHEET)
    return dict(zip(menu_df[MENU_NAME_COLUMN], menu_df[MENU_DESC_COLUMN]))


def load_input_samples(path: Path = INPUT_FILE) -> pd.DataFrame:
    df = pd.read_excel(path)
    missing_columns = REQUIRED_INPUT_COLUMNS - set(df.columns)
    if missing_columns:
        raise ValueError(f"Input file is missing required columns: {sorted(missing_columns)}")
    return df


def call_llm(client: OpenAI, model: str, request: LlmRequest) -> str:
    for attempt in range(1, LLM_MAX_RETRIES + 1):
        try:
            response = client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": request.content}],
                temperature=request.temperature,
                max_tokens=request.max_tokens,
            )
            content = response.choices[0].message.content
            if content:
                return content.strip()
        except Exception as exc:
            logger.warning(
                "LLM request failed (attempt %s/%s): %s",
                attempt,
                LLM_MAX_RETRIES,
                exc,
            )
            if attempt < LLM_MAX_RETRIES:
                time.sleep(LLM_RETRY_DELAY_SECONDS * attempt)
    return ""


def extract_json_payload(text: str) -> str | None:
    for match in JSON_FENCE_PATTERN.findall(text):
        candidate = match.strip()
        if candidate:
            return candidate

    start_index = text.find("{")
    end_index = text.rfind("}")
    if start_index != -1 and end_index > start_index:
        return text[start_index : end_index + 1]
    return None


def parse_llm_response(raw_text: str) -> JudgmentRecord | ParseFailure:
    text = raw_text.strip() if isinstance(raw_text, str) else str(raw_text).strip()
    json_payload = extract_json_payload(text)
    if not json_payload:
        return ParseFailure(raw_response=text, error="Failed to extract JSON from response")

    try:
        payload = json.loads(json_payload, strict=False)
    except json.JSONDecodeError as exc:
        return ParseFailure(raw_response=text, error=f"Invalid JSON: {exc}")

    return JudgmentRecord(
        query=str(payload.get("query", "")),
        intent=str(payload.get("intent", "")),
        result=payload.get("match_score", -1),
        reason=str(payload.get("reason", "")),
    )


def parse_llm_responses(
    raw_responses: list[str],
) -> tuple[list[JudgmentRecord], list[ParseFailure]]:
    successes: list[JudgmentRecord] = []
    failures: list[ParseFailure] = []

    for raw_response in raw_responses:
        parsed = parse_llm_response(raw_response)
        if isinstance(parsed, ParseFailure):
            failures.append(parsed)
        else:
            successes.append(parsed)

    return successes, failures


def build_llm_requests(
    samples: pd.DataFrame,
    menu_descriptions: dict[str, str],
    prompt_template: str,
) -> list[LlmRequest]:
    requests: list[LlmRequest] = []

    for _, row in samples.iterrows():
        query = row["query"]
        intent = row["intent"]
        menu_desc = menu_descriptions.get(intent)

        if menu_desc is None:
            logger.warning("Intent %r is not defined in menu descriptions; skipping", intent)
            continue

        requests.append(
            LlmRequest(
                content=build_prompt(
                    query=str(query),
                    intent=str(intent),
                    menu_desc=str(menu_desc),
                    template=prompt_template,
                )
            )
        )

    return requests


def run_llm_batch(
    client: OpenAI,
    model: str,
    requests: list[LlmRequest],
    max_workers: int = MAX_WORKERS,
) -> list[str]:
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        responses = list(
            tqdm(
                executor.map(lambda request: call_llm(client, model, request), requests),
                total=len(requests),
            )
        )
    return responses


def save_results(records: list[JudgmentRecord], path: Path = OUTPUT_FILE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame([asdict(record) for record in records]).to_excel(path, index=False)


def log_parse_failures(failures: list[ParseFailure], preview_count: int = 5) -> None:
    if not failures:
        return

    logger.warning("Failed to parse %s response(s)", len(failures))
    for index, failure in enumerate(failures[:preview_count], start=1):
        logger.warning("%s. %s", index, failure.error)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    settings = load_llm_settings()
    client = create_llm_client(settings)

    samples = load_input_samples()
    logger.info("Loaded %s input row(s)", len(samples))

    menu_descriptions = load_menu_descriptions()
    logger.info("Loaded %s intent description(s)", len(menu_descriptions))

    prompt_template = load_prompt_template()
    llm_requests = build_llm_requests(samples, menu_descriptions, prompt_template)
    logger.info("Prepared %s LLM request(s)", len(llm_requests))

    raw_responses = run_llm_batch(client, settings["model"], llm_requests)
    successes, failures = parse_llm_responses(raw_responses)
    logger.info("Parsed %s success(es) and %s failure(s)", len(successes), len(failures))

    save_results(successes)
    logger.info("Results saved to %s", OUTPUT_FILE)

    log_parse_failures(failures)


if __name__ == "__main__":
    main()
