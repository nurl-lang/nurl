// stdlib/std/mldsa.nu — ML-DSA (FIPS 204) in pure NURL.
//
// The post-quantum digital signature NIST standardised in August 2024,
// formerly CRYSTALS-Dilithium. The signing counterpart to std/mlkem.nu:
// ML-KEM replaces the key exchange, ML-DSA replaces the signature.
//
//   level  name          pk     sk     signature   classical analogue
//   44     ML-DSA-44   1312   2560        2420      AES-128
//   65     ML-DSA-65   1952   4032        3309      AES-192
//   87     ML-DSA-87   2592   4896        4627      AES-256
//
// API — the three operations:
//   ( mldsa_keygen i level )                        → *MldsaKeys
//   ( mldsa_sign i level ( Vec u ) sk
//                ( Vec u ) msg ( Vec u ) ctx )      → ( Vec u )  signature
//   ( mldsa_verify i level ( Vec u ) pk ( Vec u ) msg
//                  ( Vec u ) ctx ( Vec u ) sig )    → b
//
// `ctx` is the application context string of FIPS 204 §5.2 — up to 255
// bytes that bind a signature to its purpose, so a signature made for
// one protocol cannot be replayed into another. Pass an empty Vec when
// there is none. Signing is *hedged* by default: it draws 32 fresh
// random bytes, which keeps a fault or a repeated message from leaking
// the key the way deterministic signing can.
//
// API — the deterministic and internal forms, which FIPS 204 defines
// and NIST's ACVP vectors exercise. Production callers want the three
// above.
//   ( mldsa_keygen_derand level ( Vec u ) xi )      → *MldsaKeys
//   ( mldsa_sign_internal level ( Vec u ) sk
//         ( Vec u ) mprime ( Vec u ) rnd )          → ( Vec u )
//   ( mldsa_verify_internal level ( Vec u ) pk
//         ( Vec u ) mprime ( Vec u ) sig )          → b
//
// Accessors, sizes and cleanup:
//   ( mldsa_pk *MldsaKeys ) ( mldsa_sk *MldsaKeys ) ( mldsa_keys_free … )
//   ( mldsa_pk_len level ) ( mldsa_sk_len level ) ( mldsa_sig_len level )
//
// ── On timing ──────────────────────────────────────────────────────
//
// Signing is a rejection loop: it samples a masking vector, forms a
// candidate, and starts over if any coefficient falls outside the
// bounds that would leak the key. So *the number of iterations depends
// on the key and the message*, and signing time is variable by
// construction — that is the design of the scheme, not a defect, and
// FIPS 204 specifies it. What must not vary with the secret is the work
// inside an iteration, and it does not: the bound checks accumulate
// over every coefficient rather than exiting early, and the arithmetic
// is straight-line. Verification is not secret-dependent at all.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha3.nu`
$ `stdlib/std/hash_sha3x4.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hash_sha512.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/subtle.nu`

// ── Parameters ─────────────────────────────────────────────────────
//
// q = 8380417 = 2^23 − 2^13 + 1 and n = 256 are fixed; d = 13 is the
// number of low bits of t dropped from the public key. The level
// selects the module dimensions (k, l), the noise width η, the
// challenge weight τ, the mask range γ1, the rounding modulus γ2, the
// hint budget ω and the commitment-hash length λ/4.

: MldsaParams {
    i k
    i l
    i eta
    i tau
    i gamma1
    i gamma2
    i omega
    i lam  // c~ length in bytes
    i sbits  // bits per s1/s2 coefficient
    i zbits  // bits per z coefficient
    i wbits  // bits per w1 coefficient
}

@ __mldsa_params i level → MldsaParams {
    // gamma2 = (q-1)/88 = 95232 for level 44, (q-1)/32 = 261888 otherwise
    ? == level 65 { ^ @ MldsaParams { 6 5 4 49 524288 261888 55 48 4 20 4 } } {}
    ? == level 87 { ^ @ MldsaParams { 8 7 2 60 524288 261888 75 64 3 20 4 } } {}
    ^ @ MldsaParams { 4 4 2 39 131072 95232 80 32 3 18 6 }
}

@ mldsa_pk_len i level → i {
    : MldsaParams p ( __mldsa_params level )
    ^ + 32 * 320 . p k
}

@ mldsa_sk_len i level → i {
    : MldsaParams p ( __mldsa_params level )
    ^ + + 128 * * 32 . p sbits + . p k . p l * 416 . p k
}

@ mldsa_sig_len i level → i {
    : MldsaParams p ( __mldsa_params level )
    ^ + + . p lam * * 32 . p zbits . p l + . p omega . p k
}

// Where the hint starts inside a signature, and how much room it has.
//
// A signature is `c~ ‖ BitPack(z) ‖ HintBitPack(h)`, and the hint is the
// tail: `omega` index bytes followed by `k` running totals. The layout
// is public — it is fixed by the parameter set, not by the key — so
// anything that inspects or validates a signature's encoding can ask
// for it rather than recompute the arithmetic.
@ mldsa_hint_offset i level → i {
    : MldsaParams p ( __mldsa_params level )
    ^ + . p lam * * 32 . p zbits . p l
}

@ mldsa_omega i level → i {
    : MldsaParams p ( __mldsa_params level )
    ^ . p omega
}

@ mldsa_module_rank i level → i {
    : MldsaParams p ( __mldsa_params level )
    ^ . p k
}

// ── Arithmetic in Z_q, q = 8380417 ─────────────────────────────────
//
// Coefficients are i32; products widen to i64 (`i`) for the length of
// the multiply. This is the same shape as ML-KEM's i16 arithmetic one
// width up.

// Montgomery reduction: a·2^-32 mod q. QINV = q^-1 mod 2^32 = 58728449;
// the i32 truncation is what extracts the low half of the product.
@ __md_mont i a → i32 {
    : i32 t * # i32 a # i32 58728449
    ^ # i32 >> - a * # i t # i 8380417 # i 32
}

// a mod± q for |a| ≤ 2^31 − 2^22 − 1.
@ __reduce32 i32 a → i32 {
    : i32 t >> + a # i32 4194304 # i32 23
    ^ - a * t # i32 8380417
}

// Add q if negative, giving a representative in [0, q). The mask is an
// arithmetic shift rather than a comparison, so no branch depends on a
// coefficient's sign.
@ __caddq i32 a → i32 {
    ^ + a & >> a # i32 31 # i32 8380417
}

@ __md_fqmul i32 a i32 b → i32 {
    ^ ( __md_mont * # i a # i b )
}

// r mod± m, in (−m/2, m/2].
@ __modpm i r i m → i {
    : ~ i x % r m
    ? < x 0 { = x + x m } {}
    ? > x / m 2 { = x - x m } {}
    ^ x
}

// ζ^brv8(i)·2^32 mod q for i in 0..255 — the NTT twiddle factors in
// Montgomery domain and bit-reversed order, centred on zero. Entry 0 is
// never read (the transform starts at index 1) and is held at zero, as
// the reference implementation does.
@ __mldsa_zetas → ( Vec i32 ) {
    : ( Vec i32 ) v ( vec_with_cap [i32] 256 )
    : b _l ( vec_set_len [i32] v 256 )
    : *i32 p ( vec_data [i32] v )
    = . p 0 # i32 0 = . p 1 # i32 25847 = . p 2 # i32 -2608894 = . p 3 # i32 -518909
    = . p 4 # i32 237124 = . p 5 # i32 -777960 = . p 6 # i32 -876248 = . p 7 # i32 466468
    = . p 8 # i32 1826347 = . p 9 # i32 2353451 = . p 10 # i32 -359251 = . p 11 # i32 -2091905
    = . p 12 # i32 3119733 = . p 13 # i32 -2884855 = . p 14 # i32 3111497 = . p 15 # i32 2680103
    = . p 16 # i32 2725464 = . p 17 # i32 1024112 = . p 18 # i32 -1079900 = . p 19 # i32 3585928
    = . p 20 # i32 -549488 = . p 21 # i32 -1119584 = . p 22 # i32 2619752 = . p 23 # i32 -2108549
    = . p 24 # i32 -2118186 = . p 25 # i32 -3859737 = . p 26 # i32 -1399561 = . p 27 # i32 -3277672
    = . p 28 # i32 1757237 = . p 29 # i32 -19422 = . p 30 # i32 4010497 = . p 31 # i32 280005
    = . p 32 # i32 2706023 = . p 33 # i32 95776 = . p 34 # i32 3077325 = . p 35 # i32 3530437
    = . p 36 # i32 -1661693 = . p 37 # i32 -3592148 = . p 38 # i32 -2537516 = . p 39 # i32 3915439
    = . p 40 # i32 -3861115 = . p 41 # i32 -3043716 = . p 42 # i32 3574422 = . p 43 # i32 -2867647
    = . p 44 # i32 3539968 = . p 45 # i32 -300467 = . p 46 # i32 2348700 = . p 47 # i32 -539299
    = . p 48 # i32 -1699267 = . p 49 # i32 -1643818 = . p 50 # i32 3505694 = . p 51 # i32 -3821735
    = . p 52 # i32 3507263 = . p 53 # i32 -2140649 = . p 54 # i32 -1600420 = . p 55 # i32 3699596
    = . p 56 # i32 811944 = . p 57 # i32 531354 = . p 58 # i32 954230 = . p 59 # i32 3881043
    = . p 60 # i32 3900724 = . p 61 # i32 -2556880 = . p 62 # i32 2071892 = . p 63 # i32 -2797779
    = . p 64 # i32 -3930395 = . p 65 # i32 -1528703 = . p 66 # i32 -3677745 = . p 67 # i32 -3041255
    = . p 68 # i32 -1452451 = . p 69 # i32 3475950 = . p 70 # i32 2176455 = . p 71 # i32 -1585221
    = . p 72 # i32 -1257611 = . p 73 # i32 1939314 = . p 74 # i32 -4083598 = . p 75 # i32 -1000202
    = . p 76 # i32 -3190144 = . p 77 # i32 -3157330 = . p 78 # i32 -3632928 = . p 79 # i32 126922
    = . p 80 # i32 3412210 = . p 81 # i32 -983419 = . p 82 # i32 2147896 = . p 83 # i32 2715295
    = . p 84 # i32 -2967645 = . p 85 # i32 -3693493 = . p 86 # i32 -411027 = . p 87 # i32 -2477047
    = . p 88 # i32 -671102 = . p 89 # i32 -1228525 = . p 90 # i32 -22981 = . p 91 # i32 -1308169
    = . p 92 # i32 -381987 = . p 93 # i32 1349076 = . p 94 # i32 1852771 = . p 95 # i32 -1430430
    = . p 96 # i32 -3343383 = . p 97 # i32 264944 = . p 98 # i32 508951 = . p 99 # i32 3097992
    = . p 100 # i32 44288 = . p 101 # i32 -1100098 = . p 102 # i32 904516 = . p 103 # i32 3958618
    = . p 104 # i32 -3724342 = . p 105 # i32 -8578 = . p 106 # i32 1653064 = . p 107 # i32 -3249728
    = . p 108 # i32 2389356 = . p 109 # i32 -210977 = . p 110 # i32 759969 = . p 111 # i32 -1316856
    = . p 112 # i32 189548 = . p 113 # i32 -3553272 = . p 114 # i32 3159746 = . p 115 # i32 -1851402
    = . p 116 # i32 -2409325 = . p 117 # i32 -177440 = . p 118 # i32 1315589 = . p 119 # i32 1341330
    = . p 120 # i32 1285669 = . p 121 # i32 -1584928 = . p 122 # i32 -812732 = . p 123 # i32 -1439742
    = . p 124 # i32 -3019102 = . p 125 # i32 -3881060 = . p 126 # i32 -3628969 = . p 127 # i32 3839961
    = . p 128 # i32 2091667 = . p 129 # i32 3407706 = . p 130 # i32 2316500 = . p 131 # i32 3817976
    = . p 132 # i32 -3342478 = . p 133 # i32 2244091 = . p 134 # i32 -2446433 = . p 135 # i32 -3562462
    = . p 136 # i32 266997 = . p 137 # i32 2434439 = . p 138 # i32 -1235728 = . p 139 # i32 3513181
    = . p 140 # i32 -3520352 = . p 141 # i32 -3759364 = . p 142 # i32 -1197226 = . p 143 # i32 -3193378
    = . p 144 # i32 900702 = . p 145 # i32 1859098 = . p 146 # i32 909542 = . p 147 # i32 819034
    = . p 148 # i32 495491 = . p 149 # i32 -1613174 = . p 150 # i32 -43260 = . p 151 # i32 -522500
    = . p 152 # i32 -655327 = . p 153 # i32 -3122442 = . p 154 # i32 2031748 = . p 155 # i32 3207046
    = . p 156 # i32 -3556995 = . p 157 # i32 -525098 = . p 158 # i32 -768622 = . p 159 # i32 -3595838
    = . p 160 # i32 342297 = . p 161 # i32 286988 = . p 162 # i32 -2437823 = . p 163 # i32 4108315
    = . p 164 # i32 3437287 = . p 165 # i32 -3342277 = . p 166 # i32 1735879 = . p 167 # i32 203044
    = . p 168 # i32 2842341 = . p 169 # i32 2691481 = . p 170 # i32 -2590150 = . p 171 # i32 1265009
    = . p 172 # i32 4055324 = . p 173 # i32 1247620 = . p 174 # i32 2486353 = . p 175 # i32 1595974
    = . p 176 # i32 -3767016 = . p 177 # i32 1250494 = . p 178 # i32 2635921 = . p 179 # i32 -3548272
    = . p 180 # i32 -2994039 = . p 181 # i32 1869119 = . p 182 # i32 1903435 = . p 183 # i32 -1050970
    = . p 184 # i32 -1333058 = . p 185 # i32 1237275 = . p 186 # i32 -3318210 = . p 187 # i32 -1430225
    = . p 188 # i32 -451100 = . p 189 # i32 1312455 = . p 190 # i32 3306115 = . p 191 # i32 -1962642
    = . p 192 # i32 -1279661 = . p 193 # i32 1917081 = . p 194 # i32 -2546312 = . p 195 # i32 -1374803
    = . p 196 # i32 1500165 = . p 197 # i32 777191 = . p 198 # i32 2235880 = . p 199 # i32 3406031
    = . p 200 # i32 -542412 = . p 201 # i32 -2831860 = . p 202 # i32 -1671176 = . p 203 # i32 -1846953
    = . p 204 # i32 -2584293 = . p 205 # i32 -3724270 = . p 206 # i32 594136 = . p 207 # i32 -3776993
    = . p 208 # i32 -2013608 = . p 209 # i32 2432395 = . p 210 # i32 2454455 = . p 211 # i32 -164721
    = . p 212 # i32 1957272 = . p 213 # i32 3369112 = . p 214 # i32 185531 = . p 215 # i32 -1207385
    = . p 216 # i32 -3183426 = . p 217 # i32 162844 = . p 218 # i32 1616392 = . p 219 # i32 3014001
    = . p 220 # i32 810149 = . p 221 # i32 1652634 = . p 222 # i32 -3694233 = . p 223 # i32 -1799107
    = . p 224 # i32 -3038916 = . p 225 # i32 3523897 = . p 226 # i32 3866901 = . p 227 # i32 269760
    = . p 228 # i32 2213111 = . p 229 # i32 -975884 = . p 230 # i32 1717735 = . p 231 # i32 472078
    = . p 232 # i32 -426683 = . p 233 # i32 1723600 = . p 234 # i32 -1803090 = . p 235 # i32 1910376
    = . p 236 # i32 -1667432 = . p 237 # i32 -1104333 = . p 238 # i32 -260646 = . p 239 # i32 -3833893
    = . p 240 # i32 -2939036 = . p 241 # i32 -2235985 = . p 242 # i32 -420899 = . p 243 # i32 -2286327
    = . p 244 # i32 183443 = . p 245 # i32 -976891 = . p 246 # i32 1612842 = . p 247 # i32 -3545687
    = . p 248 # i32 -554416 = . p 249 # i32 3919660 = . p 250 # i32 -48306 = . p 251 # i32 -1362209
    = . p 252 # i32 3937738 = . p 253 # i32 1400424 = . p 254 # i32 -846154 = . p 255 # i32 1976782
    ^ v
}

// ── The number-theoretic transform ─────────────────────────────────
//
// Unlike ML-KEM's, this one is complete: q − 1 is divisible by 512, so
// a primitive 512th root of unity exists and the transform runs all
// eight layers down to 256 constants. Multiplication in the NTT domain
// is therefore an ordinary pointwise product, not a degree-1 basemul.

@ __md_ntt * i32 r i off * i32 zetas → v {
    : ~ i m 0
    : ~ i len 128
    ~ >= len 1 {
        : ~ i start 0
        ~ < start 256 {
            = m + m 1
            : i32 zeta . zetas m
            : ~ i j start
            ~ < j + start len {
                : i32 t ( __md_fqmul zeta . r + off + j len )
                = . r + off + j len - . r + off j t
                = . r + off j + . r + off j t
                = j + j 1
            }
            = start + j len
        }
        = len >> len 1
    }
}

// The inverse transform, leaving the result in Montgomery domain.
// f = 2^64 / 256 mod q = 41978 folds the 1/256 scaling and the
// Montgomery factor into one final multiply.
@ __md_invntt * i32 r i off * i32 zetas → v {
    : ~ i m 256
    : ~ i len 1
    ~ < len 256 {
        : ~ i start 0
        ~ < start 256 {
            = m - m 1
            : i32 zeta - # i32 0 . zetas m
            : ~ i j start
            ~ < j + start len {
                : i32 t . r + off j
                = . r + off j + t . r + off + j len
                = . r + off + j len - t . r + off + j len
                = . r + off + j len ( __md_fqmul zeta . r + off + j len )
                = j + j 1
            }
            = start + j len
        }
        = len << len 1
    }
    : ~ i i 0
    ~ < i 256 {
        = . r + off i ( __md_fqmul . r + off i # i32 41978 )
        = i + i 1
    }
}

// ── Polynomial helpers ─────────────────────────────────────────────

@ __md_poly_zero i n → ( Vec i32 ) {
    : i m ? > n 0 n 1
    : ( Vec i32 ) v ( vec_with_cap [i32] m )
    : b _l ( vec_set_len [i32] v m )
    : *i32 p ( vec_data [i32] v )
    : ~ i i 0
    ~ < i m { = . p i # i32 0 = i + i 1 }
    ^ v
}

@ __md_poly_add * i32 r i ro * i32 a i ao * i32 b i bo → v {
    : ~ i i 0
    ~ < i 256 { = . r + ro i + . a + ao i . b + bo i = i + i 1 }
}

@ __md_poly_sub * i32 r i ro * i32 a i ao * i32 b i bo → v {
    : ~ i i 0
    ~ < i 256 { = . r + ro i - . a + ao i . b + bo i = i + i 1 }
}

@ __md_poly_reduce * i32 r i off → v {
    : ~ i i 0
    ~ < i 256 { = . r + off i ( __reduce32 . r + off i ) = i + i 1 }
}

@ __poly_caddq * i32 r i off → v {
    : ~ i i 0
    ~ < i 256 { = . r + off i ( __caddq . r + off i ) = i + i 1 }
}

@ __poly_shiftl * i32 r i off → v {
    : ~ i i 0
    ~ < i 256 { = . r + off i << . r + off i # i32 13 = i + i 1 }
}

@ __poly_pointwise * i32 r i ro * i32 a i ao * i32 b i bo → v {
    : ~ i i 0
    ~ < i 256 {
        = . r + ro i ( __md_fqmul . a + ao i . b + bo i )
        = i + i 1
    }
}

// Accumulate Σ a_j ∘ b_j over l polynomials, in NTT domain.
@ __polyvec_pointwise_acc * i32 r i ro * i32 a i ao * i32 b i bo i n ( Vec i32 ) scratch → v {
    : *i32 t ( vec_data [i32] scratch )
    ( __poly_pointwise r ro a ao b bo )
    : ~ i i 1
    ~ < i n {
        ( __poly_pointwise t 0 a + ao * 256 i b + bo * 256 i )
        ( __md_poly_add r ro r ro t 0 )
        = i + i 1
    }
}

// ‖a‖∞ < bound, over the centred representatives.
//
// The whole polynomial is scanned even once a coefficient has failed:
// an early return would make the loop's length depend on where the
// out-of-range coefficient sits, which is secret.
@ __poly_chknorm * i32 a i off i bound → b {
    : ~ i bad 0
    : ~ i i 0
    ~ < i 256 {
        : i32 x . a + off i
        // |x| without a branch: t = x - 2·(x>>31 & x) is |x| for the
        // centred range this is called on.
        : i32 s >> x # i32 31
        : i32 t - x & s << x # i32 1
        = bad | bad ? >= # i t bound 1 0
        = i + i 1
    }
    ^ == bad 0
}

// ── Rounding ───────────────────────────────────────────────────────

// Power2Round: split r into high bits r1 and centred low bits r0 with
// r = r1·2^13 + r0.
//
// Division-free. The spec states these in terms of `mod±`, which reads
// as a remainder; every one of them is a shift and a mask on a power of
// two, or a reciprocal multiply where the modulus is not one. That
// matters here because rounding runs 256·k times per signing attempt
// and signing retries several times: a 25-cycle `idiv` in that loop
// costs more than the polynomial arithmetic around it.
@ __poly_power2round * i32 a1 i o1 * i32 a0 i o0 * i32 a i oa → v {
    : ~ i i 0
    ~ < i 256 {
        : i32 x ( __caddq . a + oa i )
        : i32 t1 >> + x # i32 4095 # i32 13
        = . a1 + o1 i t1
        = . a0 + o0 i - x << t1 # i32 13
        = i + i 1
    }
}

// Decompose: r = r1·2γ2 + r0 with r0 centred, except at the wrap point
// where r1 is forced to 0 — the case that makes HighBits take only
// (q−1)/(2γ2) distinct values.
//
// The two parameter sets need different reciprocals, so the branch is
// hoisted out of the loop. 1025/2^22 approximates 1/(2·261888) and
// 11275/2^24 approximates 1/(2·95232), each chosen so the truncating
// shift lands on the exact quotient over the whole input range. The
// wrap case falls out of the arithmetic rather than needing a compare:
// for γ2=(q−1)/32 the mask `& 15` wraps 16 to 0, and for (q−1)/88 the
// `^` folds 44 back to 0.
@ __poly_decompose * i32 a1 i o1 * i32 a0 i o0 * i32 a i oa i g2 → v {
    : ~ i i 0
    ? == g2 261888 {
        ~ < i 256 {
            : i32 x ( __caddq . a + oa i )
            : ~ i32 t1 >> + x # i32 127 # i32 7
            = t1 & >> + * t1 # i32 1025 # i32 2097152 # i32 22 # i32 15
            : ~ i32 t0 - x * t1 # i32 523776
            = t0 - t0 & >> - # i32 4190208 t0 # i32 31 # i32 8380417
            = . a1 + o1 i t1
            = . a0 + o0 i t0
            = i + i 1
        }
    } {
        ~ < i 256 {
            : i32 x ( __caddq . a + oa i )
            : ~ i32 t1 >> + x # i32 127 # i32 7
            = t1 >> + * t1 # i32 11275 # i32 8388608 # i32 24
            = t1 ^^ t1 & >> - # i32 43 t1 # i32 31 t1
            : ~ i32 t0 - x * t1 # i32 190464
            = t0 - t0 & >> - # i32 4190208 t0 # i32 31 # i32 8380417
            = . a1 + o1 i t1
            = . a0 + o0 i t0
            = i + i 1
        }
    }
}

// MakeHint, from the decomposed pair rather than from two HighBits
// calls.
//
// The spec writes it as `HighBits(r) ≠ HighBits(r + z)`, which is two
// decompositions per coefficient. Given `a0` — the low part after the
// signer has already folded in −⟨⟨c·s2⟩⟩ and ⟨⟨c·t0⟩⟩ — and `a1`, the
// high part of w, the same predicate is a range test on a0 alone.
@ __makehint i32 a0 i32 a1 i g2 → i {
    ^ ? | | > # i a0 g2 < # i a0 - 0 g2 & == # i a0 - 0 g2 != # i a1 0 1 0
}

// UseHint: recover HighBits(r + z) from HighBits(r) and one bit.
@ __usehint i h i r i g2 → i {
    : i32 x ( __caddq # i32 r )
    : ~ i32 t1 >> + x # i32 127 # i32 7
    : ~ i32 t0 # i32 0
    ? == g2 261888 {
        = t1 & >> + * t1 # i32 1025 # i32 2097152 # i32 22 # i32 15
        = t0 - x * t1 # i32 523776
    } {
        = t1 >> + * t1 # i32 11275 # i32 8388608 # i32 24
        = t1 ^^ t1 & >> - # i32 43 t1 # i32 31 t1
        = t0 - x * t1 # i32 190464
    }
    = t0 - t0 & >> - # i32 4190208 t0 # i32 31 # i32 8380417
    ? == h 0 { ^ # i t1 } {}
    ? == g2 261888 {
        ? > # i t0 0 { ^ & + # i t1 1 15 } {}
        ^ & - # i t1 1 15
    } {}
    ? > # i t0 0 { ^ ? == # i t1 43 0 + # i t1 1 } {}
    ^ ? == # i t1 0 43 - # i t1 1
}

// ── Bit packing ────────────────────────────────────────────────────
//
// SimpleBitPack writes coefficients as they are; BitPack writes b − x,
// which maps a centred range onto an unsigned one. Both go through one
// bit cursor rather than a hand-unrolled routine per width — ML-DSA
// uses 3, 4, 6, 10, 13, 18 and 20 bits in different places.

@ __simple_bitpack * i32 a i off i bits ( Vec u ) out → v {
    : i mask - << 1 bits 1
    : ~ i acc 0
    : ~ i nb 0
    : ~ i i 0
    ~ < i 256 {
        = acc | acc << & # i . a + off i mask nb
        = nb + nb bits
        ~ >= nb 8 {
            ( vec_push [u] out # u & acc 255 )
            = acc >> acc 8
            = nb - nb 8
        }
        = i + i 1
    }
}

@ __simple_bitunpack ( Vec u ) src i soff i bits * i32 r i off → v {
    : *u sp ( vec_data [u] src )
    : i mask - << 1 bits 1
    : ~ i acc 0
    : ~ i nb 0
    : ~ i pos 0
    : ~ i i 0
    ~ < i 256 {
        ~ < nb bits {
            = acc | acc << # i . sp + soff pos nb
            = nb + nb 8
            = pos + pos 1
        }
        = . r + off i # i32 & acc mask
        = acc >> acc bits
        = nb - nb bits
        = i + i 1
    }
}

// BitPack(w, a, b): each coefficient stored as b − w[i].
@ __bitpack * i32 a i off i bits i b ( Vec u ) out → v {
    : i mask - << 1 bits 1
    : ~ i acc 0
    : ~ i nb 0
    : ~ i i 0
    ~ < i 256 {
        = acc | acc << & - b # i . a + off i mask nb
        = nb + nb bits
        ~ >= nb 8 {
            ( vec_push [u] out # u & acc 255 )
            = acc >> acc 8
            = nb - nb 8
        }
        = i + i 1
    }
}

@ __bitunpack ( Vec u ) src i soff i bits i b * i32 r i off → v {
    : *u sp ( vec_data [u] src )
    : i mask - << 1 bits 1
    : ~ i acc 0
    : ~ i nb 0
    : ~ i pos 0
    : ~ i i 0
    ~ < i 256 {
        ~ < nb bits {
            = acc | acc << # i . sp + soff pos nb
            = nb + nb 8
            = pos + pos 1
        }
        = . r + off i # i32 - b & acc mask
        = acc >> acc bits
        = nb - nb bits
        = i + i 1
    }
}

// ── Sampling ───────────────────────────────────────────────────────

// One SHAKE stream, pulled a block at a time.
//
// A block is squeezed and consumed; the sponge is one continuous
// stream, so refilling costs one permutation rather than a permutation
// per candidate.

// RejNTTPoly (FIPS 204 Algorithm 30): coefficients uniform in [0, q)
// from SHAKE128(ρ ‖ s ‖ r), three bytes per candidate with the top bit
// masked off. Rejection depends only on ρ, which is public.
// Rejection sampling over one squeezed block (FIPS 204 Algorithm 30).
// Three bytes give one 23-bit candidate; anything at or above q is
// dropped. Shared by the one-at-a-time and four-at-a-time samplers so
// the two cannot disagree about what a block yields.
@ __rej_uniform_q * i32 r i off i ctr ( Vec u ) buf i blen → i {
    : *u bp ( vec_data [u] buf )
    : ~ i c ctr
    : ~ i pos 0
    ~ & < c 256 <= + pos 3 blen {
        : i z | | # i . bp pos << # i . bp + pos 1 8 << & # i . bp + pos 2 127 16
        = pos + pos 3
        ? < z 8380417 {
            = . r + off c # i32 z
            = c + c 1
        } {}
    }
    ^ c
}

@ __poly_uniform * i32 r i off ( Vec u ) rho i x1 i x2 → v {
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
        = ctr ( __rej_uniform_q r off ctr buf 168 )
        ( vec_free [u] buf )
    }
    ( sha3_free xof )
}

// The two index bytes of cell `c` of the k×l matrix: ρ‖s‖r, column
// before row, as FIPS 204 §3.7 writes ExpandA.
@ __md_a_idx i l i c → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u % c l )
    ( vec_push [u] v # u / c l )
    ^ v
}

// Four cells of Â at once, on the four-way sponge.
//
// Same shape as ML-KEM's matrix: independent SHAKE128 streams differing
// only in two trailing bytes, and rejection makes each consume a
// different number of them, so the loop runs until the last lane has
// its 256 coefficients. See stdlib/std/hash_sha3x4.nu.
@ __poly_uniform_x4 * i32 r ( Vec u ) rho i l i c0 → v {
    : *Sha3x4 xof ( shake128x4_init )
    ( sha3x4_absorb xof rho rho rho rho )
    : ( Vec u ) x0 ( __md_a_idx l + c0 0 )
    : ( Vec u ) x1 ( __md_a_idx l + c0 1 )
    : ( Vec u ) x2 ( __md_a_idx l + c0 2 )
    : ( Vec u ) x3 ( __md_a_idx l + c0 3 )
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
            = n0 ( __rej_uniform_q r * 256 + c0 0 n0 b0 168 )
            = n1 ( __rej_uniform_q r * 256 + c0 1 n1 b1 168 )
            = n2 ( __rej_uniform_q r * 256 + c0 2 n2 b2 168 )
            = n3 ( __rej_uniform_q r * 256 + c0 3 n3 b3 168 )
        }
    }
    ( vec_free [u] b0 ) ( vec_free [u] b1 )
    ( vec_free [u] b2 ) ( vec_free [u] b3 )
    ( sha3x4_free xof )
}

// ExpandA (FIPS 204 §3.7): the whole k×l matrix from ρ.
//
// One function, three callers — keygen, sign and verify each built the
// same nested loop, and a matrix that disagreed between signing and
// verifying would be a silent interoperability failure rather than a
// crash. Cell c is row c/l, column c%l, which walks the same cells in
// the same order and writes the same offsets the loops did.
//
// k·l is 16, 30 or 56, so ML-DSA-65 leaves two cells for the scalar
// sampler after the groups of four.
@ __md_expand_a ( Vec i32 ) a ( Vec u ) rho i k i l → v {
    : *i32 ap ( vec_data [i32] a )
    : i n * k l
    : ~ i c 0
    ~ <= + c 4 n {
        ( __poly_uniform_x4 ap rho l c )
        = c + c 4
    }
    ~ < c n {
        ( __poly_uniform ap * 256 c rho % c l / c l )
        = c + c 1
    }
}

// CoeffFromHalfByte (Algorithm 15) — the η-bounded sampler's inner map.
// Returns 100 for a rejected nibble (outside any legal coefficient).
@ __coeff_from_halfbyte i b i eta → i {
    ? == eta 2 {
        ? < b 15 { ^ - 2 % b 5 } {}
        ^ 100
    } {}
    ? < b 9 { ^ - 4 b } {}
    ^ 100
}

// RejBoundedPoly (Algorithm 31): coefficients in [−η, η] from
// SHAKE256(ρ' ‖ nonce), two candidates per byte.
// Four RejBoundedPoly streams at once (nonces n0..n0+3, same ρ').
// Rejection makes the lanes consume different amounts, so the group
// squeezes until its last lane has 256 coefficients — the same shape
// as __poly_uniform_x4, with the nibble sampler in place of the
// 24-bit one. Writes polynomial g+w at r[off0 + (g+w)·256].
@ __eta_reject * i32 r i off i ctr ( Vec u ) buf i blen i eta → i {
    : *u bp ( vec_data [u] buf )
    : ~ i c ctr
    : ~ i pos 0
    ~ & < c 256 < pos blen {
        : i byte # i . bp pos
        = pos + pos 1
        : i c0 ( __coeff_from_halfbyte & byte 15 eta )
        ? & != c0 100 < c 256 {
            = . r + off c # i32 c0
            = c + c 1
        } {}
        : i c1 ( __coeff_from_halfbyte >> byte 4 eta )
        ? & != c1 100 < c 256 {
            = . r + off c # i32 c1
            = c + c 1
        } {}
    }
    ^ c
}

@ __uniform_eta_x4 * i32 r i off0 ( Vec u ) rhop i n0 i count i eta → v {
    : ~ i g 0
    ~ < g count {
        : i m1 ? < + g 1 count + g 1 - count 1
        : i m2 ? < + g 2 count + g 2 - count 1
        : i m3 ? < + g 3 count + g 3 - count 1
        : *Sha3x4 h ( shake256x4_init )
        ( sha3x4_absorb h rhop rhop rhop rhop )
        : ( Vec u ) b0 ( vec_new [u] ) ( vec_push [u] b0 # u & + n0 g 255 ) ( vec_push [u] b0 # u & >> + n0 g 8 255 )
        : ( Vec u ) b1 ( vec_new [u] ) ( vec_push [u] b1 # u & + n0 m1 255 ) ( vec_push [u] b1 # u & >> + n0 m1 8 255 )
        : ( Vec u ) b2 ( vec_new [u] ) ( vec_push [u] b2 # u & + n0 m2 255 ) ( vec_push [u] b2 # u & >> + n0 m2 8 255 )
        : ( Vec u ) b3 ( vec_new [u] ) ( vec_push [u] b3 # u & + n0 m3 255 ) ( vec_push [u] b3 # u & >> + n0 m3 8 255 )
        ( sha3x4_absorb h b0 b1 b2 b3 )
        ( vec_free [u] b0 ) ( vec_free [u] b1 ) ( vec_free [u] b2 ) ( vec_free [u] b3 )
        : ( Vec u ) o0 ( vec_with_cap [u] 136 )
        : ( Vec u ) o1 ( vec_with_cap [u] 136 )
        : ( Vec u ) o2 ( vec_with_cap [u] 136 )
        : ( Vec u ) o3 ( vec_with_cap [u] 136 )
        : ~ i c0 0
        : ~ i c1 0
        : ~ i c2 0
        : ~ i c3 0
        ~ | | | < c0 256 < c1 256 < c2 256 < c3 256 {
            : b z0 ( vec_set_len [u] o0 0 )
            : b z1 ( vec_set_len [u] o1 0 )
            : b z2 ( vec_set_len [u] o2 0 )
            : b z3 ( vec_set_len [u] o3 0 )
            ? ! & & & z0 z1 z2 z3 { = c0 256 = c1 256 = c2 256 = c3 256 } {
                ( sha3x4_squeeze h 136 o0 o1 o2 o3 )
                = c0 ( __eta_reject r + off0 * 256 g c0 o0 136 eta )
                = c1 ( __eta_reject r + off0 * 256 m1 c1 o1 136 eta )
                = c2 ( __eta_reject r + off0 * 256 m2 c2 o2 136 eta )
                = c3 ( __eta_reject r + off0 * 256 m3 c3 o3 136 eta )
            }
        }
        ( vec_free [u] o0 ) ( vec_free [u] o1 )
        ( vec_free [u] o2 ) ( vec_free [u] o3 )
        ( sha3x4_free h )
        = g + g 4
    }
}

@ __poly_uniform_eta * i32 r i off ( Vec u ) rhop i nonce i eta → v {
    : *Sha3 xof ( shake256_init )
    ( sha3_absorb xof rhop )
    : ( Vec u ) nb ( vec_new [u] )
    ( vec_push [u] nb # u & nonce 255 )
    ( vec_push [u] nb # u & >> nonce 8 255 )
    ( sha3_absorb xof nb )
    ( vec_free [u] nb )
    : ~ i ctr 0
    ~ < ctr 256 {
        : ( Vec u ) buf ( sha3_squeeze xof 136 )
        : *u bp ( vec_data [u] buf )
        : ~ i pos 0
        ~ & < ctr 256 < pos 136 {
            : i byte # i . bp pos
            = pos + pos 1
            : i c0 ( __coeff_from_halfbyte & byte 15 eta )
            ? & != c0 100 < ctr 256 {
                = . r + off ctr # i32 c0
                = ctr + ctr 1
            } {}
            : i c1 ( __coeff_from_halfbyte >> byte 4 eta )
            ? & != c1 100 < ctr 256 {
                = . r + off ctr # i32 c1
                = ctr + ctr 1
            } {}
        }
        ( vec_free [u] buf )
    }
    ( sha3_free xof )
}

// ExpandMask's per-polynomial half (Algorithm 34): a masking polynomial
// with coefficients in (−γ1, γ1], unpacked straight from the stream.
// Four ExpandMask streams at once: nonces κ..κ+3, fixed 32·zbits bytes
// each — no rejection, so this is pure equal-length lockstep. Runs once
// per signing attempt over the l mask polynomials, which makes it the
// hottest sampler in the scheme: a rejected attempt pays it again.
@ __gamma1_x4 * i32 r i off0 ( Vec u ) rhop i kappa i count i g1 i zbits → v {
    : ~ i g 0
    ~ < g count {
        : i m1 ? < + g 1 count + g 1 - count 1
        : i m2 ? < + g 2 count + g 2 - count 1
        : i m3 ? < + g 3 count + g 3 - count 1
        : *Sha3x4 h ( shake256x4_init )
        ( sha3x4_absorb h rhop rhop rhop rhop )
        : i n0 + kappa g
        : i n1 + kappa m1
        : i n2 + kappa m2
        : i n3 + kappa m3
        : ( Vec u ) b0 ( vec_new [u] ) ( vec_push [u] b0 # u & n0 255 ) ( vec_push [u] b0 # u & >> n0 8 255 )
        : ( Vec u ) b1 ( vec_new [u] ) ( vec_push [u] b1 # u & n1 255 ) ( vec_push [u] b1 # u & >> n1 8 255 )
        : ( Vec u ) b2 ( vec_new [u] ) ( vec_push [u] b2 # u & n2 255 ) ( vec_push [u] b2 # u & >> n2 8 255 )
        : ( Vec u ) b3 ( vec_new [u] ) ( vec_push [u] b3 # u & n3 255 ) ( vec_push [u] b3 # u & >> n3 8 255 )
        ( sha3x4_absorb h b0 b1 b2 b3 )
        ( vec_free [u] b0 ) ( vec_free [u] b1 ) ( vec_free [u] b2 ) ( vec_free [u] b3 )
        : ( Vec u ) o0 ( vec_with_cap [u] * 32 zbits )
        : ( Vec u ) o1 ( vec_with_cap [u] * 32 zbits )
        : ( Vec u ) o2 ( vec_with_cap [u] * 32 zbits )
        : ( Vec u ) o3 ( vec_with_cap [u] * 32 zbits )
        ( sha3x4_squeeze h * 32 zbits o0 o1 o2 o3 )
        ( sha3x4_free h )
        ( __bitunpack o0 0 zbits g1 r + off0 * 256 + g 0 )
        ? < + g 1 count { ( __bitunpack o1 0 zbits g1 r + off0 * 256 + g 1 ) } {}
        ? < + g 2 count { ( __bitunpack o2 0 zbits g1 r + off0 * 256 + g 2 ) } {}
        ? < + g 3 count { ( __bitunpack o3 0 zbits g1 r + off0 * 256 + g 3 ) } {}
        ( vec_free [u] o0 ) ( vec_free [u] o1 )
        ( vec_free [u] o2 ) ( vec_free [u] o3 )
        = g + g 4
    }
}

@ __poly_uniform_gamma1 * i32 r i off ( Vec u ) rhop i nonce i g1 i zbits → v {
    : *Sha3 xof ( shake256_init )
    ( sha3_absorb xof rhop )
    : ( Vec u ) nb ( vec_new [u] )
    ( vec_push [u] nb # u & nonce 255 )
    ( vec_push [u] nb # u & >> nonce 8 255 )
    ( sha3_absorb xof nb )
    ( vec_free [u] nb )
    : ( Vec u ) buf ( sha3_squeeze xof * 32 zbits )
    ( sha3_free xof )
    ( __bitunpack buf 0 zbits g1 r off )
    ( vec_free [u] buf )
}

// SampleInBall (Algorithm 29): a polynomial with exactly τ coefficients
// in {−1, +1} and the rest zero, placed by a Fisher-Yates shuffle whose
// randomness is the commitment hash.
@ __poly_challenge * i32 c i off ( Vec u ) ctilde i tau → v {
    : ~ i i 0
    ~ < i 256 { = . c + off i # i32 0 = i + i 1 }
    : *Sha3 xof ( shake256_init )
    ( sha3_absorb xof ctilde )
    : ( Vec u ) sb ( sha3_squeeze xof 8 )
    : *u sp ( vec_data [u] sb )
    : ~ i signs 0
    : ~ i b 0
    ~ < b 8 { = signs | signs << # i . sp b * 8 b = b + b 1 }
    ( vec_free [u] sb )
    : ~ i pos 256
    : ( Vec u ) buf ( sha3_squeeze xof 136 )
    : ~ ( Vec u ) cur buf
    : ~ i cp 0
    : ~ i n - 256 tau
    ~ < n 256 {
        : ~ i j 256
        ~ > j n {
            ? >= cp ( vec_len [u] cur ) {
                ( vec_free [u] cur )
                = cur ( sha3_squeeze xof 136 )
                = cp 0
            } {}
            : *u cbp ( vec_data [u] cur )
            = j # i . cbp cp
            = cp + cp 1
        }
        = . c + off n . c + off j
        = . c + off j # i32 - 1 * 2 & signs 1
        = signs >> signs 1
        = n + n 1
    }
    ( vec_free [u] cur )
    ( sha3_free xof )
}

// ── Hint packing ───────────────────────────────────────────────────
//
// The hint is a sparse bit per coefficient, at most ω set across all k
// polynomials. It travels as the indices of the set bits followed by k
// running totals.

@ __hint_pack * i32 h ( Vec u ) out i k i omega → v {
    : ~ i idx 0
    : ( Vec u ) body ( vec_new [u] )
    : ~ i i 0
    ~ < i omega { ( vec_push [u] body # u 0 ) = i + i 1 }
    : *u bp ( vec_data [u] body )
    : ( Vec u ) tail ( vec_new [u] )
    = i 0
    ~ < i k {
        : ~ i j 0
        ~ < j 256 {
            ? != # i . h + * 256 i j 0 {
                ? < idx omega { = . bp idx # u j = idx + idx 1 } {}
            } {}
            = j + j 1
        }
        ( vec_push [u] tail # u idx )
        = i + i 1
    }
    ( bytes_extend_bytes out body )
    ( bytes_extend_bytes out tail )
    ( vec_free [u] tail )
    ( vec_free [u] body )
}

// Unpack, with the malleability checks FIPS 204 §7.2 requires.
//
// These are not optional. Without them a signature has more than one
// valid encoding — a verifier that accepts a non-canonical hint accepts
// a forgery derived from a genuine signature. The three rules: the
// running totals must be non-decreasing and within ω, the indices
// inside one polynomial must be strictly increasing, and every byte
// past the last index must be zero.
//
// Returns F when the encoding is not canonical.
@ __hint_unpack ( Vec u ) sig i soff * i32 h i k i omega → b {
    : ~ i i 0
    ~ < i * 256 k { = . h i # i32 0 = i + i 1 }
    : *u sp ( vec_data [u] sig )
    : ~ i idx 0
    = i 0
    ~ < i k {
        : i total # i . sp + soff + omega i
        ? | < total idx > total omega { ^ F } {}
        : i first idx
        ~ < idx total {
            ? & > idx first <= # i . sp + soff idx # i . sp + soff - idx 1 { ^ F } {}
            = . h + * 256 i # i . sp + soff idx # i32 1
            = idx + idx 1
        }
        = i + i 1
    }
    : ~ i j idx
    ~ < j omega {
        ? != # i . sp + soff j 0 { ^ F } {}
        = j + j 1
    }
    ^ T
}

// ── Key and signature encoding ─────────────────────────────────────

@ __pack_pk ( Vec u ) rho * i32 t1 i k ( Vec u ) out → v {
    ( bytes_extend_bytes out rho )
    : ~ i i 0
    ~ < i k { ( __simple_bitpack t1 * 256 i 10 out ) = i + i 1 }
}

@ __pack_sk ( Vec u ) rho ( Vec u ) kk ( Vec u ) tr * i32 s1 * i32 s2 * i32 t0
MldsaParams p ( Vec u ) out → v {
    ( bytes_extend_bytes out rho )
    ( bytes_extend_bytes out kk )
    ( bytes_extend_bytes out tr )
    : ~ i i 0
    ~ < i . p l { ( __bitpack s1 * 256 i . p sbits . p eta out ) = i + i 1 }
    = i 0
    ~ < i . p k { ( __bitpack s2 * 256 i . p sbits . p eta out ) = i + i 1 }
    = i 0
    ~ < i . p k { ( __bitpack t0 * 256 i 13 4096 out ) = i + i 1 }
}

// ── Key generation ─────────────────────────────────────────────────

: MldsaKeys {
    ( Vec u ) pk
    ( Vec u ) sk
}

@ mldsa_pk * MldsaKeys h → ( Vec u ) { ^ . h pk }

@ mldsa_sk * MldsaKeys h → ( Vec u ) { ^ . h sk }

@ mldsa_keys_free * MldsaKeys h → v {
    ( vec_free [u] . h pk )
    ( vec_free [u] . h sk )
    ( nurl_free # s h )
}

// ML-DSA.KeyGen_internal (Algorithm 6).
simd @ mldsa_keygen_derand i level ( Vec u ) xi → *MldsaKeys {
    : MldsaParams p ( __mldsa_params level )
    : i k . p k
    : i l . p l
    : ( Vec i32 ) zt ( __mldsa_zetas )
    : *i32 zp ( vec_data [i32] zt )

    // (ρ, ρ', K) ← H(ξ ‖ k ‖ l, 128)
    : ( Vec u ) hin ( vec_new [u] )
    ( bytes_extend_bytes hin xi )
    ( vec_push [u] hin # u k )
    ( vec_push [u] hin # u l )
    : ( Vec u ) g ( shake256_pure hin 128 )
    ( vec_free [u] hin )
    : ( Vec u ) rho ( bytes_slice g 0 32 )
    : ( Vec u ) rhop ( bytes_slice g 32 96 )
    : ( Vec u ) kk ( bytes_slice g 96 128 )
    ( vec_free [u] g )

    // Â ← ExpandA(ρ) — the seed suffix is (column, row), in that order
    : ( Vec i32 ) a ( __md_poly_zero * 256 * k l )
    ( __md_expand_a a rho k l )
    : *i32 ap ( vec_data [i32] a )

    // (s1, s2) ← ExpandS(ρ')
    : ( Vec i32 ) s1 ( __md_poly_zero * 256 l )
    : ( Vec i32 ) s2 ( __md_poly_zero * 256 k )
    : *i32 s1p ( vec_data [i32] s1 )
    : *i32 s2p ( vec_data [i32] s2 )
    ( __uniform_eta_x4 s1p 0 rhop 0 l . p eta )
    ( __uniform_eta_x4 s2p 0 rhop l k . p eta )
    : ~ i i 0

    // t ← NTT^-1(Â ∘ NTT(s1)) + s2
    : ( Vec i32 ) s1h ( __md_poly_zero * 256 l )
    : *i32 s1hp ( vec_data [i32] s1h )
    = i 0
    ~ < i * 256 l { = . s1hp i . s1p i = i + i 1 }
    = i 0
    ~ < i l { ( __md_ntt s1hp * 256 i zp ) = i + i 1 }

    : ( Vec i32 ) t ( __md_poly_zero * 256 k )
    : ( Vec i32 ) scratch ( __md_poly_zero 256 )
    : *i32 tp ( vec_data [i32] t )
    = i 0
    ~ < i k {
        ( __polyvec_pointwise_acc tp * 256 i ap * 256 * i l s1hp 0 l scratch )
        ( __md_poly_reduce tp * 256 i )
        ( __md_invntt tp * 256 i zp )
        ( __md_poly_add tp * 256 i tp * 256 i s2p * 256 i )
        ( __poly_caddq tp * 256 i )
        = i + i 1
    }

    // (t1, t0) ← Power2Round(t)
    : ( Vec i32 ) t1 ( __md_poly_zero * 256 k )
    : ( Vec i32 ) t0 ( __md_poly_zero * 256 k )
    : *i32 t1p ( vec_data [i32] t1 )
    : *i32 t0p ( vec_data [i32] t0 )
    = i 0
    ~ < i k {
        ( __poly_power2round t1p * 256 i t0p * 256 i tp * 256 i )
        = i + i 1
    }

    : ( Vec u ) pk ( vec_with_cap [u] ( mldsa_pk_len level ) )
    ( __pack_pk rho t1p k pk )
    : ( Vec u ) tr ( shake256_pure pk 64 )
    : ( Vec u ) sk ( vec_with_cap [u] ( mldsa_sk_len level ) )
    ( __pack_sk rho kk tr s1p s2p t0p p sk )

    : *MldsaKeys h # *MldsaKeys ( nurl_alloc Z MldsaKeys )
    = . h pk pk
    = . h sk sk

    ( vec_free [u] tr )
    ( vec_free [i32] t0 ) ( vec_free [i32] t1 )
    ( vec_free [i32] scratch ) ( vec_free [i32] t )
    ( vec_free [i32] s1h ) ( vec_free [i32] s2 ) ( vec_free [i32] s1 )
    ( vec_free [i32] a )
    ( vec_free [u] kk ) ( vec_free [u] rhop ) ( vec_free [u] rho )
    ( vec_free [i32] zt )
    ^ h
}

@ mldsa_keygen i level → *MldsaKeys {
    : ( Vec u ) xi ( rand_bytes 32 )
    : *MldsaKeys h ( mldsa_keygen_derand level xi )
    ( vec_free [u] xi )
    ^ h
}

// ── Key and signature decoding ─────────────────────────────────────

@ __unpack_pk ( Vec u ) pk * i32 t1 i k → v {
    : ~ i i 0
    ~ < i k { ( __simple_bitunpack pk + 32 * 320 i 10 t1 * 256 i ) = i + i 1 }
}

@ __unpack_sk ( Vec u ) sk * i32 s1 * i32 s2 * i32 t0 MldsaParams p → v {
    : i eb * 32 . p sbits
    : ~ i off 128
    : ~ i i 0
    ~ < i . p l {
        ( __bitunpack sk + off * eb i . p sbits . p eta s1 * 256 i )
        = i + i 1
    }
    = off + off * . p l eb
    = i 0
    ~ < i . p k {
        ( __bitunpack sk + off * eb i . p sbits . p eta s2 * 256 i )
        = i + i 1
    }
    = off + off * . p k eb
    = i 0
    ~ < i . p k {
        ( __bitunpack sk + off * 416 i 13 4096 t0 * 256 i )
        = i + i 1
    }
}

// w1Encode (FIPS 204 §7.2) — the commitment, packed at the width the
// level's γ2 implies.
@ __pack_w1 * i32 w1 i k i wbits ( Vec u ) out → v {
    : ~ i i 0
    ~ < i k { ( __simple_bitpack w1 * 256 i wbits out ) = i + i 1 }
}

// ── Signing ────────────────────────────────────────────────────────

// ML-DSA.Sign_internal (Algorithm 7).
//
// Returns an empty Vec if the rejection loop fails to terminate within
// a generous bound. That cannot happen for a well-formed key — the
// expected iteration count is between 4 and 7 depending on the level —
// but an unbounded loop on a corrupted secret key would hang a server,
// and failing is recoverable where hanging is not.
simd @ mldsa_sign_mu i level ( Vec u ) sk ( Vec u ) mu ( Vec u ) rnd → ( Vec u ) {
    : MldsaParams p ( __mldsa_params level )
    : i k . p k
    : i l . p l
    : i g1 . p gamma1
    : i g2 . p gamma2
    : i beta * . p tau . p eta
    : ( Vec i32 ) zt ( __mldsa_zetas )
    : *i32 zp ( vec_data [i32] zt )

    : ( Vec u ) rho ( bytes_slice sk 0 32 )
    : ( Vec u ) kk ( bytes_slice sk 32 64 )
    : ( Vec u ) tr ( bytes_slice sk 64 128 )
    : ( Vec i32 ) s1 ( __md_poly_zero * 256 l )
    : ( Vec i32 ) s2 ( __md_poly_zero * 256 k )
    : ( Vec i32 ) t0 ( __md_poly_zero * 256 k )
    : *i32 s1p ( vec_data [i32] s1 )
    : *i32 s2p ( vec_data [i32] s2 )
    : *i32 t0p ( vec_data [i32] t0 )
    ( __unpack_sk sk s1p s2p t0p p )

    : ~ i i 0
    ~ < i l { ( __md_ntt s1p * 256 i zp ) = i + i 1 }
    = i 0
    ~ < i k { ( __md_ntt s2p * 256 i zp ) = i + i 1 }
    = i 0
    ~ < i k { ( __md_ntt t0p * 256 i zp ) = i + i 1 }

    : ( Vec i32 ) a ( __md_poly_zero * 256 * k l )
    ( __md_expand_a a rho k l )
    : *i32 ap ( vec_data [i32] a )

    // ρ'' ← H(K ‖ rnd ‖ μ, 64)
    : *Sha3 hr ( shake256_init )
    ( sha3_absorb hr kk )
    ( sha3_absorb hr rnd )
    ( sha3_absorb hr mu )
    : ( Vec u ) rhopp ( sha3_squeeze hr 64 )
    ( sha3_free hr )

    : ( Vec i32 ) y ( __md_poly_zero * 256 l )
    : ( Vec i32 ) yh ( __md_poly_zero * 256 l )
    : ( Vec i32 ) w ( __md_poly_zero * 256 k )
    : ( Vec i32 ) w1 ( __md_poly_zero * 256 k )
    : ( Vec i32 ) w0 ( __md_poly_zero * 256 k )
    : ( Vec i32 ) cp ( __md_poly_zero 256 )
    : ( Vec i32 ) cs1 ( __md_poly_zero * 256 l )
    : ( Vec i32 ) cs2 ( __md_poly_zero * 256 k )
    : ( Vec i32 ) ct0 ( __md_poly_zero * 256 k )
    : ( Vec i32 ) hint ( __md_poly_zero * 256 k )
    : ( Vec i32 ) scratch ( __md_poly_zero 256 )
    : *i32 yp ( vec_data [i32] y )
    : *i32 yhp ( vec_data [i32] yh )
    : *i32 wp ( vec_data [i32] w )
    : *i32 w1p ( vec_data [i32] w1 )
    : *i32 w0p ( vec_data [i32] w0 )
    : *i32 cpp ( vec_data [i32] cp )
    : *i32 cs1p ( vec_data [i32] cs1 )
    : *i32 cs2p ( vec_data [i32] cs2 )
    : *i32 ct0p ( vec_data [i32] ct0 )
    : *i32 hp ( vec_data [i32] hint )

    : ~ ( Vec u ) sig ( vec_new [u] )
    : ~ i kappa 0
    : ~ i tries 0
    : ~ b done F
    ~ & ! done < tries 1000 {
        = tries + tries 1

        // y ← ExpandMask(ρ'', κ) ; w ← NTT^-1(Â ∘ NTT(y))
        ( __gamma1_x4 yp 0 rhopp kappa l g1 . p zbits )
        = i 0
        ~ < i * 256 l { = . yhp i . yp i = i + i 1 }
        = i 0
        ~ < i l { ( __md_ntt yhp * 256 i zp ) = i + i 1 }
        = i 0
        ~ < i k {
            ( __polyvec_pointwise_acc wp * 256 i ap * 256 * i l yhp 0 l scratch )
            ( __md_poly_reduce wp * 256 i )
            ( __md_invntt wp * 256 i zp )
            ( __poly_caddq wp * 256 i )
            ( __poly_decompose w1p * 256 i w0p * 256 i wp * 256 i g2 )
            = i + i 1
        }

        // c~ ← H(μ ‖ w1Encode(w1), λ/4) ; c ← SampleInBall(c~)
        : ( Vec u ) w1enc ( vec_new [u] )
        ( __pack_w1 w1p k . p wbits w1enc )
        : *Sha3 hc ( shake256_init )
        ( sha3_absorb hc mu )
        ( sha3_absorb hc w1enc )
        : ( Vec u ) ctilde ( sha3_squeeze hc . p lam )
        ( sha3_free hc )
        ( vec_free [u] w1enc )
        ( __poly_challenge cpp 0 ctilde . p tau )
        ( __md_ntt cpp 0 zp )

        // z ← y + ⟨⟨c·s1⟩⟩
        = i 0
        ~ < i l {
            ( __poly_pointwise cs1p * 256 i cpp 0 s1p * 256 i )
            ( __md_invntt cs1p * 256 i zp )
            ( __md_poly_add cs1p * 256 i cs1p * 256 i yp * 256 i )
            ( __md_poly_reduce cs1p * 256 i )
            = i + i 1
        }
        : ~ b ok T
        = i 0
        ~ < i l {
            = ok & ok ( __poly_chknorm cs1p * 256 i - g1 beta )
            = i + i 1
        }

        // r0 ← LowBits(w − ⟨⟨c·s2⟩⟩)
        ? ok {
            = i 0
            ~ < i k {
                ( __poly_pointwise cs2p * 256 i cpp 0 s2p * 256 i )
                ( __md_invntt cs2p * 256 i zp )
                ( __md_poly_sub w0p * 256 i w0p * 256 i cs2p * 256 i )
                ( __md_poly_reduce w0p * 256 i )
                = i + i 1
            }
            = i 0
            ~ < i k {
                = ok & ok ( __poly_chknorm w0p * 256 i - g2 beta )
                = i + i 1
            }
        } {}

        // h ← MakeHint(−⟨⟨c·t0⟩⟩, w − ⟨⟨c·s2⟩⟩ + ⟨⟨c·t0⟩⟩)
        ? ok {
            = i 0
            ~ < i k {
                ( __poly_pointwise ct0p * 256 i cpp 0 t0p * 256 i )
                ( __md_invntt ct0p * 256 i zp )
                ( __md_poly_reduce ct0p * 256 i )
                = i + i 1
            }
            = i 0
            ~ < i k {
                = ok & ok ( __poly_chknorm ct0p * 256 i g2 )
                = i + i 1
            }
        } {}

        ? ok {
            : ~ i ones 0
            = i 0
            ~ < i k {
                ( __md_poly_add w0p * 256 i w0p * 256 i ct0p * 256 i )
                : ~ i j 0
                ~ < j 256 {
                    // w0 now holds LowBits(w) − ⟨⟨c·s2⟩⟩ + ⟨⟨c·t0⟩⟩ and
                    // w1 holds HighBits(w), so the hint is a range test
                    // on w0 — no second decomposition needed.
                    : i bit ( __makehint . w0p + * 256 i j . w1p + * 256 i j g2 )
                    = . hp + * 256 i j # i32 bit
                    = ones + ones bit
                    = j + j 1
                }
                = i + i 1
            }
            ? > ones . p omega { = ok F } {}
        } {}

        ? ok {
            ( vec_free [u] sig )
            = sig ( vec_with_cap [u] ( mldsa_sig_len level ) )
            ( bytes_extend_bytes sig ctilde )
            = i 0
            ~ < i l { ( __bitpack cs1p * 256 i . p zbits g1 sig ) = i + i 1 }
            ( __hint_pack hp sig k . p omega )
            = done T
        } {}
        ( vec_free [u] ctilde )
        = kappa + kappa l
    }

    ( vec_free [i32] scratch ) ( vec_free [i32] hint ) ( vec_free [i32] ct0 )
    ( vec_free [i32] cs2 ) ( vec_free [i32] cs1 ) ( vec_free [i32] cp )
    ( vec_free [i32] w0 ) ( vec_free [i32] w1 ) ( vec_free [i32] w )
    ( vec_free [i32] yh ) ( vec_free [i32] y )
    ( vec_free [u] rhopp )
    ( vec_free [i32] a )
    ( vec_free [i32] t0 ) ( vec_free [i32] s2 ) ( vec_free [i32] s1 )
    ( vec_free [u] tr ) ( vec_free [u] kk ) ( vec_free [u] rho )
    ( vec_free [i32] zt )
    ^ sig
}

// μ ← H(tr ‖ M', 64) — the message representative, bound to the public
// key through tr so a signature cannot be transplanted onto another key.
@ __mldsa_mu ( Vec u ) tr ( Vec u ) mprime → ( Vec u ) {
    : *Sha3 h ( shake256_init )
    ( sha3_absorb h tr )
    ( sha3_absorb h mprime )
    : ( Vec u ) mu ( sha3_squeeze h 64 )
    ( sha3_free h )
    ^ mu
}

// ML-DSA.Sign_internal (Algorithm 7) over a message representative.
@ mldsa_sign_internal i level ( Vec u ) sk ( Vec u ) mprime ( Vec u ) rnd → ( Vec u ) {
    : ( Vec u ) tr ( bytes_slice sk 64 128 )
    : ( Vec u ) mu ( __mldsa_mu tr mprime )
    : ( Vec u ) sig ( mldsa_sign_mu level sk mu rnd )
    ( vec_free [u] mu )
    ( vec_free [u] tr )
    ^ sig
}

// ── Verification ───────────────────────────────────────────────────

// ML-DSA.Verify_internal (Algorithm 8).
simd @ mldsa_verify_mu i level ( Vec u ) pk ( Vec u ) mu ( Vec u ) sig → b {
    : MldsaParams p ( __mldsa_params level )
    : i k . p k
    : i l . p l
    : i g1 . p gamma1
    : i g2 . p gamma2
    : i beta * . p tau . p eta
    ? != ( vec_len [u] pk ) ( mldsa_pk_len level ) { ^ F } {}
    ? != ( vec_len [u] sig ) ( mldsa_sig_len level ) { ^ F } {}

    : ( Vec i32 ) zt ( __mldsa_zetas )
    : *i32 zp ( vec_data [i32] zt )
    : ( Vec u ) rho ( bytes_slice pk 0 32 )
    : ( Vec i32 ) t1 ( __md_poly_zero * 256 k )
    : *i32 t1p ( vec_data [i32] t1 )
    ( __unpack_pk pk t1p k )

    : ( Vec u ) ctilde ( bytes_slice sig 0 . p lam )
    : ( Vec i32 ) z ( __md_poly_zero * 256 l )
    : *i32 zpz ( vec_data [i32] z )
    : i zb * 32 . p zbits
    : ~ i i 0
    ~ < i l {
        ( __bitunpack sig + . p lam * zb i . p zbits g1 zpz * 256 i )
        = i + i 1
    }
    : ( Vec i32 ) hint ( __md_poly_zero * 256 k )
    : *i32 hp ( vec_data [i32] hint )
    : b hok ( __hint_unpack sig + . p lam * zb l hp k . p omega )

    : ~ b ok hok
    // ‖z‖∞ < γ1 − β, checked before anything is done with z.
    = i 0
    ~ < i l { = ok & ok ( __poly_chknorm zpz * 256 i - g1 beta ) = i + i 1 }

    ? ok {
        : ( Vec i32 ) a ( __md_poly_zero * 256 * k l )
        ( __md_expand_a a rho k l )
        : *i32 ap ( vec_data [i32] a )
        : ( Vec i32 ) cp ( __md_poly_zero 256 )
        : *i32 cpp ( vec_data [i32] cp )
        ( __poly_challenge cpp 0 ctilde . p tau )
        ( __md_ntt cpp 0 zp )

        : ( Vec i32 ) zh ( __md_poly_zero * 256 l )
        : *i32 zhp ( vec_data [i32] zh )
        = i 0
        ~ < i * 256 l { = . zhp i . zpz i = i + i 1 }
        = i 0
        ~ < i l { ( __md_ntt zhp * 256 i zp ) = i + i 1 }

        : ( Vec i32 ) t1h ( __md_poly_zero * 256 k )
        : *i32 t1hp ( vec_data [i32] t1h )
        = i 0
        ~ < i * 256 k { = . t1hp i . t1p i = i + i 1 }
        = i 0
        ~ < i k {
            ( __poly_shiftl t1hp * 256 i )
            ( __md_ntt t1hp * 256 i zp )
            = i + i 1
        }

        : ( Vec i32 ) wa ( __md_poly_zero * 256 k )
        : ( Vec i32 ) tmp ( __md_poly_zero 256 )
        : ( Vec i32 ) scratch ( __md_poly_zero 256 )
        : *i32 wap ( vec_data [i32] wa )
        : *i32 tmpp ( vec_data [i32] tmp )
        = i 0
        ~ < i k {
            ( __polyvec_pointwise_acc wap * 256 i ap * 256 * i l zhp 0 l scratch )
            ( __poly_pointwise tmpp 0 cpp 0 t1hp * 256 i )
            ( __md_poly_sub wap * 256 i wap * 256 i tmpp 0 )
            ( __md_poly_reduce wap * 256 i )
            ( __md_invntt wap * 256 i zp )
            ( __poly_caddq wap * 256 i )
            = i + i 1
        }

        // w1' ← UseHint(h, w'approx)
        : ( Vec i32 ) w1 ( __md_poly_zero * 256 k )
        : *i32 w1p ( vec_data [i32] w1 )
        = i 0
        ~ < i k {
            : ~ i j 0
            ~ < j 256 {
                = . w1p + * 256 i j
                # i32 ( __usehint # i . hp + * 256 i j # i . wap + * 256 i j g2 )
                = j + j 1
            }
            = i + i 1
        }
        : ( Vec u ) w1enc ( vec_new [u] )
        ( __pack_w1 w1p k . p wbits w1enc )
        : *Sha3 hc ( shake256_init )
        ( sha3_absorb hc mu )
        ( sha3_absorb hc w1enc )
        : ( Vec u ) c2 ( sha3_squeeze hc . p lam )
        ( sha3_free hc )
        ( vec_free [u] w1enc )
        // Constant-time: the comparison itself is not secret, but a
        // length-dependent early exit is a habit worth not forming.
        = ok & ok ( constant_time_eq_vec ctilde c2 )

        ( vec_free [u] c2 )
        ( vec_free [i32] w1 )
        ( vec_free [i32] scratch ) ( vec_free [i32] tmp ) ( vec_free [i32] wa )
        ( vec_free [i32] t1h ) ( vec_free [i32] zh ) ( vec_free [i32] cp )
        ( vec_free [i32] a )
    } {}

    ( vec_free [i32] hint ) ( vec_free [i32] z ) ( vec_free [u] ctilde )
    ( vec_free [i32] t1 ) ( vec_free [u] rho ) ( vec_free [i32] zt )
    ^ ok
}

// ML-DSA.Verify_internal (Algorithm 8) over a message representative.
@ mldsa_verify_internal i level ( Vec u ) pk ( Vec u ) mprime ( Vec u ) sig → b {
    ? != ( vec_len [u] pk ) ( mldsa_pk_len level ) { ^ F } {}
    : ( Vec u ) tr ( shake256_pure pk 64 )
    : ( Vec u ) mu ( __mldsa_mu tr mprime )
    : b ok ( mldsa_verify_mu level pk mu sig )
    ( vec_free [u] mu )
    ( vec_free [u] tr )
    ^ ok
}

// ── The external interface ─────────────────────────────────────────

// M' = 0x00 ‖ |ctx| ‖ ctx ‖ M (FIPS 204 §5.2). The domain byte and the
// context length are what stop a signature made for one application
// being replayed into another.
@ __mldsa_mprime ( Vec u ) msg ( Vec u ) ctx → ( Vec u ) {
    : ( Vec u ) m ( vec_new [u] )
    ( vec_push [u] m # u 0 )
    ( vec_push [u] m # u ( vec_len [u] ctx ) )
    ( bytes_extend_bytes m ctx )
    ( bytes_extend_bytes m msg )
    ^ m
}

// Sign `msg` under `sk`, bound to the context string `ctx` (empty Vec
// for none). Hedged: 32 fresh random bytes go into the per-signature
// nonce, so a repeated message does not produce a repeated signature.
// Returns an empty Vec if ctx is longer than the 255 bytes FIPS 204
// allows.
@ mldsa_sign i level ( Vec u ) sk ( Vec u ) msg ( Vec u ) ctx → ( Vec u ) {
    ? > ( vec_len [u] ctx ) 255 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) mp ( __mldsa_mprime msg ctx )
    : ( Vec u ) rnd ( rand_bytes 32 )
    : ( Vec u ) sig ( mldsa_sign_internal level sk mp rnd )
    ( vec_free [u] rnd )
    ( vec_free [u] mp )
    ^ sig
}

// The deterministic variant: rnd is 32 zero bytes, so the same key and
// message always give the same signature. Interoperable, and what the
// ACVP "deterministic" vectors exercise — but hedged signing above is
// the better default, since it survives a fault or a repeated nonce.
@ mldsa_sign_deterministic i level ( Vec u ) sk ( Vec u ) msg ( Vec u ) ctx → ( Vec u ) {
    ? > ( vec_len [u] ctx ) 255 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) mp ( __mldsa_mprime msg ctx )
    : ( Vec u ) rnd ( vec_with_cap [u] 32 )
    : ~ i i 0
    ~ < i 32 { ( vec_push [u] rnd # u 0 ) = i + i 1 }
    : ( Vec u ) sig ( mldsa_sign_internal level sk mp rnd )
    ( vec_free [u] rnd )
    ( vec_free [u] mp )
    ^ sig
}

@ mldsa_verify i level ( Vec u ) pk ( Vec u ) msg ( Vec u ) ctx ( Vec u ) sig → b {
    ? > ( vec_len [u] ctx ) 255 { ^ F } {}
    : ( Vec u ) mp ( __mldsa_mprime msg ctx )
    : b ok ( mldsa_verify_internal level pk mp sig )
    ( vec_free [u] mp )
    ^ ok
}

// ── HashML-DSA (FIPS 204 §5.4) ─────────────────────────────────────
//
// The pre-hash variant: instead of signing the message, sign a digest
// of it under a named hash. That lets a signer handle a message it
// never holds whole — a multi-gigabyte file streamed past a hash — and
// lets a protocol that already has a digest avoid carrying the message
// to the signer at all.
//
// The named hash is not a free choice made at signing time and forgotten:
// its OID goes *into* the signed message representative, so a signature
// over a SHA2-256 digest cannot be reinterpreted as one over a SHA3-256
// digest of some other message. That binding is the whole reason
// HashML-DSA is a distinct mode rather than "just hash it yourself".
//
//   M' = 0x01 ‖ |ctx| ‖ ctx ‖ OID(hash) ‖ H(M)
//
// against the pure mode's `0x00 ‖ |ctx| ‖ ctx ‖ M`. The leading byte is
// what keeps the two from ever colliding.
//
// The twelve approved hashes, by the code this module takes:
//
//   1 SHA2-224     2 SHA2-256     3 SHA2-384     4 SHA2-512
//   5 SHA2-512/224 6 SHA2-512/256 7 SHA3-224     8 SHA3-256
//   9 SHA3-384    10 SHA3-512    11 SHAKE-128   12 SHAKE-256
//
// SHAKE-128 and SHAKE-256 are squeezed to 32 and 64 bytes respectively,
// the lengths FIPS 204 fixes for this use.

@ MLDSA_SHA2_224 → i { ^ 1 }

@ MLDSA_SHA2_256 → i { ^ 2 }

@ MLDSA_SHA2_384 → i { ^ 3 }

@ MLDSA_SHA2_512 → i { ^ 4 }

@ MLDSA_SHA2_512_224 → i { ^ 5 }

@ MLDSA_SHA2_512_256 → i { ^ 6 }

@ MLDSA_SHA3_224 → i { ^ 7 }

@ MLDSA_SHA3_256 → i { ^ 8 }

@ MLDSA_SHA3_384 → i { ^ 9 }

@ MLDSA_SHA3_512 → i { ^ 10 }

@ MLDSA_SHAKE_128 → i { ^ 11 }

@ MLDSA_SHAKE_256 → i { ^ 12 }

// The full DER encoding of 2.16.840.1.101.3.4.2.n, as hex — tag 0x06,
// length 0x09, then the nine content bytes. FIPS 204 §5.4 puts the
// *encoded* OID into the message representative, not its content bytes;
// dropping the two-byte header produces signatures that verify against
// nothing and is invisible until you compare with a real vector.
// Empty for an unknown code, which the callers turn into a refusal.
@ __mldsa_ph_oid_hex i alg → s {
    ? == alg 1 { ^ `0609608648016503040204` } {}
    ? == alg 2 { ^ `0609608648016503040201` } {}
    ? == alg 3 { ^ `0609608648016503040202` } {}
    ? == alg 4 { ^ `0609608648016503040203` } {}
    ? == alg 5 { ^ `0609608648016503040205` } {}
    ? == alg 6 { ^ `0609608648016503040206` } {}
    ? == alg 7 { ^ `0609608648016503040207` } {}
    ? == alg 8 { ^ `0609608648016503040208` } {}
    ? == alg 9 { ^ `0609608648016503040209` } {}
    ? == alg 10 { ^ `060960864801650304020a` } {}
    ? == alg 11 { ^ `060960864801650304020b` } {}
    ? == alg 12 { ^ `060960864801650304020c` } {}
    ^ ``
}

@ __mldsa_ph_digest i alg ( Vec u ) msg → ( Vec u ) {
    ? == alg 1 { ^ ( sha224_pure msg ) } {}
    ? == alg 2 { ^ ( sha256_pure msg ) } {}
    ? == alg 3 { ^ ( sha384_pure msg ) } {}
    ? == alg 4 { ^ ( sha512_pure msg ) } {}
    ? == alg 5 { ^ ( sha512_224_pure msg ) } {}
    ? == alg 6 { ^ ( sha512_256_pure msg ) } {}
    ? == alg 7 { ^ ( sha3_224_pure msg ) } {}
    ? == alg 8 { ^ ( sha3_256_pure msg ) } {}
    ? == alg 9 { ^ ( sha3_384_pure msg ) } {}
    ? == alg 10 { ^ ( sha3_512_pure msg ) } {}
    ? == alg 11 { ^ ( shake128_pure msg 32 ) } {}
    ? == alg 12 { ^ ( shake256_pure msg 64 ) } {}
    ^ ( vec_new [u] )
}

// The HashML-DSA message representative, `0x01 ‖ |ctx| ‖ ctx ‖ OID ‖
// H(M)`. Returns an empty Vec when the hash code is not one of the
// twelve.
//
// Public because two real callers need it and neither is served by
// `mldsa_sign_prehash`: something that wants to sign with a specific
// `rnd` rather than a fresh draw (the ACVP vectors, a deterministic
// build), and something that already holds the digest and never had
// the message.
@ mldsa_ph_mprime i alg ( Vec u ) msg ( Vec u ) ctx → ( Vec u ) {
    : s oidhex ( __mldsa_ph_oid_hex alg )
    ? == ( nurl_str_len oidhex ) 0 { ^ ( vec_new [u] ) } {}
    : !( Vec u ) ParseErr r ( bytes_from_hex oidhex )
    : ( Vec u ) oid ?? r { T v → { v } F _e → { ( vec_new [u] ) } }
    : ( Vec u ) dig ( __mldsa_ph_digest alg msg )
    : ( Vec u ) m ( vec_new [u] )
    ( vec_push [u] m # u 1 )
    ( vec_push [u] m # u ( vec_len [u] ctx ) )
    ( bytes_extend_bytes m ctx )
    ( bytes_extend_bytes m oid )
    ( bytes_extend_bytes m dig )
    ( vec_free [u] dig )
    ( vec_free [u] oid )
    ^ m
}

// Sign a digest of `msg` under the named hash, bound to `ctx`. Hedged,
// like `mldsa_sign`. Returns an empty Vec for an unknown hash code or a
// context longer than 255 bytes.
@ mldsa_sign_prehash i level ( Vec u ) sk ( Vec u ) msg ( Vec u ) ctx i alg → ( Vec u ) {
    ? > ( vec_len [u] ctx ) 255 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) mp ( mldsa_ph_mprime alg msg ctx )
    ? == ( vec_len [u] mp ) 0 { ( vec_free [u] mp ) ^ ( vec_new [u] ) } {}
    : ( Vec u ) rnd ( rand_bytes 32 )
    : ( Vec u ) sig ( mldsa_sign_internal level sk mp rnd )
    ( vec_free [u] rnd )
    ( vec_free [u] mp )
    ^ sig
}

// Deterministic HashML-DSA, for interoperability and for the ACVP
// vectors; `mldsa_sign_prehash` is the better default.
@ mldsa_sign_prehash_deterministic i level ( Vec u ) sk ( Vec u ) msg ( Vec u ) ctx i alg → ( Vec u ) {
    ? > ( vec_len [u] ctx ) 255 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) mp ( mldsa_ph_mprime alg msg ctx )
    ? == ( vec_len [u] mp ) 0 { ( vec_free [u] mp ) ^ ( vec_new [u] ) } {}
    : ( Vec u ) rnd ( vec_with_cap [u] 32 )
    : ~ i i 0
    ~ < i 32 { ( vec_push [u] rnd # u 0 ) = i + i 1 }
    : ( Vec u ) sig ( mldsa_sign_internal level sk mp rnd )
    ( vec_free [u] rnd )
    ( vec_free [u] mp )
    ^ sig
}

@ mldsa_verify_prehash i level ( Vec u ) pk ( Vec u ) msg ( Vec u ) ctx i alg ( Vec u ) sig → b {
    ? > ( vec_len [u] ctx ) 255 { ^ F } {}
    : ( Vec u ) mp ( mldsa_ph_mprime alg msg ctx )
    ? == ( vec_len [u] mp ) 0 { ( vec_free [u] mp ) ^ F } {}
    : b ok ( mldsa_verify_internal level pk mp sig )
    ( vec_free [u] mp )
    ^ ok
}
