# 债券群聊报价 — 语料填写模板（空白）

## 列说明

- **message_id**：可选，客户端稳定 ID
- **corpus_id**：必填，群内语料序号（整数，从 0 或 1 起）
- **corpus_type**：必填：报价 或 小广告（发行广告放小广告，且时间早于报价）
- **speaker_id**：报价行必填，发言人 ID
- **speaker_name**：可选，发言人昵称
- **institution_name**：可选，机构名称
- **speak_time**：必填，格式 YYYY-MM-DD HH:MM:SS
- **raw_content**：必填，聊天原文

## 表格（可复制到 Excel 或按列粘贴）

| message_id | corpus_id | corpus_type | speaker_id | speaker_name | institution_name | speak_time | raw_content |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |

填好后：上传 xlsx/csv，或整理为 JSON/YAML（BCCP）后提交解析。