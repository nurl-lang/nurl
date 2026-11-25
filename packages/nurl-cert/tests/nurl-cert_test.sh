#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  nurl-cert end-to-end tests (AGORA-1019).
#
#  Run from anywhere in a checkout:  packages/nurl-cert/tests/nurl-cert_test.sh
#  Needs: build/nurlc, Lean's lake on PATH, formal/ built (lake build C.Cert).
#  Env:   NURL_CERT  a built nurl-cert (default: build it into build/)
#         JOBS       parallel certify runs (default: nproc)
#
#  1. The certify programs (tools/ncore/certify/*.nu): each one whose name
#     does not end in _refused gets a bundle whose M.safe and M.leak are
#     `proved` under the kernel profile, and that bundle verifies; each
#     *_refused one is refused (exit 3), its bundle has no Claims.lean and
#     no claim above `open`, and it verifies as such.
#  2. Tampering: a fresh bundle verifies, and `verify` fails, naming the
#     check, on each of: one source byte changed; a claim's status edited
#     in the manifest; a theorem's statement weakened in Claims.lean;
#     `sorry` put in Claims.lean, or an axiom added to Program.lean; the
#     wrong binary given.
#  3. The fast profile: a bundle whose claims are `validated`, with the
#     compiled-code axiom listed, verifies.
# ============================================================
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
export NURL_STDLIB="$ROOT"
NURLC="$ROOT/build/nurlc"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
pass=0
ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

if [ -n "${NURL_CERT:-}" ]; then
    CERT="$NURL_CERT"
else
    CERT="$ROOT/build/nurl-cert"
    ( cd packages/nurl-cert && "$ROOT/nurl.sh" -O0 src/main.nu "$CERT" ) > "$TMP/build.log" 2>&1 \
        || { cat "$TMP/build.log"; echo "FAIL: nurl-cert did not build"; exit 1; }
fi
command -v lake > /dev/null || { echo "FAIL: lake is not on PATH"; exit 1; }
C="$CERT"
CA=(--nurlc "$NURLC" --formal "$ROOT/formal")

echo "== 1. the certify programs"
one() {
    f="$1"; n="$(basename "$f" .nu)"; d="$TMP/progs/$n"
    mkdir -p "$d"; cp "$f" "$d/$n.nu"
    "$C" certify "$d/$n.nu" "${CA[@]}" > "$d/certify.out" 2>&1; rc=$?
    "$C" verify "$d/$n.cert" --formal "$ROOT/formal" > "$d/verify.out" 2>&1; vrc=$?
    case "$n" in
        *_refused)
            if [ "$rc" = 3 ] && [ ! -e "$d/$n.cert/Claims.lean" ] && [ "$vrc" = 0 ] \
                && ! grep -q '"status": "proved"' "$d/$n.cert/manifest.json"; then
                echo "ok $n refused"
            else echo "FAIL $n: expected refused (certify rc $rc, verify rc $vrc)"; fi ;;
        *)
            if [ "$rc" = 0 ] && [ "$vrc" = 0 ] && grep -q "M.safe proved" "$d/certify.out" \
                && grep -q "M.leak proved" "$d/certify.out"; then
                echo "ok $n accepted"
            else echo "FAIL $n: expected M.safe and M.leak proved (certify rc $rc, verify rc $vrc)"; fi ;;
    esac
}
export -f one; export C TMP ROOT NURLC NURL_STDLIB
export CA_NURLC="$NURLC"
ls tools/ncore/certify/*.nu | xargs -P "$JOBS" -I{} bash -c 'CA=(--nurlc "$CA_NURLC" --formal "$ROOT/formal"); one "$@"' _ {} > "$TMP/progs.txt"
while read -r line; do
    case "$line" in ok*) ok "${line#ok }" ;; *) bad "${line#FAIL }" ;; esac
done < <(sort "$TMP/progs.txt")
nprog=$(ls tools/ncore/certify/*.nu | wc -l)
[ "$(wc -l < "$TMP/progs.txt")" = "$nprog" ] || bad "every certify program reported ($(wc -l < "$TMP/progs.txt") of $nprog)"

echo "== 2. tampering"
P="$TMP/t"; mkdir -p "$P"
cp tools/ncore/certify/vec_push_len.nu "$P/prog.nu"
"$ROOT/nurl.sh" "$P/prog.nu" "$P/prog" > /dev/null 2>&1 || bad "the program builds"
cp "$P/prog" "$P/other"; printf 'x' >> "$P/other"
"$C" certify "$P/prog.nu" "${CA[@]}" --binary "$P/prog" > /dev/null 2>&1 || bad "certify the tamper program"
B="$P/prog.cert"
fresh() { rm -rf "$P/w"; cp -r "$B" "$P/w"; cp "$P/prog.nu" "$P/prog.keep"; }
restore() { cp "$P/prog.keep" "$P/prog.nu"; }
# expect_fail NAME CHECK-TEXT [verify args…]: verify fails and its FAIL line names the check.
expect_fail() {
    name="$1"; want="$2"; shift 2
    out="$("$C" verify "$P/w" --formal "$ROOT/formal" "$@" 2>&1)"; rc=$?
    if [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q "FAIL  .*$want"; then ok "$name"
    else bad "$name (verify rc $rc; expected a FAIL naming: $want)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
}
fresh
if "$C" verify "$P/w" --formal "$ROOT/formal" --binary "$P/prog" > "$TMP/v.out" 2>&1; then ok "a fresh bundle verifies"
else bad "a fresh bundle verifies"; cat "$TMP/v.out"; fi

fresh; printf ' ' >> "$P/prog.nu"
expect_fail "one source byte changed" "every source file hashes as recorded"; restore

fresh; sed -i '0,/"status": "assumed"/s//"status": "proved"/' "$P/w/manifest.json"
expect_fail "a claim's status edited in the manifest (M.unsafe assumed → proved)" "M.unsafe is assumed"
fresh; python3 - "$P/w/manifest.json" <<'EOF'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
m["claims"][0]["status"] = "validated"
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF
expect_fail "a claim's status edited in the manifest (M.safe proved → validated)" "M.safe: the manifest's status is what Lean reports"

fresh; sed -i "s/→ ¬ A2.Stuck P m' s' :=/→ True :=/" "$P/w/Claims.lean"
grep -q "→ True :=" "$P/w/Claims.lean" || bad "the weakening edit applied"
expect_fail "a theorem's statement weakened in Claims.lean" "Claims.lean is the claims' template"

fresh; sed -i 's/:= by decide +kernel/:= by sorry/' "$P/w/Claims.lean"
expect_fail "sorry put in Claims.lean" "Claims.lean is the claims' template"
fresh; printf '\naxiom cheat : False\n' >> "$P/w/Program.lean"
expect_fail "an axiom added to Program.lean" "Program.lean only defines the program"

fresh
expect_fail "the wrong binary given" "the binary is the one certified" --binary "$P/other"

# The manifest's shape: a member dropped, a ledger row dropped.
fresh; python3 - "$P/w/manifest.json" <<'EOF2'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); del m["ledger"]
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
expect_fail "the ledger dropped from the manifest" "the manifest has the schema's members"
fresh; python3 - "$P/w/manifest.json" <<'EOF2'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
m["ledger"] = [r for r in m["ledger"] if r["id"] != "translation"]
for c in m["claims"]:
    c["premises"] = [x for x in c["premises"] if x != "translation"]
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
expect_fail "the translation's ledger row and premise dropped" "the trust ledger is the one certify writes"
fresh; python3 - "$P/w/manifest.json" <<'EOF2'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
m["claims"][0]["premises"] = [" ".join(m["claims"][0]["premises"])]
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
expect_fail "the premises merged into one string" "the claims are the template's"
fresh; python3 - "$P/w/manifest.json" <<'EOF2'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); del m["claims"][0]["reason"]
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
expect_fail "a claim's required field dropped (claims[0].reason)" "every member is the schema's"
fresh; python3 - "$P/w/manifest.json" <<'EOF2'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); m["tool"]["name"] = "some-other-tool"; m["hashes"]["extra"] = "x"
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
expect_fail "a fixed value changed (tool.name) and a member added (hashes.extra)" "every member is the schema's"

# Lean runs code while it elaborates: a Claims.lean that fails the template
# must never reach it.
fresh; rm -f "$TMP/pwned"
printf '\n#eval IO.FS.writeFile "%s" "ran"\n' "$TMP/pwned" >> "$P/w/Claims.lean"
expect_fail "code put in Claims.lean is refused" "Lean checks Program.lean and Claims.lean"
if [ -e "$TMP/pwned" ]; then bad "the planted #eval never ran"; else ok "the planted #eval never ran"; fi

# nurlc lists one file per line, or stops.
mkdir -p "$P/nl"; nlf="$P/nl/a
b.nu"
cp "$P/prog.nu" "$nlf"
if out=$("$NURLC" --emit-core --list-sources "$nlf" 2>&1 >/dev/null); then bad "a source path with a newline stops --list-sources"
else
    case "$out" in *"holds a newline"*) ok "a source path with a newline stops --list-sources" ;; *) bad "a source path with a newline stops --list-sources ($out)" ;; esac
fi

# The term swapped for another program's, every hash made to agree: a
# plain verify cannot see it (the translation is a ledger row), --rebuild
# must.
fresh
if "$C" verify "$P/w" --rebuild --nurlc "$NURLC" --formal "$ROOT/formal" > "$TMP/r.out" 2>&1; then ok "--rebuild: a fresh bundle's term is its source's"
else bad "--rebuild: a fresh bundle's term is its source's"; cat "$TMP/r.out"; fi
fresh
cp tools/ncore/certify/while_loop_summing.nu "$P/other.nu"
"$C" certify "$P/other.nu" "${CA[@]}" --out "$P/other.cert" > /dev/null 2>&1
cp "$P/other.cert/Program.lean" "$P/w/Program.lean"
python3 - "$P/w/manifest.json" "$P/w/Program.lean" <<'EOF2'
import hashlib, json, sys
p = sys.argv[1]; m = json.load(open(p))
m["hashes"]["program_lean"] = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
if "$C" verify "$P/w" --formal "$ROOT/formal" > /dev/null 2>&1; then
    echo "  note  another program's term with its hash updated passes a plain verify (the translation ledger row)"
fi
expect_fail "another program's term, every hash updated: --rebuild" "--rebuild: the translation makes Program.lean" --rebuild --nurlc "$NURLC"

echo "== 3. the fast profile"
"$C" certify "$P/prog.nu" "${CA[@]}" --profile fast --out "$P/fast.cert" > "$TMP/f.out" 2>&1
if grep -q "M.safe validated" "$TMP/f.out" && grep -q "native_decide" "$P/fast.cert/manifest.json" \
    && grep -q '"validated": 1' "$P/fast.cert/manifest.json" && ! grep -q '"status": "proved"' "$P/fast.cert/manifest.json" \
    && "$C" verify "$P/fast.cert" --formal "$ROOT/formal" > /dev/null 2>&1; then ok "fast: validated (claims and coverage), its axiom listed, verifies"
else bad "fast: validated, its axiom listed, verifies"; cat "$TMP/f.out"; fi

echo "== 4. every manifest against docs/dev/certificate.schema.json"
if python3 -c "import jsonschema" 2> /dev/null; then
    if python3 - "$ROOT/docs/dev/certificate.schema.json" "$TMP"/progs/*/*.cert/manifest.json "$B/manifest.json" "$P/fast.cert/manifest.json" <<'EOF2'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
bad = 0
for p in sys.argv[2:]:
    try:
        jsonschema.validate(json.load(open(p)), schema)
    except jsonschema.ValidationError as e:
        bad += 1
        print(f"        {p}: {e.message}")
sys.exit(1 if bad else 0)
EOF2
    then ok "every manifest is a nurl-cert/1 manifest"; else bad "every manifest is a nurl-cert/1 manifest"; fi
else
    echo "  SKIP  the schema check: python3 has no jsonschema module"
fi

echo
echo "nurl-cert: $pass passed, $fail failed"
[ "$fail" = 0 ]
