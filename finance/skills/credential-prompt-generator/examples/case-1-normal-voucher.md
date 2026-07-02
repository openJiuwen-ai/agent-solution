# 测试用例 1：标准凭证图片

## 输入

```python
from scripts.prompt_generator import CredentialPromptGenerator

generator = CredentialPromptGenerator(
    api_key="your-api-key",
    api_url="https://api.siliconflow.cn/v1",
    model="Qwen/Qwen3-VL-8B-Instruct"
)

# 传入一张电汇凭证图片
result = generator.generate(
    images=["examples/sample_wire_transfer.jpg"]
)
```

## 预期输出

```json
{
  "success": true,
  "prompt": "# 角色设定\n\n你是一位专业的银行凭证信息提取专家，擅长从电汇凭证中准确识别和提取关键信息。\n\n## 任务说明\n\n请从提供的电汇凭证图片中提取以下关键字段，并以 JSON 格式输出。\n\n## 提取指南\n\n- **付款人名称 (payer_name)**: 位于凭证左上角，通常在\"付款人\"或\"汇款人\"标签后\n- **付款人账号 (payer_account)**: 位于付款人名称下方，为一串数字\n- **收款人名称 (payee_name)**: 位于凭证中部，通常在\"收款人\"标签后\n- **收款人账号 (payee_account)**: 位于收款人名称下方\n- **汇款金额 (amount)**: 位于凭证右侧或中部，通常带有货币符号\n- **币种 (currency)**: 如 CNY、USD 等，位于金额旁边\n- **汇款日期 (transfer_date)**: 通常位于凭证底部，格式为 YYYY-MM-DD\n- **业务编号 (reference_number)**: 位于凭证右上角或底部\n\n## JSON 输出格式\n\n```json\n{\n  \"payer_info\": {\n    \"payer_name\": \"string\",\n    \"payer_account\": \"string\"\n  },\n  \"payee_info\": {\n    \"payee_name\": \"string\",\n    \"payee_account\": \"string\"\n  },\n  \"transfer_info\": {\n    \"amount\": \"string\",\n    \"currency\": \"string\",\n    \"transfer_date\": \"string\",\n    \"reference_number\": \"string\"\n  }\n}\n```\n\n请严格按照上述格式输出，确保所有字段都正确提取。如果某个字段在凭证中不存在或无法识别，请将其值设为 null。"
}
```

## 验证要点

1. 返回的 prompt 包含角色设定
2. 返回的 prompt 包含提取指南（列出字段及定位方法）
3. 返回的 prompt 包含 JSON 输出格式示例
4. prompt 中不应包含样例图片中的实际值（防止过拟合）
