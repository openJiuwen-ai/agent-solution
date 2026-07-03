# 相似问质检 — Query 意图匹配判定

## 适用场景

手机银行（及同类金融 App）**相似问数据质检**流程中的一环：对「用户语句（query）+ 标注意图（intent）」样本，借助大模型判断 query 的语义是否与该意图的菜单描述一致，用于发现错标、漏标或歧义样本。

典型用途：

- 相似问扩充后的批量质检
- 意图标注数据验收
- 训练/评测集清洗

## 目录结构

```
similar-query-qc/
├── README.md
├── requirements.txt
├── scripts/
│   └── evaluate_query_intent_match.py
├── references/
│   ├── intent_match_prompt.txt   # LLM prompt template
│   ├── menu_desc.xlsx              # Intent name and description mapping
│   └── input_samples.xlsx          # Input sample data
└── output/                         # Runtime artifacts (gitignored)
    └── evaluation_results.xlsx
```

## 输入

### 1. `references/input_samples.xlsx`

| 列名 | 说明 |
|------|------|
| `query` | 待判定的用户语句 |
| `intent` | 标注的意图名称，须与 `menu_desc.xlsx` 中 `intent_name` 一致 |

### 2. `references/menu_desc.xlsx`

| 列名 | 说明 |
|------|------|
| `intent_name` | 意图标识 |
| `intent_desc` | 意图对应的菜单/功能描述，供 LLM 比对语义 |

## 输出

`output/evaluation_results.xlsx`：

| 列名 | 说明 |
|------|------|
| `query` | 输入语句 |
| `intent` | 输入意图 |
| `result` | `1` 匹配 / `0` 不匹配 / `-1` 无法判定 |
| `reason` | 判定依据（≤50 字） |

## 使用方式

```bash
cd finance/methodology/similar-query-qc
pip install -r requirements.txt

# 配置 LLM（示例：智谱 OpenAI 兼容接口）
export LLM_API_KEY="your-api-key"
# 可选：export LLM_MODEL="glm-5.1"
# 可选：export LLM_API_BASE="https://open.bigmodel.cn/api/paas/v4/"

python scripts/evaluate_query_intent_match.py
```

将待判定数据放入 `references/input_samples.xlsx`（或替换为自有文件并修改脚本中的 `INPUT_FILE`），运行后查看 `output/evaluation_results.xlsx`。

## 判定规则

脚本内置 Prompt，由 LLM 按以下标准输出：

1. **1**：用户语句与意图描述高度一致，明确表达执行该功能的意图
2. **0**：语义明显属于其他意图或与意图描述无关
3. **-1**：存在歧义、指代不明或信息不足，无法确认

## 限制与注意

- 依赖外部 LLM API，需自行配置 `LLM_API_KEY`；调用产生费用与延迟
- `intent` 不在 `menu_desc.xlsx` 中的行会被跳过
- 默认 8 线程并发，可在脚本中调整 `max_workers`
- 输出为辅助质检参考，**不能替代人工复核**；涉及合规场景须按机构内规范二次确认
- 本工具不处理个人隐私脱敏，提交 LLM 前请按数据分级要求处理

## 在相似问质检流程中的位置

本脚本负责 **单条 query–intent 语义匹配判定**；可与同目录下其他质检脚本（如有）组合使用，形成「规则过滤 → LLM 判定 → 人工抽检」流水线。
