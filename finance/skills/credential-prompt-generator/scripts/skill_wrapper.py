"""
凭证要素提取提示词生成 Skill - MCP 注册入口

适配 skills_mcp_server 框架，添加 @skill 装饰器
"""

from pathlib import Path
from typing import Dict, Any, List, Optional

from skills_mcp_server.common.skill_utils import setup_skill_path, list_registered_skills
from skills_mcp_server.core.decorator import skill
from skills_mcp_server.core.config import VLConfig, get_config_loader

# 设置 sys.path 包含 scripts/ 目录
setup_skill_path(Path(__file__).parent.parent)

from prompt_generator import CredentialPromptGenerator


@skill(
    name="credential-prompt-generator",
    description="凭证要素提取提示词生成 - 输入凭证图片，生成适用于该类型的要素提取提示词（包含角色设定、提取指南、JSON输出格式）"
)
def generate_credential_prompt(
    images: List[str],
    field_code_mapping: Optional[List[Dict[str, str]]] = None,
    vl_config: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    生成凭证要素提取提示词

    Args:
        images: 图片列表（文件路径或 base64 编码）
        field_code_mapping: 要素编码映射，可选，格式 [{"code": "E01001", "name": "编号"}]
        vl_config: VL 模型配置，可选，格式 {"api_key": "...", "api_url": "...", "model": "...", "timeout": 300}
                   不传时使用服务端默认配置

    Returns:
        {"success": True, "prompt": "生成的提示词文本"} 或
        {"success": False, "error": "错误信息"}
    """
    # 不传时自动从服务端配置读取
    if vl_config is None:
        vl_config = get_config_loader().resolve_vl_config()
        if vl_config is None:
            return {"success": False, "error": "服务端未配置 VL 模型"}
        vl_config = vl_config.model_dump()

    # 兼容 VLConfig 对象和 dict
    if isinstance(vl_config, VLConfig):
        vl_config = vl_config.model_dump()

    # 创建生成器并执行
    generator = CredentialPromptGenerator(
        api_key=vl_config.get("api_key", ""),
        api_url=vl_config.get("api_url", ""),
        model=vl_config.get("model", ""),
        timeout=vl_config.get("timeout", 300)
    )

    return generator.generate(
        images=images,
        field_code_mapping=field_code_mapping
    )


if __name__ == "__main__":
    print(f"已注册 Skills: {list_registered_skills()}")
