#!/usr/bin/env python3
"""Deduplicate similar questions within each intent using TF-IDF clustering."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.cluster import AgglomerativeClustering
from sklearn.feature_extraction.text import TfidfVectorizer

logger = logging.getLogger(__name__)

ROOT_DIR = Path(__file__).resolve().parent.parent
REFS_DIR = ROOT_DIR / "references"
OUTPUT_DIR = ROOT_DIR / "output"

INPUT_FILE = REFS_DIR / "similar_questions_raw.xlsx"
OUTPUT_FILE = OUTPUT_DIR / "similar_questions_deduped.xlsx"

REQUIRED_INPUT_COLUMNS = frozenset({"intent_name", "similar_query"})
INTENT_COLUMN = "intent_name"
QUERY_COLUMN = "similar_query"

DEFAULT_SIMILARITY_THRESHOLD = 0.85
DEFAULT_STRATEGY = "centroid"

PUNCTUATION_PATTERN = re.compile(
    r'[，。！？、；：""\'\'（）()【】\[\]<>《》—…·]'
)
WHITESPACE_PATTERN = re.compile(r"\s+")


class RepresentativeStrategy(str, Enum):
    CENTROID = "centroid"
    LONGEST = "longest"
    MOST_SIMILAR = "most_similar"


@dataclass(frozen=True)
class ClusterDetail:
    cluster_id: int
    size: int
    representative: str
    members: list[str]


@dataclass(frozen=True)
class IntentDedupSummary:
    intent_name: str
    count_before: int
    count_after: int
    clusters: list[ClusterDetail]


@dataclass(frozen=True)
class DedupConfig:
    similarity_threshold: float = DEFAULT_SIMILARITY_THRESHOLD
    strategy: RepresentativeStrategy = RepresentativeStrategy(DEFAULT_STRATEGY)


def clean_text(text: str) -> str:
    normalized = str(text).strip()
    normalized = PUNCTUATION_PATTERN.sub("", normalized)
    return WHITESPACE_PATTERN.sub("", normalized)


class SimilarQuestionDeduplicator:
    """Deduplicate similar questions within a single intent."""

    def __init__(self) -> None:
        self._vectorizer = TfidfVectorizer(
            analyzer="char",
            ngram_range=(1, 3),
            max_features=10000,
        )

    def deduplicate(
        self,
        questions: list[str],
        similarity_threshold: float = DEFAULT_SIMILARITY_THRESHOLD,
        strategy: RepresentativeStrategy = RepresentativeStrategy.CENTROID,
    ) -> tuple[list[str], list[ClusterDetail]]:
        if not questions:
            return [], []

        if len(questions) == 1:
            cluster = ClusterDetail(
                cluster_id=0,
                size=1,
                representative=questions[0],
                members=questions,
            )
            return [questions[0]], [cluster]

        cleaned_questions = [clean_text(question) for question in questions]

        try:
            tfidf_matrix = self._vectorizer.fit_transform(cleaned_questions)
        except ValueError:
            logger.warning("Vectorization failed; keeping original questions unchanged")
            cluster = ClusterDetail(
                cluster_id=0,
                size=len(questions),
                representative=questions[0],
                members=questions,
            )
            return questions, [cluster]

        distance_threshold = 1.0 - similarity_threshold
        clustering = AgglomerativeClustering(
            n_clusters=None,
            metric="cosine",
            linkage="average",
            distance_threshold=distance_threshold,
        )
        labels = clustering.fit_predict(tfidf_matrix.toarray())

        return self._select_representatives(
            questions=questions,
            embeddings=tfidf_matrix.toarray(),
            labels=labels,
            strategy=strategy,
        )

    def _select_representatives(
        self,
        questions: list[str],
        embeddings: np.ndarray,
        labels: np.ndarray,
        strategy: RepresentativeStrategy,
    ) -> tuple[list[str], list[ClusterDetail]]:
        representatives: list[str] = []
        details: list[ClusterDetail] = []

        for cluster_id in sorted(set(labels)):
            indices = [index for index, label in enumerate(labels) if label == cluster_id]
            cluster_questions = [questions[index] for index in indices]
            cluster_embeddings = embeddings[indices]

            best_local_index = self._pick_representative_index(
                cluster_questions,
                cluster_embeddings,
                strategy,
            )
            best_index = indices[best_local_index]

            representatives.append(questions[best_index])
            details.append(
                ClusterDetail(
                    cluster_id=int(cluster_id),
                    size=len(indices),
                    representative=questions[best_index],
                    members=cluster_questions,
                )
            )

        return representatives, details

    @staticmethod
    def _pick_representative_index(
        cluster_questions: list[str],
        cluster_embeddings: np.ndarray,
        strategy: RepresentativeStrategy,
    ) -> int:
        if strategy == RepresentativeStrategy.LONGEST:
            return int(np.argmax([len(question) for question in cluster_questions]))

        if strategy == RepresentativeStrategy.MOST_SIMILAR:
            average_similarities = []
            for index, embedding in enumerate(cluster_embeddings):
                other_embeddings = np.delete(cluster_embeddings, index, axis=0)
                if len(other_embeddings) == 0:
                    average_similarities.append(0.0)
                else:
                    average_similarities.append(float(np.mean(other_embeddings @ embedding)))
            return int(np.argmax(average_similarities))

        centroid = np.mean(cluster_embeddings, axis=0)
        similarities = cluster_embeddings @ centroid
        return int(np.argmax(similarities))


def load_input_samples(path: Path = INPUT_FILE) -> pd.DataFrame:
    dataframe = pd.read_excel(path)
    missing_columns = REQUIRED_INPUT_COLUMNS - set(dataframe.columns)
    if missing_columns:
        raise ValueError(f"Input file is missing required columns: {sorted(missing_columns)}")

    cleaned = dataframe.dropna(subset=[INTENT_COLUMN, QUERY_COLUMN]).copy()
    cleaned[QUERY_COLUMN] = cleaned[QUERY_COLUMN].astype(str).str.strip()
    return cleaned[cleaned[QUERY_COLUMN] != ""]


def deduplicate_by_intent(
    samples: pd.DataFrame,
    deduplicator: SimilarQuestionDeduplicator,
    config: DedupConfig,
) -> tuple[pd.DataFrame, list[IntentDedupSummary]]:
    output_rows: list[dict[str, str]] = []
    summaries: list[IntentDedupSummary] = []

    intent_names = samples[INTENT_COLUMN].unique()
    logger.info("Deduplicating %s intent(s)", len(intent_names))
    logger.info(
        "Config: similarity_threshold=%s strategy=%s",
        config.similarity_threshold,
        config.strategy.value,
    )

    for index, intent_name in enumerate(intent_names, start=1):
        group = samples[samples[INTENT_COLUMN] == intent_name]
        questions = group[QUERY_COLUMN].tolist()

        representatives, cluster_details = deduplicator.deduplicate(
            questions=questions,
            similarity_threshold=config.similarity_threshold,
            strategy=config.strategy,
        )

        for question in representatives:
            output_rows.append({INTENT_COLUMN: intent_name, QUERY_COLUMN: question})

        summary = IntentDedupSummary(
            intent_name=str(intent_name),
            count_before=len(questions),
            count_after=len(representatives),
            clusters=cluster_details,
        )
        summaries.append(summary)

        logger.info(
            "[%s/%s] intent=%r before=%s after=%s",
            index,
            len(intent_names),
            intent_name,
            summary.count_before,
            summary.count_after,
        )
        for cluster in cluster_details:
            logger.debug("  cluster %s: %s", cluster.cluster_id, cluster.members)

    return pd.DataFrame(output_rows), summaries


def log_summary(summaries: list[IntentDedupSummary]) -> None:
    total_before = sum(summary.count_before for summary in summaries)
    total_after = sum(summary.count_after for summary in summaries)
    if total_before == 0:
        logger.info("No rows to deduplicate")
        return

    dedup_rate = (1 - total_after / total_before) * 100
    logger.info(
        "Summary: %s -> %s rows (dedup rate %.1f%%)",
        total_before,
        total_after,
        dedup_rate,
    )


def save_results(dataframe: pd.DataFrame, path: Path = OUTPUT_FILE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    dataframe.to_excel(path, index=False)
    logger.info("Results saved to %s", path)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    config = DedupConfig()
    samples = load_input_samples()
    logger.info("Loaded %s input row(s)", len(samples))

    deduplicator = SimilarQuestionDeduplicator()
    results, summaries = deduplicate_by_intent(samples, deduplicator, config)

    log_summary(summaries)
    save_results(results)


if __name__ == "__main__":
    main()
