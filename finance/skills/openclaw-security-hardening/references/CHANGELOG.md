# CHANGELOG — OpenClaw 安全加固工具包

### v8.07 (2026-05-15)

Windows OpenClaw 审查修复版本。

**修复内容：**
- 🐛 `container-rocky-audit.sh` — JSON 空值兜底：bind_address / config_permissions / dir_permissions 从 `""` 改为 `"N/A"`
- 🐛 `container-pre-post-diff.sh` — POST_SCORE 算术保护：增加 `=~ ^[0-9]+$` 正则校验，防止空字符串/非数字导致 crash
- 🐛 `file-integrity.sh` — 版本号更新为 8.07

---

### v8.06 (2026-05-15)
- `gateway.bind` 从 `127.0.0.1` 改为 `loopback`
- `container-post-validate.sh` 删除重复 set 命令
- `file-integrity.sh` broken pipe 修复（while|node → 临时文件）
- 空值规范化兜底（PRE_/POST_ 变量）

### v8 (2026-05-15)
- 语法修复、类型匹配、jq 优先降级、健康检查增强
