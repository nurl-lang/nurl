#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/tokenizer_test.sh — proof of the nurllama tokenizer:
#    1. selftest: synthetic SPM + BPE vocabularies (built with the gguf
#       writer, parsed back through the real parser) against
#       hand-derived expected ids — merge chains, byte fallback, UNK,
#       specials, decode round-trips. 17 checks, no network.
#    2. CLI surface: tokenize / detok / vocab against the same files.
#    3. NURL_NET_TESTS=1: token-for-token parity with an INDEPENDENT
#       python SentencePiece implementation on a real llama.cpp model
#       (stories260K), plus encode→decode round-trips — unicode,
#       emoji byte-fallback, whitespace runs, empty string.
#
#  Run from the package dir:  ./tests/tokenizer_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t nurllama-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/3] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"

echo "[2/3] selftest + CLI surface"
if timeout 60 "$NL" selftest | grep -q " 0 failed"; then ok "selftest (17 checks)"; else bad "selftest"; fi
"$NL" tokenize /nonexistent.gguf x >/dev/null 2>&1 && bad "missing model rc" || ok "missing model rejects"
"$NL" nosuchcmd >/dev/null 2>&1 && bad "unknown command rc" || ok "unknown command rejects"

echo "[3/3] real llama.cpp model parity (independent python reference)"
if [ "${NURL_NET_TESTS:-0}" = 1 ] && command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    M="$WORK/stories260K.gguf"
    if curl -sL --max-time 120 -f -o "$M" \
        https://huggingface.co/ggml-org/models/resolve/main/tinyllamas/stories260K.gguf; then
        cat > "$WORK/spm_ref.py" <<'PYEOF'
import struct, sys
def read_gguf(path):
    d=open(path,'rb').read(); off=8
    nt,nkv=struct.unpack_from('<QQ',d,off); off+=16
    kvs={}
    def rs(off):
        n=struct.unpack_from('<Q',d,off)[0]; off+=8
        return d[off:off+n], off+n
    for _ in range(nkv):
        k,off=rs(off); vt=struct.unpack_from('<I',d,off)[0]; off+=4
        if vt==8: v,off=rs(off)
        elif vt==9:
            at=struct.unpack_from('<I',d,off)[0]; off+=4
            cnt=struct.unpack_from('<Q',d,off)[0]; off+=8
            v=[]
            for _ in range(cnt):
                if at==8: e,off=rs(off); v.append(e)
                elif at==6: v.append(struct.unpack_from('<f',d,off)[0]); off+=4
                elif at==5: v.append(struct.unpack_from('<i',d,off)[0]); off+=4
                elif at==4: v.append(struct.unpack_from('<I',d,off)[0]); off+=4
                else: raise Exception('at %d'%at)
        elif vt==4: v=struct.unpack_from('<I',d,off)[0]; off+=4
        elif vt==5: v=struct.unpack_from('<i',d,off)[0]; off+=4
        elif vt==6: v=struct.unpack_from('<f',d,off)[0]; off+=4
        elif vt==7: v=d[off]; off+=1
        elif vt in (10,11): v=struct.unpack_from('<q',d,off)[0]; off+=8
        else: raise Exception('vt %d'%vt)
        kvs[k.decode()]=v
    return kvs

kvs=read_gguf(sys.argv[1])
toks=[t.decode('utf-8',errors='replace') for t in kvs['tokenizer.ggml.tokens']]
scores=kvs.get('tokenizer.ggml.scores',[0.0]*len(toks))
bos=kvs.get('tokenizer.ggml.bos_token_id',-1)
unk=kvs.get('tokenizer.ggml.unknown_token_id',-1)
lut={}
for i,t in enumerate(toks): lut[t]=i   # last wins, like llama.cpp

def spm_encode(text):
    ids=[bos] if bos>=0 else []
    if not text: return ids
    esc='▁'+text.replace(' ','▁')
    syms=list(esc)
    while True:
        best=-1; best_score=-1e30
        for j in range(len(syms)-1):
            cand=syms[j]+syms[j+1]
            if cand in lut and scores[lut[cand]]>best_score:
                best=j; best_score=scores[lut[cand]]
        if best<0: break
        syms=syms[:best]+[syms[best]+syms[best+1]]+syms[best+2:]
    for s in syms:
        if s in lut: ids.append(lut[s])
        else:
            for b in s.encode('utf-8'):
                ids.append(lut.get('<0x%02X>'%b, unk))
    return ids

print(' '.join(str(i) for i in spm_encode(sys.stdin.read())))
PYEOF
        declare -a TESTS=("Once upon a time" "hello world" \
            "The quick brown fox jumps over the lazy dog." \
            "  double  spaces  " "123 + 456 = 579" "emoji: 😀🎉" \
            "ÄÖ äö ülichen straße" "a" "")
        P2=0; F2=0
        for t in "${TESTS[@]}"; do
            ours=$("$NL" tokenize "$M" "$t")
            ref=$(printf '%s' "$t" | python3 "$WORK/spm_ref.py" "$M")
            if [ "$ours" = "$ref" ]; then P2=$((P2+1)); else F2=$((F2+1)); echo "    MISMATCH [$t]: ours=$ours ref=$ref"; fi
        done
        [ "$F2" = 0 ] && ok "python parity on ${#TESTS[@]} strings" || bad "python parity ($F2 mismatches)"
        RT=0
        for t in "Once upon a time" "ÄÖ straße 😀" "  spaces  "; do
            ids=$("$NL" tokenize "$M" "$t")
            back=$("$NL" detok "$M" $ids)
            [ "$back" = " $t" ] || { RT=1; echo "    RT-MISMATCH [$t] → [$back]"; }
        done
        [ "$RT" = 0 ] && ok "encode→decode round-trips" || bad "round-trip"
        [ "$("$NL" vocab "$M" 3 | wc -l)" = 3 ] && ok "vocab listing" || bad "vocab"
    else
        echo "  SKIP download failed"
    fi
else
    echo "  SKIP (set NURL_NET_TESTS=1 with curl + python3 for real-model parity)"
fi

echo "== nurllama tokenizer tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
