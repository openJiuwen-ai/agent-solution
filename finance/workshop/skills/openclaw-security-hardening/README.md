# OpenClaw Security Hardening Skill

> 面向多发行版容器环境的 OpenClaw 全生命周期安全加固方案

## 快速开始

```bash
# 1. 语法验证（部署前必做）
for f in scripts/*.sh; do bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"; done

# 2. 前置检查
bash scripts/rocky-prereq-check.sh

# 3. 预评估
bash scripts/container-rocky-audit.sh --output reports/

# 4. 加固（推荐 L3）
bash scripts/container-rocky-harden.sh --level 3 --report-dir reports/ --skip-ssh

# 5. 后验证
bash scripts/container-post-validate.sh --report-dir reports/

# 6. 对比报告
bash scripts/container-pre-post-diff.sh --report-dir reports/

# 7. 最终报告
bash scripts/container-report.sh --report-dir reports/

# 日常健康检查
bash scripts/health-check.sh

# 如需恢复
bash scripts/container-rocky-restore.sh --backup-dir reports/
```

## 核心特性

| 特性 | 说明 |
|------|------|
| 预评估 | 自动采集系统、OpenClaw、容器配置基线 |
| 分级加固 | L1-L5 五级安全等级，按需选择 |
| 后验证 | 18 项验证 + Gateway HTTP 健康检查 |
| 前后对比 | 自动化 diff，Markdown 对比报告 |
| 恢复功能 | SHA256 完整性校验 + 全量/选择性恢复 |
| 多发行版 | 支持 Rocky/Debian/Ubuntu/Alpine |
| 容器适配 | 自动检测容器模式，跳过不适用的检查项 |

## 安全等级

| 等级 | 名称 | 适用场景 | 风险 |
|------|------|----------|------|
| L1 | 基础加固 | 开发/测试环境 | 低 |
| L2 | 标准加固 | 一般生产环境 | 低-中 |
| L3 | 增强加固 | 重要生产环境（推荐） | 中 |
| L4 | 严格加固 | 高安全要求 | 中-高 |
| L5 | 极限加固 | 最高安全等级 | 高 |

## 目录结构

```
openclaw-security-hardening-skill/
├── SKILL.md                          # Skill 主文档（完整说明）
├── README.md                         # 快速开始（本文件）
├── LICENSE                           # Apache 2.0 许可证
├── references/                       # 参考文档
│   ├── BACKGROUND.md                 # 项目背景与演进说明
│   ├── PLAN.md                       # 加固项清单
│   ├── DEPLOY-GUIDE.md               # 部署指南
│   ├── EXECUTION-GUIDE.md            # 执行步骤说明
│   ├── PRODUCT-OVERVIEW.md           # 产品说明
│   ├── CHANGELOG.md                  # 版本历史
│   └── OPTIMIZATION-v8.md            # 优化说明
├── scripts/                          # 11 个自动化脚本
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
└── templates/                        # 安全配置模板
    ├── docker-compose-security.yml   # docker-compose 示例
    ├── seccomp-openclaw.json         # seccomp 白名单
    ├── SOUL-security-append.md       # SOUL.md 安全规则
    └── AGENTS-security-append.md     # AGENTS.md 安全规则
```

## 适用环境

| 发行版 | 包管理器 | 兼容性 |
|--------|---------|--------|
| Rocky Linux 8/9 | dnf | 完全支持 |
| CentOS 8/9 | dnf | 完全支持 |
| Debian 11/12 | apt | 完全支持 |
| Ubuntu 20.04/22.04 | apt | 完全支持 |
| Alpine Linux | apk | 有限支持 |

## 许可证

Apache License 2.0
