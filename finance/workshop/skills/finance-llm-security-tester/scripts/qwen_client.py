"""
模型服务接口
支持两种HTTP客户端模式：
1. requests: 同步请求（Linux环境下性能良好）
2. httpx: 真正的异步请求（Windows环境推荐）
"""
import asyncio
import copy
import requests
import logging
import json
from typing import Optional
from config import QWEN_API_URL, QWEN_API_KEY, QWEN_MODEL_NAME, SYSTEM_PROMPT, MODEL_REQUEST_CONFIG, USE_ASYNC_HTTP

# 根据配置决定是否导入httpx
if USE_ASYNC_HTTP:
    try:
        import httpx
        HTTPX_AVAILABLE = True
    except ImportError:
        HTTPX_AVAILABLE = False
        logging.warning("httpx未安装，将使用requests作为后备方案")
else:
    HTTPX_AVAILABLE = False

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class QwenClient:
    """模型客户端"""
    
    def __init__(self, api_url: str = QWEN_API_URL, api_key: str = QWEN_API_KEY):
        """
        初始化模型客户端
        
        Args:
            api_url: API地址
            api_key: API密钥
        """
        self.api_url = api_url
        self.api_key = api_key
        self.model_name = QWEN_MODEL_NAME
        
        # 根据配置决定使用哪种HTTP客户端
        self.use_async = USE_ASYNC_HTTP and HTTPX_AVAILABLE
        self._async_client = None  # httpx异步客户端（懒加载）
        
        if self.use_async:
            logger.info("使用httpx异步HTTP客户端")
        else:
            logger.info("使用requests同步HTTP客户端")

    async def send_request(self, prompt: str, timeout: int = 60, max_retries: int = 1) -> Optional[str]:
        """
        发送请求到被测模型（带重试机制）

        Args:
            prompt: 提示词内容
            timeout: 超时时间（秒）
            max_retries: 最大重试次数（默认1次）

        Returns:
            模型响应内容，失败返回None
        """
        # 构造请求体（使用全局配置）
        payload = self._build_payload(prompt)
        # 记录发送的提示词
        content = payload["messages"][1]["content"]
        # 日志中的提示词内容
        content_print = f"{content[:100]}..." if len(content) > 100 else content
        # 设置请求头
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.api_key}"
        }

        # 重试机制
        for attempt in range(max_retries + 1):
            try:
                # 根据配置选择不同的请求方法
                if self.use_async:
                    result = await self._send_async_request(payload, headers, timeout, content_print)
                else:
                    result = await self._send_sync_request(payload, headers, timeout, content_print)
                
                # 返回None表示不需要重试的情况（如超时、响应格式异常等）
                return result
                
            except Exception as e:
                error_type = type(e).__name__
                logger.error(f"提示词：{content_print}，请求异常 [{error_type}]: {str(e)}")
                # 如果还有重试机会，继续重试
                if attempt < max_retries:
                    logger.warning(f"第 {attempt + 1} 次尝试失败，准备重试...")
                    await asyncio.sleep(3)
                else:
                    logger.error(f"所有 {max_retries + 1} 次尝试均失败")

        return None
    
    async def close(self):
        """关闭HTTP客户端（如果使用httpx）"""
        if self._async_client and not self._async_client.is_closed:
            await self._async_client.aclose()
            self._async_client = None

    # ==================== Private ====================

    @staticmethod
    def _build_payload(prompt: str) -> dict:
        """
        构造请求体

        Args:
            prompt: 用户提示词

        Returns:
            请求体字典
        """
        values = copy.deepcopy(MODEL_REQUEST_CONFIG)
        values["messages"][1]["content"] = prompt
        return values

    async def _send_sync_request(self, payload: dict, headers: dict, timeout: int, prompt: str) -> Optional[str]:
        """
        使用requests发送同步请求（在事件循环中运行，会阻塞）

        Args:
            payload: 请求体
            headers: 请求头
            timeout: 超时时间（秒）

        Returns:
            模型响应内容，失败返回None
        """
        try:
            # 使用requests发送同步请求
            response = requests.post(
                self.api_url, 
                headers=headers, 
                json=payload, 
                timeout=timeout, 
                verify=False
            )

            # 检查响应状态
            response.raise_for_status()

            # 解析响应
            result = response.json()
            return self._parse_response(result, prompt)

        except requests.exceptions.Timeout as e:
            logger.error(f"请求超时: {str(e)}")
            raise
        except requests.exceptions.HTTPError as e:
            logger.error(f"HTTP错误: {str(e)}")
            raise

    async def _send_async_request(self, payload: dict, headers: dict, timeout: int, prompt: str) -> Optional[str]:
        """
        使用httpx发送真正的异步请求（不阻塞事件循环）

        Args:
            payload: 请求体
            headers: 请求头
            timeout: 超时时间（秒）

        Returns:
            模型响应内容，失败返回None
        """
        # 懒加载httpx客户端
        if self._async_client is None or self._async_client.is_closed:
            self._async_client = httpx.AsyncClient(verify=False, timeout=timeout)
        
        try:
            # 使用httpx发送异步请求
            response = await self._async_client.post(
                self.api_url, 
                headers=headers, 
                json=payload
            )

            # 检查响应状态
            response.raise_for_status()

            # 解析响应
            result = response.json()
            return self._parse_response(result, prompt)

        except httpx.TimeoutException as e:
            logger.error(f"请求超时: {str(e)}")
            raise
        except httpx.HTTPStatusError as e:
            logger.error(f"HTTP错误: {str(e)}")
            raise

    @staticmethod
    def _parse_response(result: dict, prompt: str) -> Optional[str]:
        """
        解析API响应（通用方法）

        Args:
            result: API响应字典

        Returns:
            模型回复内容，失败返回None
        """
        # 记录完整的响应结构（用于调试）
        logger.debug(f"完整响应: {result}")

        # 提取模型回复内容（Chat Completions API格式）
        if "choices" in result and len(result["choices"]) > 0:
            # Chat Completions API的响应格式：choices[0].message.content
            choice = result["choices"][0]
            logger.debug(f"choices[0]: {choice}")

            reply = choice.get("message", {}).get("content", "")

            # 检查是否成功提取到响应
            if reply:
                # 移除思考标签（如果存在）
                if "<think>" in reply and "</think>" in reply:
                    reply = reply.replace("<think>", "").replace("</think>", "").strip()
                # 移除```json代码块
                if "```json" in reply and "```" in reply:
                    reply = reply.replace("```json", "").replace("```", "").strip()
                reply_print = f"{reply[:100]}..." if len(reply) > 100 else reply
                logger.info(f"提示词：{prompt}\n收到响应: {reply_print}")
                return reply
            else:
                logger.error(f"无法从响应中提取content，choice结构: {choice}")
                return None
        else:
            logger.error(f"响应格式异常，没有choices字段或choices为空: {result}")
            return None
