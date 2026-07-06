# Similar Query QC — 相似问质检

本目录提供手机银行（及同类金融 App）**相似问数据质检**方法论工具，覆盖入库前去重与意图匹配判定等环节。

## 工具列表

| 脚本 | 用途 |
|------|------|
| `scripts/deduplicate_similar_questions.py` | 同一意图下相似问 TF-IDF 聚类去重 |
| `scripts/evaluate_query_intent_match.py` | LLM 判定 query 与 intent 是否语义匹配 |

典型流水线：**去重 → 意图匹配判定 → 人工抽检**

## 目录结构

```
similar-query-qc/
├── README.md
├── requirements.txt
├── scripts/
│   ├── deduplicate_similar_questions.py
│   └── evaluate_query_intent_match.py
├── references/
│   ├── intent_match_prompt.txt      # LLM prompt template
│   ├── menu_desc.xlsx               # Intent descriptions (for evaluation)
│   ├── input_samples.xlsx           # Intent-match input sample
│   └── similar_questions_raw.xlsx   # Dedup input sample
└── output/                          # Runtime artifacts (gitignored)
    ├── evaluation_results.xlsx
    └── similar_questions_deduped.xlsx
```

---

## 1. 相似问去重 (`deduplicate_similar_questions.py`)

### 适用场景

相似问扩充后、**入库前**对同一意图下的问法进行去重，合并语义高度相近的条目。

### 输入 — `references/similar_questions_raw.xlsx`

| 列名 | 说明 |
|------|------|
| `intent_name` | 意图标识 |
| `similar_query` | 待入库的相似问 |

### 输出 — `output/similar_questions_deduped.xlsx`

| 列名 | 说明 |
|------|------|
| `intent_name` | 意图标识 |
| `similar_query` | 去重后保留的代表问法 |

### 使用方式

```bash
cd finance/methodology/similar-query-qc
pip install -r requirements.txt
python scripts/deduplicate_similar_questions.py
```

### 配置

在脚本顶部常量中可调整：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `DEFAULT_SIMILARITY_THRESHOLD` | `0.85` | 相似度阈值（0.80 激进 / 0.85 适中 / 0.90 保守） |
| `DEFAULT_STRATEGY` | `centroid` | 代表选取策略：`centroid` / `longest` / `most_similar` |

---

## 2. 意图匹配判定 (`evaluate_query_intent_match.py`)

### 适用场景

对「用户语句（query）+ 标注意图（intent）」样本，借助大模型判断 query 的语义是否与该意图的菜单描述一致，用于发现错标、漏标或歧义样本。

### 输入

**`references/input_samples.xlsx`**

| 列名 | 说明 |
|------|------|
| `query` | 待判定的用户语句 |
| `intent` | 标注的意图名称，须与 `menu_desc.xlsx` 中 `intent_name` 一致 |

**`references/menu_desc.xlsx`**

| 列名 | 说明 |
|------|------|
| `intent_name` | 意图标识 |
| `intent_desc` | 意图对应的菜单/功能描述 |

### 输出 — `output/evaluation_results.xlsx`

| 列名 | 说明 |
|------|------|
| `query` | 输入语句 |
| `intent` | 输入意图 |
| `result` | `1` 匹配 / `0` 不匹配 / `-1` 无法判定 |
| `reason` | 判定依据（≤50 字） |

### 使用方式

```bash
export LLM_API_KEY="your-api-key"
# 可选：export LLM_MODEL="glm-5.1"
# 可选：export LLM_API_BASE="https://open.bigmodel.cn/api/paas/v4/"

python scripts/evaluate_query_intent_match.py
```

### 判定规则

1. **1**：用户语句与意图描述高度一致，明确表达执行该功能的意图
2. **0**：语义明显属于其他意图或与意图描述无关
3. **-1**：存在歧义、指代不明或信息不足，无法确认

---

## 限制与注意

- 去重脚本基于字符级 TF-IDF + 层次聚类，对轻微改写可能不敏感，阈值需按业务调优
- 意图匹配脚本依赖外部 LLM API，需配置 `LLM_API_KEY`；调用产生费用与延迟
- 输出为辅助质检参考，**不能替代人工复核**
- 提交 LLM 前请按数据分级要求处理隐私脱敏
