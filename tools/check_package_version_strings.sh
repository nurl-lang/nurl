#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_package_version_strings.sh — assert that a package's
#  hand-written `--version` string matches its manifest.
#
#  `cli_new prog about VERSION` takes the version as a STRING LITERAL.
#  Nothing derives it from `nurl.toml`, so the two drift the moment a
#  release bumps one and forgets the other — and the drift is invisible
#  in the repo, because no test runs `--version` and compares it to
#  anything.
#
#  anomaly shipped 0.5.3 and then 0.5.4 while `anomaly --version` kept
#  answering `0.5.2`. It was found the only way it can be found without
#  this gate: by installing the published package and running the
#  binary. That is two releases too late, and the published artifacts
#  cannot be corrected — a version can be yanked, never replaced.
#
#  Comments are stripped before matching, so the doc example in
#  `packages/cli/src/cli.nu` ("cli_new `greet` `a tiny greeter`
#  `1.0.0`") is not mistaken for a real call.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
checked=0

for toml in packages/*/nurl.toml; do
    pkg=$(basename "$(dirname "$toml")")
    manifest=$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$toml" | head -1)
    [ -n "$manifest" ] || continue

    for src in packages/"$pkg"/src/*.nu; do
        [ -e "$src" ] || continue
        # Strip `//` comments, then find `cli_new … `X.Y.Z``.
        while IFS= read -r lit; do
            checked=$((checked + 1))
            if [ "$lit" != "$manifest" ]; then
                echo "MISMATCH: $pkg — nurl.toml says '$manifest' but $src passes '$lit' to cli_new"
                fail=1
            fi
        done < <(sed 's://.*::' "$src" \
                 | grep -o 'cli_new[^)]*`[0-9]\+\.[0-9]\+\.[0-9]\+`' \
                 | grep -o '`[0-9]\+\.[0-9]\+\.[0-9]\+`$' \
                 | tr -d '`')

        # …and the OTHER spelling: a literal that prints the package's own
        # name followed by its version, with no framework in sight —
        # `( nurl_print \`gguf 0.3.0\\n\` )`. The cli_new form above was
        # the only one this gate knew, so gguf shipped 0.3.1 announcing
        # itself as 0.3.0 hours after the gate was written to stop exactly
        # that. Keyed on the package's OWN name so a spec version the code
        # legitimately mentions (\`version is 3\`, a dependency's number)
        # cannot match.
        while IFS= read -r lit; do
            checked=$((checked + 1))
            if [ "$lit" != "$manifest" ]; then
                echo "MISMATCH: $pkg — nurl.toml says '$manifest' but $src prints '$pkg $lit'"
                fail=1
            fi
        done < <(sed 's://.*::' "$src" \
                 | grep -o "\`$pkg [0-9]\+\.[0-9]\+\.[0-9]\+" \
                 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+$')
    done
done

if [ "$fail" -ne 0 ]; then
    echo
    echo "A package's --version is hand-written and must be bumped WITH the"
    echo "manifest. Fix the literal, or the published binary will report a"
    echo "version that does not exist."
    exit 1
fi

echo "package version strings: OK — $checked hand-written --version literal(s) match their manifest."
