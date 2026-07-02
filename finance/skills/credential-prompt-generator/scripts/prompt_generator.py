"""
凭证要素提取提示词生成器

根据凭证图片样例，自动生成适用于该凭证类型的要素提取提示词。
"""

import base64
import re
import yaml
import httpx
from pathlib import Path
from typing import List, Dict, Any, Optional
from loguru import logger


class CredentialPromptGenerator:
    """凭证要素提取提示词生成器"""

    def __init__(self, api_key: str, api_url: str, model: str, timeout: int = 300):
        """
        初始化生成器

        Args:
            api_key: API 密钥
            api_url: API 地址（如 https://api.siliconflow.cn/v1）
            model: 模型名称（如 Qwen/Qwen3-VL-8B-Instruct）
            timeout: 请求超时时间（秒）
        """
        self.api_key = api_key
        self.api_url = api_url.rstrip("/")
        self.model = model
        self.timeout = timeout
        self.template = self._load_template()

    def _load_template(self) -> str:
        """从 assets/prompts/ 加载提示词模板"""
        template_path = Path(__file__).parent.parent / "assets" / "prompts" / "generate_prompt.yaml"
        if not template_path.exists():
            raise FileNotFoundError(f"提示词模板不存在: {template_path}")

        with open(template_path, "r", encoding="utf-8") as f:
            config = yaml.safe_load(f)

        return config.get("generate_prompt", "")

    def generate(
        self,
        images: List[str],
        field_code_mapping: Optional[List[Dict[str, str]]] = None,
        voucher_type: str = "",
    ) -> Dict[str, Any]:
        """
        生成提示词

        Args:
            images: 图片列表（文件路径或 base64 编码）
            field_code_mapping: 可选的要素编码映射 [{code: "E01001", name: "编号"}]
            voucher_type: 凭证类型名称（预留，暂未使用）

        Returns:
            {"success": True, "prompt": "生成的提示词文本"} 或
            {"success": False, "error": "错误信息"}
        """
        if not images:
            return {"success": False, "error": "至少需要一张图片"}

        logger.info(f"开始生成提示词，图片数量: {len(images)}")

        try:
            # 构建字段命名提示
            field_names_hint = ""
            if field_code_mapping:
                logger.info(f"使用要素编码映射，共 {len(field_code_mapping)} 个字段")
                field_names_hint = self._build_code_mapping_hint(field_code_mapping)

            # 渲染模板
            prompt_text = self._render_template(field_names_hint)

            # 获取图片 base64
            images_base64 = [self._get_image_base64(img) for img in images]

            # 调用 LLM
            result = self._call_llm(prompt_text, images_base64)

            # 清理 markdown 代码块
            result = self._strip_markdown_code_blocks(result)

            logger.info(f"提示词生成成功，长度: {len(result)}")
            logger.info(f"生成的提示词内容:\n{result}")
            return {"success": True, "prompt": result}

        except Exception as e:
            logger.error(f"提示词生成失败: {str(e)}")
            return {"success": False, "error": str(e)}

    def _build_code_mapping_hint(self, mappings: List[Dict[str, str]]) -> str:
        """
        从要素编码映射构建字段命名提示

        Args:
            mappings: 要素编码映射列表 [{code: "E01001", name: "编号"}]

        Returns:
            字段命名规范提示文本
        """
        # 使用前3个作为示例
        sample_codes = [m["code"] for m in mappings[:3]]
        sample_names = [m["name"] for m in mappings[:3]]

        lines = [
            "【重要 - 字段命名规范覆盖】",
            "以下要素编码映射将覆盖模板中的JSON命名规范。生成提示词时请严格遵守：",
            "",
            "1. 提取指南：使用扁平列表，每个字段以\"要素编码(中文名)\"作为标识，不要再使用嵌套分组结构",
            "2. 输出JSON格式：使用扁平结构，以要素编码作为key，不需要嵌套对象",
            "",
            "示例 - 提取指南写法：",
        ]

        for code, name in zip(sample_codes, sample_names):
            lines.append(f"  * **{code}({name})**: 在凭证图片中查找对应的字段值...")

        lines.append("")
        lines.append("示例 - JSON输出格式写法：")
        json_example = ", ".join(f'"{code}": "string"' for code in sample_codes)
        lines.append(f"  {{{json_example}}}")
        lines.append("")
        lines.append("要素编码映射清单：")

        # 按编码前缀分组
        groups: Dict[str, List[Dict[str, str]]] = {}
        for m in sorted(mappings, key=lambda x: x["code"]):
            prefix = m["code"][:3] if len(m["code"]) > 3 else m["code"]
            groups.setdefault(prefix, []).append(m)

        for group_code, items in sorted(groups.items()):
            fields = ", ".join(f"{m['code']}({m['name']})" for m in items)
            lines.append(f"- {group_code}: {fields}")

        return "\n".join(lines)

    def _render_template(self, field_names_hint: str = "") -> str:
        """
        渲染提示词模板

        Args:
            field_names_hint: 字段命名提示（可选）

        Returns:
            渲染后的提示词文本
        """
        result = self.template
        placeholder = "{{ field_names_hint }}"

        if placeholder in result:
            result = result.replace(placeholder, field_names_hint)
        elif field_names_hint:
            logger.warning(f"模板中缺少占位符 '{placeholder}'，字段命名提示被丢弃")

        return result

    def _call_llm(self, prompt_text: str, images_base64: List[str]) -> str:
        """
        调用 LLM API（多模态：文本 + 图片）

        Args:
            prompt_text: 提示词文本
            images_base64: base64 编码的图片列表

        Returns:
            LLM 返回的文本内容
        """
        # 构建消息内容
        content: List[Dict[str, Any]] = [{"type": "text", "text": prompt_text}]

        for image_base64 in images_base64:
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}
            })

        messages = [{"role": "user", "content": content}]

        # 日志记录
        prompt_preview = prompt_text[:200] + "..." if len(prompt_text) > 200 else prompt_text
        logger.info(f"调用 VL 模型: {self.model}")
        logger.info(f"入参 - 图片数量: {len(images_base64)}, Prompt (前200字符): {prompt_preview}")

        # 发送请求
        with httpx.Client(timeout=self.timeout) as client:
            response = client.post(
                f"{self.api_url}/chat/completions",
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self.api_key}"
                },
                json={
                    "model": self.model,
                    "messages": messages,
                    "max_tokens": 4096,
                    "temperature": 0.0
                }
            )

        if response.status_code != 200:
            raise RuntimeError(f"API 请求失败: {response.status_code} - {response.text}")

        data = response.json()

        if not data.get("choices") or len(data["choices"]) == 0:
            raise RuntimeError(f"API 返回数据格式错误: {data}")

        content_text = data["choices"][0]["message"]["content"]

        # 记录 token 使用情况
        if "usage" in data:
            usage = data["usage"]
            logger.info(
                f"Token 使用: prompt={usage.get('prompt_tokens', 'N/A')}, "
                f"completion={usage.get('completion_tokens', 'N/A')}, "
                f"total={usage.get('total_tokens', 'N/A')}"
            )

        return content_text

    def _get_image_base64(self, image_input: str) -> str:
        """
        获取图片的 base64 编码

        Args:
            image_input: 文件路径或 base64 编码

        Returns:
            base64 编码字符串（不含 data:image/... 前缀）
        """
        # 尝试作为文件路径
        try:
            path = Path(image_input)
            if path.exists() and path.is_file():
                return base64.b64encode(path.read_bytes()).decode()
        except Exception:
            pass

        # 检查是否已经是 base64（可能带 data:image/ 前缀）
        if image_input.startswith("data:image/"):
            # 提取 base64 部分
            if ";base64," in image_input:
                return image_input.split(";base64,")[1]
            return image_input

        # 尝试直接作为 base64 验证
        try:
            # 尝试解码来验证是否为有效的 base64
            decoded = base64.b64decode(image_input[:100] + "==")  # 添加 padding 尝试解码
            return image_input
        except Exception:
            pass

        raise ValueError(f"无法识别输入类型: {image_input[:50]}... (既不是有效文件路径也不是有效的base64编码)")

    def _strip_markdown_code_blocks(self, text: str) -> str:
        """
        剥离模型返回的 markdown 代码块标记

        例如：```markdown ... ``` -> ...

        Args:
            text: 原始文本

        Returns:
            清理后的文本
        """
        text = text.strip()
        match = re.match(r'^```(?:\w+)?\s*([\s\S]*?)\s*```$', text)
        if match:
            return match.group(1).strip()
        return text
