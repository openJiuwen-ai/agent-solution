# 脱敏说明（Redaction）

本包为对外阉割版。下列文件与内部完整版 **故意保持一致**（仅 BCCP 输入模板、
契约 Schema 与共用脚本），不含 system prompt、Few-shot 案例库或内部 API 文档。
差分审计时请跳过以下路径。

## shared_files

- `REDACTION.md`
- `assets/empty-bccp.json`
- `assets/empty-bccp.yaml`
- `assets/empty-chat-grid.csv`
- `assets/empty-chat-grid.xlsx`
- `assets/empty-chat-template.md`
- `assets/sample-bccp.json`
- `assets/sample-bccp.yaml`
- `assets/sample-chat-grid.csv`
- `assets/sample-chat-grid.xlsx`
- `assets/sample-chat-template.md`
- `references/chat-export-template.csv`
- `references/config.example.env`
- `references/input-schema-v1.json`
- `references/output-schema-v1.json`
- `references/sample-bccp-minimal.json`
- `references/shared-files.json`
- `scripts/bccp_from_csv.py`
- `scripts/submit_parse.py`
- `scripts/validate_bccp.py`

## 路径映射（完整版）

| 阉割版 | 完整版 |
|--------|--------|
| `SKILL.md` | `SKILL.external.md` |

