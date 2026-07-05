"""
正则表达式验证器重导出模块。

实际实现已迁移到 shared/validators/regex_validator.py，
此模块仅用于保持向后兼容的导入路径。
"""

import sys
from pathlib import Path

# 添加 shared 目录到 Python 路径
# validators -> src -> scripts -> finance-ai-security-guardrail -> methodology -> shared
_shared_path = Path(__file__).parent.parent.parent.parent.parent / "shared"
if str(_shared_path) not in sys.path:
    sys.path.insert(0, str(_shared_path))

from validators.regex_validator import *  # noqa: F401, F403
from validators.regex_validator import (  # noqa: F401
    RegexMatchValidator,
    RegexBlacklistValidator,
    GUARDRAILS_AVAILABLE,
    GUARDRAILS_INTEGRATION_AVAILABLE,
)
