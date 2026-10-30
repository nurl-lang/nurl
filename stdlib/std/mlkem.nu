// stdlib/std/mlkem.nu — ML-KEM (FIPS 203) in pure NURL.
//
// The post-quantum key-encapsulation mechanism NIST standardised in
// August 2024, formerly CRYSTALS-Kyber. Three parameter sets:
//
//   level  name           ek     dk     ct    classical analogue
//   512    ML-KEM-512    800   1632    768    AES-128
//   768    ML-KEM-768   1184   2400   1088    AES-192
//   1024   ML-KEM-1024  1568   3168   1568    AES-256
//
// ML-KEM-768 is the one that matters in practice: paired with X25519 it
// is the `X25519MLKEM768` group that current browsers negotiate by
// default, and `stdlib/std/tls.nu` offers it for exactly that reason.
//
// API — the three KEM operations:
//   ( mlkem_keygen i level )                      → MlkemKeys
//   ( mlkem_encaps i level ( Vec u ) ek )         → MlkemEncap    (ct, ss)
//   ( mlkem_decaps i level ( Vec u ) dk
//                          ( Vec u ) ct )         → ( Vec u )     32-byte ss
// An ek, dk or ct of the wrong size for the level gives an empty ct and
// ss (encaps) or an empty Vec (decaps).
//
// API — the deterministic forms, which take the randomness as an
// argument instead of drawing it. These exist because FIPS 203 defines
// the algorithms this way and NIST's ACVP test vectors exercise them;
// production callers want the three above.
//   ( mlkem_keygen_derand level ( Vec u ) d ( Vec u ) z ) → MlkemKeys
//   ( mlkem_encaps_derand level ( Vec u ) ek ( Vec u ) m ) → MlkemEncap
//
// Accessors and sizes:
//   ( mlkem_ek MlkemKeys ) ( mlkem_dk MlkemKeys )       the keys' own bytes, lent
//   ( mlkem_ct MlkemEncap ) ( mlkem_ss MlkemEncap )
//   ( mlkem_ek_len level ) ( mlkem_dk_len level ) ( mlkem_ct_len level )
//   ( mlkem_keys_free k ) ( mlkem_encap_free e )      early release (optional)
//
// MlkemKeys and MlkemEncap are library handles (docs/MEMORY.md §7.6):
// every copy is the same keys, and the last owner releases them.
//
// Every operation is checked byte-for-byte against NIST's ACVP vectors
// by tools/mlkem_gate.sh — keygen, encapsulation and both decapsulation
// paths, including the implicit-rejection path that a wrong ciphertext
// must take.
//
// ── On constant time ───────────────────────────────────────────────
//
// Decapsulation must not branch on secret data, and does not: the
// re-encryption comparison is `subtle`'s constant-time equality, and
// the implicit-rejection select is an arithmetic mask, not an `?`. The
// arithmetic is likewise data-independent — Montgomery and Barrett
// reduction are straight-line, and the two places a value is folded
// into canonical range use an arithmetic-shift mask rather than a
// comparison. Rejection sampling in `SampleNTT` does branch on its
// input, which is correct: it consumes ρ, which is public.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha3.nu`
$ `stdlib/std/hash_sha3x4.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/subtle.nu`
$ `stdlib/core/rcbox.nu`

// ── Parameters ─────────────────────────────────────────────────────
//
// n = 256 and q = 3329 are fixed across all three sets; k (the module
// rank), η1/η2 (the noise widths) and du/dv (the ciphertext compression
// widths) are what the level selects.

: MlkemParams {
    i k
    i eta1
    i eta2
    i du
    i dv
}

@ __mlkem_params i level → MlkemParams {
    ? == level 512 { ^ @ MlkemParams { 2 3 2 10 4 } } {}
    ? == level 1024 { ^ @ MlkemParams { 4 2 2 11 5 } } {}
    ^ @ MlkemParams { 3 2 2 10 4 }  // 768, the default
}

@ mlkem_ek_len i level → i {
    : MlkemParams p ( __mlkem_params level )
    ^ + * 384 . p k 32
}

@ mlkem_dk_len i level → i {
    : MlkemParams p ( __mlkem_params level )
    ^ + * 768 . p k 96
}

@ mlkem_ct_len i level → i {
    : MlkemParams p ( __mlkem_params level )
    ^ + * * 32 . p du . p k * 32 . p dv
}

// ── Arithmetic in Z_q, q = 3329 ────────────────────────────────────
//
// Coefficients live in i16 throughout, held in signed representation
// and kept small by Montgomery and Barrett reduction rather than by
// division. Products widen to i32 for exactly as long as the multiply
// needs and come straight back down.

// Montgomery reduction: a·2^-16 mod q, for |a| < q·2^15.
// QINV = -3329^-1 mod 2^16 = -3327 in signed form; the low half of the
// product is what the i16 truncation extracts.
@ __mont i32 a → i16 {
    : i16 t * # i16 a # i16 -3327
    ^ # i16 >> - a * # i32 t # i32 3329 # i32 16
}

// Barrett reduction: a mod± q, for any i16 a. 20159 = ⌊(2^26 + q/2)/q⌋.
@ __barrett i16 a → i16 {
    : i16 t # i16 >> + * # i32 20159 # i32 a # i32 33554432 # i32 26
    ^ - a * t # i16 3329
}

// Fold a signed representative into [0, q). Written as an
// arithmetic-shift mask rather than `? < a 0`: `a >> 15` is 0 for
// non-negative a and -1 (all ones) for negative, so the branch that
// would otherwise depend on a secret coefficient disappears.
@ __csubq_add i16 a → i16 {
    ^ + a & >> a # i16 15 # i16 3329
}

// ζ^brv7(i)·2^16 mod q for i in 0..127 — the NTT twiddle factors, in
// Montgomery domain and bit-reversed order, centred on zero.
@ __mlkem_zetas → ( Vec i16 ) {
    : ( Vec i16 ) v ( vec_with_cap [i16] 128 )
    : b _l ( vec_set_len [i16] v 128 )
    : *i16 p ( vec_data [i16] v )
    = . p 0 # i16 -1044 = . p 1 # i16 -758 = . p 2 # i16 -359 = . p 3 # i16 -1517 = . p 4 # i16 1493 = . p 5 # i16 1422 = . p 6 # i16 287 = . p 7 # i16 202
    = . p 8 # i16 -171 = . p 9 # i16 622 = . p 10 # i16 1577 = . p 11 # i16 182 = . p 12 # i16 962 = . p 13 # i16 -1202 = . p 14 # i16 -1474 = . p 15 # i16 1468
    = . p 16 # i16 573 = . p 17 # i16 -1325 = . p 18 # i16 264 = . p 19 # i16 383 = . p 20 # i16 -829 = . p 21 # i16 1458 = . p 22 # i16 -1602 = . p 23 # i16 -130
    = . p 24 # i16 -681 = . p 25 # i16 1017 = . p 26 # i16 732 = . p 27 # i16 608 = . p 28 # i16 -1542 = . p 29 # i16 411 = . p 30 # i16 -205 = . p 31 # i16 -1571
    = . p 32 # i16 1223 = . p 33 # i16 652 = . p 34 # i16 -552 = . p 35 # i16 1015 = . p 36 # i16 -1293 = . p 37 # i16 1491 = . p 38 # i16 -282 = . p 39 # i16 -1544
    = . p 40 # i16 516 = . p 41 # i16 -8 = . p 42 # i16 -320 = . p 43 # i16 -666 = . p 44 # i16 -1618 = . p 45 # i16 -1162 = . p 46 # i16 126 = . p 47 # i16 1469
    = . p 48 # i16 -853 = . p 49 # i16 -90 = . p 50 # i16 -271 = . p 51 # i16 830 = . p 52 # i16 107 = . p 53 # i16 -1421 = . p 54 # i16 -247 = . p 55 # i16 -951
    = . p 56 # i16 -398 = . p 57 # i16 961 = . p 58 # i16 -1508 = . p 59 # i16 -725 = . p 60 # i16 448 = . p 61 # i16 -1065 = . p 62 # i16 677 = . p 63 # i16 -1275
    = . p 64 # i16 -1103 = . p 65 # i16 430 = . p 66 # i16 555 = . p 67 # i16 843 = . p 68 # i16 -1251 = . p 69 # i16 871 = . p 70 # i16 1550 = . p 71 # i16 105
    = . p 72 # i16 422 = . p 73 # i16 587 = . p 74 # i16 177 = . p 75 # i16 -235 = . p 76 # i16 -291 = . p 77 # i16 -460 = . p 78 # i16 1574 = . p 79 # i16 1653
    = . p 80 # i16 -246 = . p 81 # i16 778 = . p 82 # i16 1159 = . p 83 # i16 -147 = . p 84 # i16 -777 = . p 85 # i16 1483 = . p 86 # i16 -602 = . p 87 # i16 1119
    = . p 88 # i16 -1590 = . p 89 # i16 644 = . p 90 # i16 -872 = . p 91 # i16 349 = . p 92 # i16 418 = . p 93 # i16 329 = . p 94 # i16 -156 = . p 95 # i16 -75
    = . p 96 # i16 817 = . p 97 # i16 1097 = . p 98 # i16 603 = . p 99 # i16 610 = . p 100 # i16 1322 = . p 101 # i16 -1285 = . p 102 # i16 -1465 = . p 103 # i16 384
    = . p 104 # i16 -1215 = . p 105 # i16 -136 = . p 106 # i16 1218 = . p 107 # i16 -1335 = . p 108 # i16 -874 = . p 109 # i16 220 = . p 110 # i16 -1187 = . p 111 # i16 -1659
    = . p 112 # i16 -1185 = . p 113 # i16 -1530 = . p 114 # i16 -1278 = . p 115 # i16 794 = . p 116 # i16 -1510 = . p 117 # i16 -854 = . p 118 # i16 -870 = . p 119 # i16 478
    = . p 120 # i16 -108 = . p 121 # i16 -308 = . p 122 # i16 996 = . p 123 # i16 991 = . p 124 # i16 958 = . p 125 # i16 -1460 = . p 126 # i16 1522 = . p 127 # i16 1628
    ^ v
}

// The transform's whole table, built once per process and shared
// through publish-once slot 12 (registry: stdlib/std/tls_server.nu):
// the 128 zetas above, then the zeta VECTORS the narrow layers and the
// base multiplication read — each sixteen lanes laid out the way the
// lane shuffles of __ntt_step / __invntt_step / __poly_basemul put the
// coefficients (see there). i16 offsets:
//
//     ZT_F8 128  ZT_F4 256  ZT_F2 384     forward layers len 8, 4, 2
//     ZT_I2 512  ZT_I4 640  ZT_I8 768     inverse layers len 2, 4, 8
//     ZT_BM 896                           base multiplication (256 lanes)
: ~ i g_mlkem_ztab 0

@ __mlkem_ztab → *i16 {
    ? == g_mlkem_ztab 0 {
        : ( Vec i16 ) z ( __mlkem_zetas )
        : *i16 zp ( vec_data [i16] z )
        : ( Vec i16 ) t ( vec_zeroed [i16] 1152 )
        : *i16 tp ( vec_data [i16] t )
        : ~ i i 0
        ~ < i 128 { = . tp i . zp i = i + i 1 }
        // Eight steps of 32 coefficients a layer. Lane l of a step's
        // vector belongs to block `blk` of that layer, `per` lanes a
        // block-slot: len 8 — lanes 0-7 block 2s, 8-15 block 2s+1; len 4
        // — four-lane slots of blocks 4s, 4s+2, 4s+1, 4s+3; len 2 —
        // two-lane slots of blocks 8s + 0, 4, 1, 5, 2, 6, 3, 7.
        : ~ i st 0
        ~ < st 8 {
            : ~ i l 0
            ~ < l 16 {
                : i b8 + * st 2 / l 8
                : i q4 / l 4
                : i b4 + * st 4 ? == q4 0 0 ? == q4 1 2 ? == q4 2 1 3
                : i q2 / l 2
                : i b2 + * st 8 + / q2 2 * 4 % q2 2
                : i o + * st 16 l
                = . tp + 128 o . zp + 16 b8
                = . tp + 256 o . zp + 32 b4
                = . tp + 384 o . zp + 64 b2
                = . tp + 512 o . zp - 127 b2
                = . tp + 640 o . zp - 63 b4
                = . tp + 768 o . zp - 31 b8
                = l + l 1
            }
            = st + st 1
        }
        // Base multiplication: pair 4g in even lane 4g with ζ, pair
        // 4g + 2 in even lane 4g + 2 with −ζ, ζ = zetas[64 + g].
        = i 0
        ~ < i 64 {
            : i16 zv . zp + 64 i
            = . tp + 896 * 4 i zv
            = . tp + + 896 * 4 i 2 - # i16 0 zv
            = i + i 1
        }
        // The winner lives for the rest of the program, through the global.
        = g_mlkem_ztab ( vec_publish_once [i16] 12 t )
    } {}
    ^ ( vec_data [i16] @ ( Vec i16 ) { # s g_mlkem_ztab } )
}

// ── The number-theoretic transform ─────────────────────────────────
//
// q ≡ 1 (mod 256) would give a full 256-point transform, but 3329 only
// satisfies q ≡ 1 (mod 512) partially: there is no primitive 512th root
// of unity, so the transform stops one layer early. Seven layers leave
// 128 degree-1 polynomials rather than 256 constants, which is why
// multiplication in the NTT domain is `__poly_basemul` below and not a
// pointwise product.

// Sixteen Montgomery products at once, bit-identical to __mont per
// lane: lo(x·y) and its q-inverse multiple share their low 16 bits, so
// (x·y − t·q) >> 16 is exactly mulhi(x,y) − mulhi(t,q) — the borrow
// can never happen. This is the vpmullw/vpmulhw spelling every
// production ML-KEM uses; here it is also the proof obligation, because
// ACVP pins the bytes and "congruent mod q" would not be enough to
// notice a broken lane.
@ __fqmul_v v256 x v256 z v256 qv v256 qinv → v256 {
    : v256 lo ( nurl_v256_mullo16 x z )
    : v256 t ( nurl_v256_mullo16 lo qinv )
    ^ ( nurl_v256_sub16 ( nurl_v256_mulhi16 x z ) ( nurl_v256_mulhi16 t qv ) )
}

// Sixteen Barrett reductions: (20159·a + 2^25) >> 26 computed as
// ((20159·a >> 16) + 512) >> 10 — the discarded low half can never
// carry into the rounding constant, so the lanes match the scalar
// __barrett bit for bit.
@ __barrett_v v256 a v256 qv v256 c20159 → v256 {
    : v256 t ( nurl_v256_sra16 ( nurl_v256_add16 ( nurl_v256_mulhi16 a c20159 ) ( nurl_v256_bcast16 512 ) ) 10 )
    ^ ( nurl_v256_sub16 a ( nurl_v256_mullo16 t qv ) )
}

// The narrow layers, 32 coefficients a step (two v256, A and B), each
// pair of butterfly operands gathered into X and Y by in-lane shuffles
// and scattered back after:
//
//     len 8   X = A.lo ‖ B.lo, Y = A.hi ‖ B.hi        (permlo/hi128)
//     len 4   X, Y = the 64-bit halves interleaved     (unpacklo/hi64)
//     len 2   the 32-bit pairs split even / odd        (unpack32, unpack64)
//
// The butterflies are __fqmul_v / __barrett_v, lane for lane the scalar
// ones they replace, so the coefficients — which ACVP pins byte for
// byte — are the same; only where they sit in a register differs, and
// the zeta vectors (__mlkem_ztab) follow it.
inline @ __nl_gather v256 a v256 b i len inout v256 x inout v256 y → v {
    ? == len 8 {
        = x ( nurl_v256_permlo128 a b )
        = y ( nurl_v256_permhi128 a b )
    } {
        ? == len 4 {
            = x ( nurl_v256_unpacklo64 a b )
            = y ( nurl_v256_unpackhi64 a b )
        } {
            : v256 t0 ( nurl_v256_unpacklo32 a b )
            : v256 t1 ( nurl_v256_unpackhi32 a b )
            = x ( nurl_v256_unpacklo64 t0 t1 )
            = y ( nurl_v256_unpackhi64 t0 t1 )
        }
    }
}

// __nl_gather's inverse: X and Y back to A and B, stored at `p`.
inline @ __nl_scatter v256 x v256 y i len * i16 p → v {
    ? == len 8 {
        ( nurl_v256_st # s p ( nurl_v256_permlo128 x y ) )
        ( nurl_v256_st # s + # i p 32 ( nurl_v256_permhi128 x y ) )
    } {
        ? == len 4 {
            ( nurl_v256_st # s p ( nurl_v256_unpacklo64 x y ) )
            ( nurl_v256_st # s + # i p 32 ( nurl_v256_unpackhi64 x y ) )
        } {
            : v256 u0 ( nurl_v256_unpacklo32 x y )
            : v256 u1 ( nurl_v256_unpackhi32 x y )
            ( nurl_v256_st # s p ( nurl_v256_unpacklo64 u0 u1 ) )
            ( nurl_v256_st # s + # i p 32 ( nurl_v256_unpackhi64 u0 u1 ) )
        }
    }
}

// The clone ML-KEM's NTT, inverse NTT and base multiply run on this CPU,
// by name: `avx2` (the x86-64-v3 clone of each `simd @` function) or
// `baseline`. NURL_CPU_V3=0 masks the first. For reports and diagnostics.
@ mlkem_cpu_tier → s { ^ ? != 0 # i ( nurl_cpu_x86_v3 ) `avx2` `baseline` }

simd @ __ntt * i16 r i off * i16 zetas → v {
    : v256 qv ( nurl_v256_bcast16 3329 )
    : v256 qinv ( nurl_v256_bcast16 -3327 )
    : ~ i len 128
    : ~ i k 1
    // Layers with len >= 16: a butterfly's two operands are 16-lane
    // contiguous runs, so sixteen go at once.
    ~ >= len 16 {
        : ~ i start 0
        ~ < start 256 {
            : v256 vz ( nurl_v256_bcast16 # i . zetas k )
            = k + k 1
            : ~ i j start
            ~ < j + start len {
                : s pa # s + # i r * 2 + off j
                : s pb # s + # i r * 2 + off + j len
                : v256 va ( nurl_v256_ld pa )
                : v256 vb ( nurl_v256_ld pb )
                : v256 t ( __fqmul_v vb vz qv qinv )
                ( nurl_v256_st pb ( nurl_v256_sub16 va t ) )
                ( nurl_v256_st pa ( nurl_v256_add16 va t ) )
                = j + j 16
            }
            = start + start * 2 len
        }
        = len >> len 1
    }
    // Layers 8, 4, 2: operands interleave below vector width — gathered
    // into whole vectors first (__nl_gather).
    : ~ i zo 128
    ~ >= len 2 {
        : ~ i st 0
        ~ < st 8 {
            : *i16 p # *i16 + # i r * 2 + off * st 32
            : ~ v256 x ( nurl_v256_zero )
            : ~ v256 y ( nurl_v256_zero )
            ( __nl_gather ( nurl_v256_ld # s p ) ( nurl_v256_ld # s + # i p 32 ) len x y )
            : v256 t ( __fqmul_v y ( nurl_v256_ld # s + # i zetas * 2 + zo * st 16 ) qv qinv )
            ( __nl_scatter ( nurl_v256_add16 x t ) ( nurl_v256_sub16 x t ) len p )
            = st + st 1
        }
        = zo + zo 128
        = len >> len 1
    }
}

// The inverse transform, leaving its result multiplied by 2^16 (the
// Montgomery factor) — every caller wants a Montgomery-domain value
// next, so folding the 1/128 scaling and the factor into one constant
// saves a pass. f = 1441 = 2^32/128 mod q.
simd @ __invntt * i16 r i off * i16 zetas → v {
    : v256 qv ( nurl_v256_bcast16 3329 )
    : v256 qinv ( nurl_v256_bcast16 -3327 )
    : v256 c20159 ( nurl_v256_bcast16 20159 )
    : ~ i len 2
    : ~ i k 15
    // Narrow layers on gathered vectors, as the forward transform.
    : ~ i zo 512
    ~ <= len 8 {
        : ~ i st 0
        ~ < st 8 {
            : *i16 p # *i16 + # i r * 2 + off * st 32
            : ~ v256 x ( nurl_v256_zero )
            : ~ v256 y ( nurl_v256_zero )
            ( __nl_gather ( nurl_v256_ld # s p ) ( nurl_v256_ld # s + # i p 32 ) len x y )
            : v256 vz ( nurl_v256_ld # s + # i zetas * 2 + zo * st 16 )
            ( __nl_scatter ( __barrett_v ( nurl_v256_add16 x y ) qv c20159 )
            ( __fqmul_v ( nurl_v256_sub16 y x ) vz qv qinv ) len p )
            = st + st 1
        }
        = zo + zo 128
        = len << len 1
    }
    ~ <= len 128 {
        : ~ i start 0
        ~ < start 256 {
            : v256 vz ( nurl_v256_bcast16 # i . zetas k )
            = k - k 1
            : ~ i j start
            ~ < j + start len {
                : s pa # s + # i r * 2 + off j
                : s pb # s + # i r * 2 + off + j len
                : v256 t ( nurl_v256_ld pa )
                : v256 vb ( nurl_v256_ld pb )
                ( nurl_v256_st pa ( __barrett_v ( nurl_v256_add16 t vb ) qv c20159 ) )
                ( nurl_v256_st pb ( __fqmul_v ( nurl_v256_sub16 vb t ) vz qv qinv ) )
                = j + j 16
            }
            = start + start * 2 len
        }
        = len << len 1
    }
    // ·(2^32/128 mod q), sixteen lanes at a time.
    : v256 fv ( nurl_v256_bcast16 1441 )
    : ~ i i 0
    ~ < i 256 {
        : s pp # s + # i r * 2 + off i
        ( nurl_v256_st pp ( __fqmul_v ( nurl_v256_ld pp ) fv qv qinv ) )
        = i + i 16
    }
}

// Base multiplication: 128 products of degree-1 polynomials modulo
// X² − ζ, (a0 + a1·X)(b0 + b1·X) = (a0·b0 + ζ·a1·b1) + (a0·b1 + a1·b0)·X,
// every product a Montgomery one. Sixteen coefficients — eight pairs — a
// step: with P = a·b and Q = a·swap(b) lane by lane (swap exchanges the
// two coefficients of each pair), the even lane takes P's even + ζ·P's
// odd and the odd lane Q's even + Q's odd. The ζ of each pair sits in its
// even lane of the table (__mlkem_ztab).
simd @ __poly_basemul * i16 r i ro * i16 a i ao * i16 b i bo * i16 zetas → v {
    : v256 qv ( nurl_v256_bcast16 3329 )
    : v256 qinv ( nurl_v256_bcast16 -3327 )
    : v256 ev ( nurl_v256_bcast32 65535 )
    : ~ i i 0
    ~ < i 256 {
        : v256 va ( nurl_v256_ld # s + # i a * 2 + ao i )
        : v256 vb ( nurl_v256_ld # s + # i b * 2 + bo i )
        : v256 vz ( nurl_v256_ld # s + # i zetas * 2 + 896 i )
        : v256 pp ( __fqmul_v va vb qv qinv )
        : v256 qq ( __fqmul_v va ( nurl_v256_rotl32 vb 16 ) qv qinv )
        : v256 ee ( nurl_v256_add16 pp ( __fqmul_v ( nurl_v256_rotl32 pp 16 ) vz qv qinv ) )
        : v256 oo ( nurl_v256_add16 qq ( nurl_v256_rotl32 qq 16 ) )
        ( nurl_v256_st # s + # i r * 2 + ro i ( nurl_v256_or ( nurl_v256_and ee ev ) ( nurl_v256_andnot ev oo ) ) )
        = i + i 16
    }
}

// ── Polynomial helpers ─────────────────────────────────────────────

@ __poly_zero i n → ( Vec i16 ) {
    : ( Vec i16 ) v ( vec_with_cap [i16] ? > n 0 n 1 )
    : b _l ( vec_set_len [i16] v ? > n 0 n 1 )
    : *i16 p ( vec_data [i16] v )
    : ~ i i 0
    ~ < i n { = . p i # i16 0 = i + i 1 }
    ^ v
}

@ __poly_add * i16 r i ro * i16 a i ao * i16 b i bo → v {
    : ~ i i 0
    ~ < i 256 { = . r + ro i + . a + ao i . b + bo i = i + i 1 }
}

@ __poly_sub * i16 r i ro * i16 a i ao * i16 b i bo → v {
    : ~ i i 0
    ~ < i 256 { = . r + ro i - . a + ao i . b + bo i = i + i 1 }
}

@ __poly_reduce * i16 r i off → v {
    : ~ i i 0
    ~ < i 256 { = . r + off i ( __barrett . r + off i ) = i + i 1 }
}

// Lift out of the "plain" domain into Montgomery domain.
// f = 2^32 mod q = 1353.
@ __poly_tomont * i16 r i off → v {
    : ~ i i 0
    ~ < i 256 {
        = . r + off i ( __mont * # i32 . r + off i # i32 1353 )
        = i + i 1
    }
}

// Accumulate Σ a_i ∘ b_i over the k polynomials of a vector.
@ __polyvec_basemul_acc * i16 r i ro * i16 a i ao * i16 b i bo i k * i16 zetas * i16 t → v {
    ( __poly_basemul r ro a ao b bo zetas )
    : ~ i i 1
    ~ < i k {
        ( __poly_basemul t 0 a + ao * 256 i b + bo * 256 i zetas )
        ( __poly_add r ro r ro t 0 )
        = i + i 1
    }
    ( __poly_reduce r ro )
}

// ── Sampling ───────────────────────────────────────────────────────

// SampleNTT (FIPS 203 Algorithm 7): rejection-sample 256 coefficients
// uniformly from [0, q) out of a SHAKE128 stream keyed by ρ and two
// index bytes.
//
// Three stream bytes yield two 12-bit candidates, each kept only if it
// is below q — about a 19% rejection rate, so the number of bytes
// consumed depends on ρ. That is fine: ρ is public, it travels in the
// clear inside the encapsulation key.
//
// The stream is pulled a full SHAKE128 block at a time rather than
// three bytes at a time. Both give the same bytes — the sponge is one
// continuous stream either way — but a 168-byte pull costs one
// permutation where 56 three-byte pulls would cost the same permutation
// plus 56 rounds of call and bookkeeping.
// Rejection sampling over one squeezed block (FIPS 203 Algorithm 7).
// Consumes three bytes at a time, keeps each 12-bit half below q, and
// returns the new coefficient count. Shared by the one-at-a-time and
// four-at-a-time samplers below so the two cannot disagree about which
// candidates a block yields.
@ __rej_uniform * i16 r i off i ctr ( Vec u ) buf i blen → i {
    : *u bp ( vec_data [u] buf )
    : ~ i c ctr
    : ~ i pos 0
    ~ & < c 256 <= + pos 3 blen {
        : i b0 # i . bp pos
        : i b1 # i . bp + pos 1
        : i b2 # i . bp + pos 2
        : i d1 & | b0 << b1 8 4095
        : i d2 & | >> b1 4 << b2 4 4095
        = pos + pos 3
        ? & < d1 3329 < c 256 {
            = . r + off c # i16 d1
            = c + c 1
        } {}
        ? & < d2 3329 < c 256 {
            = . r + off c # i16 d2
            = c + c 1
        } {}
    }
    ^ c
}

@ __sample_ntt * i16 r i off ( Vec u ) rho i x1 i x2 → v {
    : Sha3 xof ( shake128_init )
    ( sha3_absorb xof rho )
    : ( Vec u ) idx ( vec_new [u] )
    ( vec_push [u] idx # u x1 )
    ( vec_push [u] idx # u x2 )
    ( sha3_absorb xof idx )

    : ~ i ctr 0
    ~ < ctr 256 {
        : ( Vec u ) buf ( sha3_squeeze xof 168 )
        = ctr ( __rej_uniform r off ctr buf 168 )
    }
}

// The two index bytes of cell `c` of a k×k matrix, in the order FIPS
// 203 asks for: ρ‖j‖i for key generation, ρ‖i‖j for the transpose
// encryption wants.
@ __mat_idx i k b transposed i c → ( Vec u ) {
    : i i / c k
    : i j % c k
    : ( Vec u ) v ( vec_new [u] )
    ? transposed
    { ( vec_push [u] v # u i ) ( vec_push [u] v # u j ) }
    { ( vec_push [u] v # u j ) ( vec_push [u] v # u i ) }
    ^ v
}

// Four matrix cells at once, on the four-way sponge.
//
// The cells of Â are independent SHAKE128 streams that differ only in
// two trailing index bytes, which is exactly the shape hash_sha3x4
// exists for. Rejection makes the four streams consume DIFFERENT
// numbers of bytes — a block yields between 0 and 112 usable
// coefficients — so the loop runs until the LAST lane has its 256 and
// the lanes that finished early simply stop reading. That is wasted
// squeezing, and it is still far cheaper than four separate sponges:
// the four share one permutation, and the permutation is the cost.
@ __sample_ntt_x4 * i16 r ( Vec u ) rho i k b transposed i c0 → v {
    : Sha3x4 xof ( shake128x4_init )
    ( sha3x4_absorb xof rho rho rho rho )
    : ( Vec u ) x0 ( __mat_idx k transposed + c0 0 )
    : ( Vec u ) x1 ( __mat_idx k transposed + c0 1 )
    : ( Vec u ) x2 ( __mat_idx k transposed + c0 2 )
    : ( Vec u ) x3 ( __mat_idx k transposed + c0 3 )
    ( sha3x4_absorb xof x0 x1 x2 x3 )

    : ( Vec u ) b0 ( vec_with_cap [u] 168 )
    : ( Vec u ) b1 ( vec_with_cap [u] 168 )
    : ( Vec u ) b2 ( vec_with_cap [u] 168 )
    : ( Vec u ) b3 ( vec_with_cap [u] 168 )
    : ~ i n0 0
    : ~ i n1 0
    : ~ i n2 0
    : ~ i n3 0
    ~ | | | < n0 256 < n1 256 < n2 256 < n3 256 {
        : b z0 ( vec_set_len [u] b0 0 )
        : b z1 ( vec_set_len [u] b1 0 )
        : b z2 ( vec_set_len [u] b2 0 )
        : b z3 ( vec_set_len [u] b3 0 )
        ? ! & & & z0 z1 z2 z3 { = n0 256 = n1 256 = n2 256 = n3 256 } {
            ( sha3x4_squeeze xof 168 b0 b1 b2 b3 )
            = n0 ( __rej_uniform r * 256 + c0 0 n0 b0 168 )
            = n1 ( __rej_uniform r * 256 + c0 1 n1 b1 168 )
            = n2 ( __rej_uniform r * 256 + c0 2 n2 b2 168 )
            = n3 ( __rej_uniform r * 256 + c0 3 n3 b3 168 )
        }
    }
}

// Four PRF_η streams at once: same seed, four nonce bytes, 64·η bytes
// each appended to o0..o3. The callers hand out consecutive nonces in
// fixed-length batches (k or 2k of them), which is the equal-length
// lockstep the four-way sponge wants; a short batch clamps the spare
// lanes to the last real nonce and discards them.
@ __mlkem_prf_x4 ( Vec u ) seed i n0 i n1 i n2 i n3 i eta ( Vec u ) o0 ( Vec u ) o1 ( Vec u ) o2 ( Vec u ) o3 → v {
    : Sha3x4 h ( shake256x4_init )
    ( sha3x4_absorb h seed seed seed seed )
    : ( Vec u ) b0 ( vec_new [u] ) ( vec_push [u] b0 # u n0 )
    : ( Vec u ) b1 ( vec_new [u] ) ( vec_push [u] b1 # u n1 )
    : ( Vec u ) b2 ( vec_new [u] ) ( vec_push [u] b2 # u n2 )
    : ( Vec u ) b3 ( vec_new [u] ) ( vec_push [u] b3 # u n3 )
    ( sha3x4_absorb h b0 b1 b2 b3 )
    ( sha3x4_squeeze h * 64 eta o0 o1 o2 o3 )
}

// One batch of `count` consecutive-nonce CBD polynomials into dst,
// starting at nonce `n0`, four streams per sponge.
simd @ __cbd_batch * i16 dst ( Vec u ) seed i n0 i count i eta → v {
    : ( Vec u ) o0 ( vec_new [u] )
    : ( Vec u ) o1 ( vec_new [u] )
    : ( Vec u ) o2 ( vec_new [u] )
    : ( Vec u ) o3 ( vec_new [u] )
    : ~ i g 0
    ~ < g count {
        : b z0 ( vec_set_len [u] o0 0 )
        : b z1 ( vec_set_len [u] o1 0 )
        : b z2 ( vec_set_len [u] o2 0 )
        : b z3 ( vec_set_len [u] o3 0 )
        ? ! & & & z0 z1 z2 z3 { = g count } {
            : i m1 ? < + g 1 count + g 1 - count 1
            : i m2 ? < + g 2 count + g 2 - count 1
            : i m3 ? < + g 3 count + g 3 - count 1
            ( __mlkem_prf_x4 seed + n0 g + n0 m1 + n0 m2 + n0 m3 eta o0 o1 o2 o3 )
            ( __cbd dst * 256 g o0 eta )
            ? < + g 1 count { ( __cbd dst * 256 + g 1 o1 eta ) } {}
            ? < + g 2 count { ( __cbd dst * 256 + g 2 o2 eta ) } {}
            ? < + g 3 count { ( __cbd dst * 256 + g 3 o3 eta ) } {}
            = g + g 4
        }
    }
}

// SamplePolyCBD_η (FIPS 203 Algorithm 8): each coefficient is the
// difference of two sums of η bits drawn consecutively from the byte
// string — a centred binomial distribution on [-η, η].
@ __cbd * i16 r i off ( Vec u ) buf i eta → v {
    : *u bp ( vec_data [u] buf )
    // The spec's per-bit loop costs 2·η loads, shifts and masks per
    // coefficient. The sums it wants are carry-free inside their own
    // bit groups, so a masked add computes η-bit-sums for a whole word
    // of coefficients at once — the standard CBD bit-slice, and the
    // same coefficients bit for bit (the ACVP vectors pin it).
    ? == eta 2 {
        // 8 coefficients per 32-bit window: d = popcount-by-pairs, each
        // 4-bit group is a₂b₂ packed as (a + (b << 2)) of 2-bit sums.
        : ~ i i 0
        ~ < i 32 {
            : i o4 * i 4
            : i t | | | # i . bp o4 << # i . bp + o4 1 8 << # i . bp + o4 2 16 << # i . bp + o4 3 24
            : i d + & t 1431655765 & >> t 1 1431655765
            : ~ i j 0
            ~ < j 8 {
                : i a & >> d * j 4 3
                : i b & >> d + * j 4 2 3
                = . r + off + * i 8 j # i16 - a b
                = j + j 1
            }
            = i + i 1
        }
        ^ v
    } {}
    ? == eta 3 {
        // 4 coefficients per 3 bytes: sums of 3 bits via 0x249249.
        : ~ i i 0
        ~ < i 64 {
            : i o3 * i 3
            : i t | | # i . bp o3 << # i . bp + o3 1 8 << # i . bp + o3 2 16
            : i d + + & t 2396745 & >> t 1 2396745 & >> t 2 2396745
            : ~ i j 0
            ~ < j 4 {
                : i a & >> d * j 6 7
                : i b & >> d + * j 6 3 7
                = . r + off + * i 4 j # i16 - a b
                = j + j 1
            }
            = i + i 1
        }
        ^ v
    } {}
    // Any other η would be a new parameter set; fail loudly rather than
    // sample a distribution FIPS 203 does not define.
    ( nurl_panic `__cbd: eta must be 2 or 3 (FIPS 203 has no other parameter set)` )
}

// ── Byte encoding, compression ─────────────────────────────────────
//
// ByteEncode_d / ByteDecode_d for d ∈ {1,4,5,10,11,12}. Eight
// coefficients are exactly d bytes, so a polynomial is 32 groups of eight,
// and a group goes through two 64-bit words (8·d ≤ 96 bits) — no bit
// cursor, no loop whose trip count changes from one coefficient to the
// next. The callers dispatch on d so each group function is compiled with
// d a literal, and unrolls into straight-line shifts and byte moves: the
// cursor this replaces was the hot loop of encapsulation, a tenth of it
// spent decoding the encapsulation key alone.

// Eight d-bit values from a[at …] into d bytes at dst[w …].
inline @ __enc8 * i16 a i at i d * u dst i w → v {
    : i mask - << 1 d 1
    : ~ u64 lo 0
    : ~ u64 hi 0
    : ~ i c 0
    ~ < c 8 {
        : u64 x # u64 & # i . a + at c mask
        : i sh * c d
        ? < sh 64 {
            = lo | lo << x # u64 sh
            ? > + sh d 64 { = hi | hi >> x # u64 - 64 sh } {}
        } { = hi | hi << x # u64 - sh 64 }
        = c + c 1
    }
    : ~ i b 0
    ~ < b d {
        : u64 wv ? < b 8 lo hi
        : i bs ? < b 8 * b 8 * - b 8 8
        = . dst + w b # u & >> wv # u64 bs 255
        = b + b 1
    }
}

// d bytes at src[w …] into eight d-bit values at r[at …].
inline @ __dec8 * u src i w i d * i16 r i at → v {
    : u64 mask # u64 - << 1 d 1
    : ~ u64 lo 0
    : ~ u64 hi 0
    : ~ i b 0
    ~ < b d {
        : u64 x # u64 . src + w b
        ? < b 8 { = lo | lo << x # u64 * b 8 } { = hi | hi << x # u64 * - b 8 8 }
        = b + b 1
    }
    : ~ i c 0
    ~ < c 8 {
        : i sh * c d
        : ~ u64 v 0
        ? < sh 64 {
            = v >> lo # u64 sh
            ? > + sh d 64 { = v | v << hi # u64 - 64 sh } {}
        } { = v >> hi # u64 - sh 64 }
        = . r + at c # i16 & v mask
        = c + c 1
    }
}

inline @ __enc_poly * i16 a i off i d * u dst i base → v {
    : ~ i g 0
    ~ < g 32 { ( __enc8 a + off * g 8 d dst + base * g d ) = g + g 1 }
}

inline @ __dec_poly * u src i srcoff i d * i16 r i off → v {
    : ~ i g 0
    ~ < g 32 { ( __dec8 src + srcoff * g d d r + off * g 8 ) = g + g 1 }
}

@ __byte_encode * i16 a i off i d ( Vec u ) out → v {
    // Exactly 32·d bytes per polynomial: reserve once, write raw. See
    // __bitpack in std/mldsa.nu for why — the same per-byte vec_push
    // cursor was the hot scalar loop of K-PKE encryption here.
    : i nbytes * 32 d
    : i base ( vec_len [u] out )
    ( vec_reserve [u] out nbytes )
    : b _l ( vec_set_len [u] out + base nbytes )
    : *u dst ( vec_data [u] out )
    ? == d 12 { ( __enc_poly a off 12 dst base ) ^ v } {}
    ? == d 10 { ( __enc_poly a off 10 dst base ) ^ v } {}
    ? == d 11 { ( __enc_poly a off 11 dst base ) ^ v } {}
    ? == d 4 { ( __enc_poly a off 4 dst base ) ^ v } {}
    ? == d 5 { ( __enc_poly a off 5 dst base ) ^ v } {}
    ? == d 1 { ( __enc_poly a off 1 dst base ) ^ v } {}
    // FIPS 203 has no other d; a new parameter set would land here.
    ( nurl_panic `__byte_encode: d must be 1, 4, 5, 10, 11 or 12` )
}

@ __byte_decode ( Vec u ) src i srcoff i d * i16 r i off → v {
    : *u sp ( vec_data [u] src )
    ? == d 12 { ( __dec_poly sp srcoff 12 r off ) ^ v } {}
    ? == d 10 { ( __dec_poly sp srcoff 10 r off ) ^ v } {}
    ? == d 11 { ( __dec_poly sp srcoff 11 r off ) ^ v } {}
    ? == d 4 { ( __dec_poly sp srcoff 4 r off ) ^ v } {}
    ? == d 5 { ( __dec_poly sp srcoff 5 r off ) ^ v } {}
    ? == d 1 { ( __dec_poly sp srcoff 1 r off ) ^ v } {}
    ( nurl_panic `__byte_decode: d must be 1, 4, 5, 10, 11 or 12` )
}

// Fold a whole polynomial into [0, q).
//
// Barrett reduction leaves coefficients centred on zero, so roughly half
// of them are negative. Compression canonicalises on its own way past,
// but ByteEncode12 is fed straight from the reduced polynomial, and
// masking a negative value down to 12 bits yields its two's-complement
// low bits rather than its residue. That is the one place the signed
// representation has to be given up explicitly.
@ __poly_canon * i16 a i off → v {
    : ~ i i 0
    ~ < i 256 {
        = . a + off i ( __csubq_add . a + off i )
        = i + i 1
    }
}

// Compress_d(x) = ⌈2^d·x/q⌋ mod 2^d, over a canonical representative.
// In 32-bit unsigned arithmetic — 2^d·x + 1664 < 2^23 for every d ≤ 11 —
// because that is a division the compiler can vectorise (a multiply-high
// by the reciprocal of 3329, eight lanes at a time); spelled in 64-bit
// signed `i` it stayed a scalar loop of multiplies and sign fix-ups, the
// hottest loop left in encapsulation.
@ __poly_compress * i16 a i off i d → v {
    : u32 mask # u32 - << 1 d 1
    : u32 sh # u32 d
    : ~ i i 0
    ~ < i 256 {
        : u32 t # u32 # i ( __csubq_add . a + off i )
        = . a + off i # i16 & / + << t sh # u32 1664 # u32 3329 mask
        = i + i 1
    }
}

// Decompress_d(y) = ⌈q·y/2^d⌋.
@ __poly_decompress * i16 a i off i d → v {
    : i half << 1 - d 1
    : ~ i i 0
    ~ < i 256 {
        : i t # i . a + off i
        = . a + off i # i16 >> + * t 3329 half d
        = i + i 1
    }
}

// ── K-PKE ──────────────────────────────────────────────────────────

// Â — the k×k matrix expanded from ρ. `transposed` selects which of the
// two index orders FIPS 203 asks for: key generation samples Â[i][j]
// from ρ‖j‖i, encryption wants Â^T and so samples from ρ‖i‖j.
//
// The k*k cells are walked in groups of four so the four-way sponge can
// take them; k*k is 4, 9 or 16, so k=3 leaves one cell for the scalar
// sampler. Cell c is row c/k, column c%k, which is the same traversal
// the nested loops did, in the same order, writing the same offsets.
@ __gen_matrix * i16 ap ( Vec u ) rho i k b transposed * i16 _zetas → v {
    : i n * k k
    : ~ i c 0
    ~ <= + c 4 n {
        ( __sample_ntt_x4 ap rho k transposed c )
        = c + c 4
    }
    ~ < c n {
        : i i / c k
        : i j % c k
        : i off * 256 c
        ? transposed
        { ( __sample_ntt ap off rho i j ) }
        { ( __sample_ntt ap off rho j i ) }
        = c + c 1
    }
}

// K-PKE.KeyGen (Algorithm 13). Returns ek ‖ dk concatenated by the
// caller; here ek and dk come back as two vectors.
simd @ __kpke_keygen MlkemParams prm ( Vec u ) d ( Vec u ) ekout ( Vec u ) dkout → v {
    : i k . prm k
    : *i16 zp ( __mlkem_ztab )

    // (ρ, σ) ← G(d ‖ k)
    : ( Vec u ) gin ( vec_new [u] )
    ( bytes_extend_bytes gin d )
    ( vec_push [u] gin # u k )
    : ( Vec u ) g ( sha3_512_pure gin )
    : ( Vec u ) rho ( bytes_slice g 0 32 )
    : ( Vec u ) sigma ( bytes_slice g 32 64 )

    // One workspace: Â, then ŝ ‖ ê (contiguous, so their 2k CBD streams —
    // consecutive nonces, one η — go through the four-way sponge as one
    // batch), then t̂ and a scratch polynomial.
    : ( Vec i16 ) ws ( __poly_zero * 256 + + * k k * 3 k 1 )
    : *i16 apz ( vec_data [i16] ws )
    : *i16 sp # *i16 + # i apz * 512 * k k
    : *i16 ep # *i16 + # i sp * 512 k
    : *i16 tp # *i16 + # i ep * 512 k
    : *i16 scr # *i16 + # i tp * 512 k
    ( __gen_matrix apz rho k F zp )
    ( __cbd_batch sp sigma 0 * 2 k . prm eta1 )
    : ~ i i 0

    = i 0
    ~ < i k { ( __ntt sp * 256 i zp ) ( __poly_reduce sp * 256 i ) = i + i 1 }
    = i 0
    ~ < i k { ( __ntt ep * 256 i zp ) ( __poly_reduce ep * 256 i ) = i + i 1 }

    // t̂ ← Â ∘ ŝ + ê
    = i 0
    ~ < i k {
        ( __polyvec_basemul_acc tp * 256 i apz * 256 * i k sp 0 k zp scr )
        ( __poly_tomont tp * 256 i )
        ( __poly_add tp * 256 i tp * 256 i ep * 256 i )
        ( __poly_reduce tp * 256 i )
        = i + i 1
    }

    // ek ← ByteEncode12(t̂) ‖ ρ ; dk ← ByteEncode12(ŝ)
    = i 0
    ~ < i k { ( __poly_canon tp * 256 i ) ( __byte_encode tp * 256 i 12 ekout ) = i + i 1 }
    ( bytes_extend_bytes ekout rho )
    = i 0
    ~ < i k { ( __poly_canon sp * 256 i ) ( __byte_encode sp * 256 i 12 dkout ) = i + i 1 }

}

// K-PKE.Encrypt (Algorithm 14).
simd @ __kpke_encrypt MlkemParams prm ( Vec u ) ek ( Vec u ) m ( Vec u ) r ( Vec u ) ctout → v {
    : i k . prm k
    : *i16 zp ( __mlkem_ztab )

    // One workspace for every polynomial: t̂, Â^T, then y ‖ e1 ‖ e2 —
    // contiguous, so their 2k + 1 CBD streams (consecutive nonces) go
    // through the four-way sponge in as few batches as the two η allow —
    // then u, v, μ and a scratch polynomial.
    : ( Vec i16 ) ws ( __poly_zero * 256 + + * k k * 5 k 4 )
    : *i16 tp ( vec_data [i16] ws )
    : *i16 atp # *i16 + # i tp * 512 k
    : *i16 yp # *i16 + # i atp * 512 * k k
    : *i16 e1p # *i16 + # i yp * 512 k
    : *i16 e2p # *i16 + # i e1p * 512 k
    : *i16 up # *i16 + # i e2p 512
    : *i16 vp # *i16 + # i up * 512 k
    : *i16 mup # *i16 + # i vp 512
    : *i16 scr # *i16 + # i mup 512
    : ~ i i 0
    ~ < i k { ( __byte_decode ek * 384 i 12 tp * 256 i ) = i + i 1 }
    : ( Vec u ) rho ( bytes_slice ek * 384 k + * 384 k 32 )
    ( __gen_matrix atp rho k T zp )
    ? == . prm eta1 . prm eta2 {
        ( __cbd_batch yp r 0 + * 2 k 1 . prm eta1 )
    } {
        ( __cbd_batch yp r 0 k . prm eta1 )
        ( __cbd_batch e1p r k + k 1 . prm eta2 )
    }

    = i 0
    ~ < i k { ( __ntt yp * 256 i zp ) ( __poly_reduce yp * 256 i ) = i + i 1 }

    // u ← NTT^-1(Â^T ∘ ŷ) + e1
    = i 0
    ~ < i k {
        ( __polyvec_basemul_acc up * 256 i atp * 256 * i k yp 0 k zp scr )
        ( __invntt up * 256 i zp )
        ( __poly_add up * 256 i up * 256 i e1p * 256 i )
        ( __poly_reduce up * 256 i )
        = i + i 1
    }

    // v ← NTT^-1(t̂ᵀ ∘ ŷ) + e2 + Decompress1(m)
    ( __polyvec_basemul_acc vp 0 tp 0 yp 0 k zp scr )
    ( __invntt vp 0 zp )
    ( __poly_add vp 0 vp 0 e2p 0 )

    ( __byte_decode m 0 1 mup 0 )
    ( __poly_decompress mup 0 1 )
    ( __poly_add vp 0 vp 0 mup 0 )
    ( __poly_reduce vp 0 )

    // c ← ByteEncode_du(Compress_du(u)) ‖ ByteEncode_dv(Compress_dv(v))
    = i 0
    ~ < i k {
        ( __poly_compress up * 256 i . prm du )
        ( __byte_encode up * 256 i . prm du ctout )
        = i + i 1
    }
    ( __poly_compress vp 0 . prm dv )
    ( __byte_encode vp 0 . prm dv ctout )

}

// K-PKE.Decrypt (Algorithm 15) → the 32-byte message.
simd @ __kpke_decrypt MlkemParams prm ( Vec u ) dk ( Vec u ) ct → ( Vec u ) {
    : i k . prm k
    : *i16 zp ( __mlkem_ztab )

    // One workspace: u, v, ŝ, w and a scratch polynomial.
    : ( Vec i16 ) ws ( __poly_zero * 256 + * 2 k 3 )
    : *i16 up ( vec_data [i16] ws )
    : *i16 vp # *i16 + # i up * 512 k
    : *i16 sp # *i16 + # i vp 512
    : *i16 wp # *i16 + # i sp * 512 k
    : *i16 scr # *i16 + # i wp 512
    : i ubytes * 32 . prm du
    : ~ i i 0
    ~ < i k {
        ( __byte_decode ct * ubytes i . prm du up * 256 i )
        ( __poly_decompress up * 256 i . prm du )
        = i + i 1
    }

    ( __byte_decode ct * ubytes k . prm dv vp 0 )
    ( __poly_decompress vp 0 . prm dv )

    = i 0
    ~ < i k { ( __byte_decode dk * 384 i 12 sp * 256 i ) = i + i 1 }

    = i 0
    ~ < i k { ( __ntt up * 256 i zp ) ( __poly_reduce up * 256 i ) = i + i 1 }

    ( __polyvec_basemul_acc wp 0 sp 0 up 0 k zp scr )
    ( __invntt wp 0 zp )
    ( __poly_sub wp 0 vp 0 wp 0 )
    ( __poly_reduce wp 0 )

    ( __poly_compress wp 0 1 )
    : ( Vec u ) m ( vec_new [u] )
    ( __byte_encode wp 0 1 m )

    ^ m
}

// ── ML-KEM ─────────────────────────────────────────────────────────

: MlkemKeysImpl {
    ( Vec u ) ek
    ( Vec u ) dk
}

: MlkemEncapImpl {
    ( Vec u ) ct
    ( Vec u ) ss
}

// Both are handles on their state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: MlkemKeys { ( Shared MlkemKeysImpl ) ctl }

: MlkemEncap { ( Shared MlkemEncapImpl ) ctl }

@ MlkemKeys_share MlkemKeys h → MlkemKeys { ^ @ MlkemKeys { ( shared_clone [MlkemKeysImpl] . h ctl ) } }

@ MlkemKeys_drop sink MlkemKeys h → v {}

@ __MlkemKeys_ptr MlkemKeys h → *MlkemKeysImpl { ^ ( shared_ptr [MlkemKeysImpl] . h ctl ) }

@ MlkemEncap_share MlkemEncap h → MlkemEncap { ^ @ MlkemEncap { ( shared_clone [MlkemEncapImpl] . h ctl ) } }

@ MlkemEncap_drop sink MlkemEncap h → v {}

@ __MlkemEncap_ptr MlkemEncap h → *MlkemEncapImpl { ^ ( shared_ptr [MlkemEncapImpl] . h ctl ) }

@ mlkem_ek MlkemKeys h__h → ( Vec u ) {
    : *MlkemKeysImpl h ( __MlkemKeys_ptr h__h )
    ^ . h ek
}

@ mlkem_dk MlkemKeys h__h → ( Vec u ) {
    : *MlkemKeysImpl h ( __MlkemKeys_ptr h__h )
    ^ . h dk
}

@ mlkem_ct MlkemEncap h__h → ( Vec u ) {
    : *MlkemEncapImpl h ( __MlkemEncap_ptr h__h )
    ^ . h ct
}

@ mlkem_ss MlkemEncap h__h → ( Vec u ) {
    : *MlkemEncapImpl h ( __MlkemEncap_ptr h__h )
    ^ . h ss
}

// Let go of `h` now rather than at the end of its owner's scope.
@ mlkem_keys_free sink MlkemKeys h → v {}

// Let go of `h` now rather than at the end of its owner's scope.
@ mlkem_encap_free sink MlkemEncap h → v {}

// ML-KEM.KeyGen_internal (Algorithm 16).
@ mlkem_keygen_derand i level ( Vec u ) d ( Vec u ) z → MlkemKeys {
    : MlkemParams prm ( __mlkem_params level )
    : ( Vec u ) ek ( vec_with_cap [u] ( mlkem_ek_len level ) )
    : ( Vec u ) dk ( vec_with_cap [u] ( mlkem_dk_len level ) )
    ( __kpke_keygen prm d ek dk )
    // dk ← dk_PKE ‖ ek ‖ H(ek) ‖ z
    ( bytes_extend_bytes dk ek )
    : ( Vec u ) hek ( sha3_256_pure ek )
    ( bytes_extend_bytes dk hek )
    ( bytes_extend_bytes dk z )
    ^ @ MlkemKeys { ( shared_new [MlkemKeysImpl] @ MlkemKeysImpl { ek dk } ) }
}

@ mlkem_keygen i level → MlkemKeys {
    : ( Vec u ) d ( rand_bytes 32 )
    : ( Vec u ) z ( rand_bytes 32 )
    : MlkemKeys h ( mlkem_keygen_derand level d z )
    ^ h
}

// ML-KEM.Encaps_internal (Algorithm 17). An ek that is not the level's
// mlkem_ek_len bytes, or an m that is not 32, gives an empty ct and ss
// (FIPS 203 §7.2's input check): the encryption reads both at their
// fixed sizes.
@ mlkem_encaps_derand i level ( Vec u ) ek ( Vec u ) m → MlkemEncap {
    ? | != ( vec_len [u] ek ) ( mlkem_ek_len level ) != ( vec_len [u] m ) 32 {
        ^ @ MlkemEncap { ( shared_new [MlkemEncapImpl] @ MlkemEncapImpl { ( vec_new [u] ) ( vec_new [u] ) } ) }
    } {}
    : MlkemParams prm ( __mlkem_params level )
    // (K, r) ← G(m ‖ H(ek))
    : ( Vec u ) gin ( vec_new [u] )
    ( bytes_extend_bytes gin m )
    : ( Vec u ) hek ( sha3_256_pure ek )
    ( bytes_extend_bytes gin hek )
    : ( Vec u ) g ( sha3_512_pure gin )
    : ( Vec u ) kk ( bytes_slice g 0 32 )
    : ( Vec u ) r ( bytes_slice g 32 64 )

    : ( Vec u ) ct ( vec_with_cap [u] ( mlkem_ct_len level ) )
    ( __kpke_encrypt prm ek m r ct )
    ^ @ MlkemEncap { ( shared_new [MlkemEncapImpl] @ MlkemEncapImpl { ct kk } ) }
}

@ mlkem_encaps i level ( Vec u ) ek → MlkemEncap {
    : ( Vec u ) m ( rand_bytes 32 )
    : MlkemEncap h ( mlkem_encaps_derand level ek m )
    ^ h
}

// ML-KEM.Decaps_internal (Algorithm 18).
//
// The Fujisaki-Okamoto transform: decrypt, re-encrypt with the derived
// randomness, and accept the derived key only if the ciphertext
// reproduces exactly. A mismatch returns J(z ‖ c) instead — a key that
// is deterministic, unpredictable to the sender, and indistinguishable
// from success. This *implicit rejection* is what makes ML-KEM
// CCA-secure, so the comparison and the select below must not leak
// which path ran: the compare is `constant_time_eq_vec` and the select
// is a byte mask.
//
// A dk or ct that is not the level's size (mlkem_dk_len, mlkem_ct_len)
// gives an empty Vec: FIPS 203 §7.3's input check, and the one input
// error implicit rejection cannot absorb — decryption reads both at
// their fixed sizes.
@ mlkem_decaps i level ( Vec u ) dk ( Vec u ) ct → ( Vec u ) {
    ? | != ( vec_len [u] dk ) ( mlkem_dk_len level ) != ( vec_len [u] ct ) ( mlkem_ct_len level ) { ^ ( vec_new [u] ) } {}
    : MlkemParams prm ( __mlkem_params level )
    : i k . prm k
    : ( Vec u ) dkpke ( bytes_slice dk 0 * 384 k )
    : ( Vec u ) ekpke ( bytes_slice dk * 384 k + * 768 k 32 )
    : ( Vec u ) hh ( bytes_slice dk + * 768 k 32 + * 768 k 64 )
    : ( Vec u ) z ( bytes_slice dk + * 768 k 64 + * 768 k 96 )

    : ( Vec u ) m ( __kpke_decrypt prm dkpke ct )

    : ( Vec u ) gin ( vec_new [u] )
    ( bytes_extend_bytes gin m )
    ( bytes_extend_bytes gin hh )
    : ( Vec u ) g ( sha3_512_pure gin )
    : ( Vec u ) kprime ( bytes_slice g 0 32 )
    : ( Vec u ) rprime ( bytes_slice g 32 64 )

    // K̄ ← J(z ‖ c, 32)
    : Sha3 j ( shake256_init )
    ( sha3_absorb j z )
    ( sha3_absorb j ct )
    : ( Vec u ) kbar ( sha3_squeeze j 32 )

    : ( Vec u ) ct2 ( vec_with_cap [u] ( mlkem_ct_len level ) )
    ( __kpke_encrypt prm ekpke m rprime ct2 )

    : b same ( constant_time_eq_vec ct ct2 )
    // Constant-time implicit rejection (FIPS 203 §7.3). The output is K'
    // when the re-encryption matched and K̄ otherwise, chosen WITHOUT a
    // data-dependent branch OR a data-dependent address.
    //
    // The mask is built arithmetically from `same`: `- same` is 0 when
    // false and -1 (all ones) when true, so `mask` is 0x00…00 / 0xFF…FF
    // with no `? … 255 0` ternary — that ternary lowered to a real
    // `br i1`+phi (nurlc emits a CFG diamond for every `?`), which LLVM
    // then rewrote at -O2 into a `cmov` selecting the SOURCE POINTER
    // (`kp` vs `bp`), leaking the secret through the load address.
    //
    // The per-byte combine is the conditional-swap idiom
    // `out = bp ^ (mask & (kp ^ bp))`: it reads BOTH operands every
    // iteration and never selects a pointer, so the emitted code is a
    // straight-line xor/and/xor over both buffers regardless of `same`.
    : i mask - 0 # i same
    : ( Vec u ) out ( vec_with_cap [u] 32 )
    : b _l ( vec_set_len [u] out 32 )
    : *u op ( vec_data [u] out )
    : *u kp ( vec_data [u] kprime )
    : *u bp ( vec_data [u] kbar )
    : ~ i i 0
    ~ < i 32 {
        : i kb # i . kp i
        : i bb # i . bp i
        = . op i # u ^^ bb & mask ^^ kb bb
        = i + i 1
    }

    ^ out
}
