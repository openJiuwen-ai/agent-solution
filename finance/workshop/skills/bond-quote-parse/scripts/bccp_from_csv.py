#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CSV/表格行 → BCCP JSON（stdout）。"""
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'backend'))
sys.path.insert(0, str(ROOT))

try:
    from backend.systems.bond_quote.bond_bccp import BCCP_SCHEMA_VERSION, _normalize_corpus_type
except ImportError:
    from systems.bond_quote.bond_bccp import BCCP_SCHEMA_VERSION, _normalize_corpus_type


def _row_to_message(row: dict, idx: int) -> dict:
    corpus_id = row.get('corpus_id') or idx
    try:
        corpus_id = int(corpus_id)
    except (TypeError, ValueError):
        corpus_id = idx
    ctype_raw = row.get('corpus_type') or '报价'
    ctype, err = _normalize_corpus_type(ctype_raw)
    if err:
        ctype = 1
    msg = {
        'message_id': (row.get('message_id') or '').strip() or 'm-%s' % corpus_id,
        'corpus_id': corpus_id,
        'corpus_type': ctype,
        'speak_time': (row.get('speak_time') or '').strip(),
        'raw_content': (row.get('raw_content') or '').strip(),
    }
    sid = (row.get('speaker_id') or row.get('speaker_wxid') or '').strip()
    if sid:
        msg['speaker_id'] = sid
    sn = (row.get('speaker_name') or row.get('wx_name') or '').strip()
    if sn:
        msg['speaker_name'] = sn
    inst = (row.get('institution_name') or '').strip()
    if inst:
        msg['institution_name'] = inst
    return msg


def main():
    if len(sys.argv) < 2:
        print('用法: python bccp_from_csv.py <grid.csv>', file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1])
    with path.open('r', encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        messages = []
        for i, row in enumerate(reader, start=1):
            if not any((v or '').strip() for v in row.values()):
                continue
            messages.append(_row_to_message(row, i))
    out = {
        'schema_version': BCCP_SCHEMA_VERSION,
        'client_request_id': path.stem,
        'bond_context': {},
        'messages': messages,
        'parse_options': {},
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
