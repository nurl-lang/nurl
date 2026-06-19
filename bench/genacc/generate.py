#!/usr/bin/env python3
"""
bench/genacc/generate.py — ask a fixed model to write each task in each
language, save the raw programs for scoring.

Methodology note (read bench/genacc/README.md for the full rationale):
NURL is out-of-distribution for every model's training data, so a *fair*
test of the grammar — rather than of how much NURL the model happened to
see — hands the model NURL's one-page reference (primers/nurl.md) in the
system prompt. Python and Rust are in-distribution and get no primer by
default. Pass --primer-all to give every language its primer for symmetry,
or --no-primer to give none.

Requires ANTHROPIC_API_KEY in the environment. No third-party packages.

    export ANTHROPIC_API_KEY=sk-ant-...
    python3 bench/genacc/generate.py --model claude-sonnet-4-6 --runs 1

Output: bench/genacc/solutions/<model>/run<k>/<task>.<ext>
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"

LANGS = {
    "nurl": {"ext": "nu", "name": "NURL", "primer": "primers/nurl.md"},
    "python": {"ext": "py", "name": "Python", "primer": None},
    "rust": {"ext": "rs", "name": "Rust", "primer": None},
    "node": {"ext": "js", "name": "JavaScript (Node.js)", "primer": None},
}

# Languages that are out-of-distribution enough to warrant a primer by
# default. Mainstream languages get none unless --primer-all is set.
DEFAULT_PRIMER_LANGS = {"nurl"}


def load_primer(rel: str | None) -> str:
    if not rel:
        return ""
    p = HERE / rel
    return p.read_text(encoding="utf-8") if p.exists() else ""


def system_prompt(lang_key: str, give_primer: bool) -> str:
    info = LANGS[lang_key]
    base = (
        f"You are an expert {info['name']} programmer. You will be given a "
        f"task. Respond with a SINGLE complete {info['name']} program that "
        f"solves it, inside one fenced code block and nothing else — no "
        f"explanation before or after. The program must compile, run with no "
        f"input, and print EXACTLY the requested output (and nothing else) to "
        f"standard output."
    )
    if give_primer and info["primer"]:
        primer = load_primer(info["primer"])
        if primer:
            base += (
                "\n\nHere is a concise reference for the language. Follow it "
                "exactly:\n\n" + primer
            )
    return base


def extract_code(text: str) -> str:
    """Pull the first fenced code block; fall back to the whole reply."""
    m = re.search(r"```[a-zA-Z0-9_+-]*\n(.*?)```", text, re.DOTALL)
    return (m.group(1) if m else text).strip() + "\n"


def call_model(api_key: str, model: str, system: str, user: str,
               max_tokens: int, temperature: float) -> str:
    body = json.dumps({
        "model": model,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "system": system,
        "messages": [{"role": "user", "content": user}],
    }).encode("utf-8")
    req = urllib.request.Request(API_URL, data=body, method="POST", headers={
        "x-api-key": api_key,
        "anthropic-version": API_VERSION,
        "content-type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=120) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    parts = [b.get("text", "") for b in payload.get("content", [])
             if b.get("type") == "text"]
    return "".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="claude-sonnet-4-6",
                    help="Anthropic model id (default: claude-sonnet-4-6)")
    ap.add_argument("--runs", type=int, default=1,
                    help="independent samples per (task,lang) (default: 1)")
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--max-tokens", type=int, default=2048)
    ap.add_argument("--langs", default="nurl,python,rust",
                    help="comma list from: nurl,python,rust,node")
    ap.add_argument("--primer-all", action="store_true",
                    help="give every language its primer (symmetry)")
    ap.add_argument("--no-primer", action="store_true",
                    help="give no language a primer (raw familiarity test)")
    args = ap.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        sys.stderr.write("ANTHROPIC_API_KEY is not set.\n")
        return 2

    langs = [l.strip() for l in args.langs.split(",") if l.strip()]
    for l in langs:
        if l not in LANGS:
            sys.stderr.write(f"unknown language: {l}\n")
            return 2

    tasks = json.loads((HERE / "tasks.json").read_text())["tasks"]
    safe_model = re.sub(r"[^A-Za-z0-9._-]", "_", args.model)
    out_root = HERE / "solutions" / safe_model

    total = 0
    for run in range(args.runs):
        for task in tasks:
            for lang in langs:
                if args.no_primer:
                    give = False
                elif args.primer_all:
                    give = True
                else:
                    give = lang in DEFAULT_PRIMER_LANGS
                system = system_prompt(lang, give)
                try:
                    reply = call_model(api_key, args.model, system,
                                       task["spec"], args.max_tokens,
                                       args.temperature)
                except urllib.error.HTTPError as e:
                    sys.stderr.write(
                        f"[{task['name']}/{lang}] HTTP {e.code}: "
                        f"{e.read().decode('utf-8', 'replace')[:200]}\n")
                    continue
                code = extract_code(reply)
                dest = out_root / f"run{run}" / f"{task['name']}.{LANGS[lang]['ext']}"
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(code, encoding="utf-8")
                total += 1
                print(f"  wrote {dest.relative_to(HERE)} ({len(code)} bytes)")

    print(f"\n{total} programs written under {out_root.relative_to(HERE)}/")
    print("Score them with:  bench/genacc/score.py", out_root.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
