#!/usr/bin/env python3
"""
build_unpaywall.py

Pipeline:
 - Query CrossRef for works by keyword(s)
 - For each DOI, query Unpaywall to find OA locations
 - Prefer CrossRef 'abstract' if present; otherwise download OA PDF/HTML and extract text
 - Extract sentences/abstracts, label by keyword heuristics, write fastText training file

Usage:
  python tools/fasttext/build_unpaywall.py --queries "zakat,islamic finance,personal finance indonesia" --email you@example.com --out data/fasttext/train_unpaywall.txt --max-per-query 50

Notes:
 - Unpaywall requires an email parameter when calling their API.
 - This script is conservative about rate limits and only fetches OA copies.
 - PDF extraction uses pdfminer.six; HTML uses BeautifulSoup.
"""
import argparse
import json
import os
import re
import sys
import time
from typing import Optional

import requests
from bs4 import BeautifulSoup
from pdfminer.high_level import extract_text as extract_pdf_text

CROSSREF_API = "https://api.crossref.org/works"
UNPAYWALL_API = "https://api.unpaywall.org/v2/{doi}"
HEADERS = {"User-Agent": "ckp_temp-unpaywall/1.0 (+https://example.local)"}

LABEL_KEYWORDS = {
    "zakat": ["zakat", "zakat fitrah", "zakat mal", "zakat profesi"],
    "sedekah": ["sedekah", "sedakah", "infaq", "sadaqah", "wakaf"],
    "tabungan": ["tabungan", "menabung", "rekening tabungan"],
    "investasi": ["investasi", "saham", "reksa", "obligasi"],
    "makanan": ["makan", "restoran", "warung", "makan siang"],
    "belanja": ["belanja", "pembelian", "supermarket", "pasar"],
    "utilitas": ["listrik", "air", "internet", "telepon", "pln", "pdam"],
    "pinjaman": ["pinjaman", "kredit", "hutang", "angsuran", "cicilan"],
    "donasi": ["donasi", "sumbangan", "amal"],
}

MIN_SENTENCE_CHARS = 40


def normalize_text(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def extract_text_from_html(html: str) -> str:
    soup = BeautifulSoup(html, "lxml")
    for tag in soup(["script", "style", "noscript", "iframe"]):
        tag.decompose()
    main = soup.find("main") or soup.find("article")
    text = main.get_text(separator=" ") if main else soup.get_text(separator=" ")
    return normalize_text(text)


def split_sentences(text: str):
    parts = re.split(r"(?<=[.!?])\s+", text)
    return [p.strip() for p in parts if len(p.strip()) >= MIN_SENTENCE_CHARS]


def find_label_for_sentence(s: str):
    ls = s.lower()
    for label, kws in LABEL_KEYWORDS.items():
        for kw in kws:
            if kw in ls:
                return label
    return None


def query_crossref(query: str, rows: int = 20, offset: int = 0):
    params = {"query": query, "rows": rows, "offset": offset}
    r = requests.get(CROSSREF_API, params=params, headers=HEADERS, timeout=15)
    r.raise_for_status()
    j = r.json()
    items = j.get("message", {}).get("items", [])
    return items


def query_unpaywall(doi: str, email: str) -> Optional[dict]:
    url = UNPAYWALL_API.format(doi=doi)
    params = {"email": email}
    r = requests.get(url, params=params, headers=HEADERS, timeout=15)
    if r.status_code == 200:
        return r.json()
    return None


def download_url(url: str, timeout=30) -> Optional[bytes]:
    try:
        r = requests.get(url, headers=HEADERS, timeout=timeout)
        if r.status_code == 200:
            return r.content
    except Exception:
        return None
    return None


def extract_text_from_pdf_bytes(b: bytes, tmp_path: str) -> Optional[str]:
    try:
        with open(tmp_path, "wb") as f:
            f.write(b)
        text = extract_pdf_text(tmp_path)
        return normalize_text(text)
    except Exception:
        return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--queries", required=True, help="Comma-separated queries (quoted)")
    p.add_argument("--email", required=True, help="Email for Unpaywall API calls")
    p.add_argument("--out", required=True)
    p.add_argument("--max-per-query", type=int, default=50)
    p.add_argument("--crossref-rows", type=int, default=50)
    p.add_argument('--resume', action='store_true', help='resume previous run using state file')
    p.add_argument('--state-file', default=None, help='path to state file (defaults to <out>.state.json)')
    args = p.parse_args()

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    queries = [q.strip() for q in args.queries.split(",") if q.strip()]
    total_written = 0
    state_path = args.state_file if args.state_file else args.out + '.state.json'
    state = {}
    if args.resume and os.path.exists(state_path):
        try:
            with open(state_path, 'r', encoding='utf-8') as sf:
                state = json.load(sf)
        except Exception:
            state = {}
    tmp_pdf = os.path.join("/tmp", "ckp_temp_unpaywall_tmp.pdf")

    # open out file in append mode when resuming, otherwise overwrite
    out_mode = 'a' if args.resume else 'w'
    with open(args.out, out_mode, encoding='utf-8') as out:
        for q in queries:
            print(f"Searching CrossRef for '{q}'...", file=sys.stderr)
            qstate = state.get(q, {})
            offset = qstate.get('offset', 0)
            seen_dois = set(qstate.get('seen_dois', []))
            written_for_q = qstate.get('written', 0)
            # if we've already reached the per-query target, skip
            if written_for_q >= args.max_per_query:
                print(f"Skipping '{q}', already have {written_for_q} lines (target {args.max_per_query}).", file=sys.stderr)
                continue
            while written_for_q < args.max_per_query and offset < 1000:
                # Query CrossRef with simple retry/backoff to avoid crashing on transient network errors
                items = []
                max_retries = 3
                attempt = 0
                while attempt < max_retries:
                    try:
                        items = query_crossref(q, rows=args.crossref_rows, offset=offset)
                        break
                    except Exception as e:
                        attempt += 1
                        print(f"CrossRef query failed (attempt {attempt}/{max_retries}): {e}", file=sys.stderr)
                        # persist state so we can resume safely
                        try:
                            state[q] = {'seen_dois': list(seen_dois), 'written': written_for_q, 'offset': offset}
                            with open(state_path, 'w', encoding='utf-8') as sf:
                                json.dump(state, sf)
                        except Exception:
                            pass
                        if attempt >= max_retries:
                            print(f"Giving up on query '{q}' at offset {offset} after {attempt} attempts.", file=sys.stderr)
                            items = []
                            break
                        time.sleep(5 * attempt)
                if not items:
                    break
                for it in items:
                    doi = it.get("DOI")
                    if not doi or doi in seen_dois:
                        continue
                    seen_dois.add(doi)
                    # Prefer CrossRef abstract if available
                    cr_abstract = it.get("abstract")
                    if cr_abstract:
                        # CrossRef returns HTML-ish abstract; strip tags
                        t = re.sub(r'<.*?>', ' ', cr_abstract)
                        t = normalize_text(t)
                        sents = split_sentences(t)
                        for s in sents:
                            label = find_label_for_sentence(s)
                            if label:
                                out.write(f"__label__{label} {s}\n")
                                total_written += 1
                                written_for_q += 1
                                # persist state
                                try:
                                    state[q] = {'seen_dois': list(seen_dois), 'written': written_for_q, 'offset': offset}
                                    with open(state_path, 'w', encoding='utf-8') as sf:
                                        json.dump(state, sf)
                                except Exception:
                                    pass
                                if written_for_q >= args.max_per_query:
                                    break
                        if written_for_q >= args.max_per_query:
                            break
                    # Query Unpaywall to find OA copy
                    try:
                        up = query_unpaywall(doi, args.email)
                    except Exception:
                        up = None
                    if up and up.get("is_oa"):
                        locations = up.get("oa_locations") or []
                        # prefer pdf
                        pdf_url = None
                        html_url = None
                        for loc in locations:
                            url = loc.get("url")
                            if not url:
                                continue
                            if loc.get("url_for_landing_page") and not pdf_url:
                                html_url = loc.get("url_for_landing_page")
                            if loc.get("url_for_pdf"):
                                pdf_url = loc.get("url_for_pdf")
                                break
                        content = None
                        if pdf_url:
                            print(f"Downloading PDF {pdf_url}", file=sys.stderr)
                            b = download_url(pdf_url)
                            if b:
                                text = extract_text_from_pdf_bytes(b, tmp_pdf)
                                if text:
                                    sents = split_sentences(text)
                                    for s in sents:
                                        label = find_label_for_sentence(s)
                                        if label:
                                            out.write(f"__label__{label} {s}\n")
                                            total_written += 1
                                            written_for_q += 1
                                            try:
                                                state[q] = {'seen_dois': list(seen_dois), 'written': written_for_q, 'offset': offset}
                                                with open(state_path, 'w', encoding='utf-8') as sf:
                                                    json.dump(state, sf)
                                            except Exception:
                                                pass
                                            if written_for_q >= args.max_per_query:
                                                break
                        elif html_url:
                            print(f"Downloading HTML {html_url}", file=sys.stderr)
                            b = download_url(html_url)
                            if b:
                                try:
                                    txt = extract_text_from_html(b.decode('utf-8', errors='ignore'))
                                    sents = split_sentences(txt)
                                    for s in sents:
                                        label = find_label_for_sentence(s)
                                        if label:
                                            out.write(f"__label__{label} {s}\n")
                                            total_written += 1
                                            written_for_q += 1
                                            try:
                                                state[q] = {'seen_dois': list(seen_dois), 'written': written_for_q, 'offset': offset}
                                                with open(state_path, 'w', encoding='utf-8') as sf:
                                                    json.dump(state, sf)
                                            except Exception:
                                                pass
                                            if written_for_q >= args.max_per_query:
                                                break
                                except Exception:
                                    pass
                    # polite pause
                    time.sleep(1.0)
                    if written_for_q >= args.max_per_query:
                        break
                offset += args.crossref_rows
                # break early if we've written enough for this query
                if written_for_q >= args.max_per_query:
                    break
            print(f"Wrote {total_written} lines for query '{q}' so far.", file=sys.stderr)
            total_written = 0  # reset counter per query
            # persist per-query final state
            try:
                state[q] = {'seen_dois': list(seen_dois), 'written': written_for_q, 'offset': offset}
                with open(state_path, 'w', encoding='utf-8') as sf:
                    json.dump(state, sf)
            except Exception:
                pass
    print(f"Finished. Output -> {args.out}")


if __name__ == '__main__':
    main()
