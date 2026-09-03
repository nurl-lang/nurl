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
//   ( mlkem_keygen i level )                      → *MlkemKeys
//   ( mlkem_encaps i level ( Vec u ) ek )         → *MlkemEncap   (ct, ss)
//   ( mlkem_decaps i level ( Vec u ) dk
//                          ( Vec u ) ct )         → ( Vec u )     32-byte ss
//
// API — the deterministic forms, which take the randomness as an
// argument instead of drawing it. These exist because FIPS 203 defines
// the algorithms this way and NIST's ACVP test vectors exercise them;
// production callers want the three above.
//   ( mlkem_keygen_derand level ( Vec u ) d ( Vec u ) z ) → *MlkemKeys
//   ( mlkem_encaps_derand level ( Vec u ) ek ( Vec u ) m ) → *MlkemEncap
//
// Accessors and cleanup:
//   ( mlkem_ek *MlkemKeys ) ( mlkem_dk *MlkemKeys ) ( mlkem_keys_free … )
//   ( mlkem_ct *MlkemEncap ) ( mlkem_ss *MlkemEncap ) ( mlkem_encap_free … )
//   ( mlkem_ek_len level ) ( mlkem_dk_len level ) ( mlkem_ct_len level )
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

// Multiply two Montgomery-domain residues.
@ __fqmul i16 a i16 b → i16 {
    ^ ( __mont * # i32 a # i32 b )
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

// ── The number-theoretic transform ─────────────────────────────────
//
// q ≡ 1 (mod 256) would give a full 256-point transform, but 3329 only
// satisfies q ≡ 1 (mod 512) partially: there is no primitive 512th root
// of unity, so the transform stops one layer early. Seven layers leave
// 128 degree-1 polynomials rather than 256 constants, which is why
// multiplication in the NTT domain is `__basemul` below and not a
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
    // Layers 8, 4, 2: operands interleave below vector width — scalar,
    // same butterflies, same k walk.
    ~ >= len 2 {
        : ~ i start 0
        ~ < start 256 {
            : i16 zeta . zetas k
            = k + k 1
            : ~ i j start
            ~ < j + start len {
                : i16 t ( __fqmul zeta . r + off + j len )
                = . r + off + j len - . r + off j t
                = . r + off j + . r + off j t
                = j + j 1
            }
            = start + j len
        }
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
    : ~ i k 127
    // Narrow layers scalar, exactly as the forward transform.
    ~ <= len 8 {
        : ~ i start 0
        ~ < start 256 {
            : i16 zeta . zetas k
            = k - k 1
            : ~ i j start
            ~ < j + start len {
                : i16 t . r + off j
                = . r + off j ( __barrett + t . r + off + j len )
                = . r + off + j len - . r + off + j len t
                = . r + off + j len ( __fqmul zeta . r + off + j len )
                = j + j 1
            }
            = start + j len
        }
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

// Multiply two degree-1 polynomials modulo X² - zeta.
@ __basemul * i16 r i ri * i16 a i ai * i16 b i bi i16 zeta → v {
    : i16 a0 . a ai
    : i16 a1 . a + ai 1
    : i16 b0 . b bi
    : i16 b1 . b + bi 1
    : i16 c0 ( __fqmul ( __fqmul a1 b1 ) zeta )
    = . r ri + c0 ( __fqmul a0 b0 )
    = . r + ri 1 + ( __fqmul a0 b1 ) ( __fqmul a1 b0 )
}

simd @ __poly_basemul * i16 r i ro * i16 a i ao * i16 b i bo * i16 zetas → v {
    : ~ i i 0
    ~ < i 64 {
        : i16 z . zetas + 64 i
        ( __basemul r + ro * 4 i a + ao * 4 i b + bo * 4 i z )
        ( __basemul r + ro + * 4 i 2 a + ao + * 4 i 2 b + bo + * 4 i 2 - # i16 0 z )
        = i + i 1
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
@ __polyvec_basemul_acc * i16 r i ro * i16 a i ao * i16 b i bo i k * i16 zetas ( Vec i16 ) scratch → v {
    : *i16 t ( vec_data [i16] scratch )
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
    : *Sha3 xof ( shake128_init )
    ( sha3_absorb xof rho )
    : ( Vec u ) idx ( vec_new [u] )
    ( vec_push [u] idx # u x1 )
    ( vec_push [u] idx # u x2 )
    ( sha3_absorb xof idx )
    ( vec_free [u] idx )

    : ~ i ctr 0
    ~ < ctr 256 {
        : ( Vec u ) buf ( sha3_squeeze xof 168 )
        = ctr ( __rej_uniform r off ctr buf 168 )
        ( vec_free [u] buf )
    }
    ( sha3_free xof )
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
    : *Sha3x4 xof ( shake128x4_init )
    ( sha3x4_absorb xof rho rho rho rho )
    : ( Vec u ) x0 ( __mat_idx k transposed + c0 0 )
    : ( Vec u ) x1 ( __mat_idx k transposed + c0 1 )
    : ( Vec u ) x2 ( __mat_idx k transposed + c0 2 )
    : ( Vec u ) x3 ( __mat_idx k transposed + c0 3 )
    ( sha3x4_absorb xof x0 x1 x2 x3 )
    ( vec_free [u] x0 ) ( vec_free [u] x1 )
    ( vec_free [u] x2 ) ( vec_free [u] x3 )

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
    ( vec_free [u] b0 ) ( vec_free [u] b1 )
    ( vec_free [u] b2 ) ( vec_free [u] b3 )
    ( sha3x4_free xof )
}

// PRF_η (FIPS 203 §4.1): SHAKE256(s ‖ b, 64η).
@ __mlkem_prf ( Vec u ) seed i nonce i eta → ( Vec u ) {
    : *Sha3 h ( shake256_init )
    ( sha3_absorb h seed )
    : ( Vec u ) nb ( vec_new [u] )
    ( vec_push [u] nb # u nonce )
    ( sha3_absorb h nb )
    ( vec_free [u] nb )
    : ( Vec u ) out ( sha3_squeeze h * 64 eta )
    ( sha3_free h )
    ^ out
}

// Four PRF_η streams at once: same seed, four nonce bytes, 64·η bytes
// each appended to o0..o3. The callers hand out consecutive nonces in
// fixed-length batches (k or 2k of them), which is the equal-length
// lockstep the four-way sponge wants; a short batch clamps the spare
// lanes to the last real nonce and discards them.
@ __mlkem_prf_x4 ( Vec u ) seed i n0 i n1 i n2 i n3 i eta ( Vec u ) o0 ( Vec u ) o1 ( Vec u ) o2 ( Vec u ) o3 → v {
    : *Sha3x4 h ( shake256x4_init )
    ( sha3x4_absorb h seed seed seed seed )
    : ( Vec u ) b0 ( vec_new [u] ) ( vec_push [u] b0 # u n0 )
    : ( Vec u ) b1 ( vec_new [u] ) ( vec_push [u] b1 # u n1 )
    : ( Vec u ) b2 ( vec_new [u] ) ( vec_push [u] b2 # u n2 )
    : ( Vec u ) b3 ( vec_new [u] ) ( vec_push [u] b3 # u n3 )
    ( sha3x4_absorb h b0 b1 b2 b3 )
    ( vec_free [u] b0 ) ( vec_free [u] b1 ) ( vec_free [u] b2 ) ( vec_free [u] b3 )
    ( sha3x4_squeeze h * 64 eta o0 o1 o2 o3 )
    ( sha3x4_free h )
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
    ( vec_free [u] o0 ) ( vec_free [u] o1 )
    ( vec_free [u] o2 ) ( vec_free [u] o3 )
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
// ByteEncode_d / ByteDecode_d for d ∈ {1,4,5,10,11,12}, written once
// over a bit cursor rather than six times over hand-unrolled shifts.
// A 20-bit accumulator is enough: d never exceeds 12 and the loop
// drains to fewer than 8 bits before each new value goes in.

@ __byte_encode * i16 a i off i d ( Vec u ) out → v {
    // Exactly 32·d bytes per polynomial: reserve once, write raw. See
    // __bitpack in std/mldsa.nu for why — the same per-byte vec_push
    // cursor was the hot scalar loop of K-PKE encryption here.
    : i nbytes * 32 d
    : i base ( vec_len [u] out )
    ( vec_reserve [u] out nbytes )
    : b _l ( vec_set_len [u] out + base nbytes )
    : *u dst ( vec_data [u] out )
    : ~ i w base
    : ~ i acc 0
    : ~ i nbits 0
    : ~ i i 0
    ~ < i 256 {
        = acc | acc << & # i . a + off i - << 1 d 1 nbits
        = nbits + nbits d
        ~ >= nbits 8 {
            = . dst w # u & acc 255
            = w + w 1
            = acc >> acc 8
            = nbits - nbits 8
        }
        = i + i 1
    }
}

@ __byte_decode ( Vec u ) src i srcoff i d * i16 r i off → v {
    : *u sp ( vec_data [u] src )
    : ~ i acc 0
    : ~ i nbits 0
    : ~ i pos 0
    : ~ i i 0
    ~ < i 256 {
        ~ < nbits d {
            = acc | acc << # i . sp + srcoff pos nbits
            = nbits + nbits 8
            = pos + pos 1
        }
        = . r + off i # i16 & acc - << 1 d 1
        = acc >> acc d
        = nbits - nbits d
        = i + i 1
    }
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
@ __poly_compress * i16 a i off i d → v {
    : i mask - << 1 d 1
    : ~ i i 0
    ~ < i 256 {
        : i t # i ( __csubq_add . a + off i )
        = . a + off i # i16 & / + << t d 1664 3329 mask
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
@ __gen_matrix ( Vec i16 ) a ( Vec u ) rho i k b transposed * i16 _zetas → v {
    : *i16 ap ( vec_data [i16] a )
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
    : ( Vec i16 ) zt ( __mlkem_zetas )
    : *i16 zp ( vec_data [i16] zt )

    // (ρ, σ) ← G(d ‖ k)
    : ( Vec u ) gin ( vec_new [u] )
    ( bytes_extend_bytes gin d )
    ( vec_push [u] gin # u k )
    : ( Vec u ) g ( sha3_512_pure gin )
    ( vec_free [u] gin )
    : ( Vec u ) rho ( bytes_slice g 0 32 )
    : ( Vec u ) sigma ( bytes_slice g 32 64 )
    ( vec_free [u] g )

    : ( Vec i16 ) a ( __poly_zero * 256 * k k )
    ( __gen_matrix a rho k F zp )

    : ( Vec i16 ) s ( __poly_zero * 256 k )
    : ( Vec i16 ) e ( __poly_zero * 256 k )
    : *i16 sp ( vec_data [i16] s )
    : *i16 ep ( vec_data [i16] e )
    ( __cbd_batch sp sigma 0 k . prm eta1 )
    ( __cbd_batch ep sigma k k . prm eta1 )
    : ~ i i 0

    = i 0
    ~ < i k { ( __ntt sp * 256 i zp ) ( __poly_reduce sp * 256 i ) = i + i 1 }
    = i 0
    ~ < i k { ( __ntt ep * 256 i zp ) ( __poly_reduce ep * 256 i ) = i + i 1 }

    // t̂ ← Â ∘ ŝ + ê
    : ( Vec i16 ) t ( __poly_zero * 256 k )
    : ( Vec i16 ) scratch ( __poly_zero 256 )
    : *i16 tp ( vec_data [i16] t )
    : *i16 apz ( vec_data [i16] a )
    = i 0
    ~ < i k {
        ( __polyvec_basemul_acc tp * 256 i apz * 256 * i k sp 0 k zp scratch )
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

    ( vec_free [i16] scratch )
    ( vec_free [i16] t )
    ( vec_free [i16] e )
    ( vec_free [i16] s )
    ( vec_free [i16] a )
    ( vec_free [u] sigma )
    ( vec_free [u] rho )
    ( vec_free [i16] zt )
}

// K-PKE.Encrypt (Algorithm 14).
simd @ __kpke_encrypt MlkemParams prm ( Vec u ) ek ( Vec u ) m ( Vec u ) r ( Vec u ) ctout → v {
    : i k . prm k
    : ( Vec i16 ) zt ( __mlkem_zetas )
    : *i16 zp ( vec_data [i16] zt )

    : ( Vec i16 ) t ( __poly_zero * 256 k )
    : *i16 tp ( vec_data [i16] t )
    : ~ i i 0
    ~ < i k { ( __byte_decode ek * 384 i 12 tp * 256 i ) = i + i 1 }
    : ( Vec u ) rho ( bytes_slice ek * 384 k + * 384 k 32 )

    : ( Vec i16 ) at ( __poly_zero * 256 * k k )
    ( __gen_matrix at rho k T zp )
    : *i16 atp ( vec_data [i16] at )

    : ( Vec i16 ) y ( __poly_zero * 256 k )
    : ( Vec i16 ) e1 ( __poly_zero * 256 k )
    : ( Vec i16 ) e2 ( __poly_zero 256 )
    : *i16 yp ( vec_data [i16] y )
    : *i16 e1p ( vec_data [i16] e1 )
    : *i16 e2p ( vec_data [i16] e2 )
    ( __cbd_batch yp r 0 k . prm eta1 )
    ( __cbd_batch e1p r k k . prm eta2 )
    : ( Vec u ) prf2 ( __mlkem_prf r * 2 k . prm eta2 )
    ( __cbd e2p 0 prf2 . prm eta2 )
    ( vec_free [u] prf2 )

    = i 0
    ~ < i k { ( __ntt yp * 256 i zp ) ( __poly_reduce yp * 256 i ) = i + i 1 }

    // u ← NTT^-1(Â^T ∘ ŷ) + e1
    : ( Vec i16 ) uvec ( __poly_zero * 256 k )
    : ( Vec i16 ) scratch ( __poly_zero 256 )
    : *i16 up ( vec_data [i16] uvec )
    = i 0
    ~ < i k {
        ( __polyvec_basemul_acc up * 256 i atp * 256 * i k yp 0 k zp scratch )
        ( __invntt up * 256 i zp )
        ( __poly_add up * 256 i up * 256 i e1p * 256 i )
        ( __poly_reduce up * 256 i )
        = i + i 1
    }

    // v ← NTT^-1(t̂ᵀ ∘ ŷ) + e2 + Decompress1(m)
    : ( Vec i16 ) vpoly ( __poly_zero 256 )
    : *i16 vp ( vec_data [i16] vpoly )
    ( __polyvec_basemul_acc vp 0 tp 0 yp 0 k zp scratch )
    ( __invntt vp 0 zp )
    ( __poly_add vp 0 vp 0 e2p 0 )

    : ( Vec i16 ) mu ( __poly_zero 256 )
    : *i16 mup ( vec_data [i16] mu )
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

    ( vec_free [i16] mu )
    ( vec_free [i16] vpoly )
    ( vec_free [i16] scratch )
    ( vec_free [i16] uvec )
    ( vec_free [i16] e2 )
    ( vec_free [i16] e1 )
    ( vec_free [i16] y )
    ( vec_free [i16] at )
    ( vec_free [u] rho )
    ( vec_free [i16] t )
    ( vec_free [i16] zt )
}

// K-PKE.Decrypt (Algorithm 15) → the 32-byte message.
simd @ __kpke_decrypt MlkemParams prm ( Vec u ) dk ( Vec u ) ct → ( Vec u ) {
    : i k . prm k
    : ( Vec i16 ) zt ( __mlkem_zetas )
    : *i16 zp ( vec_data [i16] zt )

    : ( Vec i16 ) uvec ( __poly_zero * 256 k )
    : *i16 up ( vec_data [i16] uvec )
    : i ubytes * 32 . prm du
    : ~ i i 0
    ~ < i k {
        ( __byte_decode ct * ubytes i . prm du up * 256 i )
        ( __poly_decompress up * 256 i . prm du )
        = i + i 1
    }

    : ( Vec i16 ) vpoly ( __poly_zero 256 )
    : *i16 vp ( vec_data [i16] vpoly )
    ( __byte_decode ct * ubytes k . prm dv vp 0 )
    ( __poly_decompress vp 0 . prm dv )

    : ( Vec i16 ) s ( __poly_zero * 256 k )
    : *i16 sp ( vec_data [i16] s )
    = i 0
    ~ < i k { ( __byte_decode dk * 384 i 12 sp * 256 i ) = i + i 1 }

    = i 0
    ~ < i k { ( __ntt up * 256 i zp ) ( __poly_reduce up * 256 i ) = i + i 1 }

    : ( Vec i16 ) w ( __poly_zero 256 )
    : ( Vec i16 ) scratch ( __poly_zero 256 )
    : *i16 wp ( vec_data [i16] w )
    ( __polyvec_basemul_acc wp 0 sp 0 up 0 k zp scratch )
    ( __invntt wp 0 zp )
    ( __poly_sub wp 0 vp 0 wp 0 )
    ( __poly_reduce wp 0 )

    ( __poly_compress wp 0 1 )
    : ( Vec u ) m ( vec_new [u] )
    ( __byte_encode wp 0 1 m )

    ( vec_free [i16] scratch )
    ( vec_free [i16] w )
    ( vec_free [i16] s )
    ( vec_free [i16] vpoly )
    ( vec_free [i16] uvec )
    ( vec_free [i16] zt )
    ^ m
}

// ── ML-KEM ─────────────────────────────────────────────────────────

: MlkemKeys {
    ( Vec u ) ek
    ( Vec u ) dk
}

: MlkemEncap {
    ( Vec u ) ct
    ( Vec u ) ss
}

@ mlkem_ek * MlkemKeys h → ( Vec u ) { ^ . h ek }

@ mlkem_dk * MlkemKeys h → ( Vec u ) { ^ . h dk }

@ mlkem_ct * MlkemEncap h → ( Vec u ) { ^ . h ct }

@ mlkem_ss * MlkemEncap h → ( Vec u ) { ^ . h ss }

@ mlkem_keys_free * MlkemKeys h → v {
    ( vec_free [u] . h ek )
    ( vec_free [u] . h dk )
    ( nurl_free # s h )
}

@ mlkem_encap_free * MlkemEncap h → v {
    ( vec_free [u] . h ct )
    ( vec_free [u] . h ss )
    ( nurl_free # s h )
}

// ML-KEM.KeyGen_internal (Algorithm 16).
@ mlkem_keygen_derand i level ( Vec u ) d ( Vec u ) z → *MlkemKeys {
    : MlkemParams prm ( __mlkem_params level )
    : *MlkemKeys h # *MlkemKeys ( nurl_alloc Z MlkemKeys )
    : ( Vec u ) ek ( vec_with_cap [u] ( mlkem_ek_len level ) )
    : ( Vec u ) dk ( vec_with_cap [u] ( mlkem_dk_len level ) )
    ( __kpke_keygen prm d ek dk )
    // dk ← dk_PKE ‖ ek ‖ H(ek) ‖ z
    ( bytes_extend_bytes dk ek )
    : ( Vec u ) hek ( sha3_256_pure ek )
    ( bytes_extend_bytes dk hek )
    ( vec_free [u] hek )
    ( bytes_extend_bytes dk z )
    = . h ek ek
    = . h dk dk
    ^ h
}

@ mlkem_keygen i level → *MlkemKeys {
    : ( Vec u ) d ( rand_bytes 32 )
    : ( Vec u ) z ( rand_bytes 32 )
    : *MlkemKeys h ( mlkem_keygen_derand level d z )
    ( vec_free [u] z )
    ( vec_free [u] d )
    ^ h
}

// ML-KEM.Encaps_internal (Algorithm 17).
@ mlkem_encaps_derand i level ( Vec u ) ek ( Vec u ) m → *MlkemEncap {
    : MlkemParams prm ( __mlkem_params level )
    : *MlkemEncap h # *MlkemEncap ( nurl_alloc Z MlkemEncap )
    // (K, r) ← G(m ‖ H(ek))
    : ( Vec u ) gin ( vec_new [u] )
    ( bytes_extend_bytes gin m )
    : ( Vec u ) hek ( sha3_256_pure ek )
    ( bytes_extend_bytes gin hek )
    ( vec_free [u] hek )
    : ( Vec u ) g ( sha3_512_pure gin )
    ( vec_free [u] gin )
    : ( Vec u ) kk ( bytes_slice g 0 32 )
    : ( Vec u ) r ( bytes_slice g 32 64 )
    ( vec_free [u] g )

    : ( Vec u ) ct ( vec_with_cap [u] ( mlkem_ct_len level ) )
    ( __kpke_encrypt prm ek m r ct )
    ( vec_free [u] r )
    = . h ct ct
    = . h ss kk
    ^ h
}

@ mlkem_encaps i level ( Vec u ) ek → *MlkemEncap {
    : ( Vec u ) m ( rand_bytes 32 )
    : *MlkemEncap h ( mlkem_encaps_derand level ek m )
    ( vec_free [u] m )
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
@ mlkem_decaps i level ( Vec u ) dk ( Vec u ) ct → ( Vec u ) {
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
    ( vec_free [u] gin )
    : ( Vec u ) kprime ( bytes_slice g 0 32 )
    : ( Vec u ) rprime ( bytes_slice g 32 64 )
    ( vec_free [u] g )

    // K̄ ← J(z ‖ c, 32)
    : *Sha3 j ( shake256_init )
    ( sha3_absorb j z )
    ( sha3_absorb j ct )
    : ( Vec u ) kbar ( sha3_squeeze j 32 )
    ( sha3_free j )

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

    ( vec_free [u] ct2 )
    ( vec_free [u] kbar )
    ( vec_free [u] rprime )
    ( vec_free [u] kprime )
    ( vec_free [u] m )
    ( vec_free [u] z )
    ( vec_free [u] hh )
    ( vec_free [u] ekpke )
    ( vec_free [u] dkpke )
    ^ out
}
