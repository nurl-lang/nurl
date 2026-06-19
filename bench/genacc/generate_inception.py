#!/usr/bin/env python3
"""
bench/genacc/generate_inception.py — generation driver for Inception Labs'
diffusion LLM (Mercury), an OpenAI-compatible chat endpoint.

A sibling of generate.py. It reuses that file's task specs, primer logic, and
code extraction verbatim — only the HTTP call differs (OpenAI
/v1/chat/completions shape, Bearer auth, a `reasoning_effort` knob) — so the
prompts are identical to the Anthropic runs and the outputs score the same way.

    export INCEPTION_API_KEY=...
    python3 bench/genacc/generate_inception.py --model mercury-2 \
        --tasks words,brackets,csv_sum,histogram --runs 5 --tag grammar

Output: solutions/<model>__<tag>/run<k>/<task>.<ext>, scored by score.py.
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

# Reuse the prompt-building + task plumbing from the Anthropic driver so the
# two runs are identical apart from the transport.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate import (  # noqa: E402
    LANGS, DEFAULT_PRIMER_LANGS, HERE, system_prompt, extract_code,
)

API_URL = "https://api.inceptionlabs.ai/v1/chat/completions"


def call_mercury(api_key: str, model: str, system: str, user: str,
                 max_tokens: int, temperature: float,
                 reasoning_effort: str) -> str:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "max_tokens": max_tokens,
    }
    if reasoning_effort:
        payload["reasoning_effort"] = reasoning_effort
    if temperature is not None:
        payload["temperature"] = temperature
    req = urllib.request.Request(
        API_URL, data=json.dumps(payload).encode("utf-8"), method="POST",
        headers={"Authorization": f"Bearer {api_key}",
                 "Content-Type": "application/json"})

    def post(p):
        rq = urllib.request.Request(
            API_URL, data=json.dumps(p).encode("utf-8"), method="POST",
            headers={"Authorization": f"Bearer {api_key}",
                     "Content-Type": "application/json"})
        with urllib.request.urlopen(rq, timeout=180) as resp:
            return json.loads(resp.read().decode("utf-8"))

    try:
        data = post(payload)
    except urllib.error.HTTPError as e:
        # Drop optional knobs the endpoint may reject, then retry once.
        msg = e.read().decode("utf-8", "replace") if e.code == 400 else ""
        if e.code == 400 and ("temperature" in msg or "reasoning_effort" in msg
                              or "max_tokens" in msg):
            payload.pop("temperature", None)
            payload.pop("reasoning_effort", None)
            data = post(payload)
        else:
            raise
    # A reasoning/diffusion model can return content=None when it spends its
    # whole token budget before emitting code (finish_reason "length"); treat
    # that as an empty answer rather than crashing.
    msg = data.get("choices", [{}])[0].get("message", {})
    return msg.get("content") or ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="mercury-2", help="Inception model id")
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--temperature", type=float, default=0.7)
    ap.add_argument("--reasoning-effort", default="medium")
    ap.add_argument("--max-tokens", type=int, default=2048)
    ap.add_argument("--langs", default="nurl,python,rust")
    ap.add_argument("--tasks", default="")
    ap.add_argument("--tag", default="")
    ap.add_argument("--primer-all", action="store_true")
    ap.add_argument("--no-primer", action="store_true")
    args = ap.parse_args()

    api_key = os.environ.get("INCEPTION_API_KEY")
    if not api_key:
        sys.stderr.write("INCEPTION_API_KEY is not set.\n")
        return 2

    langs = [l.strip() for l in args.langs.split(",") if l.strip()]
    for l in langs:
        if l not in LANGS:
            sys.stderr.write(f"unknown language: {l}\n")
            return 2

    tasks = json.loads((HERE / "tasks.json").read_text())["tasks"]
    if args.tasks:
        want = {t.strip() for t in args.tasks.split(",") if t.strip()}
        tasks = [t for t in tasks if t["name"] in want]

    safe_model = re.sub(r"[^A-Za-z0-9._-]", "_", args.model)
    dir_name = f"{safe_model}__{args.tag}" if args.tag else safe_model
    out_root = HERE / "solutions" / dir_name

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
                    reply = call_mercury(api_key, args.model, system,
                                         task["spec"], args.max_tokens,
                                         args.temperature, args.reasoning_effort)
                except urllib.error.HTTPError as e:
                    sys.stderr.write(
                        f"[{task['name']}/{lang}] HTTP {e.code}: "
                        f"{e.read().decode('utf-8', 'replace')[:200]}\n")
                    continue
                except Exception as e:  # one bad call must not kill the run
                    sys.stderr.write(f"[{task['name']}/{lang}] {type(e).__name__}: {e}\n")
                    continue
                code = extract_code(reply)
                dest = out_root / f"run{run}" / f"{task['name']}.{LANGS[lang]['ext']}"
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(code, encoding="utf-8")
                total += 1
                print(f"  wrote {dest.relative_to(HERE)} ({len(code)} bytes)")

    print(f"\n{total} programs written under {out_root.relative_to(HERE)}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
