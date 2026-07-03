"""
Embedding-based content classifier for Finance Guardrail.

通过 langchain_openai.OpenAIEmbeddings 调用 SiliconFlow Embedding API，
实现零样本内容分类（无需本地模型文件）。
"""
import logging
from typing import Dict, List, Optional

from langchain_openai import OpenAIEmbeddings

from config.config import OPENAI_API_KEY, EMBEDDING_BASE_URL, EMBEDDING_MODEL

logger = logging.getLogger("agent_service")

# 复用 OpenAIEmbeddings 实例
_embedding_client: Optional[OpenAIEmbeddings] = None


def _get_embedding_client() -> OpenAIEmbeddings:
    """获取或创建共享的 Embedding 客户端。"""
    global _embedding_client
    if _embedding_client is None:
        _embedding_client = OpenAIEmbeddings(
            openai_api_key=OPENAI_API_KEY,
            openai_api_base=EMBEDDING_BASE_URL,
            model=EMBEDDING_MODEL,
        )
    return _embedding_client


async def fetch_embeddings(texts: List[str], model: Optional[str] = None) -> Optional[List[List[float]]]:
    """
    通过 SiliconFlow API 批量获取文本的 Embedding 向量。

    Args:
        texts: 待编码的文本列表（单条或多条）
        model: 模型名称（保留参数以兼容旧接口，实际使用初始化时的模型）

    Returns:
        每个文本对应的 embedding 向量列表，失败返回 None
    """
    if not OPENAI_API_KEY:
        logger.warning("OPENAI_API_KEY 未配置，无法获取 embedding")
        return None

    try:
        client = _get_embedding_client()
        vectors = await client.aembed_documents(texts)

        logger.debug(
            f"Embedding API 成功: model={EMBEDDING_MODEL}, "
            f"texts={len(texts)}, dims={len(vectors[0]) if vectors else 0}"
        )
        return vectors

    except Exception as e:
        logger.error(f"Embedding API 调用失败: {e}", exc_info=True)
        return None


async def fetch_embedding(text: str, model: Optional[str] = None) -> Optional[List[float]]:
    """获取单条文本的 embedding（fetch_embeddings 的便捷封装）。"""
    vectors = await fetch_embeddings([text], model)
    return vectors[0] if vectors else None


def cosine_similarity(a: List[float], b: List[float]) -> float:
    """
    计算两个归一化向量的余弦相似度。

    若向量未归一化，结果会大于 1 或小于 -1，调用方应自行 clamp。
    """
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = sum(x * x for x in a) ** 0.5
    norm_b = sum(x * x for x in b) ** 0.5
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return max(-1.0, min(1.0, dot / (norm_a * norm_b)))
