# OpenClaw Security Hardening Skill

> 面向多发行版容器环境的 OpenClaw 全生命周期安全加固方案  
> 版本：1.0.0 | 日期：2026-07-02

---

## 概述

本 Skill 提供面向 **多发行版容器环境**（Rocky/Debian/Ubuntu）中运行的 OpenClaw 实例的完整安全加固方案。涵盖预评估、分级加固、后验证、前后对比、恢复的全生命周期管理。

### 为什么需要这个 Skill

OpenClaw 部署在生产环境后，面临典型的安全风险：

| 风险 | 后果 |
|------|------|
| 默认 API Token 太短 | 容易被暴力破解，攻击者获得完全控制 |
| 配置文件权限宽松 | 服务器上其他用户可读取敏感信息 |
| Gateway 绑定公网 | 任何人都能直接访问你的 AI 助手 |
| 无安全审计机制 | 被入侵后无法发现，损失扩大 |
| 容器无安全限制 | 容器逃逸后可控制整台宿主机 |

传统手动加固方式存在明显痛点：

- 手动逐一检查几十个配置项，耗时且容易遗漏
- 缺乏统一基线，每次加固效果不一致
- 改错了无法回滚，不知道如何恢复
- 加固后不确定是否真的生效
- 改了什么、效果如何，没有记录，无法审计

### 本 Skill 的价值

本 Skill 通过自动化流程解决上述问题：

- **全自动**：一条命令完成评估→加固→验证→报告
- **标准化**：L1-L5 五个安全等级，按需选择
- **可回滚**：加固前自动备份，一键恢复到加固前状态
- **可验证**：加固后逐项检查，确保每项都生效
- **可审计**：生成完整的 Markdown 报告，前后对比一目了然

### 预期效果

| 检查项 | 加固前 | 加固后 |
|--------|--------|--------|
| API Token 长度 | 可能 < 32 位 | 48 位强随机 |
| Gateway 绑定 | 0.0.0.0（公网） | 127.0.0.1（仅本机） |
| 配置文件权限 | 644（任何人可读） | 600（仅 owner） |
| 安全评分 | 30-60 分（中高风险） | 0-10 分（低风险） |

---

## 适用场景

### 适用

- OpenClaw 运行在 Linux 容器内（Docker/Podman/LXC）
- 需要对容器环境和 OpenClaw 配置进行安全加固
- 需要可审计、可回滚的加固流程
- 支持 Rocky Linux、Debian、Ubuntu 发行版

### 不适用

- Windows 宿主环境
- 非 Linux 发行版
- 纯宿主机部署无容器（部分容器专属检查不适用）

---

## 触发条件

当用户提出以下需求时应触发此 Skill：

- 需要对 OpenClaw 实例进行安全加固
- 需要评估 OpenClaw 部署的安全状态
- 需要生成安全加固报告
- 需要从安全加固中恢复配置
- 需要进行日常安全检查

---

## 工作流

### 标准执行流程

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  ① 前置检查  │───▶│  ② 预评估    │───▶│  ③ 加固执行  │───▶│  ④ 后验证    │
│  环境就绪    │    │  采集基线    │    │  应用加固    │    │  验证效果    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                                               │
┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  ⑦ [可选]   │◀───│  ⑥ 最终报告  │◀───│  ⑤ 对比报告  │◀────────┘
│  加固恢复    │    │  评分+矩阵   │    │  前后对比    │
└─────────────┘    └─────────────┘    └─────────────┘
```

### 执行命令

```bash
REPORT_DIR="/opt/openclaw-security/reports"
mkdir -p "$REPORT_DIR"

# 1. 前置检查 — 验证环境就绪
bash scripts/rocky-prereq-check.sh

# 2. 预评估 — 采集安全基线，计算初始评分
bash scripts/container-rocky-audit.sh --output "$REPORT_DIR"

# 3. 加固执行 — 推荐 L3 等级
bash scripts/container-rocky-harden.sh --level 3 --report-dir "$REPORT_DIR" --skip-ssh

# 4. 后验证 — 确认所有加固生效
bash scripts/container-post-validate.sh --report-dir "$REPORT_DIR"

# 5. 对比报告 — 生成加固前后 Markdown 对比
bash scripts/container-pre-post-diff.sh --report-dir "$REPORT_DIR"

# 6. 最终报告 — 输出评分和状态矩阵
bash scripts/container-report.sh --report-dir "$REPORT_DIR"
```

---

## 安全等级

| 等级 | 名称 | 包含加固项 | 影响程度 | 推荐场景 |
|------|------|-----------|----------|----------|
| **L1** | 基础加固 | Token 轮换、文件权限、完整性基线 | 低 | 开发/测试环境 |
| **L2** | 标准加固 | L1 + SSH、OpenClaw 配置、日志审计 | 低-中 | 一般生产环境 |
| **L3** | 增强加固 | L2 + 内核参数、防火墙、容器安全 | 中 | 重要生产环境 ⭐ |
| **L4** | 严格加固 | L3 + 密码策略、审计增强、网络隔离 | 中-高 | 高安全要求 |
| **L5** | 极限加固 | L4 + SELinux 强制、最严 seccomp | 高 | 最高安全等级 |

---

## 加固项详情

| ID | 名称 | 最低等级 | 容器内 | 说明 |
|----|------|----------|--------|------|
| H-01 | SSH 安全配置 | L2 | ⏭️ 跳过 | 禁用 root 登录、密钥认证、超时设置 |
| H-02 | Token 轮换 | L1 | ✅ | 生成新的强随机 API Token |
| H-03 | OpenClaw 配置加固 | L2 | ✅ | 最小化配置、禁用危险功能 |
| H-04 | 文件权限修复 | L1 | ✅ | 修正关键文件和目录权限 |
| H-05 | 系统内核参数 | L3 | ⚠️ | sysctl 网络和安全调优 |
| H-06 | 防火墙规则 | L3 | ⏭️ | iptables/nftables 端口限制 |
| H-07 | 文件完整性基线 | L1 | ✅ | 关键文件 SHA256 哈希记录 |
| H-08 | 容器安全配置 | L3 | ✅ | 只读根文件系统建议、seccomp |
| H-09 | 日志审计配置 | L2 | ✅ | 日志轮转和保留策略 |
| H-10 | 密码策略 | L4 | ⏭️ | PAM 密码复杂度和过期策略 |

---

## 脚本参考

### scripts/rocky-prereq-check.sh

前置依赖检查。支持多发行版检测（Rocky/Debian/Ubuntu/Alpine）。

```bash
bash scripts/rocky-prereq-check.sh [--json]
```

检查项：操作系统、必要命令、磁盘空间、权限、容器环境检测。

---

### scripts/container-rocky-audit.sh

预评估脚本，采集系统基线并计算安全评分。

```bash
bash scripts/container-rocky-audit.sh [--output DIR] [--level N] [--path DIR]
```

输出：
- `pre-assessment-YYYYMMDD-HHMMSS.json` — 结构化基线数据
- `pre-assessment-YYYYMMDD-HHMMSS.md` — 人类可读评估报告

---

### scripts/container-rocky-harden.sh

加固执行脚本。

```bash
bash scripts/container-rocky-harden.sh [--level N] [--report-dir DIR] [--skip-ssh] [--dry-run] [--path DIR]
```

关键特性：
- `safe_node_set_key` 值通过 stdin 传递，路径通过 process.argv，消除注入风险
- 包管理器自动适配（dnf/apt）
- systemd 操作自动跳过（无 systemd 环境）

---

### scripts/container-post-validate.sh

加固后验证。

```bash
bash scripts/container-post-validate.sh [--report-dir DIR] [--state-file FILE] [--path DIR]
```

验证项：OpenClaw Gateway 状态、端口监听、API 可达性、文件权限、系统参数、容器安全配置。

---

### scripts/container-pre-post-diff.sh

加固前后对比。

```bash
bash scripts/container-pre-post-diff.sh [--report-dir DIR]
```

输出：`diff-report-YYYYMMDD-HHMMSS.md`

---

### scripts/container-report.sh

最终报告生成。

```bash
bash scripts/container-report.sh [--report-dir DIR]
```

报告内容：加固前/后安全评分、加固项状态矩阵、详细变更列表、建议和注意事项。

---

### scripts/container-rocky-restore.sh

加固恢复脚本。

```bash
bash scripts/container-rocky-restore.sh [--backup-dir DIR]
```

流程：列出可用备份 → 交互式选择恢复类型 → 人工确认（必须输入 `YES`）→ 执行恢复 → 自动验证 → 输出分析报告。

---

### scripts/health-check.sh

日常快速健康检查。

```bash
bash scripts/health-check.sh [--path DIR] [--json]
```

检查项（10项）：配置存在性、Token长度、绑定地址、文件权限、.env文件、完整性基线、审计日志、备份状态、Gateway HTTP可达性、进程运行时长。

---

### scripts/file-integrity.sh / file-perms.sh

文件完整性检查与权限管理。

```bash
bash file-integrity.sh --mode create|verify --path DIR [--baseline FILE]
bash file-perms.sh [--mode check|fix] [--path DIR] [--log FILE]
```

---

## 容器环境检测

所有脚本使用 `detect_container_mode()` 函数自动检测：

```bash
detect_container_mode() {
  if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || \
     grep -qE 'docker|lxc|kubepods' /proc/1/cgroup 2>/dev/null; then
    echo "container"
  else
    echo "host"
  fi
}
```

容器模式下自动跳过不适用的检查项（systemd、SELinux、firewalld 等）。

---

## 输出格式

### 评分输出

| 阶段 | 典型评分 | 状态 |
|------|----------|------|
| 加固前 | 30-60 分 | 🟡 中高风险 |
| 加固后 | 0-10 分 | 🟢 低风险 |

### 报告文件

- `pre-assessment-YYYYMMDD-HHMMSS.{json,md}` — 预评估报告
- `harden-state-YYYYMMDD-HHMMSS.json` — 加固状态快照
- `post-validation-YYYYMMDD-HHMMSS.md` — 后验证报告
- `diff-report-YYYYMMDD-HHMMSS.md` — 前后对比报告
- `final-report-YYYYMMDD-HHMMSS.md` — 最终汇总报告

---

## 能力边界

### 本 Skill 能做的

- 自动化安全评估与分级加固
- 生成完整的审计报告
- 支持加固回滚（需加固前备份）
- 多发行版容器环境适配

### 本 Skill 不能做的

- 不能修复操作系统层面的 CVE 漏洞
- 不能检测 AI 模型供应链风险
- 不能提供实时威胁检测
- 不能替代网络安全设备（WAF/DDoS 防护）

---

## 安全注意事项

1. **备份优先** — 加固前自动备份，但建议额外手动备份
2. **测试环境先行** — 先在测试环境完整演练
3. **维护窗口** — 加固期间 OpenClaw 会重启
4. **保留报告** — 所有报告用于审计和故障排查
5. **恢复验证** — 恢复后务必运行验证脚本确认恢复成功
6. **容器限制** — 容器内 sysctl/systemctl 可能受限，脚本会自动跳过

---

## 文件结构

```
openclaw-security-hardening-skill-v1/
├── SKILL.md                          # 本文件（Skill 主文档）
├── README.md                         # 快速开始
├── references/                       # 参考文档
│   ├── BACKGROUND.md                 # 项目背景与演进说明
│   ├── PLAN.md                       # 加固项清单
│   ├── DEPLOY-GUIDE.md               # 部署指南
│   ├── EXECUTION-GUIDE.md            # 执行步骤说明
│   ├── PRODUCT-OVERVIEW.md           # 产品说明
│   ├── CHANGELOG.md                  # 版本历史
│   └── OPTIMIZATION-v8.md            # 优化说明
├── scripts/                          # 脚本目录
│   ├── rocky-prereq-check.sh         # 前置检查
│   ├── container-rocky-audit.sh      # 预评估
│   ├── container-rocky-harden.sh     # 加固执行
│   ├── container-post-validate.sh    # 后验证
│   ├── container-pre-post-diff.sh    # 前后对比
│   ├── container-report.sh           # 报告生成
│   ├── container-rocky-restore.sh    # 加固恢复
│   ├── container-restore-validate.sh # 恢复验证
│   ├── file-integrity.sh             # 文件完整性
│   ├── file-perms.sh                 # 权限检查
│   └── health-check.sh               # 日常健康检查
└── templates/                        # 模板目录
    ├── docker-compose-security.yml   # docker-compose 示例
    ├── seccomp-openclaw.json         # seccomp 白名单
    ├── SOUL-security-append.md       # SOUL.md 安全规则
    └── AGENTS-security-append.md     # AGENTS.md 安全规则
```
