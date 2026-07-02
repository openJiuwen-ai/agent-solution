---
name: credential-prompt-generator
description: 当需要为新类型的凭证/文档生成要素提取提示词时使用。输入凭证图片，输出包含角色设定、提取指南和JSON格式的结构化提示词。不适用于已有提示词的优化迭代或批量生成。
version: 1.0.0
author: 凭证AI团队
category: 文档处理
---

# 凭证要素提取提示词生成

## 适用场景
- 为新类型的凭证/文档首次创建要素提取提示词
- 需要根据凭证图片样例自动生成结构化的提取指南
- 需要生成带要素编码映射的提示词（对接统一编码体系）
- 冷启动阶段，快速生成可用的提取提示词

## 不适用场景
- 已有提示词的优化迭代（请使用 optimize-prompt 相关能力）
- 批量为多种凭证类型生成提示词（请逐张调用）
- 凭证图片质量极差、无法识别内容
- 需要生成非结构化描述而非 JSON 提取格式

## 输入要求
- 凭证图片（1张或多张，支持文件路径或 base64 编码）
- 可选：要素编码映射 `[{code: "E01001", name: "编号"}]`
- 可选：凭证类型名称（预留字段，暂未启用）
- 可选：VL 模型配置（不传使用服务端默认）

## 执行步骤
1. 接收凭证图片，统一转换为 base64 格式
2. 如果传入要素编码映射，构建字段命名规范提示
3. 加载并渲染提示词模板，填充字段命名规范
4. 构建多模态消息（系统提示 + 图片）
5. 调用 VL 模型分析图片并生成提示词
6. 清理返回内容中的 markdown 代码块标记
7. 返回生成的结构化提示词

## 输出格式

```json
{
  "success": true,
  "prompt": "# 角色设定\n你是一位专业的...\n## 提取指南\n...\n## JSON输出格式\n{...}",
  "error": null
}
```

生成的提示词包含：
- **角色设定**：针对该凭证类型的专家角色
- **任务说明**：提取关键信息的任务描述
- **提取指南**：每个字段的定位和提取方法
- **JSON输出格式**：期望的结构化输出示例

## 合规边界
- 不保证生成的提示词可以直接用于生产，建议经过测试验证
- 生成的提示词不应包含凭证图片中的实际值（防止过拟合）
- 不处理涉密或敏感凭证，调用方需确保图片内容合规
- 模型输出可能存在偏差，关键场景建议人工审核提示词质量

## 快速开始

```python
from scripts.prompt_generator import CredentialPromptGenerator

generator = CredentialPromptGenerator(
    api_key="your-api-key",
    api_url="https://api.siliconflow.cn/v1",
    model="Qwen/Qwen3-VL-8B-Instruct"
)

result = generator.generate(
    images=["凭证.jpg"],
    field_code_mapping=[
        {"code": "E01001", "name": "凭证编号"},
        {"code": "E01002", "name": "开票日期"}
    ]
)

print(result["prompt"])
```

## 更多文档

- [提示词模板说明](references/prompt-template-guide.md)
- [测试样例](examples/)
