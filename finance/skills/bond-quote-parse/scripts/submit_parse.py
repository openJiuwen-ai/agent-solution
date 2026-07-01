#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""提交 BCCP 到 POST /api/v1/parse/batch（无状态黑盒解析）。"""
import json
import os
import sys


def _load_env_file(path):
    if not os.path.isfile(path):
        return
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            os.environ.setdefault(k.strip(), v.strip())


def main():
    if len(sys.argv) < 2:
        print('用法: python submit_parse.py <corpus.json>', file=sys.stderr)
        sys.exit(2)

    ref = os.path.join(os.path.dirname(__file__), '..', 'references')
    _load_env_file(os.path.join(ref, 'config.local.env'))
    _load_env_file(os.path.join(ref, 'config.example.env'))

    base = (os.environ.get('BOND_PARSE_API_BASE') or '').rstrip('/')
    key = (os.environ.get('BOND_PARSE_API_KEY') or '').strip()
    if not base:
        print('请设置 BOND_PARSE_API_BASE（见 references/config.example.env）', file=sys.stderr)
        sys.exit(2)

    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        payload = json.load(f)

    import urllib.request
    headers = {'Content-Type': 'application/json'}
    if key:
        headers['Authorization'] = 'Bearer %s' % key
    req = urllib.request.Request(
        base + '/api/v1/parse/batch',
        data=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
        headers=headers,
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            body = resp.read().decode('utf-8')
            print(body)
            data = json.loads(body)
            if data.get('code') != 200:
                sys.exit(1)
    except Exception as ex:
        print('请求失败:', ex, file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
