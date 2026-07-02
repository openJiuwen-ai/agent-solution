# DEPLOY-GUIDE — v8 加固工具包部署到目标 Rocky Linux

> v8 版本 | 2026-05-14

---

## 前提条件

在开始部署前，你需要准备以下信息：

| 信息 | 说明 | 示例 |
|------|------|------|
| 目标主机 IP | Rocky Linux 服务器的 IP 地址 | `192.168.1.100` |
| SSH 用户名 | 用于登录的用户 | `root` |
| SSH 认证方式 | 密码 或 SSH 密钥 | `~/.ssh/id_rsa` |
| OpenClaw 安装路径 | 目标机器上 OpenClaw 的目录 | `/root/.openclaw` |
| 是否容器部署 | OpenClaw 是否跑在 Docker/Podman 容器内 | `是` |

---

## 方案 A：通过 SCP 一键传输（推荐）

### 第 1 步：压缩工具包

在你的 Windows 机器上（PowerShell）：

```powershell
# 进入工具包所在目录
cd C:\Users\Administrator\.openclaw\workspace

# 打包整个 v8 工具包（不含 node_modules）
tar -czf openclaw-security-v8.tar.gz ^
  openclaw-security-container-rocky-v8
```

> ⚠️ 如果 PowerShell 的 tar 不支持，可以用 7-Zip 压缩成 `.zip`，到目标机器上用 `unzip` 解压。

### 第 2 步：传输到目标机器

```powershell
# 使用密码认证
scp openclaw-security-v8.tar.gz root@<目标IP>:/root/

# 使用密钥认证
scp -i C:\path\to\your\private_key openclaw-security-v8.tar.gz root@<目标IP>:/root/
```

> 💡 如果是 Windows PowerShell 没有 `scp`，可以：
> - 安装 OpenSSH 客户端：`Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0`
> - 或用 WinSCP / Tabby SSH 等图形工具拖拽上传

### 第 3 步：SSH 登录目标机器并解压

```bash
# SSH 登录
ssh root@<目标IP>
# 或用密钥
ssh -i ~/.ssh/id_rsa root@<目标IP>

# 解压到 OpenClaw 的 skills 目录
cd /root/.openclaw/workspace/skills
tar -xzf /root/openclaw-security-v8.tar.gz

# 确认解压结果
ls -la /root/.openclaw/workspace/skills/openclaw-security-container-rocky-v8/
```

### 第 4 步：赋予脚本执行权限

```bash
cd /root/.openclaw/workspace/skills/openclaw-security-container-rocky-v8/scripts
chmod +x *.sh
```

### 第 5 步：验证脚本完整性

```bash
# 检查所有脚本都有执行权限
ls -la *.sh

# 检查脚本语法（快速验证，不执行）
bash -n rocky-prereq-check.sh && echo "✅ OK" || echo "❌ FAIL"
bash -n container-rocky-audit.sh && echo "✅ OK" || echo "❌ FAIL"
bash -n container-rocky-harden.sh && echo "✅ OK" || echo "❌ FAIL"
bash -n container-post-validate.sh && echo "✅ OK" || echo "❌ FAIL"
bash -n container-pre-post-diff.sh && echo "✅ OK" || echo "❌ FAIL"
bash -n container-rocky-restore.sh && echo "✅ OK" || echo "❌ FAIL"
bash -n container-restore-validate.sh && echo "✅ OK" || echo "❌ FAIL"
bash -n container-report.sh && echo "✅ OK" || echo "❌ FAIL"
bash -n file-integrity.sh && echo "✅ OK" || echo "❌ FAIL"
bash -n file-perms.sh && echo "✅ OK" || echo "❌ FAIL"
```

---

## 方案 B：通过 rsync 同步（适合反复调试）

如果你需要反复修改脚本并同步到目标机器：

```bash
# 从 Windows（WSL 或 Git Bash）
rsync -avz --progress \
  /path/to/openclaw-security-container-rocky-v8/ \
  root@<目标IP>:/root/.openclaw/workspace/skills/openclaw-security-container-rocky-v8/
```

优势：只传输变更的文件，速度快。

---

## 方案 C：手动创建目录 + 粘贴内容（无 scp 时）

如果没有 scp/rsync 可用：

```bash
# 在目标机器上创建目录
mkdir -p /root/.openclaw/workspace/skills/openclaw-security-container-rocky-v8/{scripts,templates}

# 然后在 Windows 上用 cat 读取每个文件，复制到目标机器粘贴创建
# 例如：
#   Windows: cat C:\Users\Administrator\.openclaw\workspace\openclaw-security-container-rocky-v8\scripts\rocky-prereq-check.sh
#   目标机器: nano /root/.openclaw/workspace/skills/openclaw-security-container-rocky-v8/scripts/rocky-prereq-check.sh
#   粘贴内容，保存

# 最后赋予执行权限
chmod +x /root/.openclaw/workspace/skills/openclaw-security-container-rocky-v8/scripts/*.sh
```

---

## 部署后执行加固

### 完整流程（一键执行）

在目标机器上，依次执行以下命令：

```bash
# ========== 配置变量 ==========
SKILL_DIR="/root/.openclaw/workspace/skills/openclaw-security-container-rocky-v8"
REPORT_DIR="/root/.openclaw/workspace/security-reports"
LEVEL=3                    # 安全等级（推荐 L3，生产环境可改为 L4）
SKIP_SSH=false             # 如果已能正常 SSH 登录，改为 true 避免 SSH 被改

mkdir -p "$REPORT_DIR"
cd "$SKILL_DIR"

echo "=========================================="
echo " OpenClaw 安全加固 v8 — 开始执行"
echo "=========================================="
echo " 等级: L${LEVEL}"
echo " 跳过 SSH: ${SKIP_SSH}"
echo " 报告目录: ${REPORT_DIR}"
echo "=========================================="
echo ""

# ====== ① 前置检查 ======
echo ">>> ① 前置检查..."
bash scripts/rocky-prereq-check.sh
if [ $? -ne 0 ]; then
  echo "❌ 前置检查未通过，请修复后再执行"
  exit 1
fi
echo ""

# ====== ② 预评估 ======
echo ">>> ② 预评估（采集安全基线）..."
bash scripts/container-rocky-audit.sh \
  --output "$REPORT_DIR" \
  --level "$LEVEL"
echo ""

# ====== ③ 加固执行 ======
echo ">>> ③ 加固执行（等级 L${LEVEL}）..."

# 建议先跑一次 dry-run 看计划
echo "--- 干跑模式（预览不执行） ---"
bash scripts/container-rocky-harden.sh \
  --level "$LEVEL" \
  --report-dir "$REPORT_DIR" \
  --skip-ssh "$SKIP_SSH" \
  --dry-run
echo ""

# 确认干跑输出后，执行真实加固
read -p "确认开始加固？(输入 YES 继续): " CONFIRM
if [ "$CONFIRM" = "YES" ]; then
  bash scripts/container-rocky-harden.sh \
    --level "$LEVEL" \
    --report-dir "$REPORT_DIR" \
    $( $SKIP_SSH && echo "--skip-ssh" )
else
  echo "加固已取消"
  exit 0
fi
echo ""

# ====== ④ 后验证 ======
echo ">>> ④ 加固后验证..."
bash scripts/container-post-validate.sh \
  --report-dir "$REPORT_DIR"
echo ""

# ====== ⑤ 前后对比 ======
echo ">>> ⑤ 生成前后对比报告..."
bash scripts/container-pre-post-diff.sh \
  --report-dir "$REPORT_DIR"
echo ""

# ====== ⑥ 最终报告 ======
echo ">>> ⑥ 生成最终报告..."
bash scripts/container-report.sh \
  --report-dir "$REPORT_DIR"
echo ""

echo "=========================================="
echo " ✅ 加固执行完成！"
echo "=========================================="
echo ""
echo "📄 报告文件在: $REPORT_DIR/"
echo ""
ls -la "$REPORT_DIR/"
echo ""
echo "最终报告:"
cat "$REPORT_DIR"/final-report-*.md
echo ""
echo "=========================================="
```

---

## 各步骤独立执行命令

如果不想一键跑，可以分步执行：

```bash
cd /root/.openclaw/workspace/skills/openclaw-security-container-rocky-v8

# ① 前置检查
bash scripts/rocky-prereq-check.sh

# ② 预评估
bash scripts/container-rocky-audit.sh --output /root/.openclaw/workspace/security-reports --level 3

# ③ 干跑（预览）
bash scripts/container-rocky-harden.sh --level 3 --report-dir /root/.openclaw/workspace/security-reports --skip-ssh --dry-run

# ③ 真实加固
bash scripts/container-rocky-harden.sh --level 3 --report-dir /root/.openclaw/workspace/security-reports --skip-ssh

# ④ 后验证
bash scripts/container-post-validate.sh --report-dir /root/.openclaw/workspace/security-reports

# ⑤ 前后对比
bash scripts/container-pre-post-diff.sh --report-dir /root/.openclaw/workspace/security-reports

# ⑥ 最终报告
bash scripts/container-report.sh --report-dir /root/.openclaw/workspace/security-reports
```

---

## 恢复流程（加固出问题时使用）

```bash
cd /root/.openclaw/workspace/skills/openclaw-security-container-rocky-v8

# 执行恢复（交互式，需要人工确认）
bash scripts/container-rocky-restore.sh \
  --backup-dir /root/.openclaw/backups \
  --report-dir /root/.openclaw/workspace/security-reports

# 恢复后自动验证，也可以单独跑
bash scripts/container-restore-validate.sh \
  --report-dir /root/.openclaw/workspace/security-reports
```

---

## 报告拉回本地（Windows 查看）

```powershell
# 从目标机器拉回报告文件
scp root@<目标IP>:/root/.openclaw/workspace/security-reports/*.md C:\Users\Administrator\Desktop\加固报告\
```

---

## 参数建议

| 场景 | --level | --skip-ssh | 说明 |
|------|---------|-----------|------|
| 首次测试/开发环境 | 2 | false | 基础加固，包括 SSH |
| 已正常 SSH 登录的生产环境 | 3 | **true** | 推荐，不碰 SSH |
| 全新服务器，从头加固 | 4 | false | 严格加固，SSH 也改 |
| 合规要求最高安全 | 5 | false | 极限加固 |

---

## 注意事项

1. **先跑 `--dry-run`**：看一遍要改什么，确认无误再执行真实加固
2. **`--skip-ssh` 很重要**：如果你已经能通过 SSH 正常登录目标机器，建议加上此参数，避免 SSH 配置被改后无法登录
3. **保持 SSH 连接不关闭**：加固期间保持当前 SSH 会话连接，万一出问题可以用这个会话执行恢复
4. **备份在手**：加固脚本第一步自动备份，备份位置 `$OPENCLAW_PATH/backups/pre-harden-*.tgz`
5. **容器 vs 宿主机**：脚本会自动检测运行环境，容器内会跳过不适用的检查（如 systemd、SELinux）
