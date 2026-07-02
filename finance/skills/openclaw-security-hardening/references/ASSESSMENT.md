# ASSESSMENT — v7 工具包评估报告

> 评估日期：2026-05-15  
> 评估对象：`openclaw-security-container-rocky-v7`  
> 评估结论：**v7 有严重语法错误，修复后升级为 v8**

---

## v7 正面评价

### ✅ 成功的改进

| # | 改进项 | 效果 |
|---|--------|------|
| 1 | `safe_node_read` → `safe_node_get`（harden.sh, audit.sh） | 消除 shell 变量注入风险 |
| 2 | 备份 SHA256 完整性校验 | 备份文件可验证完整性 |
| 3 | 恢复前 SHA256 验证 | 防止恢复损坏的备份 |
| 4 | 备份保留策略（保留 5 个） | 防止磁盘占满 |
| 5 | 新增 health-check.sh | 8 项快速巡检 |
| 6 | 新增 DEPLOY-GUIDE.md | 部署文档完整 |
| 7 | 新增 PRODUCT-OVERVIEW.md | 产品说明清晰 |
| 8 | Gateway HTTP 健康检查 | post-validate 新增 curl 检查 |

---

## v7 严重缺陷（v8 修复内容）

### 🔴 致命：4 个脚本语法错误

| # | 脚本 | 问题 | 影响 |
|---|------|------|------|
| 1 | `container-post-validate.sh` | `}fe_node_read() {` 残留，`safe_node_get()` 缺失闭合括号 | 脚本无法执行 |
| 2 | `container-pre-post-diff.sh` | 同上 | 脚本无法执行 |
| 3 | `container-report.sh` | 同上 | 脚本无法执行 |
| 4 | `container-restore-validate.sh` | 同上 + 调用参数不匹配 | 脚本无法执行 |

**v7 状态：不可部署。4 个核心脚本（后验证、前后对比、报告、恢复验证）全部崩溃。**

### 🔴 严重：`safe_node_get` 调用参数错误

`container-restore-validate.sh` 中 4 处调用仍使用旧 JS 代码格式：
```bash
safe_node_get "$file" "console.log((c.gateway?.auth?.token || '').length || 0)"
```
但新函数期望键路径：`"gateway.auth.token"`。

### 🟡 性能：health-check.sh 解析慢

每项检查调用 3 次 `node -e` 解析 JSON，10 项共 30 次启动，耗时 5-10 秒。

---

## 结论

v7 的方向是正确的，增加了实用的备份安全和文档体系。但**代码重构时操作失误，导致 4 个核心脚本全部有语法错误**。

**v8 = v7 的代码 + 4 个脚本语法修复 + 调用参数修正 + health-check.sh 性能优化和功能增强**，形成完整可部署版本。
