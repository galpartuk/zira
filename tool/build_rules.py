# -*- coding: utf-8 -*-
"""Builds assets/rules/comprehensive.json from Bandai's Digimon Card Game
Comprehensive Rules PDF.

    python -I tool/build_rules.py                 # downloads the current PDF
    python -I tool/build_rules.py path/to/general_rule.pdf

Run it whenever Bandai publishes a new version, then ship a new app build.
Needs: pip install pypdf
"""
import email.utils
import json
import os
import re
import sys
import tempfile
import urllib.request

import pypdf

URL = "https://en.digimoncard.com/rule/pdf/general_rule.pdf"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "rules", "comprehensive.json")


def fetch():
    req = urllib.request.Request(URL, headers={"User-Agent": "zira-rules-builder"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
        last_mod = r.headers.get("Last-Modified", "")
    path = os.path.join(tempfile.mkdtemp(), "general_rule.pdf")
    with open(path, "wb") as fh:
        fh.write(data)
    return path, last_mod


def clean(s):
    s = re.sub(r"(\d)\s*-\s+(\d)", r"\1-\2", s)          # "15 - 8-2", "15- 8"
    s = re.sub(r"(\d)\s+-(\d)", r"\1-\2", s)             # "15 -8"
    s = re.sub(r"(\w)\s+-(\w)", r"\1-\2", s)             # "De -Digivolve", "in -game"
    s = re.sub(r"\s+", " ", s).strip()
    # The PDF repeats the link target right after a "(refer to ...)" bracket.
    s = re.sub(r"(refer to (\d+(?:-\d+)*)[^)]*\))\2(?![\d-])", r"\1", s)
    return s


def parse(text):
    head = text[:3000]
    ver = re.search(r"Ver\.\s*([\d.]+)", head)
    upd = re.search(r"Last Updated:\s*([\d/]+)", head)

    # Chapter titles from the table of contents: "16. Keyword Effects ....... 35"
    chapters = {}
    for m in re.finditer(r"^(\d{1,2})\.\s+([^.\n]+?)\s*\.{3,}", head, re.M):
        chapters[m.group(1)] = m.group(2).strip()

    start = text.index("\n1. Game Overview \n1-1.")
    hist_at = text.rindex("Update History")
    body, history = text[start:hist_at], text[hist_at:]

    ident = re.compile(r"^(\d+(?:-\d+)*)\.\s*(.*)$")
    rules, cur = [], None
    for raw in body.splitlines():
        line = raw.strip()
        if not line or re.fullmatch(r"\d{1,2}", line):  # blank line / page number
            continue
        m = ident.match(line)
        if m:
            cur = {"id": m.group(1), "t": m.group(2)}
            rules.append(cur)
        elif cur:
            # Join a word split by a line-end hyphen ("Digi-" / "volve").
            if cur["t"].endswith("-") and line[:1].islower():
                cur["t"] += line
            else:
                cur["t"] += " " + line

    ids = set()
    for r in rules:
        r["t"] = clean(r["t"])
        ids.add(r["id"])

    # Update history: "(2026/09/18) Ver. 4.3" followed by "Updated 2-3-3-3." ...
    changed = {}
    cur_ver = None
    for line in history.splitlines():
        hv = re.search(r"\(\s*\d{4}/\d{2}/\d{2}\s*[)）]\s*Ver\.?\s*([\d.]+)", line)
        if hv:
            cur_ver = hv.group(1)
            continue
        if cur_ver:
            for rid in re.findall(r"(\d+(?:-\d+)+)", clean(line)):
                if rid in ids:
                    changed[rid] = cur_ver

    # Keyword effects live in chapter 16: "16-5. <Blocker>" + "16-5-1. ... is a keyword effect ..."
    keywords = []
    by_id = {r["id"]: r for r in rules}
    for r in rules:
        km = re.fullmatch(r"<([^>]+)>(?:\s*\(.*\))?", r["t"])
        if r["id"].startswith("16-") and r["id"].count("-") == 1 and km:
            first = by_id.get(r["id"] + "-1")
            keywords.append({"name": km.group(1), "id": r["id"], "sum": first["t"] if first else ""})

    for r in rules:
        if r["id"] in changed:
            r["v"] = changed[r["id"]]

    return {
        "title": "Digimon Card Game Comprehensive Rules",
        "version": ver.group(1) if ver else "",
        "updated": upd.group(1) if upd else "",
        "chapters": chapters,
        "keywords": keywords,
        "rules": rules,
    }


def main():
    if len(sys.argv) > 1:
        path, last_mod = sys.argv[1], ""
    else:
        path, last_mod = fetch()
    reader = pypdf.PdfReader(path)
    text = "\n".join((p.extract_text() or "") for p in reader.pages)
    data = parse(text)
    data["source"] = URL
    data["lastModified"] = last_mod
    if last_mod:
        data["lastModifiedEpoch"] = int(email.utils.parsedate_to_datetime(last_mod).timestamp())

    ids = {r["id"] for r in data["rules"]}
    refs = [x for r in data["rules"] for x in re.findall(r"refer to (\d+(?:-\d+)*)", r["t"])]
    missing = sorted({x for x in refs if x not in ids})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))
    latest = sum(1 for r in data["rules"] if r.get("v") == data["version"])
    print(f"Ver {data['version']} ({data['updated']}): {len(data['rules'])} rules, "
          f"{len(data['chapters'])} chapters, {len(data['keywords'])} keywords, "
          f"{len(refs)} refs ({len(missing)} unresolved: {missing[:6]}), "
          f"{latest} changed in latest version -> {os.path.relpath(OUT, ROOT)} "
          f"({os.path.getsize(OUT) // 1024} KB)")


if __name__ == "__main__":
    main()
