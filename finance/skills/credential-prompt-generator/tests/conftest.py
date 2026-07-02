"""
测试配置
"""
import pytest
from pathlib import Path
import sys

# 将 scripts 目录加入路径
scripts_dir = Path(__file__).parent.parent / "scripts"
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))


@pytest.fixture
def sample_prompt_template():
    """示例提示词模板"""
    return """你是一个专业的提示词工程师。请根据提供的凭证图片样例，生成一个用于适用于该凭证类型的提取关键信息的通用提示词。

要求：
1. 分析图片内容，确定凭证类型
2. 根据凭证类型，定义合适的专家角色
3. 列出该类型凭证需要提取的关键字段

{{ field_names_hint }}"""


@pytest.fixture
def sample_code_mapping():
    """示例要素编码映射"""
    return [
        {"code": "E01001", "name": "凭证编号"},
        {"code": "E01002", "name": "开票日期"},
        {"code": "E02001", "name": "金额"},
        {"code": "E02002", "name": "币种"},
    ]
