import concurrent.futures
import json
import os
import re
import time
from pathlib import Path
from typing import Dict, List, Tuple, Any

import pandas as pd
from tqdm import tqdm
from openai import OpenAI

BASE_DIR = Path(__file__).resolve().parent
METHODOLOGY_DIR = BASE_DIR.parent
REFS_DIR = METHODOLOGY_DIR / "references"
OUTPUT_DIR = METHODOLOGY_DIR / "output"

LLM_API_KEY = os.environ.get("LLM_API_KEY", "")
LLM_MODEL = os.environ.get("LLM_MODEL", "glm-5.1")
LLM_API_BASE = os.environ.get("LLM_API_BASE", "https://open.bigmodel.cn/api/paas/v4/")
LLM_TEMPERATURE = 0.1
LLM_MAX_TOKENS = 2048
LLM_TIMEOUT = 60
LLM_MAX_RETRIES = 3
LLM_RETRY_DELAY = 2

INPUT_FILE = REFS_DIR / "待判定数据.xlsx"
OUTPUT_FILE = OUTPUT_DIR / "判定结果.xlsx"
MENU_DESC_FILE = REFS_DIR / "menu_desc.xlsx"

llm_client = OpenAI(base_url=LLM_API_BASE, api_key=LLM_API_KEY, timeout=LLM_TIMEOUT)

def call_llm_api(content=None, **kwargs):
    temperature = kwargs.get("temperature", LLM_TEMPERATURE)
    max_tokens = kwargs.get("max_tokens", LLM_MAX_TOKENS)

    for attempt in range(1, LLM_MAX_RETRIES + 1):
        try:
            response = llm_client.chat.completions.create(
                model=LLM_MODEL,
                messages=[{"role": "user", "content": content}],
                temperature=temperature,
                max_tokens=max_tokens,
            )
            result = response.choices[0].message.content
            if result:
                return {"content": result.strip()}, response.created
        except Exception as e:
            print(f"LLM 调用失败（第{attempt}/{LLM_MAX_RETRIES}次）: {e}")
            if attempt < LLM_MAX_RETRIES:
                time.sleep(LLM_RETRY_DELAY * attempt)
    return {"content": ""}, 0

def call_llm_api_kwargs(kwargs):
    content = kwargs.get("content", '')
    temperature = kwargs.get("temperature", LLM_TEMPERATURE)
    max_tokens = kwargs.get("max_tokens", LLM_MAX_TOKENS)
    return call_llm_api(content=content, temperature=temperature, max_tokens=max_tokens)

def get_prompt(input_query, input_intent, input_menu_desc):
    """构建判定 prompt"""
    PROMPT = """ 你是一位手机银行业务系统的语义理解专家。你的核心任务是根据给定的菜单描述，判断用户输入的语句是否表达了该菜单对应的意图。
【背景】
手机银行业务系统，涵盖转账汇款、投资理财、账户查询、信用卡、生活缴费等业务场景。

【输入信息】
待判断语句：{query}
对应意图：{intent}
意图描述：{menu_desc}

【判断逻辑】
请仔细分析“待判断语句”的语义，与“意图描述”进行比对：
1、如果用户语句的语义与意图描述高度一致，且明确表达了执行该功能的意图，结果为1.
2、如果用户语句语义明显属于其他意图或者与意图描述无关，结果为0.
3、如果用户语句存在歧义、指代不明或信息不足，导致无法确认是否属于该意图，结果为-1.

【输出要求】
1、严禁输出任何思考过程、解释或Markdown标记，仅输出JSON格式结果.
2、“原因”字段需简明扼要地说明判断依据，不要超过50个字.

【输出格式】
{{
    "输入query": "{query}",
    "输入intent": "{intent}",
    "是否更符合意图": "0/1/-1",
    "原因": "判断原因"
}}

【输出举例】
{{
    "输入query": "xx",
    "输入intent": "xx",
    "是否更符合意图": "1",
    "原因": "xx"
}}"""
    return PROMPT.format(query=input_query, intent=input_intent, menu_desc=input_menu_desc)

def read_menu_desc():
    menu_df = pd.read_excel(MENU_DESC_FILE, sheet_name="Sheet1")
    menu_dict = dict(zip(menu_df["intent_name"], menu_df["intent_desc"]))
    return menu_dict

def parse_llm_response(llm_res:List[str]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    success_list = []
    failed_list = []

    for raw_text in llm_res:
        if not isinstance(raw_text, str):
            raw_text = str(raw_text)
        text = raw_text.strip()
        json_str = None
        pattern_md = r"```(?:json)?\s*([\s\S]*?)\s*```"
        matches = re.findall(pattern_md, text, re.IGNORECASE)

        if matches:
            for match in matches:
                if match.strip():
                    json_str = match.strip()
                    break
        if not json_str:
            start_idx = text.find("{")
            end_idx = text.rfind("}")
            if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
                json_str = text[start_idx:end_idx + 1]
        if not json_str:
            failed_list.append({
                'raw_response': text,
                'error': '无法提取JSON',
            })
            continue
        try:
            data = json.loads(json_str, strict=False)
            success_list.append({
                'query': data.get('输入query', ''),
                'intent': data.get('输入intent', ''),
                'result': data.get('是否更符合意图', -1),
                'reason': data.get('原因', ''),
            })
        except json.JSONDecodeError as e:
            failed_list.append({
                'raw_response': text,
                'error': f'JSON格式错误: {e}',
            })
    return success_list, failed_list


def main():
    if not LLM_API_KEY:
        raise ValueError("请设置环境变量 LLM_API_KEY")

    df = pd.read_excel(INPUT_FILE)
    print(f"读取完成，共{len(df)}条数据")

    required_cols = {'query', 'intent'}
    if not required_cols.issubset(set(df.columns)):
        missing = required_cols - set(df.columns)
        raise ValueError(f"输入文件缺少必要的列: {missing}")

    menu_dict = read_menu_desc()
    print(f"读取完成，共{len(menu_dict)}个意图描述")

    llm_queries = []
    for _, row in df.iterrows():
        input_query = row['query']
        input_intent = row['intent']

        if input_intent in menu_dict:
            input_menu_desc = menu_dict[input_intent]
            llm_prompt = get_prompt(input_query, input_intent, input_menu_desc)
            llm_queries.append({
                'content': llm_prompt,
                'temperature': LLM_TEMPERATURE,
                'max_tokens': LLM_MAX_TOKENS,
            })
        else:
            print(f"意图'{input_intent}'不在意图描述中，跳过")

    print(f"\n共生成{len(llm_queries)}个LLM请求")

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        llm_res = list(tqdm(executor.map(call_llm_api_kwargs, llm_queries), total=len(llm_queries)))

    llm_final_res = []
    for example in llm_res:
        llm_final_res.append(example[0]['content'])

    success_data, failed_data = parse_llm_response(llm_final_res)
    print(f"\n解析完成: 成功{len(success_data)}条, 失败: {len(failed_data)}条")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    result_df = pd.DataFrame(success_data)
    result_df.to_excel(OUTPUT_FILE, index=False)
    print(f"判定结果已保存至: {OUTPUT_FILE}")

    if failed_data:
        print("\n失败记录：")
        for i, failed in enumerate(failed_data[:5], 1):
            print(f"\n{i}.{failed.get('error', '未知错误')}")

if __name__ == "__main__":
    main()
