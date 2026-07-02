# EXECUTION-GUIDE — 加固执行步骤说明

> v6 版本 | 2026-05-14

---

## 完整执行流程

```
┌─────────────────────────────────────────────────────────────┐
│                    加固完整生命周期                           │
│                                                             │
│  ① 前置检查 → ② 预评估 → ③ 加固 → ④ 后验证                  │
│       ↓                    ↓         ↓         ↓            │
│   环境就绪            采集基线    应用加固    验证效果         │
│                                                             │
│  ⑤ 对比报告 → ⑥ 最终报告 → ⑦ [可选] 恢复                      │
│       ↓                    ↓                    ↓           │
│   前后对比           评分+矩阵           恢复到加固前          │
└─────────────────────────────────────────────────────────────┘
```

---

## 步骤 1：前置检查

```bash
bash scripts/rocky-prereq-check.sh
```

**功能：**
- 检测操作系统（Rocky/Debian/Ubuntu/Alpine）
- 检查必要的命令（bash, node, openssl）
- 检查容器运行环境（容器内 vs 宿主机）
- 检查磁盘空间（至少 50MB 用于备份）
- 检查当前用户权限

**输出：** 检查清单，每项 ✅ 或 ❌

---

## 步骤 2：预评估

```bash
bash scripts/container-rocky-audit.sh \
  --output /path/to/reports/ \
  --level 3 \
  --path /root/.openclaw
```

**功能：**
- 采集系统信息（OS、内核、容器引擎）
- 采集 OpenClaw 配置和运行状态
- 采集文件权限快照
- 计算安全评分（0-100）

**输出文件：**
- `reports/pre-assessment-YYYYMMDD-HHMMSS.json` — 结构化数据
- `reports/pre-assessment-YYYYMMDD-HHMMSS.md` — 人类可读报告

---

## 步骤 3：加固执行

```bash
bash scripts/container-rocky-harden.sh \
  --level 3 \
  --report-dir /path/to/reports/ \
  [--skip-ssh] \
  [--dry-run] \
  [--path /root/.openclaw]
```

**参数：**

| 参数 | 说明 |
|------|------|
| `--level N` | 安全等级（1-5），决定加固范围 |
| `--report-dir` | 报告输出目录 |
| `--skip-ssh` | 跳过 SSH 配置修改（容器环境推荐） |
| `--dry-run` | 只输出计划执行的操作，不实际修改 |
| `--path` | OpenClaw 安装路径 |

**执行流程：**
1. 自动备份当前配置（到 `reports/backups/`）
2. 按等级执行加固项
3. 记录每项执行结果（成功/失败/跳过）
4. 写入状态文件供后续脚本使用

**进度指示：**
```
[ 1/10] ✅ Backing up current configuration...
[ 2/10] ✅ Rotating OpenClaw API Token...
[ 3/10] ⏭️  SSH configuration (skipped via --skip-ssh)
[ 4/10] ✅ Hardening OpenClaw config...
...
```

---

## 步骤 4：加固后验证

```bash
bash scripts/container-post-validate.sh \
  --report-dir /path/to/reports/ \
  --state-file /path/to/reports/harden-state-*.json
```

**验证项：**
- ✅ OpenClaw Gateway 进程是否运行
- ✅ Gateway 端口是否监听
- ✅ Gateway API 是否可达
- ✅ SSH 配置（如果加固了 SSH）
- ✅ 文件权限
- ✅ 系统参数
- ✅ 容器安全配置

**输出：** `reports/post-validation-YYYYMMDD-HHMMSS.json`

---

## 步骤 5：前后对比

```bash
bash scripts/container-pre-post-diff.sh \
  --report-dir /path/to/reports/
```

**功能：**
- 读取预评估报告和后验证报告
- 逐项对比变化
- 计算评分变化

**输出：** `reports/diff-report-YYYYMMDD-HHMMSS.md`

---

## 步骤 6：生成最终报告

```bash
bash scripts/container-report.sh \
  --report-dir /path/to/reports/
```

**内容：**
- 加固前/后安全评分
- 加固项状态矩阵
- 详细变更列表
- 建议和注意事项

**输出：** `reports/final-report-YYYYMMDD-HHMMSS.md`

---

## 步骤 7（可选）：恢复

```bash
bash scripts/container-rocky-restore.sh \
  --backup-dir /path/to/reports/backups/
```

**交互式菜单：**
```
可用的备份文件:
  [1] pre-harden-20260514-175000.tgz

选择恢复类型:
  [1] 全量恢复
  [2] 仅 SSH 配置
  [3] 仅 OpenClaw 配置
  [4] 仅系统参数
  [5] 自定义选择

请输入 YES 确认: _
```

**确认后执行，然后自动调用恢复验证。**

---

## 容器环境推荐执行

在容器环境中，推荐使用以下参数：

```bash
REPORT_DIR="/workspace/reports"
mkdir -p "$REPORT_DIR"

# 1. 前置检查
bash scripts/rocky-prereq-check.sh

# 2. 预评估
bash scripts/container-rocky-audit.sh \
  --output "$REPORT_DIR" \
  --level 3 \
  --path /root/.openclaw

# 3. Dry-run 预览（不执行）
bash scripts/container-rocky-harden.sh \
  --level 3 \
  --report-dir "$REPORT_DIR" \
  --skip-ssh \
  --dry-run

# 4. 确认后执行
bash scripts/container-rocky-harden.sh \
  --level 3 \
  --report-dir "$REPORT_DIR" \
  --skip-ssh

# 5. 后验证
bash scripts/container-post-validate.sh \
  --report-dir "$REPORT_DIR"

# 6. 对比报告
bash scripts/container-pre-post-diff.sh \
  --report-dir "$REPORT_DIR"

# 7. 最终报告
bash scripts/container-report.sh \
  --report-dir "$REPORT_DIR"
```

---

## 注意事项

1. **始终先 dry-run** — 先预览再执行
2. **测试环境先行** — 在测试环境完整演练后再用于生产
3. **记录变更** — 保留所有报告文件用于审计
4. **恢复准备** — 确认恢复流程可用后再执行加固
5. **窗口时间** — 加固期间 OpenClaw 会短暂重启，选择维护窗口
6. **容器限制** — 容器内 sysctl/systemctl 可能受限，脚本会自动跳过

---

## 故障排除

### 加固后 OpenClaw 无法启动

```bash
# 1. 检查日志
journalctl -u openclaw --no-pager -n 50 2>/dev/null || \
  cat /root/.openclaw/logs/*.log 2>/dev/null | tail -50

# 2. 查看加固状态
cat /path/to/reports/harden-status-*.json

# 3. 执行恢复
bash scripts/container-rocky-restore.sh --backup-dir /path/to/reports/backups/
```

### 恢复后仍有问题

```bash
# 运行恢复验证
bash scripts/container-restore-validate.sh \
  --backup-file /path/to/reports/backups/pre-harden-*.tgz \
  --report-dir /path/to/reports/
```

### 容器内 sysctl 失败

```bash
# 这是正常的，容器内部分内核参数是只读的
# 检查哪些参数被跳过了
cat /path/to/reports/harden-state-*.json | jq '.results[] | select(.status == "warning")'
```
