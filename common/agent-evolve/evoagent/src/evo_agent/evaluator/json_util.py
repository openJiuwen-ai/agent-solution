"""Provider-neutral JSON extraction with deterministic repair provenance."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Literal


@dataclass(frozen=True)
class JsonRepairPolicy:
    """Controls the narrow repairs allowed for one output schema."""

    allow_single_missing_comma: bool = False
    allowed_comma_next_keys: frozenset[str] = frozenset()
    required_keys: frozenset[str] = frozenset()
    reject_duplicate_keys: bool = True


@dataclass(frozen=True)
class JsonRepairOperation:
    """One deterministic source edit applied before parsing."""

    op: Literal[
        "strip_code_fence",
        "remove_comment",
        "remove_trailing_comma",
        "normalize_quote",
        "escape_control_character",
        "append_closing_delimiter",
        "insert_comma",
    ]
    offset: int | None = None
    next_key: str | None = None


@dataclass(frozen=True)
class JsonExtractionResult:
    """Parsed value and complete repair provenance."""

    data: Any | None
    error: str
    parse_mode: Literal["exact", "deterministic_repair", "deterministic_comma_repair", "failed"]
    repair_operations: tuple[JsonRepairOperation, ...] = ()
    repaired_text: str | None = None


_FENCE_RE = re.compile(r"\A\s*```(?:json)?\s*\n?(.*?)\n?```\s*\Z", re.DOTALL | re.IGNORECASE)


def fix_json_text(text: str) -> str:
    """Apply string-aware trailing-comma repair without changing string values."""
    return _remove_trailing_commas(text)[0]


def extract_json(raw: str, *, policy: JsonRepairPolicy) -> JsonExtractionResult:
    """Parse an entire JSON response, then apply only deterministic repairs."""
    exact = _loads(raw, policy=policy)
    if exact.error == "":
        return exact

    operations: list[JsonRepairOperation] = []
    candidate = raw
    fence = _FENCE_RE.match(candidate)
    if fence is not None:
        candidate = fence.group(1)
        operations.append(JsonRepairOperation("strip_code_fence"))

    candidate, quotes_normalized = _normalize_unambiguous_single_quotes(candidate)
    if quotes_normalized:
        operations.append(JsonRepairOperation("normalize_quote"))

    candidate, comments_removed = _remove_line_comments(candidate)
    if comments_removed:
        operations.append(JsonRepairOperation("remove_comment"))

    candidate, controls_escaped = _escape_string_control_characters(candidate)
    if controls_escaped:
        operations.append(JsonRepairOperation("escape_control_character"))

    candidate, removed = _remove_trailing_commas(candidate)
    if removed:
        operations.append(JsonRepairOperation("remove_trailing_comma"))

    candidate, delimiters_appended = _append_closing_delimiters(candidate)
    if delimiters_appended:
        operations.append(JsonRepairOperation("append_closing_delimiter"))

    repaired = _loads(candidate, policy=policy)
    if repaired.error == "" and operations:
        return JsonExtractionResult(
            data=repaired.data,
            error="",
            parse_mode="deterministic_repair",
            repair_operations=tuple(operations),
            repaired_text=candidate,
        )
    if policy.allow_single_missing_comma and not operations:
        comma_repair = _insert_allowed_comma(candidate, policy)
        if comma_repair is not None:
            repaired_text, operation = comma_repair
            comma_result = _loads(repaired_text, policy=policy)
            if comma_result.error == "":
                return JsonExtractionResult(
                    comma_result.data,
                    "",
                    "deterministic_comma_repair",
                    (operation,),
                    repaired_text=repaired_text,
                )
    return JsonExtractionResult(None, repaired.error or exact.error, "failed")


def extract_json_data(raw: str) -> dict[str, Any] | None:
    """Compatibility projection for callers that only need strict/shared data."""
    result = extract_json(raw, policy=JsonRepairPolicy())
    if result.data is None:
        fences = re.findall(r"```(?:json)?\s*(.*?)\s*```", raw, re.DOTALL | re.IGNORECASE)
        if len(fences) == 1:
            result = extract_json(fences[0], policy=JsonRepairPolicy())
    return result.data if isinstance(result.data, dict) else None


def _loads(text: str, *, policy: JsonRepairPolicy) -> JsonExtractionResult:
    duplicate_keys: list[str] = []

    def build_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                duplicate_keys.append(key)
            result[key] = value
        return result

    try:
        data = json.loads(text, object_pairs_hook=build_object)
    except (json.JSONDecodeError, TypeError) as exc:
        return JsonExtractionResult(None, str(exc), "failed")
    if policy.reject_duplicate_keys and duplicate_keys:
        return JsonExtractionResult(None, f"duplicate keys: {duplicate_keys!r}", "failed")
    if not isinstance(data, dict):
        return JsonExtractionResult(None, "top-level JSON value must be an object", "failed")
    missing = policy.required_keys.difference(data)
    if missing:
        return JsonExtractionResult(None, f"missing required keys: {sorted(missing)!r}", "failed")
    return JsonExtractionResult(data, "", "exact")


def _insert_allowed_comma(
    text: str, policy: JsonRepairPolicy
) -> tuple[str, JsonRepairOperation] | None:
    """Return the sole schema-allowed object comma insertion, if unambiguous."""
    candidates: list[tuple[int, str]] = []
    pattern = re.compile(
        r'(?<=[0-9eE.truefalsnul}\]"])\s+(?="(?P<key>[^"\\]+)"\s*:)',
    )
    for match in pattern.finditer(text):
        key = match.group("key")
        if key not in policy.allowed_comma_next_keys:
            continue
        if _container_at(text, match.start()) != "{":
            continue
        candidates.append((match.start(), key))
    if len(candidates) != 1:
        return None
    offset, key = candidates[0]
    operation = JsonRepairOperation("insert_comma", offset=offset, next_key=key)
    return f"{text[:offset]},{text[offset:]}", operation


def _container_at(text: str, offset: int) -> str | None:
    stack: list[str] = []
    in_string = False
    escaped = False
    for char in text[:offset]:
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char in "[{":
            stack.append(char)
        elif char == "]" and stack and stack[-1] == "[":
            stack.pop()
        elif char == "}" and stack and stack[-1] == "{":
            stack.pop()
    return stack[-1] if stack else None


def _remove_trailing_commas(text: str) -> tuple[str, bool]:
    output: list[str] = []
    in_string = False
    escaped = False
    removed = False
    index = 0
    while index < len(text):
        char = text[index]
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            output.append(char)
            index += 1
            continue
        if char == ",":
            lookahead = index + 1
            while lookahead < len(text) and text[lookahead].isspace():
                lookahead += 1
            if lookahead < len(text) and text[lookahead] in "}]":
                removed = True
                index += 1
                continue
        output.append(char)
        index += 1
    return "".join(output), removed


def _remove_line_comments(text: str) -> tuple[str, bool]:
    """Remove ``//`` through newline only while outside JSON strings."""
    output: list[str] = []
    in_string = False
    escaped = False
    removed = False
    index = 0
    while index < len(text):
        char = text[index]
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            output.append(char)
            index += 1
            continue
        if char == "/" and index + 1 < len(text) and text[index + 1] == "/":
            removed = True
            index += 2
            while index < len(text) and text[index] not in "\r\n":
                index += 1
            continue
        output.append(char)
        index += 1
    return "".join(output), removed


def _append_closing_delimiters(text: str) -> tuple[str, bool]:
    """Close a valid, uniquely determined object/array stack at end of input."""
    stack: list[str] = []
    in_string = False
    escaped = False
    for char in text:
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char in "[{":
            stack.append(char)
        elif char in "]}":
            expected = "[" if char == "]" else "{"
            if not stack or stack[-1] != expected:
                return text, False
            stack.pop()
    if in_string or escaped or not stack:
        return text, False
    closers = "".join("]" if opener == "[" else "}" for opener in reversed(stack))
    return text + closers, True


def _escape_string_control_characters(text: str) -> tuple[str, bool]:
    """JSON-escape raw U+0000..U+001F characters occurring inside strings."""
    output: list[str] = []
    in_string = False
    escaped = False
    changed = False
    for char in text:
        if not in_string:
            output.append(char)
            if char == '"':
                in_string = True
            continue
        if escaped:
            output.append(char)
            escaped = False
        elif char == "\\":
            output.append(char)
            escaped = True
        elif char == '"':
            output.append(char)
            in_string = False
        elif ord(char) < 0x20:
            output.append(json.dumps(char)[1:-1])
            changed = True
        else:
            output.append(char)
    return "".join(output), changed


def _normalize_unambiguous_single_quotes(text: str) -> tuple[str, bool]:
    """Normalize simple JSON single-quoted keys/values only with unique boundaries."""
    if "'" not in text:
        return text, False
    output: list[str] = []
    stack: list[str] = []
    index = 0
    changed = False
    while index < len(text):
        char = text[index]
        if char == '"':
            end = _quoted_end(text, index, '"')
            if end is None:
                return text, False
            output.append(text[index : end + 1])
            index = end + 1
            continue
        if char in "[{":
            stack.append(char)
        elif char in "]}":
            expected = "[" if char == "]" else "{"
            if not stack or stack[-1] != expected:
                return text, False
            stack.pop()
        if char != "'":
            output.append(char)
            index += 1
            continue

        previous = _previous_nonspace(text, index)
        is_key = bool(stack and stack[-1] == "{" and previous in {"{", ","})
        is_value = previous in {":", "[", ","} and not is_key
        if not (is_key or is_value):
            return text, False
        valid_closers: list[int] = []
        cursor = index + 1
        while True:
            cursor = text.find("'", cursor)
            if cursor < 0:
                break
            following = _next_nonspace(text, cursor)
            if (is_key and following == ":") or (is_value and following in {",", "]", "}"}):
                valid_closers.append(cursor)
                break
            cursor += 1
        if len(valid_closers) != 1:
            return text, False
        end = valid_closers[0]
        content = text[index + 1 : end]
        if "'" in content or '"' in content or "\\" in content:
            return text, False
        output.extend(('"', content, '"'))
        changed = True
        index = end + 1
    return "".join(output), changed


def _quoted_end(text: str, start: int, quote: str) -> int | None:
    escaped = False
    for index in range(start + 1, len(text)):
        char = text[index]
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == quote:
            return index
    return None


def _previous_nonspace(text: str, offset: int) -> str | None:
    index = offset - 1
    while index >= 0 and text[index].isspace():
        index -= 1
    return text[index] if index >= 0 else None


def _next_nonspace(text: str, offset: int) -> str | None:
    index = offset + 1
    while index < len(text) and text[index].isspace():
        index += 1
    return text[index] if index < len(text) else None


__all__ = [
    "JsonExtractionResult",
    "JsonRepairOperation",
    "JsonRepairPolicy",
    "extract_json",
    "extract_json_data",
    "fix_json_text",
]
