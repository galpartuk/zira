# -*- coding: utf-8 -*-
"""Builds assets/rules/qa.json from the official Digimon Card Game Q&A
(world.digimoncard.com/rule/): Rule Q&A by category and Card Q&A by product.

    python -I tool/build_qa.py            # ~80 requests, 1 s apart

Run it together with tool/build_rules.py before a release.
"""
import html
import json
import os
import re
import time
import urllib.parse
import urllib.request

URL = "https://world.digimoncard.com/rule/"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "rules", "qa.json")
DELAY = 1.0


def post(fields):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(URL, data=data, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read().decode("utf-8", "replace")


def get():
    req = urllib.request.Request(URL, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read().decode("utf-8", "replace")


def text(fragment):
    s = re.sub(r"<br\s*/?>", "\n", fragment)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r" *\n *", "\n", s)
    return s.strip()


DATE = re.compile(r"<span>\s*([A-Z][a-z]{2}\.? \d{1,2}, \d{4})\s*Updated\s*</span>")


def parse(page, kind):
    """Yields dicts for every Q/A pair in the result list of [page]."""
    marker = f'class="qaResult {kind}"'
    if marker not in page:
        return
    body = page[page.index(marker):]
    for box in re.finditer(r'<dl class="qa_box">(.*?)</dl>\s*(?=<dl class="qa_box">|</div>)', body, re.S):
        b = box.group(1)
        cat = re.search(r'<dt class="qa_category">\s*<span>(.*?)</span>(.*?)</dt>', b, re.S)
        if not cat:
            continue
        group, title = text(cat.group(1)), text(cat.group(2))
        for item in re.finditer(r'<dl class="questions">(.*?)</dl>\s*<dl class="answer">(.*?)</dl>\s*'
                                r'<div class="relation">(.*?)</div>\s*</dd>', b, re.S):
            q, a, rel = item.groups()
            qid = re.search(r"<dt>\s*Q(\d+)\s*</dt>", q)
            qdd = re.search(r"<dd>(.*?)</dd>", q, re.S).group(1)
            date = DATE.search(qdd)
            qdd = DATE.sub("", qdd)
            add = re.search(r"<dd>(.*?)</dd>", a, re.S).group(1)
            yield {
                "id": int(qid.group(1)) if qid else 0,
                "q": text(qdd),
                "a": text(add),
                "group": group,
                "title": title,
                "date": date.group(1) if date else "",
                "rel": re.findall(r"card_no=([A-Z0-9-]+)", rel),
            }


def main():
    home = get()
    cats = re.findall(r'<option value="([^"]+)"\s*>[^<]*</option>',
                      home[home.index('name="category"'):home.index('name="sub_category"')])
    prods = re.findall(r'<option value="(\d+)"\s*>([^<]+)</option>',
                       home[home.index('name="prodid"'):home.index('name="is_card_search"')])
    print(f"{len(cats)} rule categories, {len(prods)} products")

    rule = {}
    for c in cats:
        time.sleep(DELAY)
        page = post({"is_rule_search": "true", "free_rule": "", "category": c, "sub_category": ""})
        for e in parse(page, "rule"):
            rule[e["id"]] = {"id": e["id"], "q": e["q"], "a": e["a"], "cat": e["group"], "sub": e["title"],
                             "date": e["date"]}
        print(f"  rule  {c:<18} total {len(rule)}")

    card = {}
    for pid, pname in prods:
        time.sleep(DELAY)
        page = post({"is_card_search": "true", "free_card": "", "prodid": pid, "search": ""})
        code = re.search(r"\[([A-Z]+-?\d+(?:-\d+)?)\]\s*$", html.unescape(pname).strip())
        for e in parse(page, "card"):
            m = re.match(r"([A-Z]+\d*-\d+)\s+(.*)", e["title"])
            cno, cname = (m.group(1), m.group(2)) if m else ("", e["title"])
            entry = card.setdefault(e["id"], {"id": e["id"], "q": e["q"], "a": e["a"], "cards": [], "date": e["date"],
                                              "rel": []})
            if cno and not any(c["no"] == cno for c in entry["cards"]):
                entry["cards"].append({"no": cno, "name": cname})
            entry["set"] = code.group(1) if code else html.unescape(pname).strip()
            for r in e["rel"]:
                if r not in entry["rel"]:
                    entry["rel"].append(r)
        print(f"  card  {html.unescape(pname)[:44]:<44} total {len(card)}")

    out = {
        "source": URL,
        "fetched": time.strftime("%Y-%m-%d"),
        "rule": sorted(rule.values(), key=lambda e: e["id"]),
        "card": sorted(card.values(), key=lambda e: e["id"]),
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"rule Q&A {len(rule)}, card Q&A {len(card)} -> {os.path.relpath(OUT, ROOT)} "
          f"({os.path.getsize(OUT) // 1024} KB)")


if __name__ == "__main__":
    main()
