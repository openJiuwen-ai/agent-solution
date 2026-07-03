# 金融安全护栏系统 - 工程介绍与使用说明

---

## 📋 文档目录

1. [项目概述](#1-项目概述)
2. [系统架构](#2-系统架构)
3. [技术栈](#3-技术栈)
4. [核心功能模块](#4-核心功能模块)
5. [快速开始](#5-快速开始)
6. [API 接口文档](#6-api-接口文档)
7. [配置管理](#7-配置管理)
8. [部署指南](#8-部署指南)
9. [运维监控](#9-运维监控)
10. [扩展开发](#10-扩展开发)

---

## 1. 项目概述

### 1.1 项目定位

**金融安全护栏系统** 是一个基于 FastAPI + LangChain + GuardRails AI 的智能体安全防护后端服务，专为银行金融应用提供多重安全防护机制。

### 1.2 核心价值

| 维度 | 说明 |
|------|------|
| **安全防护** | 七层安全检测，全面防护提示词注入、金融欺诈、数据隐私泄露等攻击 |
| **智能对话** | 基于 LangGraph 的 8 节点对话工作流，支持流式/非流式响应 |
| **实时监控** | 完整的安全统计和请求日志分析，含 Dashboard 数据面板 |
| **灵活配置** | 规则、配置、提示词均支持运行时动态更新，无需重启服务 |
| **本地化部署** | 完全开源技术栈，数据不出域，满足金融行业合规要求 |

---

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        前端界面 (Vue 3)                          │
│         static/index.html, app.js, style.css, favicon.svg        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FastAPI 服务层 (server.py)                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ CORS 中间件   │  │请求大小验证  │  │   异常处理器         │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              LangChainAgent (src/agent.py)                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  LangGraph 8节点工作流                                   │   │
│  │                                                          │   │
│  │  节点0: white_list_check      ──▶ 白名单放行（可选）     │   │
│  │              │ 匹配 → 跳过检测，直接 call_llm            │   │
│  │              │ 未匹配 → pii_input_check                  │   │
│  │              ▼                                           │   │
│  │  节点1: pii_input_check       ──▶ PII输入检测/脱敏       │   │
│  │              │ 拦截 → END                                │   │
│  │              │ 通过 → guardrails_check                   │   │
│  │              ▼                                           │   │
│  │  节点2: guardrails_check      ──▶ 正则黑名单匹配         │   │
│  │              │ 命中 → END                                │   │
│  │              │ 通过 → content_filter_check               │   │
│  │              ▼                                           │   │
│  │  节点3: content_filter_check  ──▶ Embedding内容过滤      │   │
│  │              │ 拦截 → END                                │   │
│  │              │ 通过 → llm_defense_check                  │   │
│  │              ▼                                           │   │
│  │  节点4: llm_defense_check     ──▶ LLM深度安全检测        │   │
│  │              │ 违规 → END                                │   │
│  │              │ 通过 → call_llm                           │   │
│  │              ▼                                           │   │
│  │  节点5: call_llm              ──▶ 调用大模型生成响应     │   │
│  │              ▼                                           │   │
│  │  节点6: content_filter_output_check ──▶ 输出内容过滤检测 │   │
│  │              │ 拦截 → END                                │   │
│  │              │ 通过 → pii_output_check                   │   │
│  │              ▼                                           │   │
│  │  节点7: pii_output_check      ──▶ PII输出检测/脱敏       │   │
│  │              └──────────────▶ END                        │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    数据库层 (SQLAlchemy + SQLite)                │
│  存储：请求日志、安全规则、PII配置、提示词防御、内容过滤锚点等      │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 项目目录结构

```
finance-guardrail/
├── config/                    # 配置模块
│   ├── __init__.py
│   └── config.py              # 系统配置、API密钥、安全规则
├── data/                      # 数据文件
│   ├── samples.json           # 测试用例
│   ├── zh_core_web_sm/        # spaCy 中文模型
│   └── en_core_web_sm/        # spaCy 英文模型
├── database/                  # 数据库模块
│   ├── __init__.py
│   ├── models.py              # SQLAlchemy 数据模型
│   ├── connection.py          # 数据库连接管理
│   └── crud.py                # CRUD 操作
├── src/                       # 核心源代码
│   ├── __init__.py
│   ├── agent.py               # LangChainAgent 核心类
│   ├── pii_detection.py       # PII 检测服务层
│   ├── classifier/            # 内容过滤分类器
│   └── validators/            # 验证器模块
├── static/                    # 前端静态文件
│   ├── index.html             # 主页面
│   ├── app.js                 # Vue.js 逻辑
│   └── style.css              # 样式文件
├── test/                      # 测试代码
│   ├── testcase.py            # 单元测试
│   ├── test_guardrails.py     # GuardRails 测试
│   └── test_pii.py            # PII 检测测试
├── server.py                  # FastAPI 主服务
├── requirements.txt           # Python 依赖
├── start.bat                  # Windows 启动脚本
└── README.md                  # 项目说明
```

---

## 3. 技术栈

### 3.1 核心依赖

| 分类 | 技术 | 版本 | 用途 |
|------|------|------|------|
| **Web 框架** | FastAPI | 0.135.3 | 高性能 API 服务 |
| **AI 框架** | LangChain | 1.2.17 | LLM 应用开发 |
| **工作流** | LangGraph | 1.1.10 | 多节点工作流编排 |
| **安全防护** | GuardRails AI | 0.10.0 | 提示词注入检测 |
| **PII 检测** | Presidio | 2.2.362 | 敏感信息识别 |
| **数据库** | SQLAlchemy | 2.0.49 | ORM 框架 |
| **异步驱动** | aiosqlite | 0.22.1 | SQLite 异步支持 |

### 3.2 关键技术特性

- **异步处理**：全异步架构，支持高并发请求
- **流式响应**：Server-Sent Events (SSE) 实现实时对话流
- **持久化存储**：SQLite 数据库 + AsyncSqliteSaver 对话记忆
- **热更新能力**：规则、配置、提示词均支持运行时动态更新

---

## 4. 核心功能模块

### 4.1 安全检测层

| 层级 | 名称 | 技术实现 | 检测内容 |
|------|------|---------|---------|
| 0 | 白名单放行 | 正则匹配 | 匹配规则直接跳过所有检测 |
| 1 | PII 输入检测 | Presidio | 身份证、银行卡、手机号等 |
| 2 | GuardRails | 正则黑名单 | 金融欺诈、数据隐私等关键词 |
| 3 | 内容过滤 | Embedding 相似度 | 仇恨、辱骂、色情、暴力等 |
| 4 | LLM 深度检测 | 安全提示词 | 语义级安全分析 |
| 5 | 内容过滤输出 | Embedding 相似度 | 输出内容有害检测 |
| 6 | PII 输出检测 | Presidio | 输出敏感信息脱敏/拦截 |

### 4.2 攻击类型识别

系统自动识别并记录以下攻击类型：

- `content_filter` - 有害内容触发
- `prompt_injection` - 提示词注入
- `financial_fraud` - 金融欺诈
- `data_privacy` - 数据隐私泄露
- `malicious_instructions` - 恶意指令
- `social_engineering` - 社会工程
- `pii_leak` - PII 信息泄露

### 4.3 对话记忆管理

使用 `langgraph.checkpoint.sqlite.aio.AsyncSqliteSaver` 实现对话持久化：

- 对话历史持久化到 SQLite 数据库
- 服务重启后对话历史不丢失
- 支持多对话并行（按 `conversation_id` 隔离）

---

## 5. 快速开始

### 5.1 环境要求

- Python 3.10+
- OpenAI API 密钥（或兼容的 API 服务）

### 5.2 安装步骤

#### 1. 克隆项目

```bash
cd finance-guardrail
```

#### 2. 创建虚拟环境

```bash
python -m venv venv
venv\Scripts\activate    # Windows
# source venv/bin/activate  # Linux/Mac
```

#### 3. 安装依赖

```bash
pip install -r requirements.txt
```

> **注意**：如果 `guardrails-ai==0.10.0` 安装失败，可先注释掉，安装完成后单独从 PyPI 下载 whl 文件安装。

#### 4. 配置环境变量

创建 `.env` 文件：

```env
OPENAI_API_KEY=your-api-key
OPENAI_BASE_URL=https://api.siliconflow.cn/v1/
OPENAI_MODEL=Qwen/Qwen3-8B
HOST=0.0.0.0
PORT=8000
DEBUG=False
```

#### 5. 启动服务

```bash
# 开发模式
uvicorn server:app --reload --host 0.0.0.0 --port 8000

# 或使用启动脚本
start.bat
```

#### 6. 访问应用

| 地址 | 说明 |
|------|------|
| http://localhost:8000/static/ | 前端界面 |
| http://localhost:8000/docs | API 文档 |
| http://localhost:8000/health | 健康检查 |

---

## 6. API 接口文档

### 6.1 主要接口

#### 6.1.1 聊天接口

**POST /chat** - 非流式聊天

请求体：
```json
{
    "message": "查询我的账户余额",
    "conversation_id": "default"
}
```

响应体：
```json
{
    "response": "您好，已为您查询到账户余额...",
    "is_blocked": false,
    "detect_reason": "",
    "detected_by": null,
    "violated_rules": [],
    "conversation_id": "default",
    "timestamp": "2024-01-01T12:00:00"
}
```

#### 6.1.2 流式聊天

**POST /chat/stream** - SSE 流式聊天

请求体：
```json
{
    "message": "介绍一下理财产品",
    "conversation_id": "stream-test"
}
```

响应类型：`text/event-stream`

#### 6.1.3 健康检查

**GET /health**

响应：
```json
{
    "status": "healthy",
    "timestamp": "2024-01-01T12:00:00",
    "agent_status": "initialized"
}
```

#### 6.1.4 统计数据

**GET /statistics**

响应：
```json
{
    "total_requests": 1000,
    "blocked_requests": 50,
    "attack_requests": 30,
    "safety_rate": 0.95,
    "timestamp": "2024-01-01T12:00:00"
}
```

### 6.2 规则管理接口

#### 6.2.1 获取所有规则

**GET /guardrails/rules**

响应：
```json
{
    "default_rules": [...],
    "custom_rules": [...],
    "custom_file_path": "database"
}
```

#### 6.2.2 添加/更新规则

**POST /guardrails/rules/{rule_name}**

请求体：
```json
{
    "patterns": ["伪造.*流水", "洗钱.*资金"],
    "description": "金融欺诈检测",
    "is_new": true
}
```

#### 6.2.3 删除规则

**DELETE /guardrails/rules/{rule_name}**

### 6.3 PII 检测接口

#### 6.3.1 PII 检测

**POST /pii/detect**

请求体：
```json
{
    "text": "我的身份证是110101199001011234",
    "entity_types": ["all"]
}
```

响应：
```json
{
    "has_pii": true,
    "total_count": 1,
    "entity_counts": {"CN_ID_CARD": 1},
    "entities": [
        {
            "type": "CN_ID_CARD",
            "text": "110101********1234",
            "position": [0, 18],
            "score": 0.95
        }
    ]
}
```

#### 6.3.2 PII 匿名化

**POST /pii/anonymize**

请求体：
```json
{
    "text": "联系电话：13800138000"
}
```

响应：
```json
{
    "original_text": "联系电话：13800138000",
    "anonymized_text": "联系电话：<PHONE_NUMBER>",
    "has_pii": true,
    "entity_counts": {"CN_PHONE": 1}
}
```

### 6.4 Dashboard 接口

#### 6.4.1 安全统计

**GET /dashboard/statistics?period=24h**

响应：
```json
{
    "total_requests": 1000,
    "blocked_requests": 50,
    "attack_requests": 30,
    "safety_rate": 0.95,
    "period": "24h"
}
```

#### 6.4.2 攻击类型分布

**GET /dashboard/attack-types?period=7d**

#### 6.4.3 时间趋势

**GET /dashboard/trends?period=30d**

---

## 7. 配置管理

### 7.1 配置文件结构

配置主要存储在以下位置：

| 位置 | 内容 | 说明 |
|------|------|------|
| `config/config.py` | 系统默认配置 | 代码层面的默认值 |
| SQLite 数据库 | 运行时配置 | 可通过 API 动态修改 |
| `.env` | 环境变量 | API 密钥等敏感信息 |

### 7.2 PII 检测配置

PII 检测支持输入和输出独立配置：

| 配置项 | 说明 | 可选值 |
|--------|------|--------|
| `input_enabled` / `output_enabled` | 是否启用检测 | `True` / `False` |
| `input_entities` / `output_entities` | 检测的实体类型 | 见 `PII_ENTITY_OPTIONS` |
| `input_action_mode` / `output_action_mode` | 检测模式 | `detect` / `block` |

### 7.3 内容过滤配置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `input_enabled` | 输入检测开关 | `True` |
| `output_enabled` | 输出检测开关 | `True` |
| `action_mode` | 处理模式 | `detect` |

### 7.4 安全规则配置

系统默认规则包含 6 类安全规则：

| 规则名 | 检测内容 |
|--------|---------|
| 金融欺诈 | 伪造流水、洗钱、规避审核 |
| 数据隐私 | 查询他人身份证、银行卡 |
| 恶意指令 | 删除文件、病毒、攻击 |
| 社会工程 | 紧急转账、立即认证 |
| 违法欺诈 | 包装资料、骗贷、假公章 |
| 非法征信干预 | 征信修复、铲单、洗白 |

---

## 8. 部署指南

### 8.1 开发环境

```bash
# 安装依赖
pip install -r requirements.txt

# 设置环境变量
set OPENAI_API_KEY=your-key

# 启动服务
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

### 8.2 生产环境

#### 8.2.1 环境配置

```bash
# 设置生产环境变量
set OPENAI_API_KEY=your-production-key
set DEBUG=False
set RELOAD=False
```

#### 8.2.2 使用 Gunicorn

```bash
# 安装 Gunicorn
pip install gunicorn

# 启动服务
gunicorn -w 4 -k uvicorn.workers.UvicornWorker server:app
```

#### 8.2.3 启用 HTTPS

```bash
uvicorn server:app --host 0.0.0.0 --port 443 \
    --ssl-keyfile=key.pem --ssl-certfile=cert.pem
```

### 8.3 Docker 部署（可选）

创建 `Dockerfile`：

```dockerfile
FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
```

构建并运行：

```bash
docker build -t finance-guardrail .
docker run -p 8000:8000 finance-guardrail
```

---

## 9. 运维监控

### 9.1 日志管理

日志输出到 `logs/agent_service.log`：

```
2024-01-01 10:30:45 - agent_service - INFO - Agent initialized successfully
2024-01-01 10:31:20 - security - WARNING - Security violation detected: prompt_injection
2024-01-01 10:32:15 - agent_service - INFO - LLM response generated
```

### 9.2 关键监控指标

| 指标 | 说明 |
|------|------|
| 请求成功率 | 成功响应的请求占比 |
| 安全拦截率 | 被安全检测拦截的请求占比 |
| 平均响应时间 | 接口响应耗时 |
| 各拦截层命中率 | 各安全检测层的触发次数 |

### 9.3 故障排除

#### 常见问题

| 问题 | 排查方法 |
|------|---------|
| 服务无法启动 | 检查 Python 版本、依赖安装、端口占用 |
| OpenAI API 错误 | 验证 API 密钥、网络连接、账户余额 |
| PII 检测不可用 | 确认 Presidio 和 spaCy 模型已安装 |
| 内容过滤不可用 | 检查 Embedding API 配置 |

#### 调试模式

```bash
set DEBUG=True
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

---

## 10. 扩展开发

### 10.1 添加新的安全规则

1. 在 `config/config.py` 的 `GUARDRAILS_DEFAULT_RULES` 中添加规则定义
2. 或通过 API `POST /guardrails/rules/{rule_name}` 动态添加
3. 规则会自动热加载到 Agent

### 10.2 扩展 PII 检测实体

1. 在 `config/config.py` 的 `PII_ENTITY_OPTIONS` 中添加新实体
2. 在 `src/validators/pii_validator.py` 中注册实体识别器
3. 更新前端配置界面

### 10.3 添加新的内容过滤类别

1. 在 `src/classifier/categories.py` 中添加类别定义
2. 通过 API `POST /content_filter/categories` 添加
3. 调用 `POST /content_filter/revectorize` 重新向量化

### 10.4 测试扩展

```bash
# 运行所有测试
python -m pytest test/ -v

# 运行特定测试
python -m pytest test/test_guardrails.py -v
```

---

## 📞 技术支持

如有问题，请参考以下资源：

- 项目文档：`docs/` 目录
- API 文档：`http://localhost:8000/docs`
- 测试用例：`test/` 目录

---

**文档版本**: v1.0  
**生成时间**: 2026年  
**项目地址**: `<your-project-path>/finance-guardrail`