#!/usr/bin/env python3
"""Seed the WhisperKey glossary with domain terms mined from your own texts.

Point it at any directory of text/JSONL files you write a lot in — Claude Code
session transcripts, notes, chat exports — and it prints frequency-ranked
candidate terms (Latin-script tech terms). Review the output and copy the
terms you actually dictate into glossary.json.

Examples:
    python seed_glossary.py ~/.claude/projects/*my-project*
    python seed_glossary.py ~/notes --days 90 --min-count 5
"""

import argparse
import glob
import json
import os
import re
import time
from collections import Counter

STOP = set("""the and for you not with this that have from are was can will what all your
как что для это или json file files http https com www int str def none true false
import return print push pull commit branch main index page src dist node npm run dev
test tests build error log logs data list item items name type value text user assistant
message content session html css div span class function const let var string number
description status result output path model when then them than more once first""".split())


def extract_text(path):
    texts = []
    if path.endswith(".jsonl"):
        with open(path, errors="ignore") as fh:
            for line in fh:
                if '"type":"user"' not in line and '"type": "user"' not in line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                content = obj.get("message", {}).get("content")
                if isinstance(content, str):
                    texts.append(content)
                elif isinstance(content, list):
                    texts += [c.get("text", "") for c in content
                              if isinstance(c, dict) and c.get("type") == "text"]
    else:
        try:
            with open(path, errors="ignore") as fh:
                texts.append(fh.read())
        except OSError:
            pass
    return texts


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help="directories or glob patterns to mine")
    ap.add_argument("--days", type=int, default=45, help="only files modified in the last N days")
    ap.add_argument("--min-count", type=int, default=8, help="minimum occurrences to report")
    ap.add_argument("--max-file-mb", type=int, default=60, help="skip files larger than this")
    args = ap.parse_args()

    cutoff = time.time() - args.days * 86400
    texts = []
    nfiles = 0
    for pattern in args.paths:
        for entry in glob.glob(os.path.expanduser(pattern)):
            files = ([os.path.join(r, f) for r, _, fs in os.walk(entry) for f in fs]
                     if os.path.isdir(entry) else [entry])
            for f in files:
                try:
                    if os.path.getmtime(f) < cutoff or os.path.getsize(f) > args.max_file_mb * 1e6:
                        continue
                except OSError:
                    continue
                nfiles += 1
                texts += extract_text(f)

    blob = "\n".join(texts)
    latin = Counter(re.findall(r"\b[a-zA-Z][a-zA-Z0-9_.-]{3,}(?:\.[a-z]{2,6})?\b", blob))

    print(f"# mined {nfiles} files, {len(texts)} text chunks")
    print("# count\tterm  — copy the ones you dictate into glossary.json 'terms'")
    for w, n in latin.most_common(300):
        if n >= args.min_count and w.lower() not in STOP:
            print(f"{n}\t{w}")


if __name__ == "__main__":
    main()
