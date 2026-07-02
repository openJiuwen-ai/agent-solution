# OPTIMIZATION-v8 — v7 → v8 优化说明

> v8.07 版本 | 2026-05-15

---

## 一、v7 发现的问题

v7 在代码重构时引入 **4 个语法错误**，导致 4 个核心脚本无法运行：

### 🔴 致命：语法错误（4 个脚本）

| 脚本 | 问题 | 根因 |
|------|------|------|
| `container-post-validate.sh` | 函数定义缺失闭合括号 | `}fe_node_read() {` 残留 |
| `container-pre-post-diff.sh` | 死代码导致语法错误 | 同上 |
| `container-report.sh` | 死代码导致语法错误 | 同上 |
| `container-restore-validate.sh` | 死代码 + 调用参数错误 | 同上 + 调用仍用旧 JS 代码格式 |

**根因分析**：v7 将 `safe_node_read` 重命名为 `safe_node_get` 时，在 4 个脚本中，新函数的闭合括号 `}` 与旧函数名的首字母残留拼接成了 `}fe_node_read() {`，导致：
1. `safe_node_get()` 函数缺少闭合括号 `}` → 后续代码被吞入函数体内
2. `fe_node_read()` 不是有效的函数名（`safe_` 前缀被截断）→ 语法错误

**影响**：v7 **完全不可部署**，4 个核心脚本（后验证、前后对比、最终报告、恢复验证）全部崩溃。

### 🔴 严重：调用参数不匹配

`container-restore-validate.sh` 中 `safe_node_get` 调用仍使用旧格式：
```bash
safe_node_get "$file" "console.log((c.gateway?.auth?.token || '').length || 0)"
```
但新的 `safe_node_get` 期望的是键路径：
```bash
safe_node_get "$file" "gateway.auth.token"
```
即使语法修复，返回值也会为空。

### 🟡 性能：health-check.sh JSON 解析慢

v7 的 health-check.sh 在输出阶段对每个检查项调用 3 次 `node -e` 解析 JSON，10 项检查就是 30 次 node 启动，总耗时约 5-10 秒。使用 `jq` 只需 <0.5 秒。

---

## 二、v8 修复内容

### ✅ 修复 4 个脚本的语法错误

**方法**：将 `}fe_node_read() {` 替换为单纯的 `}`（保留 `safe_node_get()` 的闭合括号），删除残留的 `fe_node_read()` 函数体。

```diff
- }fe_node_read() {
-   node -e "..." "$1"
- }
+ }
```

**结果**：4 个脚本全部通过 `bash -n` 语法检查。

### ✅ 修正 `safe_node_get` 调用参数

`container-restore-validate.sh` 中 4 处调用全部更新：

```diff
- BACKUP_TOKEN=$(safe_node_get "$file" "console.log((c.gateway?.auth?.token || c.gateway?.token || '').length || 0)")
+ BACKUP_TOKEN_VAL=$(safe_node_get "$file" "gateway.auth.token")
+ if [[ -z "$BACKUP_TOKEN_VAL" ]]; then
+   BACKUP_TOKEN_VAL=$(safe_node_get "$file" "gateway.token")
+ fi
+ BACKUP_TOKEN_LEN=${#BACKUP_TOKEN_VAL}
```

**改进**：
- 先查新结构 `gateway.auth.token`，为空时回退到旧结构 `gateway.token`
- 使用 bash `${#var}` 获取字符串长度，不再依赖 JS 代码

### ✅ health-check.sh 性能优化

**v7**：纯 node 解析，每项检查 3 次 node 启动
**v8**：优先使用 `jq`（快 10x+），无 jq 时自动回退 node

```bash
json_val() {
  if command -v jq &>/dev/null; then
    jq -r ".gateway.auth.token // empty" "$file" 2>/dev/null
  else
    node -e "..." "$file" "gateway.auth.token"
  fi
}
```

### ✅ health-check.sh 功能增强

| 版本 | 检查项 | 说明 |
|------|--------|------|
| v7 | 8 项 | 基础健康检查 |
| v8 | **10 项** | 新增 Gateway HTTP 可达性 + 进程运行时长 |

新增项：
- **#9 Gateway HTTP**：`curl -sf --connect-timeout 3 http://127.0.0.1:${PORT}/` 探测
- **#10 进程运行时长**：通过 `/proc/$PID` 获取启动时间

---

## 三、v8 完整状态

### 脚本语法检查

| 脚本 | v7 状态 | v8 状态 |
|------|---------|---------|
| `rocky-prereq-check.sh` | ✅ | ✅ |
| `container-rocky-audit.sh` | ✅ | ✅ |
| `container-rocky-harden.sh` | ✅ | ✅ |
| `container-post-validate.sh` | ❌ 语法错误 | ✅ **已修复** |
| `container-pre-post-diff.sh` | ❌ 语法错误 | ✅ **已修复** |
| `container-report.sh` | ❌ 语法错误 | ✅ **已修复** |
| `container-rocky-restore.sh` | ✅ | ✅ |
| `container-restore-validate.sh` | ❌ 语法错误+参数错误 | ✅ **已修复** |
| `file-integrity.sh` | ✅ | ✅ |
| `file-perms.sh` | ✅ | ✅ |
| `health-check.sh` | ✅ 8项/node | ✅ **10项/jq优先** |

### 文档

| 文档 | 版本 | 说明 |
|------|------|------|
| `CHANGELOG.md` | v8 | 新增 v8 变更记录 |
| `OPTIMIZATION-v8.md` | v8 | **新增**：v7→v8 优化说明 |
| `README.md` | 更新 | 版本号、文件名更新为 v8 |
| `SKILL.md` | 更新 | 新增 health-check.sh 说明 |
| `DEPLOY-GUIDE.md` | 更新 | 路径更新为 v8 |
| `PRODUCT-OVERVIEW.md` | 更新 | 标题版本修正为 v8 |
| `PLAN.md` | 不变 | 加固项清单无变化 |
| `ASSESSMENT.md` | 更新 | 评估结论更新 |

---

## 四、使用建议

### 部署前验证

```bash
cd openclaw-security-container-rocky-v8
for f in scripts/*.sh; do
  bash -n "$f" && echo "✅ $f" || echo "❌ $f"
done
```

**预期**：11/11 全部通过。

### 日常健康检查（推荐）

```bash
# 快速巡检
bash scripts/health-check.sh

# 导出 JSON 用于自动化监控
bash scripts/health-check.sh --json > health-$(date +%Y%m%d).json

# 指定路径
bash scripts/health-check.sh --path /path/to/openclaw
```

---

## 五、v8 已知限制

| 限制 | 说明 | 优先级 |
|------|------|--------|
| 无 Windows 支持 | 仍仅面向 Linux 发行版 | 中 |
| 无镜像扫描 | 未集成 Trivy 等镜像 CVE 扫描 | 低 |
| 无远程编排 | 不支持批量管理多台机器 | 低 |
| 无 Web UI | 纯 CLI 工具，无可视化界面 | 低 |

---

*v8 由 Rocky Linux OpenClaw 🦫 基于 v7 修复和优化，确保可部署、可运行、可维护。*
