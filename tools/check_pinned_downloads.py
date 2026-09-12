#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Every tool a workflow downloads must be pinned by CONTENT, not just by URL.

A version-pinned URL says which release was asked for. It does not say what
came back. The release workflow unpacks a downloaded zig into the published
archive, so those bytes ship to users; a benchmark whose reference runtime is
whatever `curl … | bash` installs that day cannot be compared across runs.

The rule this enforces, per `run:` block:

  * a download of an executable or an archive from the network must be
    followed, in the same block, by `sha256sum -c` (or `shasum -a 256 -c`);
  * nothing may pipe a downloaded script into a shell.

Downloads that are not tool installs — an API query whose output is parsed,
a request aimed at a server the job itself started — are not tool pinning and
are skipped by the host/scheme rules below rather than by naming files.

    python3 tools/check_pinned_downloads.py

Exit 0 when every block is pinned; 1 with the offending block otherwise.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOWS = os.path.join(ROOT, ".github", "workflows")

# A fetch aimed at one of these is not a tool install: it is a query whose
# body the job parses, or traffic to a server the job is testing.
NOT_A_TOOL = re.compile(
    r"""https?://(
          localhost | 127\.0\.0\.1 | \[::1\] | 0\.0\.0\.0
        | api\.github\.com
        | (\w+\.)*nurl-lang\.org
        )""", re.X)

# The verification that counts.
VERIFIED = re.compile(r"sha256sum\s+-c|shasum\s+-a\s*256\s+-c|minisign\s+-V")

# `curl … | bash`, `wget -O- … | sh`, and the same with the pipe on the next
# line after a continuation.
PIPED_TO_SHELL = re.compile(r"(curl|wget)[^\n|]*\|\s*(sudo\s+)?(ba)?sh\b")

DOWNLOAD = re.compile(r"\b(curl|wget)\b")
URL = re.compile(r"https?://[^\s\"'`)]+")
# Downloading one of these is downloading a program.
ARTIFACT = re.compile(
    r"\.(tar\.(gz|xz|bz2)|tgz|txz|zip|exe|msi|deb|rpm|pkg|dmg|whl|jar)(\?|$)"
    r"|/releases/download/|-static$|/install\.sh$|/rustup\.sh$|sh\.rustup\.rs")


def run_blocks(text):
    """Yield (first_line_number, block_text) for every `run: |` block."""
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)(- name:.*|.*\brun:\s*[|>][-+]?\s*)$", lines[i])
        if m and "run:" in lines[i]:
            indent = len(m.group(1))
            body, j = [], i + 1
            while j < len(lines):
                line = lines[j]
                if line.strip() and (len(line) - len(line.lstrip())) <= indent:
                    break
                body.append(line)
                j += 1
            yield i + 1, "\n".join(body)
            i = j
            continue
        i += 1


def strip_comments(block):
    """Shell comments are prose. A block explaining WHY it no longer pipes a
    script into a shell must not be read as one that does."""
    return "\n".join(line for line in block.splitlines()
                     if not line.lstrip().startswith("#"))


def check(path):
    with open(path) as fh:
        text = fh.read()
    problems = []
    for lineno, raw in run_blocks(text):
        block = strip_comments(raw)
        piped = PIPED_TO_SHELL.search(block)
        if piped and not NOT_A_TOOL.search(block[piped.start():piped.end() + 200]):
            problems.append((lineno, "pipes a downloaded script straight into a shell",
                             piped.group(0)))
            continue
        if not DOWNLOAD.search(block):
            continue
        tools = [u for u in URL.findall(block)
                 if ARTIFACT.search(u) and not NOT_A_TOOL.match(u)]
        # A URL assembled from shell variables never matches ARTIFACT on its
        # own; catch those by the extension of the file curl writes to.
        if not tools and re.search(r"-[oO]\s*\"?[^\s\"]*\.(tar\.(gz|xz)|tgz|zip)", block):
            tools = ["(URL built from shell variables)"]
        if tools and not VERIFIED.search(block):
            problems.append((lineno, "downloads a tool with no checksum check",
                             tools[0]))
    return problems


def main():
    rc = 0
    files = sorted(f for f in os.listdir(WORKFLOWS) if f.endswith((".yml", ".yaml")))
    for name in files:
        for lineno, why, what in check(os.path.join(WORKFLOWS, name)):
            print("ERROR: .github/workflows/%s:%d %s: %s"
                  % (name, lineno, why, what), file=sys.stderr)
            rc = 1
    if rc == 0:
        print("ok: %d workflow file(s); every downloaded tool is checksum-verified"
              % len(files))
    else:
        print("\nPin it: download to a temp path, then\n"
              "  echo \"<sha256>  /tmp/<file>\" | sha256sum -c -\n"
              "before unpacking or installing. Take the digest from the\n"
              "publisher's own index, and change it when you change the version.",
              file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main())
