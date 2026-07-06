---
name: finance-llm-security-tester
version: 1.0.0
description: 大模型安全扫描测试工具 - 用于金融场景 LLM 安全检测能力的并发测试与评估
license: Apache-2.0
---

# Finance LLM Security Tester

## 概述

本 Skill 是一个**大模型安全扫描测试工具**，用于金融场景下 LLM（Qwen3、GLM4 等）安全检测能力的并发测试与评估。

工具从 Excel 读取测试用例，通过多协程并发调用模型 API，对比模型响应与预期结果，验证安全防护提示词（与 `finance-ai-security-guardrail` 方法论配套）的有效性。

## 触发条件

满足以下任一条件时使用本 Skill：

- 需要测试 LLM 对**金融场景安全攻击**的识别能力（提示词注入、违规内容检测等）
- 需要对**多个模型**（Qwen3-8B/30B、GLM4 等）做**横向对比**
- 需要批量跑大量测试用例并**结构化输出**到 Excel
- 需要验证 `finance-ai-security-guardrail` 方法论中提示词的实际效果

## 工作流

```
┌──────────────────┐
│  准备 Excel 用例  │  ← 用户准备测试用例（提示词 + 预期结果）
└────────┬─────────┘
         ▼
┌──────────────────┐
│ 选择提示词配置    │  ← 从 prompts/ 选择对应模型的提示词
└────────┬─────────┘
         ▼
┌──────────────────┐
│ 配置 API 参数    │  ← 编辑 scripts/config.py 填入 API 信息
└────────┬─────────┘
         ▼
┌──────────────────┐
│ 启动并发测试      │  ← python main.py（NUM_WORKERS 协程）
└────────┬─────────┘
         ▼
┌──────────────────┐
│ 输出 Excel 结果  │  ← 响应写入 Excel，保存到 data/ 目录
└──────────────────┘
```

## 能力边界

**能做**：
- ✅ 批量并发调用模型 API（支持 httpx 异步和 requests 同步）
- ✅ 自动重试（HTTP 错误、网络异常）
- ✅ 结构化 JSON 响应解析
- ✅ Excel 输入/输出（使用 openpyxl 保留原格式）
- ✅ 彩色日志输出，便于调试
- ✅ 多模型支持（Qwen3-8B/30B、GLM4 等）

**不能做**：
- ❌ 不含安全检测能力本身（仅做测试，不做防护）
- ❌ 不支持流式响应（仅同步调用）
- ❌ 不做模型微调或训练
- ❌ 不做结果统计分析（需用户自行处理 data/ 目录的 Excel）

## 输入输出

### 输入
- **Excel 文件**（`scripts/test/` 或用户自定义路径）
  - 工作表：可配置
  - 提示词列：可配置（默认 C 列）
  - 数据起始行：可配置（默认第 2 行）

- **配置文件**（`scripts/config.py`）
  - `QWEN_API_URL`：API 地址
  - `QWEN_API_KEY`：API 密钥
  - `QWEN_MODEL_NAME`：模型名称
  - `NUM_WORKERS`：并发协程数
  - `INPUT_EXCEL_PATH`：输入 Excel 路径

### 输出
- **结果文件**：`data/{原文件名}_{结束时间}.xlsx`
  - 原始列 + 结果列（默认 D 列）：模型的 pass/reject 判定

- **日志文件**：`logs/qwen_test_{开始时间}.log`
  - 每次请求的提示词和响应内容

## 目录结构

```
finance-llm-security-tester/
├── SKILL.md                # 本文件（Skill 规范）
├── README.md               # 快速开始
├── LICENSE                 # Apache 2.0
├── .gitignore              # 忽略运行时数据
├── scripts/                # 主代码
│   ├── main.py             # 主程序
│   ├── config.py           # 配置文件
│   ├── qwen_client.py      # 模型客户端（httpx/requests）
│   ├── requirements.txt    # 依赖包
│   └── test/               # 测试用例
├── prompts/                # 16+ 个针对不同模型的提示词
│   ├── 定位问题的提示词.md
│   ├── 通用注入攻击检测提示词.md
│   ├── 通用注入攻击检测提示词_Qwen3-8B.v0.1.md ... v0.31.md
│   ├── 通用注入攻击检测提示词_Qwen3-30B.v0.1.md ... v0.12.md
│   └── 通用注入攻击检测提示词_GLM47_flash_new.md
├── references/             # 详细文档
│   └── 性能测试.md          # vLLM 部署与性能测试说明
└── templates/              # Excel 模板（占位）
```

## 配套关系

| Skill | 关系 |
|-------|------|
| `finance-ai-security-guardrail` | **本 Skill 是其配套测试工具**：用本工具跑 `finance-ai-security-guardrail` 中的提示词，验证实际效果 |
| `openclaw-security-hardening` | 独立的运维安全 Skill，与本 Skill 无直接关系 |

## 依赖

```
requests
httpx
openpyxl
```

## 快速开始

详见 [README.md](README.md)。
