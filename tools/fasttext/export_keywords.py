#!/usr/bin/env python3
"""
export_keywords.py

Create a tiny rule model from labeled CSV or SQLite DB. Output a simple tab-separated file:
label\tkeyword1,keyword2,keyword3

This file is intentionally simple so a tiny native C++ predictor can load it without heavy deps.
"""
import argparse
import csv
import os
import re
import sqlite3
from collections import Counter, defaultdict


def tokenize(text):
    # simple tokenizer: lowercase, split non-word
    return [t for t in re.split(r"\W+", text.lower()) if t]


def from_csv(csv_path, out_path, top_k=10):
    labels = defaultdict(Counter)
    with open(csv_path, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for r in reader:
            label = (r.get('label') or r.get('intent') or '').strip()
            text = (r.get('text') or r.get('message') or '').strip()
            if not label or not text:
                continue
            for t in tokenize(text):
                labels[label][t] += 1
    with open(out_path, 'w', encoding='utf-8') as out:
        for label, counter in labels.items():
            top = [w for w, _ in counter.most_common(top_k)]
            out.write(label + '\t' + ','.join(top) + '\n')


def from_db(db_path, out_path, top_k=10):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    # try some likely tables/columns
    queries = [
        ("messages", "SELECT text AS text, intent AS label FROM messages WHERE text IS NOT NULL"),
        ("parsed_messages", "SELECT raw_text AS text, intent AS label FROM parsed_messages WHERE raw_text IS NOT NULL"),
        ("transactions", "SELECT description AS text, 'create' AS label FROM transactions WHERE description IS NOT NULL"),
    ]
    labels = defaultdict(Counter)
    for name, q in queries:
        try:
            cur.execute(q)
            for row in cur.fetchall():
                text = row[0] if row[0] else ''
                label = row[1] if len(row) > 1 and row[1] else 'unknown'
                for t in tokenize(text):
                    labels[label][t] += 1
        except Exception:
            continue
    with open(out_path, 'w', encoding='utf-8') as out:
        for label, counter in labels.items():
            top = [w for w, _ in counter.most_common(top_k)]
            out.write(label + '\t' + ','.join(top) + '\n')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', help='Labeled CSV')
    p.add_argument('--db', help='Path to SQLite DB')
    p.add_argument('--out', default='models/rules.model')
    p.add_argument('--topk', type=int, default=12)
    args = p.parse_args()
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    if args.csv:
        from_csv(args.csv, args.out, top_k=args.topk)
    elif args.db:
        from_db(args.db, args.out, top_k=args.topk)
    else:
        print('Provide --csv or --db')


if __name__ == '__main__':
    main()
