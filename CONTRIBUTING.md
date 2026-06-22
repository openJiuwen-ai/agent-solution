# 贡献指南

## 开发模式

本项目采用 **Fork + PR** 模式进行协作：

```
个人 fork 仓                        主仓
  main                              ├── main（最终集成线）
  feature/xxx ──────(PR)──────>    ├── module/common-runtime-java（模块长驻分支，阶段 1）
                                    └── module/xxx（其他模块分支）
```

## 开发流程

1. **Fork** 主仓到个人空间
2. 在个人 fork 上创建 feature/fix 分支开发
3. 完成后向主仓提 **Merge Request (PR)**
4. 经过 review + CI 通过后合入

## PR 合入目标

| 模块状态 | PR 目标分支 |
|---------|------------|
| 开发中（阶段 1） | `module/<模块名>` 长驻分支 |
| 已稳定（阶段 3） | `main` |

## 分支命名规范

| 分支类型 | 命名格式 | 示例 |
|---------|---------|------|
| 模块长驻分支 | `module/<模块名>` | `module/common-runtime-java` |
| 功能开发 | `feature/<描述>` | `feature/add-logging` |
| 问题修复 | `fix/<描述>` | `fix/null-pointer` |

## 模块负责人

参见 [CODEOWNERS](CODEOWNERS)
