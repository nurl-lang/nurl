#!/usr/bin/env bash
# packages/mlp/tests/oracle.sh — the sklearn MLPRegressor oracle.
#
# Generates one synthetic tabular dataset (a noisy 2-D manifold in 6-D +
# injected outliers), trains an autoencoder on the normal points with BOTH
# stacks — mlp (pure NURL) and sklearn MLPRegressor — using the same
# architecture and recipe, then checks that:
#   1. both reconstruct normal data well (MSE within 5× — both sit at
#      the injected noise floor, so small recipe differences show as a
#      constant factor),
#   2. both discriminate the same injected outliers with the p95-threshold
#      rule (≥ 90 % label agreement on the outlier set).
# Skips (exit 0) when the reference venv with sklearn is missing.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PY="$HOME/dev/python-scripts-runner/venv/bin/python"
export NURL_STDLIB="$REPO"

if [ ! -x "$PY" ] || ! "$PY" -c 'import sklearn' 2>/dev/null; then
    echo "[mlp-oracle] SKIP — no sklearn venv"; exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0

# ── 1. one dataset for both stacks ───────────────────────────────────
"$PY" - "$TMP" <<'PYEOF'
import sys, numpy as np
tmp = sys.argv[1]
rng = np.random.default_rng(42)
n = 1200
# 2-D latent → 6-D observed, mild noise
t = rng.uniform(-1, 1, (n, 2))
X = np.column_stack([
    t[:,0], t[:,1], t[:,0]*t[:,1], np.sin(2*t[:,0]),
    t[:,0]+t[:,1], t[:,0]-0.5*t[:,1],
]) + rng.normal(0, 0.02, (n, 6))
# 60 outliers: uniform noise across the box, clearly off-manifold
n_out = 60
O = rng.uniform(-2, 2, (n_out, 6))
X.astype("<f8").tofile(f"{tmp}/train.f64")
O.astype("<f8").tofile(f"{tmp}/outliers.f64")
PYEOF

# ── 2. sklearn side ──────────────────────────────────────────────────
"$PY" - "$TMP" > "$TMP/sk.out" <<'PYEOF'
import sys, numpy as np
from sklearn.neural_network import MLPRegressor
from sklearn.preprocessing import MinMaxScaler
tmp = sys.argv[1]
X = np.fromfile(f"{tmp}/train.f64", dtype="<f8").reshape(-1, 6)
O = np.fromfile(f"{tmp}/outliers.f64", dtype="<f8").reshape(-1, 6)
sc = MinMaxScaler().fit(X)
Xs, Os = sc.transform(X), sc.transform(O)
ae = MLPRegressor(hidden_layer_sizes=(64,32,64), activation='relu',
                  solver='adam', max_iter=500, random_state=42,
                  early_stopping=True, validation_fraction=0.1,
                  n_iter_no_change=10)
ae.fit(Xs, Xs)
mse = np.mean((ae.predict(Xs)-Xs)**2, axis=1)
thr = np.percentile(mse, 95)
omse = np.mean((ae.predict(Os)-Os)**2, axis=1)
flags = (omse > thr).astype(int)
print(f"train_mse {mse.mean():.8f}")
print(f"threshold {thr:.8f}")
print(f"outliers_flagged {flags.sum()} / {len(flags)}")
print("flags " + "".join(map(str, flags)))
PYEOF
cat "$TMP/sk.out"

# ── 3. NURL side (same arch, recipe, and threshold rule) ─────────────
cat > "$TMP/nurl_ae.nu" <<'NUEOF'
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/sort.nu`
$ `src/mlp.nu`

// Raw little-endian f64 file → flat ( Vec f ); rows = len / d.
@ load_f64 s path i d *u nrow → ( Vec f ) {
    : ( Vec f ) out ( vec_new [f] )
    ?? ( read_file_bytes path ) {
        T bts → {
            : i nv / ( vec_len [u] bts ) 8
            : ~ i k 0
            ~ < k nv {
                : i bits ?? ( bytes_read_u64_le bts * k 8 ) { T x → # i x F → 0 }
                ( vec_push [f] out ( bits_to_f64 bits ) )
                = k + k 1
            }
            ( vec_free [u] bts )
        }
        F _ → {}
    }
    ( nurl_poke nrow 0 / ( vec_len [f] out ) d )
    ^ out
}

@ row_mse Mlp m ( Vec f ) X i d i r → f {
    : ( Vec f ) x ( vec_new [f] )
    : ~ i k 0
    ~ < k d { ( vec_push [f] x ( _mlp_fget X + * r d k ) ) = k + k 1 }
    : ( Vec f ) y ( mlp_predict m x )
    : ~ f se 0.0
    = k 0
    ~ < k d {
        : f e - ( _mlp_fget y k ) ( _mlp_fget x k )
        = se + se * e e
        = k + k 1
    }
    ( vec_free [f] x ) ( vec_free [f] y )
    ^ / se # f d
}

@ main → i {
    : i argc ( nurl_argv_count )
    ? < argc 3 { ( nurl_print `usage: nurl_ae train.f64 outliers.f64\n` ) ^ 1 } {}
    : *u nc1 ( nurl_alloc 8 )
    : *u nc2 ( nurl_alloc 8 )
    : ( Vec f ) X ( load_f64 ( nurl_argv_get 1 ) 6 nc1 )
    : ( Vec f ) O ( load_f64 ( nurl_argv_get 2 ) 6 nc2 )
    : i n ( nurl_peek nc1 0 )
    : i no ( nurl_peek nc2 0 )
    : i d 6
    // MinMax fit on train, apply to both (the sklearn recipe)
    : MinMax mm ( minmax_fit X n d )
    ( minmax_apply mm X n )
    ( minmax_apply mm O no )
    : ( Vec i ) sz ( vec_new [i] )
    ( vec_push [i] sz d ) ( vec_push [i] sz 64 ) ( vec_push [i] sz 32 )
    ( vec_push [i] sz 64 ) ( vec_push [i] sz d )
    : ~ MlpCfg cfg ( mlp_cfg_default )
    : MlpFit fit ( mlp_fit sz X n d X d cfg 3 )
    : Mlp ae . fit model
    // per-row train MSE → p95 threshold (nearest-rank)
    : ( Vec f ) mses ( vec_new [f] )
    : ~ i r 0
    : ~ f tot 0.0
    ~ < r n {
        : f e ( row_mse ae X d r )
        ( vec_push [f] mses e )
        = tot + tot e
        = r + r 1
    }
    ( sort_by [f] mses \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    : i p95i # i * 0.95 # f n
    : f thr ( _mlp_fget mses p95i )
    ( nurl_print `train_mse ` ) ( nurl_print ( nurl_str_float / tot # f n ) ) ( nurl_print `\n` )
    ( nurl_print `threshold ` ) ( nurl_print ( nurl_str_float thr ) ) ( nurl_print `\n` )
    : ~ i flagged 0
    : String fl ( string_new )
    = r 0
    ~ < r no {
        : f e ( row_mse ae O d r )
        ? > e thr { = flagged + flagged 1 ( string_push_str fl `1` ) } { ( string_push_str fl `0` ) }
        = r + r 1
    }
    ( nurl_print `outliers_flagged ` ) ( nurl_print_int flagged )
    ( nurl_print ` / ` ) ( nurl_print_int no ) ( nurl_print `\n` )
    ( nurl_print `flags ` ) ( nurl_print ( string_data fl ) ) ( nurl_print `\n` )
    ( string_free fl )
    ( vec_free [f] mses ) ( vec_free [i] sz )
    ( mlp_free ae ) ( minmax_free mm )
    ( vec_free [f] X ) ( vec_free [f] O )
    ( nurl_free nc1 ) ( nurl_free nc2 )
    ^ 0
}
NUEOF
( cd "$HERE" && "$REPO/nurl.sh" "$TMP/nurl_ae.nu" "$TMP/nurl_ae" >/dev/null 2>&1 ) \
    || { echo "[mlp-oracle] FAIL build"; ( cd "$HERE" && "$REPO/nurl.sh" "$TMP/nurl_ae.nu" "$TMP/nurl_ae" 2>&1 | tail -5 ); exit 1; }
"$TMP/nurl_ae" "$TMP/train.f64" "$TMP/outliers.f64" > "$TMP/nu.out" || { echo "[mlp-oracle] FAIL run"; exit 1; }
cat "$TMP/nu.out"

# ── 4. compare ───────────────────────────────────────────────────────
python3 - "$TMP" <<'PYEOF' || fail=1
import sys
tmp = sys.argv[1]
def parse(p):
    d = {}
    for line in open(p):
        k, _, v = line.partition(' ')
        d[k.strip()] = v.strip()
    return d
sk, nu = parse(f"{tmp}/sk.out"), parse(f"{tmp}/nu.out")
sk_mse, nu_mse = float(sk['train_mse']), float(nu['train_mse'])
ratio = max(sk_mse, nu_mse) / max(min(sk_mse, nu_mse), 1e-12)
sk_fl, nu_fl = sk['flags'], nu['flags']
agree = sum(a == b for a, b in zip(sk_fl, nu_fl)) / len(sk_fl)
sk_n = sk_fl.count('1'); nu_n = nu_fl.count('1')
print(f"[mlp-oracle] mse ratio {ratio:.2f}x  flag agreement {agree:.0%}  (sk {sk_n}, nurl {nu_n} of {len(sk_fl)})")
ok = ratio < 5.0 and agree >= 0.9
print("[mlp-oracle]", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PYEOF

exit $fail
