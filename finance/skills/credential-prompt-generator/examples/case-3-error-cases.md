# 测试用例 3：错误情况

## 3.1 无图片输入

### 输入

```python
result = generator.generate(images=[])
```

### 预期输出

```json
{
  "success": false,
  "error": "至少需要一张图片"
}
```

---

## 3.2 无效的图片路径

### 输入

```python
result = generator.generate(images=["/path/to/nonexistent.jpg"])
```

### 预期输出

```json
{
  "success": false,
  "error": "无法识别输入类型: /path/to/nonexistent.jpg... (既不是有效文件路径也不是有效的base64编码)"
}
```

---

## 3.3 API Key 未配置

### 输入

```python
generator = CredentialPromptGenerator(
    api_key="",  # 空的 API Key
    api_url="https://api.siliconflow.cn/v1",
    model="Qwen/Qwen3-VL-8B-Instruct"
)

result = generator.generate(images=["valid_image.jpg"])
```

### 预期输出

```json
{
  "success": false,
  "error": "API 请求失败: 401 - ..."
}
```

---

## 3.4 请求超时

### 输入

```python
generator = CredentialPromptGenerator(
    api_key="your-api-key",
    api_url="https://api.siliconflow.cn/v1",
    model="Qwen/Qwen3-VL-8B-Instruct",
    timeout=1  # 很短的超时时间
)

result = generator.generate(images=["large_image.jpg"])
```

### 预期输出

```json
{
  "success": false,
  "error": "..."  # 超时相关错误信息
}
```

---

## 错误处理建议

1. **检查返回值**：始终检查 `result["success"]` 是否为 `true`
2. **显示错误信息**：当 `success` 为 `false` 时，将 `result["error"]` 展示给用户
3. **重试机制**：对于网络或超时错误，可以考虑重试
4. **输入校验**：调用前检查图片是否存在、API Key 是否配置
