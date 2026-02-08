#!/usr/bin/env python3
"""
train_fasttext.py

Extract labeled examples from the app SQLite DB (or CSV) and train a fastText supervised model.
Produces: model.bin and model.vec in the output directory.

Usage examples:
  python tools/fasttext/train_fasttext.py --db /path/to/catatan_keuangan.db --out ./models --label-map intent_map.json
  python tools/fasttext/train_fasttext.py --csv samples/sample_labeled.csv --out ./models

The script will try to detect common table/column names used by the app. If DB extraction fails,
pass a labeled CSV with two columns: label,text (header allowed).

Label format for fastText: each line: __label__<label> <text>

"""
import argparse
import csv
import json
import os
import sqlite3
import sys
import tempfile

try:
    import fasttext
except Exception:
    fasttext = None


COMMON_SQL_QUERIES = [
    # messages table (chat)
    ("messages", "SELECT text AS text, intent AS label FROM messages WHERE text IS NOT NULL"),
    # transactions table: use description -> create intent 'create'
    ("transactions", "SELECT description AS text, 'create' AS label FROM transactions WHERE description IS NOT NULL"),
    # parsed_messages table (if exists)
    ("parsed_messages", "SELECT raw_text AS text, intent AS label FROM parsed_messages WHERE raw_text IS NOT NULL"),
]


def extract_from_db(db_path, tmpfile_path, max_examples=None):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    found = 0
    with open(tmpfile_path, "w", encoding="utf-8") as out:
        for table, query in COMMON_SQL_QUERIES:
            try:
                cur.execute(query)
                rows = cur.fetchall()
                for label, text in ((r[1], r[0]) if len(r) >= 2 else (r[1], r[0]) for r in rows):
                    if not text:
                        continue
                    # sanitize label
                    label = str(label).strip() if label else "unknown"
                    line = f"__label__{label} {text.replace('\n', ' ').strip()}\n"
                    out.write(line)
                    found += 1
                    if max_examples and found >= max_examples:
                        return found
            except sqlite3.OperationalError:
                # table or column missing — skip
                continue
    return found


def csv_to_fasttext(in_csv, tmpfile_path):
    count = 0
    with open(in_csv, newline='', encoding='utf-8') as f, open(tmpfile_path, 'w', encoding='utf-8') as out:
        reader = csv.DictReader(f)
        # accept header variants: label,text or intent,text
        for r in reader:
            label = r.get('label') or r.get('intent') or r.get('Label') or r.get('intent_label')
            text = r.get('text') or r.get('Text') or r.get('message')
            if not label or not text:
                continue
            out.write(f"__label__{label.strip()} {text.replace('\n',' ').strip()}\n")
            count += 1
    return count


def train(ft_train_path, out_dir, epoch=5, lr=1.0, dim=100, ws=5, minCount=1):
    if fasttext is None:
        print("fasttext python package not installed. Install with: pip install fasttext", file=sys.stderr)
        sys.exit(2)
    os.makedirs(out_dir, exist_ok=True)
    model_path = os.path.join(out_dir, "fasttext_model.bin")
    print(f"Training fastText supervised model from '{ft_train_path}' -> '{model_path}'")
    model = fasttext.train_supervised(input=ft_train_path, epoch=epoch, lr=lr, dim=dim, ws=ws, minCount=minCount)
    model.save_model(model_path)
    # also save labels and vectors (optional)
    vec_path = os.path.join(out_dir, "fasttext_model.vec")
    model.get_input_matrix()
    try:
        model.save_model(vec_path)
    except Exception:
        # some fasttext versions don't support save in vec — ignore
        pass
    print("Training finished. Model saved to:")
    print(" -", model_path)
    return model_path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--db', help='Path to SQLite DB to extract labeled examples from')
    p.add_argument('--csv', help='Alternative: labeled CSV with header label,text')
    p.add_argument('--out', default='./models', help='Output directory for trained model')
    p.add_argument('--epoch', type=int, default=8)
    p.add_argument('--lr', type=float, default=1.0)
    p.add_argument('--dim', type=int, default=128)
    p.add_argument('--max-examples', type=int, default=0)
    args = p.parse_args()

    tmpfile = os.path.join(tempfile.gettempdir(), 'fasttext_train.txt')
    count = 0
    if args.db:
        print(f"Attempting to extract training data from DB: {args.db}")
        try:
            count = extract_from_db(args.db, tmpfile, max_examples=(args.max_examples or None))
        except Exception as e:
            print("DB extraction failed:", e, file=sys.stderr)
            sys.exit(3)
    elif args.csv:
        print(f"Reading labeled CSV: {args.csv}")
        count = csv_to_fasttext(args.csv, tmpfile)
    else:
        print("No data source provided. Please provide --db or --csv", file=sys.stderr)
        sys.exit(1)

    if count == 0:
        print("No labeled examples extracted. Provide CSV or check DB schema.")
        sys.exit(4)

    print(f"Extracted {count} examples, training...")
    model_path = train(tmpfile, args.out, epoch=args.epoch, lr=args.lr, dim=args.dim)
    print("Done. Example inference:")
    try:
        import fasttext
        m = fasttext.load_model(model_path)
        print(m.predict("transfer 20000 tabungan", k=3))
    except Exception:
        pass


if __name__ == '__main__':
    main()
