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

    # Every source of the package, comments stripped, for the rules that
    # must look past the file a literal happens to sit in.
    pkgsrc=$(sed 's://.*::' packages/"$pkg"/src/*.nu 2>/dev/null || true)

    for src in packages/"$pkg"/src/*.nu; do
        [ -e "$src" ] || continue
        # Strip `//` comments, then find `cli_new … `X.Y.Z``.
        while IFS= read -r lit; do
            checked=$((checked + 1))
            if [ "$lit" != "$manifest" ]; then
                echo "MISMATCH: $pkg — nurl.toml says '$manifest' but $src passes '$lit' to cli_new"
                fail=1
            fi
        # `cli_new prog about VERSION`: take the LAST backticked semver on
        # the line. The first cut of this used `cli_new[^)]*`, which stops
        # at the first `)` — and yoloe's about-string is "…detection &
        # instance segmentation (pure NURL, GPU)". The parenthesis inside
        # the description hid the version from the very gate written to
        # check it, and yoloe shipped 0.6.6 announcing 0.6.0.
        done < <(sed 's://.*::' "$src" \
                 | grep 'cli_new' \
                 | grep -o '`[0-9]\+\.[0-9]\+\.[0-9]\+`' \
                 | tail -1 \
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

        # …and a THIRD spelling: the literal sits in a one-line accessor,
        # `@ sm_version → s { ^ \`0.24.0\` }`, and every announcement calls
        # it. Neither rule above can see through that indirection, and both
        # MCP servers drifted behind it — swarm-mcp's manifest went to
        # 0.25.0 while its `initialize` reply kept saying 0.24.0, and
        # nurl-mcp's kept saying 0.10.0 through two releases. Resolve one
        # level: collect the accessors that return a bare semver, then
        # accept only those NAMED ALONGSIDE THE PACKAGE'S OWN NAME at a
        # call site (`mcp_initialize_result \`swarm-mcp\` ( sm_version )`).
        # That keying is what keeps wasmbuilder's `__wb_zig_version` — a
        # genuine version, of something else — out of it.
        stripped=$(sed 's://.*::' "$src")
        while IFS='|' read -r fn lit; do
            [ -n "$fn" ] || continue
            # A here-string, not a pipe — see the constant rule below for
            # why a `grep -q` at the end of a pipeline can make this gate
            # skip the check it just passed.
            grep -q "\`$pkg\`.*( *$fn *)" <<<"$stripped" || continue
            checked=$((checked + 1))
            if [ "$lit" != "$manifest" ]; then
                echo "MISMATCH: $pkg — nurl.toml says '$manifest' but $src returns '$lit' from $fn"
                fail=1
            fi
        done < <(printf '%s\n' "$stripped" \
                 | grep -oE '@ [A-Za-z_][A-Za-z0-9_]* → s \{ \^ `[0-9]+\.[0-9]+\.[0-9]+` \}' \
                 | sed -E 's/@ ([A-Za-z_][A-Za-z0-9_]*) → s \{ \^ `([0-9]+\.[0-9]+\.[0-9]+)` \}/\1|\2/')

        # …and a FOURTH spelling, which is the third one without the
        # function: a top-level CONSTANT, `: s ANOMALY_VERSION `0.31.0``,
        # named at the call site instead of a literal. Every rule above
        # reads the call site, and a call site that names a constant hides
        # the number from all of them — so anomaly 0.32.0 published a
        # `--version` and an MCP `initialize` reply that both said 0.31.0,
        # through a gate written twice over to stop exactly this. Resolved
        # like the accessor and keyed the same way (the package's own name
        # beside the constant at a call site), but searched over the whole
        # package: the constant and the call that uses it need not share a
        # file, and in anomaly they do not.
        # A here-string, not a pipe: under `set -o pipefail` a `grep -q`
        # that matches early closes the pipe, the writer takes SIGPIPE,
        # the PIPELINE reports failure — and `|| continue` then skips the
        # very check that just succeeded. This gate is silent when it is
        # wrong, so it must not have a way to be silently right either.
        while IFS='|' read -r cname lit; do
            [ -n "$cname" ] || continue
            grep -q "\`$pkg\`.*\b$cname\b" <<<"$pkgsrc" || continue
            checked=$((checked + 1))
            if [ "$lit" != "$manifest" ]; then
                echo "MISMATCH: $pkg — nurl.toml says '$manifest' but $src binds $cname = '$lit'"
                fail=1
            fi
        done < <(printf '%s\n' "$stripped" \
                 | grep -oE '^: s [A-Za-z_][A-Za-z0-9_]* `[0-9]+\.[0-9]+\.[0-9]+`' \
                 | sed -E 's/^: s ([A-Za-z_][A-Za-z0-9_]*) `([0-9]+\.[0-9]+\.[0-9]+)`/\1|\2/')
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
