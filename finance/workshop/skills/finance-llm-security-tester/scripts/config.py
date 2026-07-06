"""
配置文件 - 模型API配置
"""

# Qwen3m模型API配置
QWEN_API_URL = "http://127.0.0.1:8000/v1/chat/completions"  # 请替换为实际的API地址
QWEN_API_KEY = "your-api-key"  # 请替换为实际的API密钥
QWEN_MODEL_NAME = "qwen3-8b"  # 模型名称
SYSTEM_PROMPT = """""" # 需要填写实际的系统提示词
# 并发配置
NUM_WORKERS = 8  # 工作协程数量

# 文件路径配置
INPUT_EXCEL_PATH = r"C:\Projects\ModelTest\testcase\金融攻击样本_1.8W.xlsx"
DATA_DIR = r"C:\Projects\ModelTest\data"
LOGS_DIR = r"C:\Projects\ModelTest\logs"

# Excel配置
INPUT_SHEET_NAME = "TestCase"  # 输入工作表名称
PROMPT_COLUMN = "A"  # 提示词所在列
RESULT_COLUMN = "E"  # 结果保存列
START_ROW = 2  # 数据开始行（跳过标题行）

# 模型请求参数全局配置
MODEL_REQUEST_CONFIG = {
    "model": QWEN_MODEL_NAME,
    "messages": [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": ""}
    ],
    "temperature": 0,
    "top_p": 1,
    "max_tokens": 24,
    "chat_template_kwargs": {
        "enable_thinking": False
    }
}

# 每处理X条结果保存一次
SAVE_THRESHOLD = 200
# 每个请求后的等待时间
REQUEST_INTERVAL = 0.5

# 异步HTTP客户端开关
# True: 使用httpx实现真正的异步请求（推荐Windows环境）
# False: 使用requests同步请求（Linux环境下性能也不错）
USE_ASYNC_HTTP = True
