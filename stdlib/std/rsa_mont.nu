// stdlib/std/rsa_mont.nu — fixed-width Montgomery arithmetic for RSA.
//
// The private-key operation of std/rsa.nu, and its public one. Before this
// file, RSA ran on std/bigint.nu: 16-bit limbs, and a full long division
// for every modular multiply — one 2048-bit signature took 450 ms on the
// tls-bench CI runner, against 0.66 ms for aws-lc, so a TLS server with an
// RSA certificate completed no handshakes under load.
//
// Here a residue is n little-endian 64-bit limbs (i64 bit patterns), the
// width fixed by the modulus and never trimmed. Multiplication is
// Montgomery FIPS on nurl_mac — product scanning with the reduction
// interleaved, one widening multiply and one add-with-carry chain into a
// register accumulator per limb product, and a dedicated squaring — or,
// on a CPU with ADX, rows of nurl_mac_row with two carry chains in
// flight — and on one with AVX-512 IFMA the two halves of an RSA-2048
// CRT signature run at once in radix 2^52 (below, docs/adr/0002-ifma-
// rsa.md); exponentiation is a fixed 4-bit window whose table entry is
// picked by scanning all sixteen under a mask. For a given
// modulus size every operation runs the same instruction sequence whatever
// the key and the message: no branch and no memory index depends on a
// secret.
//
// The private operation uses the Chinese remainder theorem when the key
// carries its factors: two exponentiations at half the width, a quarter of
// the work each, recombined with Garner's formula. Two hardenings ride
// along:
//   * exponent blinding — each half exponentiates by d_p + r·(p − 1) for a
//     fresh 64-bit r, the same residue, so the exponent bits the hardware
//     sees change on every signature;
//   * a fault check — the signature is verified (s^e against the message,
//     mod p and mod q) before it is released, so a computation fault in one
//     half cannot leak a factor (the Bellcore attack).
//
// What depends on the key alone — the Montgomery contexts of p and q (or
// of n), the exponents and q^-1 as limbs — is derived ONCE, into an
// RsaKey, and never written after; a TLS listener builds one at load and
// every handshake on every worker signs with it.
//
//   ( _rsa_key_plain ( Vec u ) n ( Vec u ) e ( Vec u ) d )  → RsaKey
//        a key without its factors: one full-width exponentiation
//   ( _rsa_key_crt n e p q dp dq qinv )                    → ?RsaKey
//        the CRT form; F unless p and q are odd and every field is there
//   ( _rsa_sign_raw RsaKey k ( Vec u ) m ) → ( Vec u )
//        m^d mod n, k bytes big-endian; [] if the fault check fails
//        (or the key's limbs were changed through its fields)
//   ( _rsa_public ( Vec u ) n ( Vec u ) e ( Vec u ) s i k ) → ( Vec u )
//        s^e mod n, k bytes big-endian (e is public: variable time)

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/random.nu`

// ── context ─────────────────────────────────────────────────────────
//
// One modulus: its limbs, −m^-1 mod 2^64, R^2 mod m (R = 2^(64n)) and 1 in
// Montgomery form. Built once per modulus and never written after: a
// prepared key (RsaKey, below) holds its two and every thread signing
// with it reads them at once.
//
// A 1024-bit modulus (n = 16, the factors of an RSA-2048 key) also
// carries its radix-2^52 form for the IFMA tier (below): m52, the
// modulus as 20 limbs of 52 bits, and rr52, R'^2 mod m with R' = 2^1040,
// in the same limbs. Empty for any other width.
//
// The limb helpers below (_rm_mul_d, _rm_sqr_d, _rm_enter, _rm_leave,
// _rm_pow_ct, _rm_pow_pub, _rm_pow2_ct) are `raw` (spec §3.3e): each
// requires its context and scratch to be the ones _rm_ctx / _rm_tmp
// built (their vectors unshrunk: __rm_ctx_ok), and its residues to hold
// the context's n limbs, and indexes
// them through `vec_data` with no length check — a check per Montgomery
// operation would be paid thousands of times a signature. The three
// structs are sealed (`raw :`) for the same reason: a literal could pair
// an n with shorter limb vectors. The safe surface — _rsa_key_plain,
// _rsa_key_crt, _rsa_sign_raw, _rsa_public, and std/rsa.nu over them —
// builds every context and residue itself, and _rsa_sign_raw checks a
// key's limb counts against its contexts (__rm_key_ok) before it signs.
raw : RsaMont { i n ( Vec i ) m i n0 ( Vec i ) r2 ( Vec i ) one ( Vec i ) m52 ( Vec i ) rr52 }

// The scratch a multiply works in — accumulator t, 2n + 1 limbs (the row
// form's product); difference d, n limbs — one per operation, so a shared
// RsaMont stays read-only.
raw : RsaTmp { ( Vec i ) t ( Vec i ) d }

@ _rm_tmp RsaMont c → RsaTmp { ^ @ RsaTmp { ( __rm_zeros + * 2 . c n 1 ) ( __rm_zeros . c n ) } }

@ __rm_get ( Vec u ) v i k → i { ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 } }

// n limbs, zeroed.
@ __rm_zeros i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] ? > n 0 n 1 )
    : b _l ( vec_set_len [i] v n )
    : *i p ( vec_data [i] v )
    : ~ i k 0
    ~ < k n { = . p k 0 = k + k 1 }
    ^ v
}

@ __rm_copy_d ( Vec i ) dst ( Vec i ) a i n → v {
    : *i op ( vec_data [i] dst )
    : *i ap ( vec_data [i] a )
    : ~ i k 0
    ~ < k n { = . op k . ap k = k + k 1 }
}

// Big-endian bytes → exactly n limbs, little-endian. Bytes beyond what n
// limbs hold are dropped (callers size n to fit).
@ __rm_from_be ( Vec u ) b i n → ( Vec i ) {
    : ( Vec i ) v ( __rm_zeros n )
    : *i p ( vec_data [i] v )
    : i len ( vec_len [u] b )
    : ~ i k 0
    ~ < k len {
        // byte k from the END is bit position 8k
        : i pos k
        : i limb >> pos 3
        ? < limb n {
            : i sh * & pos 7 8
            = . p limb | . p limb # i << # u64 ( __rm_get b - - len 1 k ) # u64 sh
        } {}
        = k + k 1
    }
    ^ v
}

// n limbs → k big-endian bytes (the low k bytes of the value).
@ __rm_to_be ( Vec i ) v i n i k → ( Vec u ) {
    : ( Vec u ) out ( vec_zeroed [u] k )
    : *u op ( vec_data [u] out )
    : *i p ( vec_data [i] v )
    : ~ i j 0
    ~ < j k {
        : i limb >> j 3
        ? < limb n {
            : u64 w # u64 . p limb
            = . op - - k 1 j # u & >> w # u64 * & j 7 8 255
        } {}
        = j + j 1
    }
    ^ out
}

// Significant bytes of a big-endian magnitude (leading zeros skipped).
@ __rm_sig_bytes ( Vec u ) b → i {
    : i len ( vec_len [u] b )
    : ~ i k 0
    ~ & < k len == ( __rm_get b k ) 0 { = k + k 1 }
    ^ - len k
}

@ __rm_limbs_for ( Vec u ) b → i {
    : i nb ( __rm_sig_bytes b )
    : i n / + nb 7 8
    ^ ? > n 0 n 1
}

// ── Montgomery multiply and square (FIPS) ───────────────────────────
//
// dst = a·b·R^-1 mod m (and a²·R^-1) for a·b < m·R (true whenever a < R
// and b < m, or both < m). `dst` may alias a or b: the result is
// assembled in the context's d / t and written last.
//
// Finely Integrated Product Scanning (Koç, Acar, Kaliski): the result is
// produced a COLUMN at a time — every a[i]·b[k−i] and every reduction
// product q[i]·m[k−i] of column k summed into a three-word accumulator
// that lives in registers, then the column's low word either becomes the
// next reduction digit q[k] (k < n) or the result limb r[k−n]. A product
// is one widening multiply and one add-with-carry chain into the
// accumulator; the row-wise form this replaced (FIOS) carried two chains
// per product and loaded and stored its n-limb accumulator on every row,
// about twice the instructions a product. Squaring sums each cross
// product a[i]·a[j] (i < j) once and doubles the column — n(n+1)/2
// products for the square instead of n², and four in five Montgomery
// operations of an exponentiation are squarings.
//
// The column sums stay below 2·n·2^128 < 2^192 for every n an RSA key
// has, so three words never overflow; every loop bound depends on n and
// the column index alone, so the instruction sequence is the same for
// every operand.
//
// RSA-2048's CRT halves are 16 limbs, and for those the multiply and the
// square are generated straight-line code (tools/gen_rsa_kernels.py, the
// block between the markers below): no index arithmetic, every column's
// products written out, the a·b products and the q·m products summed in
// two accumulators so their carry chains run side by side. Measured on
// an i7-11850H: square 1 440 → 1 100 cycles, multiply 1 430 → 1 320;
// an RSA-2048 signature 0.98 → 0.79 ms. Every other width runs the loops
// (__rm_mul_gen / __rm_sqr_gen), which compiler/tests/rsa_mont_kernels
// holds both to std/bigint.
//
// On the ADX tier (BMI2 + ADX: Broadwell and later Intel, every Zen) the
// multiply and the square take the row form instead — separated operand
// scanning on nurl_mac_row: t = a·b (or a²: the cross products once, then
// doubled with the diagonal added) by rows of n products, then n rows of
// reduction. A row is mulx, adcx and adox a product, the low halves
// carried through CF and the high halves through OF at once; FIPS's
// column sums have no second chain to give it. Measured on an
// i7-11850H, 16 limbs: square 245 → 203 ns, multiply 322 → 211 ns; 32
// limbs 1.65× both; an RSA-2048 signature 0.79 → ~0.62 ms. Without ADX
// the same rows are a loop of single-chain multiply-adds, and there
// FIPS is the faster form (16 limbs: square 245 against 361 ns), so
// FIPS stays the kernel of every other CPU and target — chosen per
// call on the runtime's answer, both forms held to the same golden by
// crypto_tier_ir.sh. What remained to aws-lc on this CPU was not
// scalar: aws-lc signs with AVX-512 IFMA (rsaz_amm52x20_x2_ifma256, both
// CRT halves in one 52-bit-radix vector multiply) — and so, on such a
// CPU, does __rm_pow2_52 below.

// (z0, z1, z2) += x·y
inline @ __rm_acc inout u64 z0 inout u64 z1 inout u64 z2 u64 x u64 y → v {
    : u64 lo ( nurl_mac_lo x y z0 0 )
    : u64 hi ( nurl_mac_hi x y z0 0 )
    = z0 lo
    : u64 s ( nurl_addc_lo z1 hi 0 )
    = z2 + z2 ( nurl_addc_hi z1 hi 0 )
    = z1 s
}

// (z0, z1, z2) += (x0, x1, x2): two column sums kept apart, so their
// carry chains run side by side, joined once per column.
inline @ __rm_add3 inout u64 z0 inout u64 z1 inout u64 z2 u64 x0 u64 x1 u64 x2 → v {
    : u64 s0 ( nurl_addc_lo z0 x0 0 )
    : u64 c0 ( nurl_addc_hi z0 x0 0 )
    : u64 s1 ( nurl_addc_lo z1 x1 c0 )
    : u64 c1 ( nurl_addc_hi z1 x1 c0 )
    = z2 + + z2 x2 c1
    = z0 s0
    = z1 s1
}

// (z0, z1, z2) += 2·(w0, w1, w2)
inline @ __rm_acc2 inout u64 z0 inout u64 z1 inout u64 z2 u64 w0 u64 w1 u64 w2 → v {
    : u64 d0 << w0 1
    : u64 d1 | << w1 1 >> w0 63
    : u64 d2 | << w2 1 >> w1 63
    : u64 s0 ( nurl_addc_lo z0 d0 0 )
    : u64 c0 ( nurl_addc_hi z0 d0 0 )
    : u64 s1 ( nurl_addc_lo z1 d1 c0 )
    : u64 c1 ( nurl_addc_hi z1 d1 c0 )
    = z2 + + z2 d2 c1
    = z0 s0
    = z1 s1
}

// The reduction digit of column k (k < n): q[k] = z0·n0, after which
// z0 + q[k]·m[0] ≡ 0 (mod 2^64); then the column shifts out.
inline @ __rm_qdigit inout u64 z0 inout u64 z1 inout u64 z2 u64 n0 u64 m0 * i qp i k → v {
    : u64 q * z0 n0
    = . qp k # i q
    ( __rm_acc z0 z1 z2 q m0 )
    = z0 z1
    = z1 z2
    = z2 0
}

// r (n limbs, with `top` the bit above them) is below 2m: subtract m once
// and keep whichever is in range — by mask — into dst.
inline @ __rm_final i n * i rp * i mp * i dp u64 top ( Vec i ) dst → v {
    : ~ u64 bb 0
    : ~ i j 0
    ~ < j n {
        : u64 x # u64 . rp j
        : u64 y # u64 . mp j
        = . dp j # i ( nurl_subb_lo x y bb )
        = bb ( nurl_subb_hi x y bb )
        = j + j 1
    }
    : i topb - # i top # i bb
    : i mask ? < topb 0 0 - 0 1
    : i imask ^^ mask - 0 1
    : *i op ( vec_data [i] dst )
    = j 0
    ~ < j n { = . op j | & mask . dp j & imask . rp j = j + j 1 }
}

// requires: c from _rm_ctx, w from _rm_tmp c, and dst, a, b each . c n
// limbs.
raw @ _rm_mul_d RsaMont c RsaTmp w ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : i n . c n
    : *i qp ( vec_data [i] . w t )  // q digits, then the result
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i mp ( vec_data [i] . c m )
    : u64 n0 # u64 . c n0
    ? ( nurl_cpu_has_adx ) {
        : u64 cy ( __rm_mul_rows n ap bp mp n0 qp )
        ( __rm_final n # *i + # i qp * 8 n mp ( vec_data [i] . w d ) cy dst )
        ^ v
    } {}
    : ~ u64 top 0
    ? == n 16 { = top ( __rm_mul16 ap bp mp n0 qp ) } { = top ( __rm_mul_gen n ap bp mp n0 qp ) }
    ( __rm_final n qp mp ( vec_data [i] . w d ) top dst )
}

// The row form (SOS, the ADX tier): t = a·b by n rows of nurl_mac_row,
// then n rows of reduction; tp holds 2n + 1 limbs, the result in
// tp[n … 2n) with the bit above it returned. Row k adds a·b[k] at k and
// writes its carry word to k + n, a limb no earlier row reached.
unsafe @ __rm_mul_rows i n * i ap * i bp * i mp u64 n0 * i tp → u64 {
    : ~ i k 0
    ~ < k n { = . tp k 0 = k + k 1 }
    = k 0
    ~ < k n {
        = . tp + k n # i ( nurl_mac_row # *i + # i tp * 8 k bp n # u64 . ap k )
        = k + k 1
    }
    ^ ( __rm_redc n mp n0 tp )
}

unsafe @ __rm_sqr_rows i n * i ap * i mp u64 n0 * i tp → u64 {
    // the cross products a[i]·a[j], i < j, once: row i adds a[i+1 … n)·a[i]
    // at 2i + 1
    : ~ i k 0
    ~ <= k n { = . tp k 0 = k + k 1 }
    = . tp - * 2 n 1 0
    = k 0
    ~ < k - n 1 {
        = . tp + k n # i ( nurl_mac_row # *i + # i tp * 8 + * 2 k 1 # *i + # i ap * 8 + k 1 - - n k 1 # u64 . ap k )
        = k + k 1
    }
    // doubled, plus the squares on the diagonal
    : ~ u64 cc 0
    : ~ u64 hb 0
    = k 0
    ~ < k n {
        : u64 x0 # u64 . tp * 2 k
        : u64 x1 # u64 . tp + * 2 k 1
        : u64 d0 | << x0 1 hb
        : u64 d1 | << x1 1 >> x0 63
        = hb >> x1 63
        : u64 a # u64 . ap k
        : u64 lo ( nurl_mac_lo a a 0 0 )
        : u64 hi ( nurl_mac_hi a a 0 0 )
        = . tp * 2 k # i ( nurl_addc_lo d0 lo cc )
        = cc ( nurl_addc_hi d0 lo cc )
        = . tp + * 2 k 1 # i ( nurl_addc_lo d1 hi cc )
        = cc ( nurl_addc_hi d1 hi cc )
        = k + k 1
    }
    ^ ( __rm_redc n mp n0 tp )
}

// Montgomery reduction of t (2n limbs) by rows: row k clears limb k with
// q = t[k]·n0 and its carry word joins limb k + n, the bit above riding
// to the next row's.
unsafe @ __rm_redc i n * i mp u64 n0 * i tp → u64 {
    : ~ u64 cy 0
    : ~ i k 0
    ~ < k n {
        : u64 q * # u64 . tp k n0
        : u64 c ( nurl_mac_row # *i + # i tp * 8 k mp n q )
        : u64 x # u64 . tp + k n
        = . tp + k n # i ( nurl_addc_lo x c cy )
        = cy ( nurl_addc_hi x c cy )
        = k + k 1
    }
    ^ cy
}

// The n-limb FIPS multiply into qp (q digits, then the result); returns
// the bit above the result. Every width without a kernel of its own, and
// the reference those kernels are held to.
unsafe @ __rm_mul_gen i n * i ap * i bp * i mp u64 n0 * i qp → u64 {
    : u64 m0 # u64 . mp 0
    : ~ u64 z0 0
    : ~ u64 z1 0
    : ~ u64 z2 0
    : ~ i k 0
    ~ < k n {
        : ~ i i 0
        ~ < i k {
            ( __rm_acc z0 z1 z2 # u64 . ap i # u64 . bp - k i )
            ( __rm_acc z0 z1 z2 # u64 . qp i # u64 . mp - k i )
            = i + i 1
        }
        ( __rm_acc z0 z1 z2 # u64 . ap k # u64 . bp 0 )
        ( __rm_qdigit z0 z1 z2 n0 m0 qp k )
        = k + k 1
    }
    // Columns n … 2n−1: the result limbs. The q digits a column reads
    // (index > k − n) are never the slot it writes (k − n): r overwrites
    // q in place.
    ~ < k * 2 n {
        : ~ i i + - k n 1
        ~ < i n {
            ( __rm_acc z0 z1 z2 # u64 . ap i # u64 . bp - k i )
            ( __rm_acc z0 z1 z2 # u64 . qp i # u64 . mp - k i )
            = i + i 1
        }
        = . qp - k n # i z0
        = z0 z1
        = z1 z2
        = z2 0
        = k + k 1
    }
    ^ z0
}

// dst = a²·R^-1 mod m (a < m): _rm_mul_d with b = a, the cross products
// of each column summed once and doubled.
// requires: c from _rm_ctx, w from _rm_tmp c, dst and a each . c n limbs.
raw @ _rm_sqr_d RsaMont c RsaTmp w ( Vec i ) dst ( Vec i ) a → v {
    : i n . c n
    : *i qp ( vec_data [i] . w t )
    : *i ap ( vec_data [i] a )
    : *i mp ( vec_data [i] . c m )
    : u64 n0 # u64 . c n0
    ? ( nurl_cpu_has_adx ) {
        : u64 cy ( __rm_sqr_rows n ap mp n0 qp )
        ( __rm_final n # *i + # i qp * 8 n mp ( vec_data [i] . w d ) cy dst )
        ^ v
    } {}
    : ~ u64 top 0
    ? == n 16 { = top ( __rm_sqr16 ap mp n0 qp ) } { = top ( __rm_sqr_gen n ap mp n0 qp ) }
    ( __rm_final n qp mp ( vec_data [i] . w d ) top dst )
}

unsafe @ __rm_sqr_gen i n * i ap * i mp u64 n0 * i qp → u64 {
    : u64 m0 # u64 . mp 0
    : ~ u64 z0 0
    : ~ u64 z1 0
    : ~ u64 z2 0
    : ~ i k 0
    ~ < k * 2 n {
        // a column's cross products a[i]·a[k−i], i < k − i, once
        : i lo ? < k n 0 + - k n 1
        : ~ u64 w0 0
        : ~ u64 w1 0
        : ~ u64 w2 0
        : ~ i i lo
        ~ < * 2 i k {
            ( __rm_acc w0 w1 w2 # u64 . ap i # u64 . ap - k i )
            = i + i 1
        }
        ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
        // the square on the diagonal
        ? == & k 1 0 {
            : u64 h # u64 . ap >> k 1
            ( __rm_acc z0 z1 z2 h h )
        } {}
        // the reduction products q[i]·m[k−i]
        : i qlo lo
        : i qhi ? < k n k n
        = i qlo
        ~ < i qhi {
            ( __rm_acc z0 z1 z2 # u64 . qp i # u64 . mp - k i )
            = i + i 1
        }
        ? < k n {
            ( __rm_qdigit z0 z1 z2 n0 m0 qp k )
        } {
            = . qp - k n # i z0
            = z0 z1
            = z1 z2
            = z2 0
        }
        = k + k 1
    }
    ^ z0
}

// ── generated by tools/gen_rsa_kernels.py 16 — do not edit by hand ──
// a·b·R^-1 into rp (n = 16 limbs, not yet reduced below m); returns
// the bit above them. Straight-line: tools/gen_rsa_kernels.py.
unsafe @ __rm_mul16 * i ap * i bp * i mp u64 n0 * i rp → u64 {
    : ~ u64 z0 0
    : ~ u64 z1 0
    : ~ u64 z2 0
    : ~ u64 x0 0
    : ~ u64 x1 0
    : ~ u64 x2 0
    : ~ u64 y0 0
    : ~ u64 y1 0
    : ~ u64 y2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 0 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    : u64 q0 * z0 n0
    ( __rm_acc z0 z1 z2 q0 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q1 * z0 n0
    ( __rm_acc z0 z1 z2 q1 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q2 * z0 n0
    ( __rm_acc z0 z1 z2 q2 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q3 * z0 n0
    ( __rm_acc z0 z1 z2 q3 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q4 * z0 n0
    ( __rm_acc z0 z1 z2 q4 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q5 * z0 n0
    ( __rm_acc z0 z1 z2 q5 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q6 * z0 n0
    ( __rm_acc z0 z1 z2 q6 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q7 * z0 n0
    ( __rm_acc z0 z1 z2 q7 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q8 * z0 n0
    ( __rm_acc z0 z1 z2 q8 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q9 * z0 n0
    ( __rm_acc z0 z1 z2 q9 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q10 * z0 n0
    ( __rm_acc z0 z1 z2 q10 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q11 * z0 n0
    ( __rm_acc z0 z1 z2 q11 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q12 * z0 n0
    ( __rm_acc z0 z1 z2 q12 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q13 * z0 n0
    ( __rm_acc z0 z1 z2 q13 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q14 * z0 n0
    ( __rm_acc z0 z1 z2 q14 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 0 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 1 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 0 )
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q15 * z0 n0
    ( __rm_acc z0 z1 z2 q15 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 1 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 2 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 1 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 0 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 2 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 3 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 2 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 2 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 1 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 3 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 4 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 3 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 3 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 2 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 4 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 5 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 4 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 4 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 3 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 5 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 6 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 5 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 5 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 4 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 6 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 7 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 6 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 6 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 5 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 7 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 8 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 7 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 7 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 6 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 8 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 9 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 8 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 8 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 7 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 9 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 10 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 9 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 9 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 8 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 10 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 11 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 10 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 10 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 9 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 11 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 12 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 11 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 11 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 10 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 12 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 13 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 12 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 12 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 11 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 13 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 14 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 13 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 13 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 12 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 14 # u64 . bp 15 )
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 14 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 14 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 13 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_acc x0 x1 x2 # u64 . ap 15 # u64 . bp 15 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 15 )
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 14 # i z0
    = z0 z1 = z1 z2 = z2 0
    = x0 0 = x1 0 = x2 0 = y0 0 = y1 0 = y2 0
    ( __rm_add3 z0 z1 z2 x0 x1 x2 )
    = . rp 15 # i z0
    = z0 z1 = z1 z2 = z2 0
    ^ z0
}

// a²·R^-1 into rp, as __rm_mul16 with each column's cross products
// summed once and doubled.
unsafe @ __rm_sqr16 * i ap * i mp u64 n0 * i rp → u64 {
    : ~ u64 z0 0
    : ~ u64 z1 0
    : ~ u64 z2 0
    : ~ u64 w0 0
    : ~ u64 w1 0
    : ~ u64 w2 0
    : ~ u64 y0 0
    : ~ u64 y1 0
    : ~ u64 y2 0
    ( __rm_acc z0 z1 z2 # u64 . ap 0 # u64 . ap 0 )
    : u64 q0 * z0 n0
    ( __rm_acc z0 z1 z2 q0 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 1 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q1 * z0 n0
    ( __rm_acc z0 z1 z2 q1 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 2 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 1 )
    ( __rm_acc z0 z1 z2 # u64 . ap 1 # u64 . ap 1 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q2 * z0 n0
    ( __rm_acc z0 z1 z2 q2 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 3 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 2 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q3 * z0 n0
    ( __rm_acc z0 z1 z2 q3 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 4 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 3 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 1 )
    ( __rm_acc z0 z1 z2 # u64 . ap 2 # u64 . ap 2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q4 * z0 n0
    ( __rm_acc z0 z1 z2 q4 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 5 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 4 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 3 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q5 * z0 n0
    ( __rm_acc z0 z1 z2 q5 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 6 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 5 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 4 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 1 )
    ( __rm_acc z0 z1 z2 # u64 . ap 3 # u64 . ap 3 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q6 * z0 n0
    ( __rm_acc z0 z1 z2 q6 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 7 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 6 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 5 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 4 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q7 * z0 n0
    ( __rm_acc z0 z1 z2 q7 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 8 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 7 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 6 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 5 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 1 )
    ( __rm_acc z0 z1 z2 # u64 . ap 4 # u64 . ap 4 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q8 * z0 n0
    ( __rm_acc z0 z1 z2 q8 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 9 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 8 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 7 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 6 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 5 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q9 * z0 n0
    ( __rm_acc z0 z1 z2 q9 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 10 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 9 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 8 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 7 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 6 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 1 )
    ( __rm_acc z0 z1 z2 # u64 . ap 5 # u64 . ap 5 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q10 * z0 n0
    ( __rm_acc z0 z1 z2 q10 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 11 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 10 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 9 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 8 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 7 )
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 6 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q11 * z0 n0
    ( __rm_acc z0 z1 z2 q11 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 11 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 10 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 9 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 8 )
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 7 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 1 )
    ( __rm_acc z0 z1 z2 # u64 . ap 6 # u64 . ap 6 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q12 * z0 n0
    ( __rm_acc z0 z1 z2 q12 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 11 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 10 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 9 )
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 8 )
    ( __rm_acc w0 w1 w2 # u64 . ap 6 # u64 . ap 7 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q13 * z0 n0
    ( __rm_acc z0 z1 z2 q13 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 11 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 10 )
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 9 )
    ( __rm_acc w0 w1 w2 # u64 . ap 6 # u64 . ap 8 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 1 )
    ( __rm_acc z0 z1 z2 # u64 . ap 7 # u64 . ap 7 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q14 * z0 n0
    ( __rm_acc z0 z1 z2 q14 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 0 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 11 )
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 10 )
    ( __rm_acc w0 w1 w2 # u64 . ap 6 # u64 . ap 9 )
    ( __rm_acc w0 w1 w2 # u64 . ap 7 # u64 . ap 8 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q0 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 1 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    : u64 q15 * z0 n0
    ( __rm_acc z0 z1 z2 q15 # u64 . mp 0 )
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 1 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 11 )
    ( __rm_acc w0 w1 w2 # u64 . ap 6 # u64 . ap 10 )
    ( __rm_acc w0 w1 w2 # u64 . ap 7 # u64 . ap 9 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q1 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 2 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 1 )
    ( __rm_acc z0 z1 z2 # u64 . ap 8 # u64 . ap 8 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 0 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 2 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 6 # u64 . ap 11 )
    ( __rm_acc w0 w1 w2 # u64 . ap 7 # u64 . ap 10 )
    ( __rm_acc w0 w1 w2 # u64 . ap 8 # u64 . ap 9 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q2 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 3 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 2 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 1 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 3 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 6 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 7 # u64 . ap 11 )
    ( __rm_acc w0 w1 w2 # u64 . ap 8 # u64 . ap 10 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q3 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 4 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 3 )
    ( __rm_acc z0 z1 z2 # u64 . ap 9 # u64 . ap 9 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 2 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 4 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 6 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 7 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 8 # u64 . ap 11 )
    ( __rm_acc w0 w1 w2 # u64 . ap 9 # u64 . ap 10 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q4 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 5 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 4 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 3 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 5 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 6 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 7 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 8 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 9 # u64 . ap 11 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q5 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 6 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 5 )
    ( __rm_acc z0 z1 z2 # u64 . ap 10 # u64 . ap 10 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 4 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 6 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 7 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 8 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 9 # u64 . ap 12 )
    ( __rm_acc w0 w1 w2 # u64 . ap 10 # u64 . ap 11 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q6 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 7 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 6 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 5 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 7 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 8 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 9 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 10 # u64 . ap 12 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q7 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 8 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 7 )
    ( __rm_acc z0 z1 z2 # u64 . ap 11 # u64 . ap 11 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 6 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 8 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 9 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 10 # u64 . ap 13 )
    ( __rm_acc w0 w1 w2 # u64 . ap 11 # u64 . ap 12 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q8 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 9 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 8 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 7 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 9 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 10 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 11 # u64 . ap 13 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q9 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 10 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 9 )
    ( __rm_acc z0 z1 z2 # u64 . ap 12 # u64 . ap 12 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 8 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 10 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 11 # u64 . ap 14 )
    ( __rm_acc w0 w1 w2 # u64 . ap 12 # u64 . ap 13 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q10 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 11 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 10 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 9 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 11 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 12 # u64 . ap 14 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q11 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 12 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 11 )
    ( __rm_acc z0 z1 z2 # u64 . ap 13 # u64 . ap 13 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 10 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 12 # u64 . ap 15 )
    ( __rm_acc w0 w1 w2 # u64 . ap 13 # u64 . ap 14 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q12 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 13 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 12 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 11 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 13 # u64 . ap 15 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q13 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 14 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 13 )
    ( __rm_acc z0 z1 z2 # u64 . ap 14 # u64 . ap 14 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 12 # i z0
    = z0 z1 = z1 z2 = z2 0
    = w0 0 = w1 0 = w2 0
    ( __rm_acc w0 w1 w2 # u64 . ap 14 # u64 . ap 15 )
    ( __rm_acc2 z0 z1 z2 w0 w1 w2 )
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q14 # u64 . mp 15 )
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 14 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 13 # i z0
    = z0 z1 = z1 z2 = z2 0
    = y0 0 = y1 0 = y2 0
    ( __rm_acc y0 y1 y2 q15 # u64 . mp 15 )
    ( __rm_acc z0 z1 z2 # u64 . ap 15 # u64 . ap 15 )
    ( __rm_add3 z0 z1 z2 y0 y1 y2 )
    = . rp 14 # i z0
    = z0 z1 = z1 z2 = z2 0
    = . rp 15 # i z0
    = z0 z1 = z1 z2 = z2 0
    ^ z0
}
// ── end of generated kernels ──

// dst = a + b mod m (a, b < m), constant time.
@ __rm_add_d RsaMont c RsaTmp w ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : i n . c n
    : *i tp ( vec_data [i] . w t )
    : *i dp ( vec_data [i] . w d )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i mp ( vec_data [i] . c m )
    : ~ u64 cc 0
    : ~ i j 0
    ~ < j n {
        : u64 x # u64 . ap j
        : u64 y # u64 . bp j
        = . tp j # i ( nurl_addc_lo x y cc )
        = cc ( nurl_addc_hi x y cc )
        = j + j 1
    }
    : ~ u64 bb 0
    = j 0
    ~ < j n {
        : u64 x2 # u64 . tp j
        : u64 y2 # u64 . mp j
        = . dp j # i ( nurl_subb_lo x2 y2 bb )
        = bb ( nurl_subb_hi x2 y2 bb )
        = j + j 1
    }
    : i topb - # i cc # i bb
    : i mask ? < topb 0 0 - 0 1
    : i imask ^^ mask - 0 1
    : *i op ( vec_data [i] dst )
    = j 0
    ~ < j n { = . op j | & mask . dp j & imask . tp j = j + j 1 }
}

// dst = a − b mod m (a, b < m), constant time.
@ __rm_sub_d RsaMont c RsaTmp w ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : i n . c n
    : *i tp ( vec_data [i] . w t )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i mp ( vec_data [i] . c m )
    : ~ u64 bb 0
    : ~ i j 0
    ~ < j n {
        : u64 x # u64 . ap j
        : u64 y # u64 . bp j
        = . tp j # i ( nurl_subb_lo x y bb )
        = bb ( nurl_subb_hi x y bb )
        = j + j 1
    }
    // borrowed → add m back (masked)
    : u64 mask ? == # i bb 0 0 18446744073709551615
    : ~ u64 cc 0
    : *i op ( vec_data [i] dst )
    = j 0
    ~ < j n {
        : u64 x2 # u64 . tp j
        : u64 y2 & mask # u64 . mp j
        = . op j # i ( nurl_addc_lo x2 y2 cc )
        = cc ( nurl_addc_hi x2 y2 cc )
        = j + j 1
    }
}

// x = 2x mod m (x < m). Only for building R^2 from the public modulus.
@ __rm_dbl_d RsaMont c RsaTmp w ( Vec i ) x → v {
    : i n . c n
    : *i xp ( vec_data [i] x )
    : *i tp ( vec_data [i] . w t )
    : *i mp ( vec_data [i] . c m )
    : ~ u64 hi 0
    : ~ i j 0
    ~ < j n {
        : u64 xw # u64 . xp j
        = . tp j # i | << xw 1 hi
        = hi >> xw 63
        = j + j 1
    }
    : ~ u64 bb 0
    = j 0
    ~ < j n {
        : u64 tw # u64 . tp j
        : u64 mw # u64 . mp j
        = . xp j # i ( nurl_subb_lo tw mw bb )
        = bb ( nurl_subb_hi tw mw bb )
        = j + j 1
    }
    // 2x < m (no carry out and the subtraction borrowed): undo it
    ? & == # i hi 0 != # i bb 0 {
        = j 0
        ~ < j n { = . xp j . tp j = j + j 1 }
    } {}
}

// A context for an odd modulus given big-endian.
@ _rm_ctx ( Vec u ) mod_be → RsaMont {
    : i n ( __rm_limbs_for mod_be )
    : ( Vec i ) m ( __rm_from_be mod_be n )
    // −m^-1 mod 2^64 by Newton: each step doubles the correct low bits.
    : i m0i ?? ( vec_get [i] m 0 ) { T v → v F _ → 1 }
    : u64 m0 # u64 m0i
    : ~ u64 x 1
    : ~ i it 0
    ~ < it 6 { = x * x - 2 * m0 x = it + it 1 }
    : i n0 # i - 0 x
    : b r52 == n 16
    : RsaMont c @ RsaMont { n m n0 ( __rm_zeros n ) ( __rm_zeros n ) ( __rm_zeros ? r52 20 0 ) ( __rm_zeros ? r52 20 0 ) }
    : RsaTmp w ( _rm_tmp c )
    // R^2 mod m. 64n = s·2^h with s odd: double 1 up to 2^(64n + s) mod m
    // — that is 2^s in Montgomery form — then h Montgomery squarings take
    // it to 2^(s·2^h) = 2^(64n) = R in Montgomery form, i.e. R^2 mod m.
    : ~ i s * 64 n
    : ~ i h 0
    ~ == & s 1 0 { = s >> s 1 = h + h 1 }
    // r2 and one are filled in place, through the context's own vectors.
    ( vec_put [i] . c r2 0 1 )
    : ~ i k 0
    ~ < k + * 64 n s { ( __rm_dbl_d c w . c r2 ) = k + k 1 }
    = k 0
    ~ < k h { ( _rm_sqr_d c w . c r2 . c r2 ) = k + k 1 }
    // 1 in Montgomery form: R^2·1·R^-1.
    : ( Vec i ) one1 ( __rm_zeros n )
    ( vec_put [i] one1 0 1 )
    ( _rm_mul_d c w . c one . c r2 one1 )
    // The IFMA tier's R'^2 = 2^2080 mod m: R^2 = 2^2048 doubled 32 times.
    ? r52 {
        : ( Vec i ) x ( __rm_zeros n )
        ( __rm_copy_d x . c r2 n )
        = k 0
        ~ < k 32 { ( __rm_dbl_d c w x ) = k + k 1 }
        ( __rm_to52 ( vec_data [i] . c m ) n ( vec_data [i] . c m52 ) )
        ( __rm_to52 ( vec_data [i] x ) n ( vec_data [i] . c rr52 ) )
    } {}
    ^ c
}

// Plain x (any number of limbs) → Montgomery form mod m, by Horner over
// n-limb chunks from the top: acc = acc·R + chunk, each chunk entered as
// chunk·R^2·R^-1. Valid for any x, so a 2048-bit message reduces into a
// 1024-bit factor's domain directly.
// requires: c from _rm_ctx, w from _rm_tmp c, and 0 ≤ xn ≤ vec_len x.
raw @ _rm_enter RsaMont c RsaTmp w ( Vec i ) x i xn → ( Vec i ) {
    : i n . c n
    : ( Vec i ) acc ( __rm_zeros n )
    : ( Vec i ) ch ( __rm_zeros n )
    : *i xp ( vec_data [i] x )
    : *i cp ( vec_data [i] ch )
    : i chunks / + xn - n 1 n
    : ~ i q - chunks 1
    ~ >= q 0 {
        : ~ i j 0
        ~ < j n {
            : i at + * q n j
            = . cp j 0
            ? < at xn { = . cp j . xp at } {}
            = j + j 1
        }
        ( _rm_mul_d c w acc acc . c r2 )  // acc·R (in form: acc·R·R)
        ( _rm_mul_d c w ch ch . c r2 )  // chunk in form
        ( __rm_add_d c w acc acc ch )
        = q - q 1
    }
    ^ acc
}

// Montgomery form → plain.
// requires: c from _rm_ctx, w from _rm_tmp c, a . c n limbs.
raw @ _rm_leave RsaMont c RsaTmp w ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) one1 ( __rm_zeros . c n )
    ( vec_put [i] one1 0 1 )
    : ( Vec i ) out ( __rm_zeros . c n )
    ( _rm_mul_d c w out a one1 )
    ^ out
}

// base^e for a SECRET exponent: base in Montgomery form, e as en limbs
// (little-endian). Fixed 4-bit windows over all en limbs, table entry
// chosen by a masked scan of all sixteen: the same work for every e of
// that width. Result in Montgomery form.
// requires: c from _rm_ctx, w from _rm_tmp c, base . c n limbs and
// 0 ≤ en ≤ vec_len e.
raw @ _rm_pow_ct RsaMont c RsaTmp w ( Vec i ) base ( Vec i ) e i en → ( Vec i ) {
    : i n . c n
    : ( Vec i ) tbl ( __rm_zeros * 16 n )
    : *i tb ( vec_data [i] tbl )
    : *i op ( vec_data [i] . c one )
    : *i bp ( vec_data [i] base )
    : ~ i j 0
    ~ < j n { = . tb j . op j = . tb + n j . bp j = j + j 1 }
    : ( Vec i ) prev ( __rm_zeros n )
    : ( Vec i ) cur ( __rm_zeros n )
    : *i pp ( vec_data [i] prev )
    : *i cp ( vec_data [i] cur )
    : ~ i wi 2
    ~ < wi 16 {
        = j 0
        ~ < j n { = . pp j . tb + * - wi 1 n j = j + j 1 }
        ( _rm_mul_d c w cur prev base )
        = j 0
        ~ < j n { = . tb + * wi n j . cp j = j + j 1 }
        = wi + wi 1
    }
    : ( Vec i ) acc ( __rm_zeros n )
    ( __rm_copy_d acc . c one n )
    : ( Vec i ) sel ( __rm_zeros n )
    : *i sp ( vec_data [i] sel )
    : *i ep ( vec_data [i] e )
    : ~ i li - en 1
    ~ >= li 0 {
        : u64 limb # u64 . ep li
        : ~ i nib 15
        ~ >= nib 0 {
            ( _rm_sqr_d c w acc acc )
            ( _rm_sqr_d c w acc acc )
            ( _rm_sqr_d c w acc acc )
            ( _rm_sqr_d c w acc acc )
            : u64 dig & >> limb # u64 * nib 4 15
            = j 0
            ~ < j n { = . sp j 0 = j + j 1 }
            : ~ i k 0
            ~ < k 16 {
                // all-ones exactly when k == dig, without a branch
                : u64 dz - ^^ # u64 k dig 1
                : i mask - 0 # i >> dz 63
                = j 0
                ~ < j n { = . sp j | . sp j & mask . tb + * k n j = j + j 1 }
                = k + k 1
            }
            ( _rm_mul_d c w acc acc sel )
            = nib - nib 1
        }
        = li - li 1
    }
    ^ acc
}

// base^e for a PUBLIC exponent (big-endian bytes): plain square-and-
// multiply, Montgomery form in and out.
// requires: c from _rm_ctx, w from _rm_tmp c, base . c n limbs.
raw @ _rm_pow_pub RsaMont c RsaTmp w ( Vec i ) base ( Vec u ) e → ( Vec i ) {
    : ( Vec i ) acc ( __rm_zeros . c n )
    ( __rm_copy_d acc . c one . c n )
    : i len ( vec_len [u] e )
    : ~ i k 0
    ~ < k len {
        : i by ( __rm_get e k )
        : ~ i bit 7
        ~ >= bit 0 {
            ( _rm_sqr_d c w acc acc )
            ? != & >> by bit 1 0 { ( _rm_mul_d c w acc acc base ) } {}
            = bit - bit 1
        }
        = k + k 1
    }
    ^ acc
}

@ __rm_eq ( Vec i ) a ( Vec i ) b i n → b {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : ~ i diff 0
    : ~ i j 0
    ~ < j n { = diff | diff ^^ . ap j . bp j = j + j 1 }
    ^ == diff 0
}

// ── the IFMA tier: both CRT halves at once, radix 2^52 ──────────────
//
// On a CPU with AVX-512 IFMA (nurl_cpu_has_ifma: Ice Lake, Zen 4 and
// later) the two 1024-bit exponentiations of an RSA-2048 signature run
// in lockstep on nurl_v256_madd52lo / _hi, each operand 20 limbs of 52
// bits in five v256 registers. A VPMADD52 adds the low or high 52 bits
// of four limb products to four 64-bit lanes and carries nothing: each
// lane has 12 bits of headroom, so a whole multiply accumulates with no
// carry chain at all and is normalised once at the end — where the
// scalar forms above serialise every product on a carry.
//
// The multiply is an almost Montgomery multiply (AMM): for a, b < 2m
// and 4m < R' = 2^1040 it answers a·b·R'^-1 mod m, below 2m but not
// reduced. Operand scanning, one limb b_i of b at a time:
//   r += a·b_i (low halves) ; y = r_0·k0 mod 2^52 ; r += m·y (low)
//   r /= 2^52 — exact: r_0 ≡ 0 — one limb down the registers
//   r += a·b_i, m·y (high halves, which belong one limb up: now here)
// r_0, y and the carry out of limb 0 are scalar; nothing in the loop
// depends on a secret but the values. Two independent multiplies are
// interleaved, the p half and the q half: the scalar step of one hides
// in the other's vector latency. Measured on an i7-11850H, a 1024-bit
// AMM costs 88 ns this way against 203 ns for the ADX rows.
//
// Exponentiation keeps the fixed 4-bit window and the masked scan of
// all sixteen table entries; values stay in the AMM domain (x·R' mod m,
// below 2m) from entry to exit, and only the result is reduced. Moduli
// of other widths and CPUs without IFMA take _rm_pow_ct.

// n 64-bit limbs → 20 limbs of 52 bits (the low 1040 bits).
unsafe @ __rm_to52 * i src i n * i dst → v {
    : u64 m52 0xfffffffffffff
    : ~ i j 0
    ~ < j 20 {
        : i bit * j 52
        : i w >> bit 6
        : u64 sh # u64 & bit 63
        : ~ u64 v 0
        ? < w n { = v >> # u64 . src w sh } {}
        ? & > sh 12 < + w 1 n { = v | v << # u64 . src + w 1 - 64 sh } {}
        = . dst j # i & v m52
        = j + j 1
    }
}

// 20 normalised limbs of 52 bits → n 64-bit limbs.
unsafe @ __rm_from52 * i src * i dst i n → v {
    : ~ u64 acc 0
    : ~ u64 have 0
    : ~ i o 0
    : ~ i k 0
    ~ < k n { = . dst k 0 = k + k 1 }
    = k 0
    ~ < k 20 {
        : u64 x # u64 . src k
        = acc | acc << x have
        = have + have 52
        ? >= have 64 {
            ? < o n { = . dst o # i acc } {}
            = o + o 1
            = have - have 64
            = acc >> x - 52 have
        } {}
        = k + k 1
    }
    ? < o n { = . dst o # i acc } {}
}

// One register block of the low or high half: r += a·bv + m·yv, block k.
inline unsafe @ __rm_a52lo inout v256 r * i a * i m i k v256 bv v256 yv → v {
    : i off * k 32
    = r ( nurl_v256_madd52lo ( nurl_v256_madd52lo r ( nurl_v256_ld # s + # i a off ) bv ) ( nurl_v256_ld # s + # i m off ) yv )
}

inline unsafe @ __rm_a52hi inout v256 r * i a * i m i k v256 bv v256 yv → v {
    : i off * k 32
    = r ( nurl_v256_madd52hi ( nurl_v256_madd52hi r ( nurl_v256_ld # s + # i a off ) bv ) ( nurl_v256_ld # s + # i m off ) yv )
}

// The registers r0..r4 as 20 normalised limbs at rp: each lane's bits
// above 52 carried into the next. The value is below 2m < 2^1025, so
// nothing leaves limb 19.
inline unsafe @ __rm_a52_out * i rp v256 g0 v256 g1 v256 g2 v256 g3 v256 g4 → v {
    ( nurl_v256_st # s rp g0 )
    ( nurl_v256_st # s + # i rp 32 g1 )
    ( nurl_v256_st # s + # i rp 64 g2 )
    ( nurl_v256_st # s + # i rp 96 g3 )
    ( nurl_v256_st # s + # i rp 128 g4 )
    : u64 m52 0xfffffffffffff
    : ~ u64 c 0
    : ~ i j 0
    ~ < j 20 {
        : u64 x + # u64 . rp j c
        = . rp j # i & x m52
        = c >> x 52
        = j + j 1
    }
}

// rp = AMM(ap, bp) mod mp and sp = AMM(cp, dp) mod np, 20 limbs each
// (k1, k2: −m^-1 mod 2^52). rp may be ap or bp, sp cp or dp: the
// operands are read in the loop, the results written after it.
inline unsafe @ __rm_amm52x2 * i rp * i ap * i bp * i mp u64 k1 * i sp * i cp * i dp * i np u64 k2 → v {
    : u64 m52 0xfffffffffffff
    : v256 z ( nurl_v256_zero )
    : ~ v256 r0 z : ~ v256 r1 z : ~ v256 r2 z : ~ v256 r3 z : ~ v256 r4 z
    : ~ v256 s0 z : ~ v256 s1 z : ~ v256 s2 z : ~ v256 s3 z : ~ v256 s4 z
    : u64 a0 # u64 . ap 0
    : u64 m0 # u64 . mp 0
    : u64 c0 # u64 . cp 0
    : u64 n0 # u64 . np 0
    : ~ u64 x0 0
    : ~ u64 w0 0
    : ~ i ix 0
    ~ < ix 20 {
        : u64 bi # u64 . bp ix
        : u64 di # u64 . dp ix
        : u64 t + x0 & * a0 bi m52
        : u64 u + w0 & * c0 di m52
        : u64 y & * t k1 m52
        : u64 q & * u k2 m52
        : u64 cy >> + t & * m0 y m52 52
        : u64 cq >> + u & * n0 q m52 52
        : v256 bv ( nurl_v256_bcast64 bi )
        : v256 yv ( nurl_v256_bcast64 y )
        : v256 dv ( nurl_v256_bcast64 di )
        : v256 qv ( nurl_v256_bcast64 q )
        ( __rm_a52lo r0 ap mp 0 bv yv ) ( __rm_a52lo s0 cp np 0 dv qv )
        ( __rm_a52lo r1 ap mp 1 bv yv ) ( __rm_a52lo s1 cp np 1 dv qv )
        ( __rm_a52lo r2 ap mp 2 bv yv ) ( __rm_a52lo s2 cp np 2 dv qv )
        ( __rm_a52lo r3 ap mp 3 bv yv ) ( __rm_a52lo s3 cp np 3 dv qv )
        ( __rm_a52lo r4 ap mp 4 bv yv ) ( __rm_a52lo s4 cp np 4 dv qv )
        // one limb down; limb 0's carry (scalar, above) into the new 0
        = r0 ( nurl_v256_add64 ( nurl_v256_shrlane64 r0 r1 ) ( nurl_v256_set64 cy 0 0 0 ) )
        = r1 ( nurl_v256_shrlane64 r1 r2 )
        = r2 ( nurl_v256_shrlane64 r2 r3 )
        = r3 ( nurl_v256_shrlane64 r3 r4 )
        = r4 ( nurl_v256_shrlane64 r4 z )
        = s0 ( nurl_v256_add64 ( nurl_v256_shrlane64 s0 s1 ) ( nurl_v256_set64 cq 0 0 0 ) )
        = s1 ( nurl_v256_shrlane64 s1 s2 )
        = s2 ( nurl_v256_shrlane64 s2 s3 )
        = s3 ( nurl_v256_shrlane64 s3 s4 )
        = s4 ( nurl_v256_shrlane64 s4 z )
        ( __rm_a52hi r0 ap mp 0 bv yv ) ( __rm_a52hi s0 cp np 0 dv qv )
        ( __rm_a52hi r1 ap mp 1 bv yv ) ( __rm_a52hi s1 cp np 1 dv qv )
        ( __rm_a52hi r2 ap mp 2 bv yv ) ( __rm_a52hi s2 cp np 2 dv qv )
        ( __rm_a52hi r3 ap mp 3 bv yv ) ( __rm_a52hi s3 cp np 3 dv qv )
        ( __rm_a52hi r4 ap mp 4 bv yv ) ( __rm_a52hi s4 cp np 4 dv qv )
        = x0 ( nurl_v256_get64 r0 0 )
        = w0 ( nurl_v256_get64 s0 0 )
        = ix + ix 1
    }
    ( __rm_a52_out rp r0 r1 r2 r3 r4 )
    ( __rm_a52_out sp s0 s1 s2 s3 s4 )
}

// sel = the table entry `dig` of 16 (20 limbs each), by a masked scan of
// all sixteen.
inline unsafe @ __rm_sel52 * i tb u64 dig * i sel → v {
    : v256 z ( nurl_v256_zero )
    : ~ v256 o0 z : ~ v256 o1 z : ~ v256 o2 z : ~ v256 o3 z : ~ v256 o4 z
    : ~ i k 0
    ~ < k 16 {
        // all-ones exactly when k == dig, without a branch
        : u64 dz - ^^ # u64 k dig 1
        : v256 mv ( nurl_v256_bcast64 - 0 >> dz 63 )
        : i e + # i tb * k 160
        = o0 ( nurl_v256_or o0 ( nurl_v256_and mv ( nurl_v256_ld # s e ) ) )
        = o1 ( nurl_v256_or o1 ( nurl_v256_and mv ( nurl_v256_ld # s + e 32 ) ) )
        = o2 ( nurl_v256_or o2 ( nurl_v256_and mv ( nurl_v256_ld # s + e 64 ) ) )
        = o3 ( nurl_v256_or o3 ( nurl_v256_and mv ( nurl_v256_ld # s + e 96 ) ) )
        = o4 ( nurl_v256_or o4 ( nurl_v256_and mv ( nurl_v256_ld # s + e 128 ) ) )
        = k + k 1
    }
    ( nurl_v256_st # s sel o0 )
    ( nurl_v256_st # s + # i sel 32 o1 )
    ( nurl_v256_st # s + # i sel 64 o2 )
    ( nurl_v256_st # s + # i sel 96 o3 )
    ( nurl_v256_st # s + # i sel 128 o4 )
}

// x1^e1 mod m1 and x2^e2 mod m2 at once, for two 1024-bit moduli with
// their radix-2^52 forms: x1, x2 plain (16 limbs, below their modulus),
// e1, e2 SECRET exponents of en limbs each; the results plain and fully
// reduced into o1, o2 (16 limbs).
unsafe simd @ __rm_pow2_52 RsaMont c1 RsaMont c2 * i x1 * i x2 * i e1 * i e2 i en * i o1 * i o2 → v {
    : *i m1 ( vec_data [i] . c1 m52 )
    : *i m2 ( vec_data [i] . c2 m52 )
    : *i rr1 ( vec_data [i] . c1 rr52 )
    : *i rr2 ( vec_data [i] . c2 rr52 )
    : u64 k1 & # u64 . c1 n0 0xfffffffffffff
    : u64 k2 & # u64 . c2 n0 0xfffffffffffff
    // two tables of 16 entries, then acc, sel and a scratch 1, per half
    : ( Vec i ) buf ( __rm_zeros * 2 * 19 20 )
    : *i t1 ( vec_data [i] buf )
    : *i t2 # *i + # i t1 * 8 320
    : *i a1 # *i + # i t2 * 8 320
    : *i a2 # *i + # i a1 160
    : *i s1 # *i + # i a2 160
    : *i s2 # *i + # i s1 160
    : *i u1 # *i + # i s2 160
    : *i u2 # *i + # i u1 160
    // entry 1 = x·R' (x·R'^2·R'^-1); entry 0 = R' mod m (1·R'^2·R'^-1)
    ( __rm_to52 x1 16 s1 )
    ( __rm_to52 x2 16 s2 )
    : *i t11 # *i + # i t1 160
    : *i t21 # *i + # i t2 160
    ( __rm_amm52x2 t11 s1 rr1 m1 k1 t21 s2 rr2 m2 k2 )
    = . u1 0 1
    = . u2 0 1
    ( __rm_amm52x2 t1 u1 rr1 m1 k1 t2 u2 rr2 m2 k2 )
    : ~ i wi 2
    ~ < wi 16 {
        : i off * wi 160
        : i prev - off 160
        ( __rm_amm52x2 # *i + # i t1 off # *i + # i t1 prev t11 m1 k1 # *i + # i t2 off # *i + # i t2 prev t21 m2 k2 )
        = wi + wi 1
    }
    : ~ i j 0
    ~ < j 20 { = . a1 j . t1 j = . a2 j . t2 j = j + j 1 }
    : ~ i li - en 1
    ~ >= li 0 {
        : u64 l1 # u64 . e1 li
        : u64 l2 # u64 . e2 li
        : ~ i nib 15
        ~ >= nib 0 {
            ( __rm_amm52x2 a1 a1 a1 m1 k1 a2 a2 a2 m2 k2 )
            ( __rm_amm52x2 a1 a1 a1 m1 k1 a2 a2 a2 m2 k2 )
            ( __rm_amm52x2 a1 a1 a1 m1 k1 a2 a2 a2 m2 k2 )
            ( __rm_amm52x2 a1 a1 a1 m1 k1 a2 a2 a2 m2 k2 )
            : u64 sh # u64 * nib 4
            ( __rm_sel52 t1 & >> l1 sh 15 s1 )
            ( __rm_sel52 t2 & >> l2 sh 15 s2 )
            ( __rm_amm52x2 a1 a1 s1 m1 k1 a2 a2 s2 m2 k2 )
            = nib - nib 1
        }
        = li - li 1
    }
    // out of the domain: AMM(acc, 1) = acc·R'^-1, at most m
    ( __rm_amm52x2 s1 a1 u1 m1 k1 s2 a2 u2 m2 k2 )
    ( __rm_from52 s1 o1 16 )
    ( __rm_from52 s2 o2 16 )
    ( __rm_reduce_once o1 ( vec_data [i] . c1 m ) )
    ( __rm_reduce_once o2 ( vec_data [i] . c2 m ) )
}

// x1^e1 mod m1 and x2^e2 mod m2 for SECRET exponents (en1 and en2
// limbs), bases and results plain and below their modulus, into o1 and
// o2: the two halves of a CRT signature. On the IFMA tier with two
// 1024-bit moduli both at once (__rm_pow2_52), else one after the other
// by _rm_pow_ct — the same answers, which rsa_pow2_agree holds both to.
// requires: c1, c2 from _rm_ctx, w1, w2 from _rm_tmp of them; x1 and o1
// . c1 n limbs, x2 and o2 . c2 n limbs; 0 ≤ en1 ≤ vec_len e1 and
// 0 ≤ en2 ≤ vec_len e2.
raw @ _rm_pow2_ct RsaMont c1 RsaTmp w1 ( Vec i ) x1 ( Vec i ) e1 i en1 RsaMont c2 RsaTmp w2 ( Vec i ) x2 ( Vec i ) e2 i en2 ( Vec i ) o1 ( Vec i ) o2 → v {
    ? & & & ( nurl_cpu_has_ifma ) == en1 en2 > ( vec_len [i] . c1 m52 ) 0 > ( vec_len [i] . c2 m52 ) 0 {
        ( __rm_pow2_52 c1 c2 ( vec_data [i] x1 ) ( vec_data [i] x2 ) ( vec_data [i] e1 ) ( vec_data [i] e2 ) en1 ( vec_data [i] o1 ) ( vec_data [i] o2 ) )
        ^ v
    } {}
    : ( Vec i ) r1 ( _rm_leave c1 w1 ( _rm_pow_ct c1 w1 ( _rm_enter c1 w1 x1 . c1 n ) e1 en1 ) )
    : ( Vec i ) r2 ( _rm_leave c2 w2 ( _rm_pow_ct c2 w2 ( _rm_enter c2 w2 x2 . c2 n ) e2 en2 ) )
    ( __rm_copy_d o1 r1 . c1 n )
    ( __rm_copy_d o2 r2 . c2 n )
}

// x (16 limbs, at most m) → x mod m: subtract m when x ≥ m, by mask.
unsafe @ __rm_reduce_once * i xp * i mp → v {
    : ( Vec i ) d ( __rm_zeros 16 )
    : *i dp ( vec_data [i] d )
    : ~ u64 bb 0
    : ~ i j 0
    ~ < j 16 {
        : u64 x # u64 . xp j
        : u64 y # u64 . mp j
        = . dp j # i ( nurl_subb_lo x y bb )
        = bb ( nurl_subb_hi x y bb )
        = j + j 1
    }
    // no borrow: x ≥ m, keep the difference
    : i keep - # i bb 1
    = j 0
    ~ < j 16 { = . xp j | & keep . dp j & ^^ keep - 0 1 . xp j = j + j 1 }
}

// ── prepared private key ────────────────────────────────────────────
//
// n and e as big-endian bytes (the signature length, and the fault check's
// exponent). A CRT key (`crt`) carries the contexts of p and q, d_p and d_q
// as limbs of their factor's width, q^-1 mod p as limbs of p's and q as
// limbs of its own; a key without its factors carries the context of n
// and d as limbs. The other half is empty. Sealed, as RsaMont is: the
// signing path trusts its limb counts to match its contexts.
raw : RsaKey {
    ( Vec u ) n
    ( Vec u ) e
    b crt
    RsaMont cn
    ( Vec i ) d
    RsaMont cp
    RsaMont cq
    ( Vec i ) dp
    ( Vec i ) dq
    ( Vec i ) qinv
    ( Vec i ) ql
}

@ __rm_ctx_none → RsaMont { ^ @ RsaMont { 0 ( vec_new [i] ) 0 ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) } }

// Does `c` still hold the limbs its width says (what _rm_ctx built)? The
// seal stops a literal, but a context's vectors are readable fields, and
// safe code may shrink one in place (`vec_clear`, `vec_shrink_to_fit` on
// `. c m`). The signing entry asks once, before a raw kernel indexes them.
@ __rm_ctx_ok RsaMont c → b {
    : i n . c n
    : i w52 ? == n 16 20 0
    ^ & & & & & > n 0 == ( vec_len [i] . c m ) n == ( vec_len [i] . c r2 ) n == ( vec_len [i] . c one ) n == ( vec_len [i] . c m52 ) w52 == ( vec_len [i] . c rr52 ) w52
}

// The same for a whole key: its contexts, and every limb vector the
// width of the context it is used under.
@ __rm_key_ok RsaKey k → b {
    ? . k crt {
        : RsaMont cp . k cp
        : RsaMont cq . k cq
        ^ & & & & & ( __rm_ctx_ok cp ) ( __rm_ctx_ok cq ) == ( vec_len [i] . k dp ) . cp n == ( vec_len [i] . k dq ) . cq n == ( vec_len [i] . k qinv ) . cp n == ( vec_len [i] . k ql ) . cq n
    } {}
    : RsaMont cn . k cn
    ^ & ( __rm_ctx_ok cn ) == ( vec_len [i] . k d ) . cn n
}

@ __rm_copy_bytes ( Vec u ) b → ( Vec u ) { ^ ( bytes_slice b 0 ( vec_len [u] b ) ) }

@ _rsa_key_plain ( Vec u ) n ( Vec u ) e ( Vec u ) d → RsaKey {
    : RsaMont cn ( _rm_ctx n )
    : ( Vec i ) dl ( __rm_from_be d . cn n )
    ^ @ RsaKey { ( __rm_copy_bytes n ) ( __rm_copy_bytes e ) F cn dl ( __rm_ctx_none ) ( __rm_ctx_none ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) }
}

// An odd modulus above 1 — what a Montgomery context needs.
@ __rm_odd_modulus ( Vec u ) x → b {
    : i len ( vec_len [u] x )
    ? == len 0 { ^ F } {}
    ? == & ( __rm_get x - len 1 ) 1 0 { ^ F } {}
    ^ | > ( __rm_sig_bytes x ) 1 > ( __rm_get x - len 1 ) 1
}

@ _rsa_key_crt ( Vec u ) n ( Vec u ) e ( Vec u ) p ( Vec u ) q ( Vec u ) dp ( Vec u ) dq ( Vec u ) qinv → ?RsaKey {
    ? ! & ( __rm_odd_modulus p ) ( __rm_odd_modulus q ) { ^ @ ?RsaKey { F } } {}
    ? | | == ( vec_len [u] dp ) 0 == ( vec_len [u] dq ) 0 == ( vec_len [u] qinv ) 0 { ^ @ ?RsaKey { F } } {}
    : RsaMont cp ( _rm_ctx p )
    : RsaMont cq ( _rm_ctx q )
    : ( Vec i ) dpl ( __rm_from_be dp . cp n )
    : ( Vec i ) dql ( __rm_from_be dq . cq n )
    : ( Vec i ) qil ( __rm_from_be qinv . cp n )
    : ( Vec i ) ql ( __rm_from_be q . cq n )
    ^ @ ?RsaKey { T @ RsaKey { ( __rm_copy_bytes n ) ( __rm_copy_bytes e ) T ( __rm_ctx_none ) ( vec_new [i] ) cp cq dpl dql qil ql } }
}

// d_x + r·(x − 1) for a fresh 64-bit r, as nx + 1 limbs: the same exponent
// modulo the group order x − 1, different bits every call. `dx` is nx limbs.
@ __rm_blind_exp ( Vec i ) dx RsaMont cx → ( Vec i ) {
    : i n . cx n
    : ( Vec i ) out ( __rm_zeros + n 1 )
    : *i op ( vec_data [i] out )
    : *i mp ( vec_data [i] . cx m )
    : *i dp ( vec_data [i] dx )
    : u64 r # u64 ( rand_u64 )
    : ~ u64 cr 0
    : ~ i j 0
    ~ < j n {
        // (x − 1) differs from x only in bit 0 of limb 0 (x is odd)
        : u64 xj ? == j 0 & # u64 . mp 0 18446744073709551614 # u64 . mp j
        : u64 lo ( nurl_mac_lo xj r # u64 . dp j cr )
        = cr ( nurl_mac_hi xj r # u64 . dp j cr )
        = . op j # i lo
        = j + j 1
    }
    = . op n # i cr
    ^ out
}

// The CRT private operation; [] when the fault check rejects the result.
@ __rsa_crt RsaKey key ( Vec i ) msg i msgn i k → ( Vec u ) {
    : RsaMont cp . key cp
    : RsaMont cq . key cq
    : RsaTmp wp ( _rm_tmp cp )
    : RsaTmp wq ( _rm_tmp cq )
    : i np . cp n
    : i nq . cq n
    // the message in each half's domain
    : ( Vec i ) mp ( _rm_enter cp wp msg msgn )
    : ( Vec i ) mq ( _rm_enter cq wq msg msgn )
    : ( Vec i ) ep ( __rm_blind_exp . key dp cp )
    : ( Vec i ) eq ( __rm_blind_exp . key dq cq )
    // both halves' powers, plain: s_p < p, s_q < q
    : ( Vec i ) spl ( __rm_zeros np )
    : ( Vec i ) sq ( __rm_zeros nq )
    ( _rm_pow2_ct cp wp ( _rm_leave cp wp mp ) ep + np 1 cq wq ( _rm_leave cq wq mq ) eq + nq 1 spl sq )
    : ( Vec i ) sp ( _rm_enter cp wp spl np )  // Montgomery form mod p
    // Garner: h = (s_p − s_q)·q^-1 mod p ; s = s_q + q·h
    : ( Vec i ) sqp ( _rm_enter cp wp sq nq )
    : ( Vec i ) diff ( __rm_zeros np )
    ( __rm_sub_d cp wp diff sp sqp )
    : ( Vec i ) h ( __rm_zeros np )
    ( _rm_mul_d cp wp h diff . key qinv )  // (form)·plain → plain
    : i sn + np nq
    : ( Vec i ) s ( __rm_zeros + sn 1 )
    : *i spp ( vec_data [i] s )
    : *i qp ( vec_data [i] . key ql )
    : *i hp ( vec_data [i] h )
    : *i sqpp ( vec_data [i] sq )
    : ~ i a 0
    ~ < a nq { = . spp a . sqpp a = a + a 1 }
    = a 0
    ~ < a np {
        : u64 hb # u64 . hp a
        : ~ u64 cr 0
        : ~ i b 0
        ~ < b nq {
            : u64 x # u64 . spp + a b
            : u64 qw # u64 . qp b
            : u64 lo ( nurl_mac_lo qw hb x cr )
            = cr ( nurl_mac_hi qw hb x cr )
            = . spp + a b # i lo
            = b + b 1
        }
        // carry ripples into the limbs above
        : ~ i z + a nq
        ~ < z + sn 1 {
            : u64 y # u64 . spp z
            = . spp z # i ( nurl_addc_lo y cr 0 )
            = cr ( nurl_addc_hi y cr 0 )
            = z + z 1
        }
        = a + a 1
    }
    // Fault check: s^e ≡ m (mod p) and (mod q) before s leaves.
    : ( Vec i ) chkp ( _rm_pow_pub cp wp ( _rm_enter cp wp s + sn 1 ) . key e )
    : ( Vec i ) chkq ( _rm_pow_pub cq wq ( _rm_enter cq wq s + sn 1 ) . key e )
    ? ! & ( __rm_eq chkp mp np ) ( __rm_eq chkq mq nq ) { ^ ( vec_new [u] ) } {}
    ^ ( __rm_to_be s + sn 1 k )
}

// m^d mod n, as many big-endian bytes as n has. [] when the CRT fault
// check fails, or when the key's limbs no longer match its contexts
// (__rm_key_ok: one check a signature).
@ _rsa_sign_raw RsaKey key ( Vec u ) m → ( Vec u ) {
    ? ! ( __rm_key_ok key ) { ^ ( vec_new [u] ) } {}
    : i k ( vec_len [u] . key n )
    : i mn ( __rm_limbs_for m )
    : ( Vec i ) ml ( __rm_from_be m mn )
    ? . key crt { ^ ( __rsa_crt key ml mn k ) } {}
    : RsaMont c . key cn
    : RsaTmp w ( _rm_tmp c )
    : i dn . c n
    : ( Vec i ) r ( _rm_pow_ct c w ( _rm_enter c w ml mn ) . key d dn )
    ^ ( __rm_to_be ( _rm_leave c w r ) dn k )
}

// s^e mod n, k bytes big-endian (public exponent: variable time).
@ _rsa_public ( Vec u ) n ( Vec u ) e ( Vec u ) s i k → ( Vec u ) {
    : RsaMont c ( _rm_ctx n )
    : RsaTmp w ( _rm_tmp c )
    : i sn ( __rm_limbs_for s )
    : ( Vec i ) sl ( __rm_from_be s sn )
    : ( Vec i ) r ( _rm_pow_pub c w ( _rm_enter c w sl sn ) e )
    ^ ( __rm_to_be ( _rm_leave c w r ) . c n k )
}
