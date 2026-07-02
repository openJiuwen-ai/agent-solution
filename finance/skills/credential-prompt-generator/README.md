# 凭证要素提取提示词生成

根据凭证图片样例，自动生成适用于该凭证类型的要素提取提示词。

## 功能说明

本 Skill 用于凭证要素提取的"冷启动"阶段：当你有一张新的凭证类型图片，需要快速生成一个可用于提取该凭证关键信息的提示词时，使用本 Skill。

**输入**：凭证图片（支持文件路径或 base64 编码）  
**输出**：结构化的提取提示词（包含角色设定、提取指南、JSON 输出格式）

## 安装方式

本 Skill 已集成到 skills MCP Server 中，支持以下调用方式：

### 1. Python 直接调用

```python
from skills.credential_prompt_generator.scripts.prompt_generator import CredentialPromptGenerator

generator = CredentialPromptGenerator(
    api_key="your-api-key",
    api_url="https://api.siliconflow.cn/v1",
    model="Qwen/Qwen3-VL-8B-Instruct"
)

result = generator.generate(
    images=["凭证图片.jpg"],
    field_code_mapping=[
        {"code": "E01001", "name": "凭证编号"},
        {"code": "E01002", "name": "开票日期"}
    ]
)

if result["success"]:
    print(result["prompt"])
else:
    print(f"生成失败: {result['error']}")
```

### 2. MCP 协议调用

通过 skills MCP Server 暴露的 MCP 接口调用：

```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "credential-prompt-generator",
    "arguments": {
      "images": ["base64_encoded_image..."],
      "field_code_mapping": [
        {"code": "E01001", "name": "凭证编号"}
      ]
    }
  }
}
```

### 3. HTTP REST 调用

```bash
curl -X POST http://localhost:8005/skill/credential-prompt-generator \
  -H "Content-Type: application/json" \
  -d '{
    "images": ["base64_encoded_image..."],
    "field_code_mapping": [
      {"code": "E01001", "name": "凭证编号"}
    ]
  }'
```

## 参数说明

| 参数 | 类型 | 必选 | 说明 |
|------|------|------|------|
| `images` | `List[str]` | 是 | 图片列表，支持文件路径或 base64 编码 |
| `field_code_mapping` | `List[Dict]` | 否 | 要素编码映射，格式 `[{"code": "E01001", "name": "编号"}]` |
| `vl_config` | `Dict` | 否 | VL 模型配置，不传使用服务端默认 |

## 返回值

成功时：

```json
{
  "success": true,
  "prompt": "# 角色设定\n你是一位专业的...\n## 提取指南\n..."
}
```

失败时：

```json
{
  "success": false,
  "error": "错误信息"
}
```

## 注意事项

1. **模型要求**：需要使用支持多模态输入的 VL 模型（如 Qwen/Qwen3-VL-8B-Instruct）
2. **图片格式**：支持 JPG/PNG 等常见格式，建议图片清晰可辨
3. **防止过拟合**：生成的提示词不应包含样例中的实际值，确保可用于同类型其他凭证
4. **要素编码映射**：传入后会覆盖默认的 JSON 字段命名规范，使用要素编码作为 key

## 目录结构

```
credential-prompt-generator/
├── SKILL.md                    # Skill 描述文件
├── README.md                   # 本文档
├── scripts/
│   ├── prompt_generator.py     # 核心业务逻辑
│   └── skill_wrapper.py        # MCP 注册入口
├── assets/
│   └── prompts/
│       └── generate_prompt.yaml  # 提示词模板
├── tests/                      # 单元测试
├── examples/                   # 测试样例
└── references/                 # 参考文档
```

## 相关文档

- [Skill 规范文档](../../docs/skill-specification-and-best-practices.md)
- [提示词模板说明](references/prompt-template-guide.md)
- [实施方案](../../docs/credential-prompt-generator-skill-plan.md)
