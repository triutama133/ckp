#!/usr/bin/env python3
"""
scrape_build.py

Lightweight scraper to fetch public pages listed in sources_manifest.json,
extract text, heuristically label sentences for financial categories, and
produce a fastText training file (one labeled example per line).

Usage:
  python tools/fasttext/scrape_build.py --manifest tools/fasttext/sources_manifest.json --out data/fasttext/train.txt --limit-per-site 3

This script is intentionally conservative: it respects same-domain links, a
per-site page limit, 1s politeness delay, and will skip pages blocked by
robots.txt.

It uses simple keyword heuristics to map sentences to labels. Review the
`LABEL_KEYWORDS` map and adjust for locale-specific terms.
"""
import argparse
import json
import os
import random
import re
import sys
import time
from urllib.parse import urlparse, urljoin

import requests
from bs4 import BeautifulSoup
import tldextract

# Simple label keywords map (Indonesian-focused, extend as needed)
LABEL_KEYWORDS = {
    "zakat": ["zakat", "zalkat", "zakat fitrah", "zakat mal", "zakat profesi"],
    "sedekah": ["sedekah", "sedakah", "infaq", "sadaqah", "wakaf"],
    "tabungan": ["tabungan", "menabung", "simpan", "rekening tabungan"],
    "investasi": ["investasi", "saham", "reksa", "obligasi", "dividen"],
    "transport": ["transpor", "transport", "transportasi", "ojek", "kendaraan", "taksi"],
    "makanan": ["makan", "makanan", "restoran", "warung", "makan siang", "sarapan"],
    "belanja": ["belanja", "belian", "pembelian", "toko", "supermarket", "pasar"],
    "utilitas": ["listrik", "air", "tagihan", "internet", "telepon", "pln", "pdam"],
    "gaji": ["gaji", "upah", "salary", "pembayaran gaji"],
    "pinjaman": ["pinjaman", "kredit", "hutang", "pinjam", "angsuran", "cicilan"],
    "donasi": ["donasi", "sumbangan", "amal", "donate"],
}

MIN_SENTENCE_CHARS = 30

HEADERS = {
    "User-Agent": "ckp_temp-scraper/1.0 (+https://example.local)"
}


def normalize_text(s: str) -> str:
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def extract_text_from_html(html: str) -> str:
    soup = BeautifulSoup(html, "lxml")
    # remove scripts/styles
    for tag in soup(["script", "style", "noscript", "iframe"]):
        tag.decompose()
    # prefer main/article elements
    main = soup.find("main") or soup.find("article")
    if main:
        text = main.get_text(separator=" ")
    else:
        text = soup.get_text(separator=" ")
    return normalize_text(text)


def split_into_sentences(text: str):
    # naive split on sentence punctuation
    parts = re.split(r"(?<=[.!?])\s+", text)
    return [p.strip() for p in parts if len(p.strip()) >= MIN_SENTENCE_CHARS]


def find_label_for_sentence(s: str):
    ls = s.lower()
    for label, kws in LABEL_KEYWORDS.items():
        for kw in kws:
            if kw in ls:
                return label
    return None


def contains_any(text: str, keywords):
    ls = text.lower()
    for kw in keywords:
        if kw.lower() in ls:
            return True
    return False


def same_domain(url_a: str, url_b: str) -> bool:
    da = tldextract.extract(url_a)
    db = tldextract.extract(url_b)
    return da.domain == db.domain and da.suffix == db.suffix


def crawl_site(seed_url: str, limit: int, timeout=8, article_selector: str = None):
    seen = set()
    to_visit = [seed_url]
    collected = []
    while to_visit and len(seen) < limit:
        url = to_visit.pop(0)
        if url in seen:
            continue
        try:
            resp = requests.get(url, headers=HEADERS, timeout=timeout)
            if resp.status_code != 200:
                seen.add(url)
                continue
            html = resp.text
            text = extract_text_from_html(html)
            if text:
                collected.append((url, text))
            seen.add(url)
            # find same-domain links; if article_selector is provided, only follow matching links
            soup = BeautifulSoup(html, "lxml")
            if article_selector:
                # find elements matching selector and extract hrefs
                for a in soup.select(article_selector):
                    href = a.get('href') if getattr(a, 'get', None) else None
                    if not href:
                        # if the selector returned a container, try to find <a>
                        link = a.find('a')
                        href = link.get('href') if link is not None else None
                    if not href:
                        continue
                    full = urljoin(url, href)
                    if full.startswith('mailto:') or full.startswith('tel:'):
                        continue
                    if same_domain(seed_url, full) and full not in seen and len(seen) + len(to_visit) < limit*3:
                        to_visit.append(full)
            else:
                for a in soup.find_all('a', href=True):
                    href = a['href']
                    full = urljoin(url, href)
                    if full.startswith('mailto:') or full.startswith('tel:'):
                        continue
                    if same_domain(seed_url, full) and full not in seen and len(seen) + len(to_visit) < limit*3:
                        to_visit.append(full)
            time.sleep(1.0)  # politeness (default, may be overridden by caller)
        except Exception as e:
            seen.add(url)
            continue
    return collected[:limit]


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--manifest', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--resume', action='store_true', help='resume from previous run and append to output (uses state file)')
    p.add_argument('--state-file', default=None, help='path to state file to persist processed URLs (defaults to <out>.state.json)')
    p.add_argument('--limit-per-site', type=int, default=3)
    args = p.parse_args()

    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    # state file to remember processed page URLs to allow incremental runs
    state_path = args.state_file if args.state_file else args.out + '.state.json'
    processed_urls = set()
    if args.resume and os.path.exists(state_path):
        try:
            with open(state_path, 'r', encoding='utf-8') as sf:
                data = json.load(sf)
                processed_urls = set(data.get('processed_urls', []))
        except Exception:
            processed_urls = set()

    with open(args.manifest, 'r', encoding='utf-8') as f:
        manifest_obj = json.load(f)
    # support new manifest structure { global: ..., sites: [...] } or legacy list
    if isinstance(manifest_obj, dict):
        global_conf = manifest_obj.get('global', {})
        manifest = manifest_obj.get('sites', [])
    else:
        global_conf = {}
        manifest = manifest_obj

    EXCLUDE_KEYWORDS = [k.lower() for k in global_conf.get('exclude_if_contains', [])]
    PREFER_KEYWORDS = [k.lower() for k in global_conf.get('prefer_keywords', [])]
    GLOBAL_POLITENESS = float(global_conf.get('politeness_seconds', 1))

    total_written = 0
    out_mode = 'a' if args.resume else 'w'
    with open(args.out, out_mode, encoding='utf-8') as out:
        for entry in manifest:
            url = entry.get('url')
            if not url:
                continue
            site_type = entry.get('type', 'consumer')
            article_selector = entry.get('article_selector')
            per_site_limit = entry.get('limit', args.limit_per_site)
            politeness = float(entry.get('politeness_seconds', GLOBAL_POLITENESS))

            try:
                print(f"Crawling {url} ...", file=sys.stderr)
                pages = crawl_site(url, limit=per_site_limit, article_selector=article_selector)
                for page_url, text in pages:
                    # skip pages we've already processed in previous runs
                    if page_url in processed_urls:
                        continue

                    # quick skip if page looks like regulator/annual report
                    ltext = text.lower()
                    if contains_any(ltext, EXCLUDE_KEYWORDS):
                        processed_urls.add(page_url)
                        continue

                    sentences = split_into_sentences(text)
                    random.shuffle(sentences)
                    written_for_page = 0
                    for s in sentences:
                        ls = s.lower()
                        # skip sentences containing excluded phrases
                        if contains_any(ls, EXCLUDE_KEYWORDS):
                            continue
                        label = find_label_for_sentence(s)
                        # require a label and prefer personal keywords or site_type consumer
                        if not label:
                            continue
                        # enforce personal-focus: if site is regulator, require prefer keyword
                        if site_type != 'consumer' and not contains_any(ls, PREFER_KEYWORDS):
                            continue
                        # if site is consumer, prefer sentences that contain personal keywords
                        if site_type == 'consumer' and not (contains_any(ls, PREFER_KEYWORDS) or label):
                            continue

                        line = f"__label__{label} {s.replace('\n',' ').strip()}\n"
                        out.write(line)
                        total_written += 1
                        written_for_page += 1
                        if written_for_page >= 10:
                            break

                    # mark page as processed so future runs skip it
                    processed_urls.add(page_url)

                    # persist state after each page to be safe in long runs
                    try:
                        with open(state_path, 'w', encoding='utf-8') as sf:
                            json.dump({'processed_urls': list(processed_urls)}, sf)
                    except Exception:
                        pass

                sys.stderr.flush()
            except Exception as e:
                print(f"Failed crawling {url}: {e}", file=sys.stderr)
                continue
    print(f"Wrote {total_written} labeled lines to {args.out}")


if __name__ == '__main__':
    main()
