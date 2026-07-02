# 测试用例 2：带要素编码映射

## 输入

```python
from scripts.prompt_generator import CredentialPromptGenerator

generator = CredentialPromptGenerator(
    api_key="your-api-key",
    api_url="https://api.siliconflow.cn/v1",
    model="Qwen/Qwen3-VL-8B-Instruct"
)

# 传入凭证图片 + 要素编码映射
result = generator.generate(
    images=["examples/sample_invoice.jpg"],
    field_code_mapping=[
        {"code": "E01001", "name": "发票号码"},
        {"code": "E01002", "name": "开票日期"},
        {"code": "E02001", "name": "购买方名称"},
        {"code": "E02002", "name": "购买方纳税人识别号"},
        {"code": "E03001", "name": "销售方名称"},
        {"code": "E03002", "name": "销售方纳税人识别号"},
        {"code": "E04001", "name": "金额合计"},
        {"code": "E04002", "name": "税额合计"},
    ]
)
```

## 预期输出

```json
{
  "success": true,
  "prompt": "# 角色设定\n\n你是一位专业的发票信息提取专家...\n\n## 提取指南\n\n- **E01001(发票号码)**: 位于发票右上角，由8位数字组成\n- **E01002(开票日期)**: 位于发票顶部，格式为 YYYY年MM月DD日\n- **E02001(购买方名称)**: 位于发票左侧\"购买方\"区域\n- **E02002(购买方纳税人识别号)**: 位于购买方名称下方\n...\n\n## JSON 输出格式\n\n```json\n{\n  \"E01001\": \"string\",\n  \"E01002\": \"string\",\n  \"E02001\": \"string\",\n  \"E02002\": \"string\",\n  \"E03001\": \"string\",\n  \"E03002\": \"string\",\n  \"E04001\": \"string\",\n  \"E04002\": \"string\"\n}\n```\n\n请严格按照要素编码作为 JSON key 输出。"
}
```

## 验证要点

1. 返回的 prompt 使用要素编码（如 E01001）作为 JSON key
2. 提取指南中使用"要素编码(中文名)"格式标识字段
3. JSON 输出格式为扁平结构，不使用嵌套对象
4. 所有传入的要素编码都出现在输出格式中

## 编码映射分组显示

在提示词生成过程中，要素编码会按前缀分组显示给 LLM：

```
要素编码映射清单：
- E01: E01001(发票号码), E01002(开票日期)
- E02: E02001(购买方名称), E02002(购买方纳税人识别号)
- E03: E03001(销售方名称), E03002(销售方纳税人识别号)
- E04: E04001(金额合计), E04002(税额合计)
```

这有助于 LLM 理解字段的逻辑分组，生成更合理的提取指南。
