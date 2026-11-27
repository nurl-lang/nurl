#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  nurl-cert end-to-end tests (AGORA-1019).
#
#  Run from anywhere in a checkout:  packages/nurl-cert/tests/nurl-cert_test.sh
#  Needs: build/nurlc, Lean's lean (and lake) on PATH, formal/ built (lake build C.Cert C.Cert3 C.Elab).
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
#  1b. The one Lean file certify and verify check agrees with the module
#     way (Program.olean, then Claims.lean and Elab.lean) on three bundles;
#     a candidate whose Elab.lean part fails is accepted without Elab.lean.
#  2. Tampering: a fresh bundle verifies, and `verify` fails, naming the
#     check, on each of: one source byte changed; a claim's status edited
#     in the manifest; a theorem's statement weakened in Claims.lean;
#     `sorry` put in Claims.lean, or an axiom added to Program.lean; the
#     wrong binary given. Then the term checked by the kernel (a bundle with
#     Elab.lean): another scalar program's Program.lean swapped in with its
#     hash updated fails a plain verify, on Cert.elab; so do Elab.lean
#     deleted, its words edited and its theorem edited; a bundle downgraded
#     honestly (Elab.lean removed, its hash dropped, and the kernel's rows,
#     core-ir-words and the encodings', the translator's translation row
#     again, in the ledger and the premises) verifies, as the weaker bundle
#     it is. And every word of a core IR is a string literal
#     Lean reads back as the word.
#  3. The fast profile: a bundle whose claims are `validated`, with the
#     compiled-code axiom listed, verifies.
# ============================================================
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
export NURL_STDLIB="$ROOT"
NURLC="$ROOT/build/nurlc"
# Windows (Git Bash): the driver is nurl.bat and a program is <name>.exe
# (AGORA-1031); elsewhere nurl.sh and <name>.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WIN=1; EXE=.exe ;; *) WIN=0; EXE= ;; esac
# build_prog SRC OUT [driver options…]: OUT$EXE, built by the repository's driver.
build_prog() {
    src="$1"; dst="$2"; shift 2
    if [ "$WIN" = 1 ]; then cmd //c "$(cygpath -w "$ROOT/nurl.bat")" "$@" "$(cygpath -w "$src")" "$(cygpath -w "$dst")"
    else "$ROOT/nurl.sh" "$@" "$src" "$dst"; fi
}
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
    ( cd packages/nurl-cert && build_prog src/main.nu "$CERT" -O0 ) > "$TMP/build.log" 2>&1 \
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
# (the accepted ones among EXPECT_CERTIFY: a refused program gets no Elab.lean)
have_elab=$(sed -n 's/^ok \(.*\) accepted (elab)$/\1/p' "$TMP/progs.txt" | sort | tr '\n' ' ')
want_elab=$(printf '%s\n' cursor_over_a_vec int_recursion_early_return joins_each_freeing_a_different_vec \
    loop_with_continue_and_break moved_on_one_branch_only owner_moved_only_on_an_early_return_from_a_loop \
    owners_rotated_in_a_loop raw_string_given_to_a_sink raw_strings_literal_and_fresh \
    temporary_dropped_in_an_if_arm vec_elements_read_between_pushes vec_push_len while_loop_summing \
    view_taken_after_the_pushes vec_cleared_then_pushed vec_reserved_then_pushed foreach_summing_a_vec \
    raw_strings_held_in_a_vec clo_called_in_a_loop clo_changes_a_captured_vec clo_no_captures_two_arguments \
    clo_number_capture_called clo_returned_owning_a_vec_capture clo_returned_with_a_number_capture \
    clo_string_captured_and_read_after clo_two_captures_passed_to_a_function \
    struct_field_handed_to_a_reader struct_fields_read vec_moved_into_a_struct option_built_and_matched \
    destructor_frame_left_by_an_early_return destructor_reads_a_view_of_a_live_source \
    chan_int_sent_and_received chan_string_sent_and_received \
    thread_sends_on_a_channel_main_receives thread_spawned_with_a_number_capture \
    | sort | tr '\n' ' ')
if [ "$have_elab" = "$want_elab" ]; then ok "exactly the 36 accepted certify programs in the subset have Elab.lean (Cert.elab)"
else bad "exactly the 36 accepted certify programs in the subset have Elab.lean (Cert.elab): have $have_elab"; fi
# (since step 10 every certify program is in the subset: none keeps the
# translator's term; the selftest's own program outside it is part 2's)
if ! grep -q "accepted (translator)" "$TMP/progs.txt"; then ok "every accepted certify program has Elab.lean (no term the translator's)"
else bad "every accepted certify program has Elab.lean: $(grep 'accepted (translator)' "$TMP/progs.txt" | tr '\n' ' ')"; fi

echo "== 1b. one Lean file, and the module way"
# certify and verify check a bundle in one Lean file (Program.lean's
# definitions in a section, then Claims.lean's and Elab.lean's bodies). The
# module way (Program.lean compiled to its olean, then Claims.lean and
# Elab.lean against it) must say the same: the verdict, each claim's
# axioms, and Cert.elab.
for n in vec_push_len thread_sends_on_a_channel_main_receives struct_fields_read; do
    B="$TMP/progs/$n/$n.cert"; W="$TMP/mod/$n"; mkdir -p "$W"
    ( cd "$ROOT/formal" && lake env lean --root="$B" -o "$W/Program.olean" "$B/Program.lean" > "$W/p.log" 2>&1 \
        && LEAN_PATH="$W" lake env lean "$B/Claims.lean" > "$W/c.log" 2>&1 \
        && { [ ! -e "$B/Elab.lean" ] || LEAN_PATH="$W" lake env lean "$B/Elab.lean" > "$W/e.log" 2>&1; } ); mrc=$?
    if [ "$mrc" = 0 ] && python3 - "$B" "$W" <<'EOF2'
import json, os, re, sys
b, w = sys.argv[1:]
m = json.load(open(os.path.join(b, "manifest.json")))
log = open(os.path.join(w, "c.log")).read()
def axioms(text, name):
    x = re.search(r"^'%s' (depends on axioms: \[(.*)\]|does not depend on any axioms)" % re.escape(name), text, re.M)
    return None if x is None else ([] if x.group(2) is None else x.group(2).split(", "))
lean = [c for c in m["claims"] if c["lean"]]   # (M.unsafe is the ledger's, not Lean's)
ok = len(lean) >= 2 and all(c["status"] == "proved" and axioms(log, c["lean"]) == c["axioms"] for c in lean)
has_elab = os.path.exists(os.path.join(b, "Elab.lean"))
if has_elab:
    ok = ok and "elab_lean" in m["hashes"] and axioms(open(os.path.join(w, "e.log")).read(), "Cert.elab") == ["propext", "Quot.sound"]
else:
    ok = ok and "elab_lean" not in m["hashes"]
sys.exit(0 if ok else 1)
EOF2
    then ok "$n: the module way agrees with the combined check (verdict, each claim's axioms, Cert.elab)"
    else bad "$n: the module way agrees with the combined check (lean rc $mrc)"; cat "$W"/*.log | head -5; fi
done
# A candidate (every constructor of its term is one elabIR builds) that
# elabIR refuses (a Vec of Strings): the Elab.lean part of the one file
# fails, and that only means no Elab.lean. The program is accepted, its
# term the translator's, and the bundle verifies.
P1="$TMP/c1"; mkdir -p "$P1"
printf '$ `stdlib/core/vec.nu`\n\n@ main → i {\n    : ~ ( Vec String ) v ( vec_new [String] )\n    ^ ( vec_len [String] v )\n}\n' > "$P1/vs.nu"
"$C" certify "$P1/vs.nu" "${CA[@]}" > "$P1/out" 2>&1; rc=$?
ctors=$(sed -n 's/^: s ELAB_CTORS `\(.*\)`$/\1/p' packages/nurl-cert/src/claims.nu)
cand=$(python3 - "$P1/vs.cert/Program.lean" "$ctors" <<'EOF2'
import re, sys
t = "".join(l for l in open(sys.argv[1]) if not l.startswith(("import ", "open ")))
used = set(re.findall(r"(?<![A-Za-z0-9_])\.([A-Za-z_][A-Za-z0-9_]*)", t))
print("yes" if used and used <= set(sys.argv[2].split()) else "no")
EOF2
)
if [ "$rc" = 0 ] && [ "$cand" = yes ] && [ -n "$ctors" ] && grep -q "M.safe proved" "$P1/out" && grep -q "M.leak proved" "$P1/out" \
    && grep -q "term: the translator's" "$P1/out" && [ ! -e "$P1/vs.cert/Elab.lean" ] \
    && grep -Eq "^  Cert.elab not proved: .*All\.lean:[0-9]+:[0-9]+: error" "$P1/out" \
    && "$C" verify "$P1/vs.cert" --formal "$ROOT/formal" > /dev/null 2>&1; then
    ok "a candidate whose Elab.lean part fails: accepted, no Elab.lean, verifies"
else bad "a candidate whose Elab.lean part fails: accepted, no Elab.lean, verifies (rc $rc, candidate $cand)"; cat "$P1/out" | head -5; fi

# Lean's messages are placed by their own line in the one file (Program.lean
# and Claims.lean before the Elab.lean part's first line, Elab.lean from it),
# not by where they come in the output. (a) certify: each refused program
# in the subset had an Elab.lean part the kernel proves next to the
# claims' refusal, and is refused. (b) verify: a refused program's term
# in a bundle with Elab.lean (the claims and Elab.lean both fail) does not
# verify, and fails on the claims. (c) An error in the Elab.lean part alone
# only drops Elab.lean: the candidate above, and part 2b's swapped term.
nref=0; badref=""
for n in moved_on_one_branch_then_read_refused owner_moved_in_a_loop_without_returning_refused \
    owner_read_after_its_move_in_the_round_before_refused raw_string_read_after_its_sink_refused \
    use_after_move_refused vec_element_read_after_its_move_refused \
    view_kept_across_a_realloc_refused view_kept_across_pushes_in_a_loop_refused \
    view_kept_across_a_clear_refused view_kept_across_a_reserve_refused \
    string_copied_from_a_view_of_a_freed_string_refused string_pushed_its_own_view_refused \
    vec_pushed_while_iterated_refused raw_string_held_in_a_vec_past_its_source_refused \
    clo_called_on_a_moved_vec_refused clo_called_with_a_moved_vec_refused \
    clo_changes_a_captured_vec_under_a_slice_refused \
    clo_returned_over_a_parameter_then_called_after_its_free_refused \
    clo_string_capture_rebound_then_called_refused \
    destructor_frame_left_by_an_early_return_after_its_source_moved_refused \
    destructor_reads_a_view_of_a_moved_source_refused \
    chan_string_read_after_its_send_refused \
    thread_body_reads_a_vec_after_its_move_refused thread_channel_read_after_an_alias_took_it_refused; do
    pl="$TMP/progs/$n/$n.cert/Program.lean"
    c=$(python3 - "$pl" "$ctors" <<'EOF2'
import re, sys
t = "".join(l for l in open(sys.argv[1]) if not l.startswith(("import ", "open ")))
used = set(re.findall(r"(?<![A-Za-z0-9_])\.([A-Za-z_][A-Za-z0-9_]*)", t))
print("yes" if used and used <= set(sys.argv[2].split()) else "no")
EOF2
)
    if [ "$c" = yes ] && grep -qx "ok $n refused" "$TMP/progs.txt"; then nref=$((nref + 1)); else badref="$badref $n"; fi
done
[ "$nref" = 24 ] && ok "the 24 refused programs in the subset (an Elab.lean part beside the claims' refusal) are refused" \
    || bad "the refused programs in the subset are refused:$badref"
R="$TMP/rv"; rm -rf "$R"; cp -r "$TMP/progs/vec_push_len/vec_push_len.cert" "$R"
cp "$TMP/progs/use_after_move_refused/use_after_move_refused.cert/Program.lean" "$R/Program.lean"
python3 - "$R/manifest.json" "$R/Program.lean" <<'EOF2'
import hashlib, json, sys
p = sys.argv[1]; m = json.load(open(p))
m["hashes"]["program_lean"] = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
out=$("$C" verify "$R" --formal "$ROOT/formal" 2>&1); vrc=$?
# (Lean's own refusal, placed in the claims' part; not a check before Lean)
if [ "$vrc" != 0 ] && printf '%s\n' "$out" | grep -Eq "FAIL  Lean checks Program.lean and Claims.lean: .*All\.lean:[0-9]+:[0-9]+: error" \
    && ! printf '%s\n' "$out" | grep -q "not run" && ! printf '%s\n' "$out" | grep -q "ok    M.safe"; then
    ok "a refused program's term in a bundle with Elab.lean: verify fails on the claims"
else bad "a refused program's term in a bundle with Elab.lean: verify fails on the claims (rc $vrc)"; printf '%s\n' "$out" | sed 's/^/        /' | head -12; fi

# A Lean run that ends abnormally (here: a lean that dies, exit 137, on any
# file with an Elab.lean part) costs the optional Cert.elab only: certify
# checks the claims again alone and keeps them; verify of a bundle that holds
# Elab.lean still fails on Cert.elab.
if [ "$WIN" = 1 ]; then
    # (Windows starts no script by its #! line: the same lean as a .cmd)
    KL="$TMP/killlean.cmd"; cat > "$KL" <<'EOF2'
@echo off
for %%a in (%*) do (
  if /I "%%~xa"==".lean" (
    findstr /B /C:"import C.Elab" "%%~fa" > nul 2>&1 && exit /b 137
  )
)
lean %*
EOF2
else
    KL="$TMP/killlean"; cat > "$KL" <<'EOF2'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *.lean) grep -q '^import C.Elab$' "$a" && exit 137;; esac; done
exec lean "$@"
EOF2
    chmod +x "$KL"
fi
K="$TMP/kl"; rm -rf "$K"; mkdir -p "$K"; cp tools/ncore/certify/vec_push_len.nu "$K/p.nu"
"$C" certify "$K/p.nu" "${CA[@]}" --lean "$KL" > "$K/out" 2>&1; krc=$?
kv=$("$C" verify "$TMP/progs/vec_push_len/vec_push_len.cert" --formal "$ROOT/formal" --lean "$KL" 2>&1); kvrc=$?
if [ "$krc" = 0 ] && grep -q "M.safe proved" "$K/out" && grep -q "M.leak proved" "$K/out" && [ ! -e "$K/p.cert/Elab.lean" ] \
    && grep -q "Cert.elab not proved: the Lean run ended abnormally (exit 137)" "$K/out" \
    && "$C" verify "$K/p.cert" --formal "$ROOT/formal" > /dev/null 2>&1 \
    && [ "$kvrc" != 0 ] && printf '%s\n' "$kv" | grep -q "FAIL  Lean proves Cert.elab"; then
    ok "a Lean run that dies in the Elab.lean part: certify keeps the claims without Elab.lean, verify still needs Cert.elab"
else bad "a Lean run that dies in the Elab.lean part (certify rc $krc, verify rc $kvrc)"; head -8 "$K/out"; fi

echo "== 2. tampering"
# (a program outside C.Elab's subset, of A2's checker: its bundle's term is
# the translator's, and its ledger row the one a downgraded bundle must
# have, part 2b. Since step 9 every certify program of A2's is in the
# subset, so it is the selftest's own: tests/outside_elab.nu, a Vec of
# Strings)
P="$TMP/t"; mkdir -p "$P"
cp packages/nurl-cert/tests/outside_elab.nu "$P/prog.nu"
build_prog "$P/prog.nu" "$P/prog" > /dev/null 2>&1 || bad "the program builds"
cp "$P/prog$EXE" "$P/other"; printf 'x' >> "$P/other"
"$C" certify "$P/prog.nu" "${CA[@]}" --binary "$P/prog$EXE" > /dev/null 2>&1 || bad "certify the tamper program"
B="$P/prog.cert"
if [ -e "$B/Claims.lean" ] && [ ! -e "$B/Elab.lean" ]; then ok "the tamper program (outside the subset) is accepted, with no Elab.lean"
else bad "the tamper program (outside the subset) is accepted, with no Elab.lean"; fi
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
if "$C" verify "$P/w" --formal "$ROOT/formal" --binary "$P/prog$EXE" > "$TMP/v.out" 2>&1; then ok "a fresh bundle verifies"
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
# (Windows file names cannot hold a newline: nothing to list there)
if [ "$WIN" = 1 ]; then echo "  SKIP  a source path with a newline stops --list-sources: no such path on Windows"
else
mkdir -p "$P/nl"; nlf="$P/nl/a
b.nu"
cp "$P/prog.nu" "$nlf"
if out=$("$NURLC" --emit-core --list-sources=t "$nlf" 2>&1 >/dev/null); then bad "a source path with a newline stops --list-sources"
else
    case "$out" in *"holds a newline"*) ok "a source path with a newline stops --list-sources" ;; *) bad "a source path with a newline stops --list-sources ($out)" ;; esac
fi
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
    && grep -q '"id": "core-ir-words"' "$P/w/manifest.json" && grep -q '"id": "enc-numbers"' "$P/w/manifest.json" \
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
# (a word put after the first `scope`: its number is `scope`'s bytes, last
# to first, after `nat_lit 0x1`; `x` is 0x178)
efresh; sed -i '0,/nat_lit 0x165706f6373\]/s//nat_lit 0x165706f6373, nat_lit 0x178]/' "$P/w/Elab.lean"; rehash elab_lean "$P/w/Elab.lean"
grep -q 'nat_lit 0x165706f6373, nat_lit 0x178' "$P/w/Elab.lean" || bad "the edit of Elab.lean's words applied"
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
# Downgraded: Elab.lean removed and its hash dropped. With the translator's
# row again in place of the kernel's (`core-ir-words` and the encodings'
# rows, AGORA-1029), in the ledger and in each claim's premises, it is the
# weaker bundle, and verifies as one; with the kernel's rows kept, it does
# not (its premises and its ledger are not the translator's).
efresh; rm "$P/w/Elab.lean"
python3 - "$P/w/manifest.json" <<'EOF2'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
del m["hashes"]["elab_lean"]
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
out="$("$C" verify "$P/w" --formal "$ROOT/formal" 2>&1)"; rc=$?
nf=$(printf '%s\n' "$out" | grep "^  FAIL" | grep -c -v ': not run\|: not checked$')
if [ "$rc" != 0 ] && [ "$nf" = 2 ] && printf '%s\n' "$out" | grep -q "FAIL  the trust ledger is the one certify writes" \
    && printf '%s\n' "$out" | grep -q "FAIL  the claims are the template's"; then ok "downgraded, the kernel's ledger rows kept: its ledger and premises fail"
else bad "downgraded, the kernel's ledger rows kept: its ledger and premises fail (verify rc $rc, $nf failed)"; printf '%s\n' "$out" | grep -v "^  ok" | sed 's/^/        /'; fi
python3 - "$P/w/manifest.json" "$B/manifest.json" <<'EOF2'
import json, sys
p, q = sys.argv[1:]; m = json.load(open(p)); row = [r for r in json.load(open(q))["ledger"] if r["id"] == "translation"][0]
kern = lambda i: i == "core-ir-words" or i.startswith("enc-")
L = []
for r in m["ledger"]:
    if r["id"] == "core-ir-words": L.append(row)
    elif not kern(r["id"]): L.append(r)
m["ledger"] = L
for c in m["claims"]:
    ps = []
    for x in c["premises"]:
        if x == "core-ir-words": ps.append("translation")
        elif not kern(x): ps.append(x)
    c["premises"] = ps
open(p, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF2
if "$C" verify "$P/w" --formal "$ROOT/formal" > "$TMP/v.out" 2>&1 && grep -q "ok    no Elab.lean" "$TMP/v.out"; then
    ok "downgraded honestly (the translator's row again): verifies as the weaker bundle"
else bad "downgraded honestly (the translator's row again): verifies as the weaker bundle"; cat "$TMP/v.out"; fi
# The other way: Elab.lean put into a bundle whose manifest records none.
fresh; cp "$E/Elab.lean" "$P/w/Elab.lean"
expect_fail "Elab.lean beside a manifest that records none" "no Elab.lean"

echo "== 2c. every word of a core IR decodes to its bytes"
# Quotes, backslashes, comment openers and closers, a would-be declaration,
# control characters, a CR, a header's empty word, a line of tabs only,
# non-ASCII UTF-8 (two, three and four bytes), and bytes that are not
# UTF-8. Each word is a number (`nat_lit 0x1`, then its bytes last to
# first); Lean must read every word back as its bytes (`C.Elab.wordOf`),
# and declare nothing but `ir`.
printf 'fn\tq"uo\\te\ti64\t0\t1\t/d i r/\303\244\342\202\254\360\237\230\200.nu\t0\t\n' > "$TMP/x.core"
printf 'let 0 -/ /- "] axiom cheat : False -- \\x41 \\ "" \\"\n' >> "$TMP/x.core"
printf 'eval \001\037\177 end" /-!\n\t\t\n  \n--\tret c\r\n' >> "$TMP/x.core"
printf 'eval \377 \300\257 \355\240\200 \364\220\200\200 \303\n' >> "$TMP/x.core"
if "$C" words "$TMP/x.core" > "$TMP/x.words" 2> "$TMP/x.err"; then
    { echo "import C.Elab"; cat "$TMP/x.words"; echo; echo '#eval IO.println (toString (ir.map (·.map C.Elab.wordOf)))'; echo '#print axioms ir'; } > "$TMP/x.lean"
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
        ok "every word is a number Lean reads back as its bytes (non-UTF-8 bytes included)"
    else bad "every word is a number Lean reads back as its bytes (lean rc $lrc)"; printf '%s\n%s\n' "$want" "$have" | head -5 | cut -c1-300 | sed 's/^/        /'; fi
else bad "nurl-cert words reads the crafted core IR"; cat "$TMP/x.err"; fi
# A long word (2000 bytes: its number has ~4800 decimal digits) reaches the
# parity test's JSON whole, from the words and from every line alike.
printf 'eval %s\n' "$(head -c 2000 /dev/zero | tr '\0' 'x')" > "$TMP/long.core"
if "$C" words "$TMP/long.core" > "$TMP/long.words" 2> /dev/null \
    && python3 "$ROOT/tools/ncore/elab_parity_json.py" "$TMP/long.words" > "$TMP/long.json" \
    && python3 "$ROOT/tools/ncore/elab_parity_full.py" "$TMP/long.core" > "$TMP/long.full" \
    && python3 - "$TMP/long.json" "$TMP/long.full" <<'EOF2'
import json, sys
hasattr(sys, "set_int_max_str_digits") and sys.set_int_max_str_digits(0)
a, b = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
w = b"x" * 2000
sys.exit(0 if a == b == [[256 ** 4 + int.from_bytes(b"eval"[::-1], "big"), 256 ** 2000 + int.from_bytes(w, "big")]] else 1)
EOF2
then ok "a 2000-byte word reaches the parity JSON whole"
else bad "a 2000-byte word reaches the parity JSON whole"; fi
# The words are made from the text up to its first NUL: a core IR with one
# has no words (`ret c`, NUL, 0xff).
printf 'ret c\000\377\n' > "$TMP/y.core"
if "$C" words "$TMP/y.core" > /dev/null 2>&1; then bad "a core IR with a NUL has no words"
else ok "a core IR with a NUL has no words"; fi

echo "== 2d. a library function is left out of the words only when Lean's reader reads it"
# A library function (file under stdlib/) and main. The words leave the
# library function out when C.Elab.readFns would accept its records, and
# print its records when it would not, so that the reader (and elabIR)
# refuses the words as it refuses every line. Each case: the reader
# (`fnsOf`) accepts the words exactly when it accepts every line, and that
# is the answer the case expects.
lib_case() {  # name, want (true/false), then the core IR's lines
    local n="$1" want="$2"; shift 2
    printf '%s\n' "$@" > "$TMP/l_$n.core"
    if "$C" words "$TMP/l_$n.core" > "$TMP/l_$n.words" 2> /dev/null; then
        # every line, split as the words are, each word its number
        full=$(python3 "$ROOT/tools/ncore/elab_parity_full.py" "$TMP/l_$n.core")
        { echo "namespace L_$n"; cat "$TMP/l_$n.words"; echo "def full : C.Elab.IR := $full"
          echo "#eval IO.println s!\"$n {(C.Elab.fnsOf ir).isSome} {(C.Elab.fnsOf full).isSome} $want\""; echo "end L_$n"; } >> "$TMP/l.lean"
    else bad "nurl-cert words reads the library case $n"; fi
}
echo "import C.Elab" > "$TMP/l.lean"
T=$'\t'
LF="fn${T}libf${T}i64${T}1${T}1${T}stdlib/core/x.nu${T}0${T}"
LV="v${T}0${T}0${T}0${T}0${T}1${T}-1${T}x${T}i64"
MAIN=("fn${T}main${T}i64${T}0${T}5${T}m.nu${T}0${T}" "ret c" "endfn")
lib_case clean true "$LF" "$LV" "ret v0" "endfn" "${MAIN[@]}"
lib_case kind_0003 true "$LF" "v${T}0${T}0003${T}0${T}0${T}1${T}-1${T}x${T}i64" "endfn" "${MAIN[@]}"
lib_case stmt_v true "$LF" "$LV" "v 0 0 0 0 1" "endfn" "${MAIN[@]}"
lib_case kind_4 false "$LF" "v${T}0${T}4${T}0${T}0${T}1${T}-1${T}x${T}i64" "endfn" "${MAIN[@]}"
lib_case stmt_v_kind_9 false "$LF" "$LV" "v 0 9 0 0 1" "endfn" "${MAIN[@]}"
lib_case flags_x false "$LF" "v${T}0${T}0${T}0${T}x${T}1${T}-1${T}x${T}i64" "endfn" "${MAIN[@]}"
lib_case v_short false "$LF" "v${T}0${T}0${T}0${T}0" "endfn" "${MAIN[@]}"
lib_case np_empty false "fn${T}libf${T}i64${T}${T}1${T}stdlib/core/x.nu${T}0${T}" "$LV" "endfn" "${MAIN[@]}"
lib_case nested false "$LF" "$LV" "fn${T}q${T}i64${T}0${T}1${T}q.nu${T}0${T}" "endfn" "${MAIN[@]}"
lib_case in_main false "${MAIN[0]}" "$LF" "$LV" "endfn" "ret c" "endfn"
lib_case unclosed false "${MAIN[@]}" "$LF" "$LV" "ret v0"
if grep -q "$(python3 -c 'print("0x1" + b"libf"[::-1].hex())')" "$TMP/l_clean.words"; then bad "a library function the reader reads is left out of the words"
else ok "a library function the reader reads is left out of the words"; fi
have=$(cd "$ROOT/formal" && lake env lean "$TMP/l.lean" 2>&1); lrc=$?
nl=$(printf '%s\n' "$have" | awk 'NF == 4 && $2 == $3 && $3 == $4' | wc -l)
if [ "$lrc" = 0 ] && [ "$nl" = 11 ] && [ "$(printf '%s\n' "$have" | wc -l)" = 11 ]; then
    ok "the reader accepts the words of each library case as it accepts its every line (11 cases)"
else bad "the reader accepts the words of each library case as it accepts its every line (lean rc $lrc)"; printf '%s\n' "$have" | head -20 | sed 's/^/        /'; fi

echo "== 2e. a sum line is left out of the words only outside every function"
# A top-level `sum` line no other word names is left out (elabIR looks a
# summary up only by a function's, a callee's or a let-called function's
# name); one inside a function is a statement of its body, kept, so that
# elabIR refuses the words as it refuses every line. Each case: elabIR
# answers on the words as on every line, the answer the case expects, and
# the line is left out (or kept) as the case says.
sum_case() {  # name, want (true/false), out (left out: true/false), then the core IR's lines
    local n="$1" want="$2" out="$3"; shift 3
    printf '%s\n' "$@" > "$TMP/s_$n.core"
    if "$C" words "$TMP/s_$n.core" > "$TMP/s_$n.words" 2> /dev/null; then
        full=$(python3 "$ROOT/tools/ncore/elab_parity_full.py" "$TMP/s_$n.core")
        { echo "namespace S_$n"; cat "$TMP/s_$n.words"; echo "def full : C.Elab.IR := $full"
          echo "#eval IO.println s!\"$n {(C.Elab.elabIR ir).isSome} {(C.Elab.elabIR full).isSome} $want\""; echo "end S_$n"; } >> "$TMP/s.lean"
        if grep -q "$(python3 -c 'print("0x1" + b"unused"[::-1].hex())')" "$TMP/s_$n.words"; then o=false; else o=true; fi
        [ "$o" = "$out" ] && ok "sum case $n: the line is $( [ "$out" = true ] && echo left out || echo kept )" \
            || bad "sum case $n: the line is $( [ "$out" = true ] && echo left out || echo kept )"
    else bad "nurl-cert words reads the sum case $n"; fi
}
echo "import C.Elab" > "$TMP/s.lean"
sum_case top_unused true true "${MAIN[@]}" "sum${T}unused${T}0"
sum_case top_before_main true true "sum${T}unused${T}0" "${MAIN[@]}"
sum_case in_main_stmt false false "${MAIN[0]}" "sum unused 0" "ret c" "endfn"
sum_case in_main_header false false "${MAIN[0]}" "sum${T}unused${T}0" "ret c" "endfn"
have=$(cd "$ROOT/formal" && lake env lean "$TMP/s.lean" 2>&1); lrc=$?
nl=$(printf '%s\n' "$have" | awk 'NF == 4 && $2 == $3 && $3 == $4' | wc -l)
if [ "$lrc" = 0 ] && [ "$nl" = 4 ] && [ "$(printf '%s\n' "$have" | wc -l)" = 4 ]; then
    ok "elabIR answers on the words of each sum case as on its every line (4 cases)"
else bad "elabIR answers on the words of each sum case as on its every line (lean rc $lrc)"; printf '%s\n' "$have" | head -20 | sed 's/^/        /'; fi

echo "== 3. the fast profile"
"$C" certify "$P/prog.nu" "${CA[@]}" --profile fast --out "$P/fast.cert" > "$TMP/f.out" 2>&1
if grep -q "M.safe validated" "$TMP/f.out" && grep -q "native_decide" "$P/fast.cert/manifest.json" \
    && grep -q '"validated": [1-9]' "$P/fast.cert/manifest.json" && ! grep -q '"status": "proved"' "$P/fast.cert/manifest.json" \
    && "$C" verify "$P/fast.cert" --formal "$ROOT/formal" > /dev/null 2>&1; then ok "fast: validated (claims and coverage), its axiom listed, verifies"
else bad "fast: validated, its axiom listed, verifies"; cat "$TMP/f.out"; fi

echo "== 3b. coverage, function by function (AGORA-1015)"
# Two functions the translation does not cover (a raw pointer parameter),
# one it does, and main: each its own status; the program refused with the
# first one's reason, exactly as before.
mkdir -p "$TMP/cov"
cat > "$TMP/cov/two_gaps.nu" <<'EOF3'
@ peek_a * u p → i { ^ 0 }

@ add i a i b → i { ^ + a b }

@ peek_b * u p → i { ^ 1 }

@ main → i { ^ ( add 1 2 ) }
EOF3
"$C" certify "$TMP/cov/two_gaps.nu" "${CA[@]}" --out "$TMP/cov/two_gaps.cert" > "$TMP/cov.out" 2>&1; crc=$?
"$C" translate "$TMP/cov/two_gaps.cert/Program.core" > /dev/null 2> "$TMP/cov.tr"
if [ "$crc" = 2 ] && python3 - "$TMP/cov/two_gaps.cert/manifest.json" "$(cat "$TMP/cov.tr")" <<'EOF3'
import json, sys
m = json.load(open(sys.argv[1]))
st = {f["name"]: (f["status"], f["reason"]) for f in m["coverage"]["functions"]}
first = sys.argv[2].removeprefix("unsupported: ")
ok = (st["peek_a"] == ("unsupported", "type %u8*") and st["peek_b"] == ("unsupported", "type %u8*")
      and st["add"][0] == "open" and st["main"][0] == "open"
      and m["program"]["verdict"] == "unsupported" and m["program"]["reason"] == first == st["peek_a"][1]
      and m["coverage"]["unsupported"] == 2 and m["coverage"]["open"] == 2
      and all(c["status"] != "proved" for c in m["claims"]))
sys.exit(0 if ok else 1)
EOF3
then ok "each function its own status; the program refused with the first one's reason, as translate says"
else bad "each function its own status"; cat "$TMP/cov.out"; cat "$TMP/cov/two_gaps.cert/manifest.json" | head -80; fi
"$C" coverage "$TMP/cov" > "$TMP/cov.md" 2>&1
if grep -q '^| 1 | 0 | 0 | 1 | 0 |$' "$TMP/cov.md" && grep -q '^| by count (4) | 0 (0.0 %) | 0 (0.0 %) | 0 (0.0 %) | 2 (50.0 %) | 2 (50.0 %) | 0 (0.0 %) |$' "$TMP/cov.md" \
    && grep -q '^| 2 | [0-9]* | `type %u8\*` | `two_gaps.cert peek_a` |$' "$TMP/cov.md"; then
    ok "coverage: programs by verdict, functions by status, one row per reason family"
else bad "coverage: the table"; cat "$TMP/cov.md"; fi
# A program refused before any function is translated (no main): none of
# its functions is `open` ("translated"); each is unsupported, with the
# program's reason.
mkdir -p "$TMP/nomain"
printf '@ add i a i b → i { ^ + a b }\n\n@ twice i a → i { ^ ( add a a ) }\n' > "$TMP/nomain/lib.nu"
"$C" certify "$TMP/nomain/lib.nu" "${CA[@]}" --out "$TMP/nomain/lib.cert" > /dev/null 2>&1
if python3 - "$TMP/nomain/lib.cert/manifest.json" <<'EOF3'
import json, sys
m = json.load(open(sys.argv[1]))
fs = m["coverage"]["functions"]
ok = (m["program"]["verdict"] == "unsupported" and m["program"]["reason"] == "no main" and len(fs) == 2
      and all(f["status"] == "unsupported" and f["reason"].startswith("not translated: ") and f["reason"].endswith("no main")
              for f in fs)
      and m["coverage"].get("unsupported") == 2 and "open" not in m["coverage"])
sys.exit(0 if ok else 1)
EOF3
then ok "a program refused before its functions are translated: each unsupported, none open"
else bad "a program refused before its functions are translated"; head -c 1500 "$TMP/nomain/lib.cert/manifest.json"; fi

echo "== 4. every manifest against docs/dev/certificate.schema.json"
if python3 -c "import jsonschema" 2> /dev/null; then
    if python3 - "$ROOT/docs/dev/certificate.schema.json" "$TMP"/progs/*/*.cert/manifest.json "$B/manifest.json" "$E/manifest.json" "$P/fast.cert/manifest.json" "$TMP/cov/two_gaps.cert/manifest.json" <<'EOF2'
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
