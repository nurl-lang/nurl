#!/usr/bin/env python3
"""
bench/genacc/repair.py — one round of COMPILER-FEEDBACK repair over an
existing solutions directory.

This measures the second half of the diagnostic-first claim: score.py's
first-pass numbers deliberately allow no retries, but a real agent sees the
compiler's error and tries again. This script replays exactly that loop, in
the strictest honest form:

  * A program that already compiles is copied through UNCHANGED — repair can
    never improve a program the compiler accepted (a compiles-but-wrong-output
    program stays wrong; the model never sees the expected output).
  * A program that fails to compile is sent back to the SAME model with the
    original task, its own program, and the compiler's stderr — nothing else —
    and its single corrected attempt is recorded.
  * Every language gets the same treatment (Python/Rust/JS repair the same
    way; in practice they compile first-pass, so this is a no-op for them).

The signal, then, is: how far does ONE round of NURL's compiler diagnostics
carry a model on a language it has never seen? Score the output directory
with score.py and compare against the input directory.

    export ANTHROPIC_API_KEY=...           # Claude models
    export INCEPTION_API_KEY=...           # mercury (diffusion) models
    python3 bench/genacc/repair.py claude-opus-4-8__v3
    python3 bench/genacc/repair.py mercury-2__v3high --reasoning-effort high

Output: solutions/<indir>repair/run<k>/<task>.<ext> + repair_log.json.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate import (  # noqa: E402
    API_URL as ANTHROPIC_URL, API_VERSION, HERE, LANGS,
    extract_code, system_prompt,
)

INCEPTION_URL = "https://api.inceptionlabs.ai/v1/chat/completions"
ROOT = HERE.parent.parent
NURLC = ROOT / "build" / "nurlc"
RUNTIME = ROOT / "stdlib" / "runtime.o"
BUILD = HERE / "_build"
EXT_LANG = {v["ext"]: k for k, v in LANGS.items()}
ERR_CAP = 2500  # chars of compiler stderr handed back to the model

PYTHON3 = shutil.which("python3") or "python3"


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def feature_libs() -> list[str]:
    libs: list[str] = []
    for sentinel, pkg in [("runtime.curl", "libcurl"), ("runtime.openssl", "openssl"),
                          ("runtime.sqlite3", "sqlite3"), ("runtime.pq", "libpq"),
                          ("runtime.z", "zlib"), ("runtime.zstd", "libzstd")]:
        if (ROOT / "stdlib" / sentinel).exists():
            try:
                out = subprocess.run(["pkg-config", "--libs", pkg],
                                     capture_output=True, text=True)
                libs += out.stdout.split()
            except FileNotFoundError:
                pass
    return libs


def compile_check(lang: str, src: Path, name: str) -> tuple[bool, str]:
    """Return (compiled, stderr). Mirrors score.py's build steps exactly,
    but keeps the error text — that text IS the experiment."""
    BUILD.mkdir(exist_ok=True)
    if lang == "nurl":
        r = sh([str(NURLC), str(src)], cwd=str(ROOT))
        if r.returncode != 0:
            return False, r.stderr
        ll = BUILD / f"{name}_repair.ll"
        ll.write_text(r.stdout)
        binp = BUILD / f"{name}_repair_nurl"
        link = sh(["clang", "-O2", "-flto", str(ll), str(RUNTIME),
                   "-lm", "-lpthread", *feature_libs(), "-o", str(binp)])
        if link.returncode != 0:
            return False, link.stderr
        return True, ""
    if lang == "python":
        r = sh([PYTHON3, "-m", "py_compile", str(src)])
        return r.returncode == 0, r.stderr
    if lang == "rust":
        binp = BUILD / f"{name}_repair_rs"
        r = sh(["rustc", "-O", str(src), "-o", str(binp)])
        return r.returncode == 0, r.stderr
    if lang == "node":
        r = sh(["node", "--check", str(src)])
        return r.returncode == 0, r.stderr
    raise ValueError(lang)


def call_anthropic(api_key: str, model: str, system: str, messages: list[dict],
                   max_tokens: int, temperature: float | None) -> str:
    payload: dict = {"model": model, "max_tokens": max_tokens,
                     "system": system, "messages": messages}
    if temperature is not None:
        payload["temperature"] = temperature

    def post(p):
        req = urllib.request.Request(
            ANTHROPIC_URL, data=json.dumps(p).encode("utf-8"), method="POST",
            headers={"x-api-key": api_key, "anthropic-version": API_VERSION,
                     "content-type": "application/json"})
        with urllib.request.urlopen(req, timeout=180) as resp:
            return json.loads(resp.read().decode("utf-8"))

    try:
        data = post(payload)
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", "replace") if e.code == 400 else ""
        if e.code == 400 and "temperature" in msg:
            payload.pop("temperature", None)
            data = post(payload)
        else:
            raise
    return "".join(b.get("text", "") for b in data.get("content", [])
                   if b.get("type") == "text")


def call_inception(api_key: str, model: str, system: str, messages: list[dict],
                   max_tokens: int, temperature: float | None,
                   reasoning_effort: str) -> str:
    payload: dict = {"model": model, "max_tokens": max_tokens,
                     "messages": [{"role": "system", "content": system}, *messages]}
    if reasoning_effort:
        payload["reasoning_effort"] = reasoning_effort
    if temperature is not None:
        payload["temperature"] = temperature

    def post(p):
        req = urllib.request.Request(
            INCEPTION_URL, data=json.dumps(p).encode("utf-8"), method="POST",
            headers={"Authorization": f"Bearer {api_key}",
                     "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=180) as resp:
            return json.loads(resp.read().decode("utf-8"))

    try:
        data = post(payload)
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", "replace") if e.code == 400 else ""
        if e.code == 400 and ("temperature" in msg or "reasoning_effort" in msg
                              or "max_tokens" in msg):
            payload.pop("temperature", None)
            payload.pop("reasoning_effort", None)
            data = post(payload)
        else:
            raise
    content = (data.get("choices") or [{}])[0].get("message", {}).get("content")
    return content or ""


def repair_prompt(err: str) -> str:
    err = err.strip()
    if len(err) > ERR_CAP:
        err = err[:ERR_CAP] + "\n... (truncated)"
    return (
        "That program failed to compile. Compiler output:\n\n"
        f"{err}\n\n"
        "Fix the program. Reply with the corrected COMPLETE program in a "
        "single fenced code block and nothing else."
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("indir", help="existing dir under solutions/ to repair")
    ap.add_argument("--model", default="",
                    help="model id (default: the part of indir before '__')")
    ap.add_argument("--provider", choices=["anthropic", "inception"], default="",
                    help="API to use (default: inception for mercury*, else anthropic)")
    ap.add_argument("--tag", default="",
                    help="output dir name (default: <indir>repair)")
    ap.add_argument("--rounds", type=int, default=1,
                    help="max repair rounds per failing program (default: 1)")
    ap.add_argument("--max-tokens", type=int, default=2048)
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--reasoning-effort", default="",
                    help="inception-only reasoning_effort knob")
    args = ap.parse_args()

    indir = HERE / "solutions" / args.indir
    if not indir.is_dir():
        sys.stderr.write(f"no such solutions dir: {args.indir}\n")
        return 2
    model = args.model or args.indir.split("__")[0]
    provider = args.provider or ("inception" if model.startswith("mercury") else "anthropic")
    key_var = "INCEPTION_API_KEY" if provider == "inception" else "ANTHROPIC_API_KEY"
    api_key = os.environ.get(key_var)
    if not api_key:
        sys.stderr.write(f"{key_var} is not set.\n")
        return 2

    out_root = HERE / "solutions" / (args.tag or f"{args.indir}repair")
    tasks = {t["name"]: t for t in
             json.loads((HERE / "tasks.json").read_text())["tasks"]}

    log: list[dict] = []
    n_copied = n_repaired = n_fixed = 0
    for run in sorted(indir.glob("run*")):
        for src in sorted(run.iterdir()):
            lang = EXT_LANG.get(src.suffix.lstrip("."))
            if lang is None or src.stem not in tasks:
                continue
            name = src.stem
            dest = out_root / run.name / src.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            code = src.read_text(errors="replace")
            ok, err = compile_check(lang, src, f"{run.name}_{name}")
            if ok:
                dest.write_text(code, encoding="utf-8")
                n_copied += 1
                log.append({"run": run.name, "task": name, "lang": lang,
                            "status": "copied"})
                continue
            # Failed first-pass: replay the agent loop — task, own program,
            # compiler stderr — for up to --rounds corrected attempts.
            n_repaired += 1
            system = system_prompt(lang, lang in {"nurl"})
            messages = [
                {"role": "user", "content": tasks[name]["spec"]},
                {"role": "assistant", "content": f"```\n{code}```"},
            ]
            first_err = err
            for _ in range(args.rounds):
                messages.append({"role": "user", "content": repair_prompt(err)})
                if provider == "inception":
                    reply = call_inception(api_key, model, system, messages,
                                           args.max_tokens, args.temperature,
                                           args.reasoning_effort)
                else:
                    reply = call_anthropic(api_key, model, system, messages,
                                           args.max_tokens, args.temperature)
                code = extract_code(reply)
                dest.write_text(code, encoding="utf-8")
                ok, err = compile_check(lang, dest, f"{run.name}_{name}")
                if ok:
                    break
                messages.append({"role": "assistant", "content": f"```\n{code}```"})
            n_fixed += int(ok)
            log.append({"run": run.name, "task": name, "lang": lang,
                        "status": "repaired", "compile_after": ok,
                        "first_error": first_err.strip()[:400]})
            print(f"  {run.name}/{name}.{LANGS[lang]['ext']}: "
                  f"{'fixed' if ok else 'STILL FAILS'}")

    (out_root / "repair_log.json").write_text(
        json.dumps({"source": args.indir, "model": model, "provider": provider,
                    "rounds": args.rounds, "entries": log}, indent=2) + "\n")
    print(f"\n{n_copied} copied (compiled first-pass), {n_repaired} repaired, "
          f"{n_fixed} of those now compile → {out_root.relative_to(HERE)}/")
    print("Score with:  bench/genacc/score.py", out_root.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
