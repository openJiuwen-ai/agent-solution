# Finance LLM Security Tester

> 大模型安全扫描测试工具 - 金融场景 LLM 安全检测能力的并发测试与评估

## 简介

本工具是一个**基于 Python 的大模型安全扫描测试工具**，用于并发测试模型的安全性。工具从 Excel 文件中读取测试用例，通过**多协程并发**方式调用模型 API，并将响应结果保存回 Excel 文件。

适用于以下场景：
- 验证 `finance-ai-security-guardrail` 方法论中安全提示词的实际效果
- 对比不同模型（Qwen3-8B/30B、GLM4 等）安全检测能力的差异
- 批量评估提示词质量

## 项目结构

```
finance-llm-security-tester/
├── scripts/                # 主代码
│   ├── main.py             # 主程序
│   ├── config.py           # 配置文件
│   ├── qwen_client.py      # 模型客户端
│   ├── requirements.txt   # 依赖
│   └── test/               # 测试用例
├── prompts/                # 16+ 个针对不同模型的提示词
├── references/             # 详细文档
├── templates/              # Excel 模板
├── SKILL.md                # Skill 规范
├── LICENSE                 # Apache 2.0
└── .gitignore
```

## 快速开始

### 1. 安装依赖

```bash
cd scripts
pip install -r requirements.txt
```

### 2. 配置 API 信息

编辑 `scripts/config.py`：

```python
QWEN_API_URL = "https://api.siliconflow.cn/v1/chat/completions"
QWEN_API_KEY = "your-api-key"          # 替换为实际密钥
QWEN_MODEL_NAME = "Qwen/Qwen3-8B"
NUM_WORKERS = 2
INPUT_EXCEL_PATH = r"<your-excel-path>"
```

### 3. 准备测试用例

按 `scripts/test/` 中的示例 Excel 格式准备测试用例（提示词列 + 预期结果列）。

### 4. 选择提示词

从 `prompts/` 选择对应模型的提示词文件，按需修改 `scripts/test/test1.py` 中的 `SYSTEM_PROMPT`。

### 5. 运行测试

```bash
cd scripts
python main.py
```

输出：
- 结果文件：`data/{原文件名}_{结束时间}.xlsx`
- 日志文件：`logs/qwen_test_{开始时间}.log`

## 核心特性

- **多协程并发**：通过 `asyncio.Queue` + 工作协程实现
- **顺序处理**：每协程一次只处理 1 个请求，避免阻塞
- **自动重试**：HTTP 错误/网络异常自动重试 1 次
- **Excel 兼容**：使用 openpyxl 保留原格式和公式
- **彩色日志**：便于调试
- **多模型支持**：Qwen3-8B/30B、GLM4 等

## 配套方法论

本工具是 [`finance-ai-security-guardrail`](../../methodology/finance-ai-security-guardrail/) 方法论的**配套测试工具**。`prompts/` 目录下的提示词与该方法论中的 `SECURITY_CHECK_PROMPT` 配套使用，用于验证实际防护效果。

## 详细文档

- 性能测试说明：[`references/性能测试.md`](references/性能测试.md)
- Skill 规范：[`SKILL.md`](SKILL.md)

## 许可证

Apache License 2.0
