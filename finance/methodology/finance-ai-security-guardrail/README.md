# 金融 AI 应用安全防护体系方法论

## 适用场景

为面向客户的金融 AI 智能体（如银行客服、理财顾问、信贷助手）构建多层安全防护体系，抵御提示词注入、金融欺诈、数据隐私泄露、社会工程攻击。

## 核心方法：六层防御漏斗

```
用户输入
  │
  ▼ [第0层] 白名单放行 ──── 匹配 → 快速响应
  │ 未匹配
  ▼ [第1层] PII 输入检测 ── 拦截 → 告警
  │ 通过           │
  ▼ [第2层] 正则黑名单 ─── 拦截 → 告警
  │ 通过
  ▼ [第3层] Embedding    ── 拦截 → 告警
  │      内容过滤
  │ 通过
  ▼ [第4层] LLM 深度检测 ── 拦截 → 告警
  │ 通过
  ▼ [第5层] 正常生成响应
  │
  ▼ [第6层] PII 输出检测 ── 脱敏后返回
```

**每层独立可配置、可降级，按需裁剪层数平衡安全与延迟。**

## 关键设计决策

### 决策 1：检测粒度与延迟的权衡

| 场景 | 建议层数 | 原因 |
|------|---------|------|
| 高安全（对客信贷审批助手） | 全 6 层 | 合规要求覆盖全面 |
| 中安全（理财咨询机器人） | 4 层（跳过白名单+LLM深度） | 响应快且防护够用 |
| 低延迟（实时风控查询） | 2 层（白名单+正则） | 毫秒级响应 |

### 决策 2：拦截 vs. 脱敏

| 模式 | 适用 | 说明 |
|------|------|------|
| `block` | PII 实体命中即拦截 | 合规严格场景 |
| `detect` | 检测后自动脱敏，请求继续 | 客户体验优先 |

### 决策 3：本地化 vs. 云端

| 方案 | 适用 |
|------|------|
| **本地（本项目）** | 数据不出域，金融合规必须 |
| AWS Bedrock / Azure | 已在对应云平台，运维成本低 |
| Llama Guard | 有 GPU 资源，需要离线 LLM 检测 |

详细对比见 [references/PROJECT_DOCUMENTATION.md](references/PROJECT_DOCUMENTATION.md)

## 参考实现

`scripts/` 目录包含完整可运行实现：

- **技术栈**：FastAPI + LangChain + LangGraph + GuardRails AI + Presidio
- **LLM**：Qwen3-8B（兼容任意 OpenAI API）
- **语言**：Python 3.10+

### 快速启动

```bash
cd scripts
pip install -r requirements.txt
# 复制 .env.example 到上级目录的 .env 并填入 API Key
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

访问 `http://localhost:8000/static/` 查看演示界面。

## 文件说明

| 路径 | 内容 |
|------|------|
| `scripts/` | 完整参考实现代码 |
| `references/project-readme.md` | 原项目详细 README |
| `references/PROJECT_DOCUMENTATION.md` | 工程文档（API 接口、部署指南） |
| `references/.env.example` | 环境变量模板 |

## 能力边界

- **不是** WAF/网络层防火墙，不防御 DDoS、SQL 注入等网络攻击
- **不保证** 100% 拦截零误判，正则和 Embedding 检测存在模糊边界
- **需要** OpenAI API（或兼容接口）支持 LLM 深度检测层
- **中文 PII** 依赖 Presidio + spaCy 中文模型，覆盖率有限，需按业务补充
