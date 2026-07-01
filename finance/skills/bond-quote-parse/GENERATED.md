# 自动生成目录

本目录由 `scripts/sync_skills.py` 从 `bond-quote-parse-full/` 派生，**请勿手改**。

- 改对外 Skill 说明：编辑 `bond-quote-parse-full/SKILL.external.md` 后执行 `python scripts/sync_skills.py`
- 改共用脚本/模板/契约：在 `bond-quote-parse-full/` 修改后同步
- 改提示词/Few-shot：改 `backend/systems/bond_quote/assets/` 后同步

```bash
python scripts/sync_skills.py
```
