#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""本地校验 BCCP JSON（可选调用服务端 /api/v1/parse/validate）。"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
BACKEND = os.path.join(ROOT, 'backend')
if BACKEND not in sys.path:
    sys.path.insert(0, BACKEND)

try:
    from backend.systems.bond_quote.bond_bccp import validate_and_normalize_bccp
except ImportError:
    from systems.bond_quote.bond_bccp import validate_and_normalize_bccp


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
        print('用法: python validate_bccp.py <corpus.json> [--remote]', file=sys.stderr)
        sys.exit(2)
    ref = os.path.join(os.path.dirname(__file__), '..', 'references')
    _load_env_file(os.path.join(ref, 'config.local.env'))
    _load_env_file(os.path.join(ref, 'config.example.env'))

    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        payload = json.load(f)
    ok, norm, errors, warnings = validate_and_normalize_bccp(payload)
    if warnings:
        for w in warnings:
            print('WARN:', w)
    if not ok:
        for e in errors:
            print('ERROR:', e)
        sys.exit(1)
    print('OK: %d messages' % len(norm['messages']))

    base = (os.environ.get('BOND_PARSE_API_BASE') or '').rstrip('/')
    key = os.environ.get('BOND_PARSE_API_KEY') or ''
    if base and '--remote' in sys.argv:
        try:
            import urllib.request
            req = urllib.request.Request(
                base + '/api/v1/parse/validate',
                data=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer %s' % key,
                },
                method='POST',
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                print('REMOTE:', resp.read().decode('utf-8')[:2000])
        except Exception as ex:
            print('REMOTE failed:', ex, file=sys.stderr)
            sys.exit(1)


if __name__ == '__main__':
    main()
