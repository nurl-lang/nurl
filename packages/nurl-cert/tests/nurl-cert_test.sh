#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  nurl-cert end-to-end tests (AGORA-1019).
#
#  Run from anywhere in a checkout:  packages/nurl-cert/tests/nurl-cert_test.sh
#  Needs: build/nurlc, Lean's lake on PATH, formal/ built (lake build C.Cert C.Cert3 C.Elab).
#  Env:   NURL_CERT  a built nurl-cert (default: build it into build/)
#         JOBS       parallel certify runs (default: nproc)
#
#  1. The certify programs (tools/ncore/certify/*.nu): each one whose name
#     does not end in _refused gets a bundle whose M.safe and M.leak are
#     `proved` under the kernel profile (a thread_* one M.race too, from
#     A3's claim), and that bundle verifies; each
#     *_refused one is refused (exit 3), its bundle has no Claims.lean and
#     no claim above `open`, and it verifies as such. Exactly the programs
#     in C.Elab's subset get Elab.lean (the kernel builds their term,
#     Cert.elab); the rest none.
#  2. Tampering: a fresh bundle verifies, and `verify` fails, naming the
#     check, on each of: one source byte changed; a claim's status edited
#     in the manifest; a theorem's statement weakened in Claims.lean;
#     `sorry` put in Claims.lean, or an axiom added to Program.lean; the
#     wrong binary given. Then the term checked by the kernel (a bundle with
#     Elab.lean): another scalar program's Program.lean swapped in with its
#     hash updated fails a plain verify, on Cert.elab; so do Elab.lean
#     deleted, its words edited and its theorem edited; a bundle downgraded
#     honestly (Elab.lean removed, its hash dropped and the translation row
#     the translator's again) verifies, as the weaker bundle it is. And every word of a core IR is a string literal
#     Lean reads back as the word.
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
            race=ok
            case "$n" in thread_*) grep -q "M.race proved" "$d/certify.out" || race=missing ;; esac
            # (Cert.elab: the bundle has Elab.lean exactly when certify says the
            # kernel built the term, and its manifest records it)
            el=translator
            if [ -e "$d/$n.cert/Elab.lean" ]; then el=elab; fi
            elok=ok
            if [ "$el" = elab ]; then
                grep -q "term: Cert.elab" "$d/certify.out" && grep -q '"elab_lean"' "$d/$n.cert/manifest.json" || elok=bad
            else
                grep -q "term: the translator's" "$d/certify.out" && ! grep -q '"elab_lean"' "$d/$n.cert/manifest.json" || elok=bad
            fi
            if [ "$rc" = 0 ] && [ "$vrc" = 0 ] && grep -q "M.safe proved" "$d/certify.out" \
                && grep -q "M.leak proved" "$d/certify.out" && [ "$race" = ok ] && [ "$elok" = ok ]; then
                echo "ok $n accepted ($el)"
            else echo "FAIL $n: expected M.safe and M.leak proved (certify rc $rc, verify rc $vrc, term $el $elok)"; fi ;;
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
# Exactly the certify programs in C.Elab's subset (tools/ncore/elab_parity.sh's
# EXPECT_CERTIFY) get the kernel's term. A program in it that loses its
# Elab.lean fails here: so does a stale constructor list in claims.nu
# (ELAB_CTORS), which would skip Lean on it. One that gains it fails too,
# until it is added here and there.
have_elab=$(sed -n 's/^ok \(.*\) accepted (elab)$/\1/p' "$TMP/progs.txt" | sort | tr '\n' ' ')
want_elab="int_recursion_early_return loop_with_continue_and_break while_loop_summing "
if [ "$have_elab" = "$want_elab" ]; then ok "exactly the 3 certify programs in the subset have Elab.lean (Cert.elab)"
else bad "exactly the 3 certify programs in the subset have Elab.lean (Cert.elab): have $have_elab"; fi
if grep -qx "ok vec_push_len accepted (translator)" "$TMP/progs.txt"; then ok "vec_push_len (outside the subset): no Elab.lean, and it verifies"
else bad "vec_push_len (outside the subset): no Elab.lean, and it verifies"; fi

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
# edit_manifest PY: apply one Python statement to the manifest `m`.
edit_manifest() {
    python3 - "$P/w/manifest.json" "$1" <<'EOF2'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); exec(sys.argv[2])
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
}
fresh; edit_manifest 'm["tool"]["name"] = "some-other-tool"'
expect_fail "a fixed value changed (tool.name)" "every member is the schema's"
fresh; edit_manifest 'm["hashes"]["extra"] = "x"'
expect_fail "a member added (hashes.extra)" "every member is the schema's"
fresh; edit_manifest 'm["coverage"]["functions"] = None'
expect_fail "coverage.functions made null" "every member is the schema's"
fresh; edit_manifest 'm["coverage"]["bad"] = -1'
expect_fail "a negative coverage count" "every member is the schema's"
fresh; edit_manifest 'm["program"]["slots"] = 1.5'
expect_fail "a fractional slot count" "every member is the schema's"
fresh; edit_manifest 'm["coverage"]["functions"][0]["name"] = None'
expect_fail "a coverage row's string field made null" "every member is the schema's"

# Lean runs code while it elaborates: a Claims.lean that fails the template
# must never reach it.
fresh; rm -f "$TMP/pwned"
printf '\n#eval IO.FS.writeFile "%s" "ran"\n' "$TMP/pwned" >> "$P/w/Claims.lean"
expect_fail "code put in Claims.lean is refused" "Lean checks Program.lean and Claims.lean"
if [ -e "$TMP/pwned" ]; then bad "the planted #eval never ran"; else ok "the planted #eval never ran"; fi

# The hashes are of the bytes nurlc compiled: a file on disk that differs
# from its snapshot (here a NUL byte, past which nurlc reads nothing)
# certifies nothing.
cp "$P/prog.nu" "$P/nul.nu"; printf '\n// after\0hidden\n' >> "$P/nul.nu"
if out=$("$C" certify "$P/nul.nu" "${CA[@]}" --out "$P/nul.cert" 2>&1); then bad "a file that is not its compiled snapshot certifies nothing"
else
    case "$out" in *"not the bytes nurlc compiled"*) ok "a file that is not its compiled snapshot certifies nothing" ;; *) bad "a file that is not its compiled snapshot certifies nothing ($out)" ;; esac
fi

# The unsafe report comes from a compile of the same bytes, and a source
# line that reads like a report row is not one: one `unsafe` function, one
# ledger row.
printf '// looks like a row: prog.nu:12 fake\nunsafe @ f → i { ^ 1 }\n@ main → i { ^ ( f ) }\n' > "$P/uns.nu"
"$C" certify "$P/uns.nu" "${CA[@]}" --out "$P/uns.cert" > /dev/null 2>&1
nu=$(grep -c '"id": "unsafe-[0-9]' "$P/uns.cert/manifest.json" 2>/dev/null || echo 0)
if [ "$nu" = 1 ] && grep -q 'uns.nu:2 f' "$P/uns.cert/manifest.json"; then ok "the unsafe report: one row per unsafe function, none from source text"
else bad "the unsafe report: one row per unsafe function, none from source text ($nu rows)"; fi

# nurlc lists one file per line, or stops.
mkdir -p "$P/nl"; nlf="$P/nl/a
b.nu"
cp "$P/prog.nu" "$nlf"
if out=$("$NURLC" --emit-core --list-sources=t "$nlf" 2>&1 >/dev/null); then bad "a source path with a newline stops --list-sources"
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

echo "== 2b. the term checked by the kernel (Elab.lean)"
E="$P/e.cert"
cp tools/ncore/certify/int_recursion_early_return.nu "$P/e.nu"
cp tools/ncore/certify/while_loop_summing.nu "$P/w2.nu"
"$C" certify "$P/e.nu" "${CA[@]}" > /dev/null 2>&1 || bad "certify the scalar tamper program"
"$C" certify "$P/w2.nu" "${CA[@]}" > /dev/null 2>&1 || bad "certify the other scalar program"
efresh() { rm -rf "$P/w"; cp -r "$E" "$P/w"; }
# rehash KEY FILE: the manifest's hashes.KEY made to agree with FILE.
rehash() {
    python3 - "$P/w/manifest.json" "$1" "$2" <<'EOF2'
import hashlib, json, sys
p, k, f = sys.argv[1:]; m = json.load(open(p))
m["hashes"][k] = hashlib.sha256(open(f, "rb").read()).hexdigest()
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
}
# expect_only_fail NAME CHECK-TEXT: verify fails, and on that check alone
# (besides the Lean checks it then does not run).
expect_only_fail() {
    out="$("$C" verify "$P/w" --formal "$ROOT/formal" 2>&1)"; rc=$?
    nf=$(printf '%s\n' "$out" | grep "^  FAIL" | grep -c -v ': not run\|: not checked$')
    if [ "$rc" != 0 ] && [ "$nf" = 1 ] && printf '%s\n' "$out" | grep -q "FAIL  .*$2"; then ok "$1"
    else bad "$1 (verify rc $rc, $nf failed checks; expected one FAIL naming: $2)"; printf '%s\n' "$out" | grep -v "^  ok" | sed 's/^/        /'; fi
}
efresh
if [ -e "$P/w/Elab.lean" ] && grep -q '"elab_lean"' "$P/w/manifest.json" \
    && grep -q 'Cert.elab: C.Elab.elabIR builds P and entry' "$P/w/manifest.json" \
    && "$C" verify "$P/w" --formal "$ROOT/formal" > "$TMP/v.out" 2>&1 \
    && grep -q "ok    Lean proves Cert.elab" "$TMP/v.out"; then ok "a fresh scalar bundle has Elab.lean, its ledger says so, and it verifies"
else bad "a fresh scalar bundle has Elab.lean, its ledger says so, and it verifies"; cat "$TMP/v.out"; fi

# THE case: another program's term, its hash updated. Today's plain verify
# passes this on a bundle without Elab.lean (the note in part 2); with
# Elab.lean the kernel refuses it.
efresh
cmp -s "$P/w/Claims.lean" "$P/w2.cert/Claims.lean" || bad "the two scalar programs share a Claims.lean (one slot each)"
cmp -s "$P/w/Program.lean" "$P/w2.cert/Program.lean" && bad "the two scalar programs have different terms"
cp "$P/w2.cert/Program.lean" "$P/w/Program.lean"; rehash program_lean "$P/w/Program.lean"
expect_only_fail "another scalar program's term, its hash updated: plain verify fails on Cert.elab" "Lean proves Cert.elab"
efresh; rm "$P/w/Elab.lean"
expect_fail "Elab.lean deleted, the manifest kept" "Elab.lean is there"
efresh; sed -i '0,/"scope"/s//"scope", "x"/' "$P/w/Elab.lean"; rehash elab_lean "$P/w/Elab.lean"
grep -q '"scope", "x"' "$P/w/Elab.lean" || bad "the edit of Elab.lean's words applied"
expect_only_fail "Elab.lean's words edited, its hash updated" "Elab.lean is Program.core's words and the template"
efresh; sed -i 's/= some (P, entry) :=/= some (P, entry) ∨ True :=/' "$P/w/Elab.lean"; rehash elab_lean "$P/w/Elab.lean"
grep -q '∨ True' "$P/w/Elab.lean" || bad "the Elab.lean edit applied"
expect_only_fail "Elab.lean's theorem edited, its hash updated" "Elab.lean is Program.core's words and the template"
efresh; rm -f "$TMP/pwned"; printf '\n#eval IO.FS.writeFile "%s" "ran"\n' "$TMP/pwned" >> "$P/w/Elab.lean"; rehash elab_lean "$P/w/Elab.lean"
expect_fail "code put in Elab.lean is refused" "Lean proves Cert.elab (Elab.lean) on the standard axioms: not run"
if [ -e "$TMP/pwned" ]; then bad "the #eval planted in Elab.lean never ran"; else ok "the #eval planted in Elab.lean never ran"; fi
# A NUL byte, and what follows it, read to the end: the files are checked
# as the bytes Lean reads, not as the C string up to the first NUL.
efresh; printf '\000\377\n' >> "$P/w/Program.core"; rehash core_ir "$P/w/Program.core"
expect_fail "a NUL and a byte that is not UTF-8 after Program.core's text, its hash updated" "Elab.lean is Program.core's words and the template"
efresh; printf '\000\naxiom cheat : False\n' >> "$P/w/Program.lean"; rehash program_lean "$P/w/Program.lean"
expect_fail "a NUL and an axiom after Program.lean's term, its hash updated: the grammar sees it, Lean never runs" "Program.lean only defines the program"
# Downgraded: Elab.lean removed and its hash dropped. With the translation
# row the translator's again it is the weaker bundle, and verifies as one;
# with the kernel's row kept, it does not.
efresh; rm "$P/w/Elab.lean"
python3 - "$P/w/manifest.json" <<'EOF2'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
del m["hashes"]["elab_lean"]
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
expect_only_fail "downgraded, the kernel's ledger row kept" "the trust ledger is the one certify writes"
python3 - "$P/w/manifest.json" "$B/manifest.json" <<'EOF2'
import json, sys
p, q = sys.argv[1:]; m = json.load(open(p)); row = [r for r in json.load(open(q))["ledger"] if r["id"] == "translation"][0]
m["ledger"] = [row if r["id"] == "translation" else r for r in m["ledger"]]
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
if "$C" verify "$P/w" --formal "$ROOT/formal" > "$TMP/v.out" 2>&1 && grep -q "ok    no Elab.lean" "$TMP/v.out"; then
    ok "downgraded honestly (the translator's row again): verifies as the weaker bundle"
else bad "downgraded honestly (the translator's row again): verifies as the weaker bundle"; cat "$TMP/v.out"; fi
# The other way: Elab.lean put into a bundle whose manifest records none.
fresh; cp "$E/Elab.lean" "$P/w/Elab.lean"
expect_fail "Elab.lean beside a manifest that records none" "no Elab.lean"

echo "== 2c. every word of a core IR is a string literal"
# Quotes, backslashes, comment openers and closers, a would-be declaration,
# control characters, a CR, a header's empty word, a line of tabs only, and
# non-ASCII UTF-8 (two, three and four bytes). Lean must read every word
# back as its bytes, and declare nothing but `ir`.
printf 'fn\tq"uo\\te\ti64\t0\t1\t/d i r/\303\244\342\202\254\360\237\230\200.nu\t0\t\n' > "$TMP/x.core"
printf 'let 0 -/ /- "] axiom cheat : False -- \\x41 \\ "" \\"\n' >> "$TMP/x.core"
printf 'eval \001\037\177 end" /-!\n\t\t\n  \n--\tret c\r\n' >> "$TMP/x.core"
if "$C" words "$TMP/x.core" > "$TMP/x.words" 2> "$TMP/x.err"; then
    { echo "import C.Elab"; cat "$TMP/x.words"; echo; echo '#eval IO.println (toString (ir.map (·.map C.Elab.bytesOf)))'; echo '#print axioms ir'; } > "$TMP/x.lean"
    want=$(python3 - "$TMP/x.core" <<'EOF2'
import sys
t = open(sys.argv[1], "rb").read()
hdr = (b"fn\t", b"v\t", b"ty\t", b"sum\t")
rows = [l.split(b"\t") if l.startswith(hdr) else [w for w in l.replace(b"\t", b" ").split(b" ") if w]
        for l in t.split(b"\n") if l.strip(b" ")]
print(str([[list(w) for w in r] for r in rows]))
EOF2
)
    have=$(cd "$ROOT/formal" && lake env lean "$TMP/x.lean" 2>&1); lrc=$?
    if [ "$lrc" = 0 ] && [ "$(printf '%s\n' "$have" | head -1)" = "$want" ] \
        && [ "$(printf '%s\n' "$have" | sed -n 2p)" = "'ir' does not depend on any axioms" ] && [ "$(printf '%s\n' "$have" | wc -l)" = 2 ]; then
        ok "every word is a string literal Lean reads back as its bytes"
    else bad "every word is a string literal Lean reads back as its bytes (lean rc $lrc)"; printf '%s\n%s\n' "$want" "$have" | head -5 | cut -c1-300 | sed 's/^/        /'; fi
else bad "nurl-cert words reads the crafted core IR"; cat "$TMP/x.err"; fi
# A byte Lean would read as U+FFFD: no words (and so no Elab.lean).
for b in '\377' '\300\257' '\355\240\200' '\364\220\200\200' '\303'; do
    printf "fn\tmain\ti64\t0\t1\ta$b.nu\t0\t\n" > "$TMP/y.core"
    if "$C" words "$TMP/y.core" > /dev/null 2>&1; then bad "a core IR that is not UTF-8 ($b) has no words"
    else ok "a core IR that is not UTF-8 ($b) has no words"; fi
done
# The bytes after a NUL are read too: `ret c`, NUL, 0xff.
printf 'ret c\000\377\n' > "$TMP/y.core"
if "$C" words "$TMP/y.core" > /dev/null 2>&1; then bad "a core IR with a NUL and a byte that is not UTF-8 after it has no words"
else ok "a core IR with a NUL and a byte that is not UTF-8 after it has no words"; fi

echo "== 3. the fast profile"
"$C" certify "$P/prog.nu" "${CA[@]}" --profile fast --out "$P/fast.cert" > "$TMP/f.out" 2>&1
if grep -q "M.safe validated" "$TMP/f.out" && grep -q "native_decide" "$P/fast.cert/manifest.json" \
    && grep -q '"validated": 1' "$P/fast.cert/manifest.json" && ! grep -q '"status": "proved"' "$P/fast.cert/manifest.json" \
    && "$C" verify "$P/fast.cert" --formal "$ROOT/formal" > /dev/null 2>&1; then ok "fast: validated (claims and coverage), its axiom listed, verifies"
else bad "fast: validated, its axiom listed, verifies"; cat "$TMP/f.out"; fi

echo "== 4. every manifest against docs/dev/certificate.schema.json"
if python3 -c "import jsonschema" 2> /dev/null; then
    if python3 - "$ROOT/docs/dev/certificate.schema.json" "$TMP"/progs/*/*.cert/manifest.json "$B/manifest.json" "$E/manifest.json" "$P/fast.cert/manifest.json" <<'EOF2'
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
