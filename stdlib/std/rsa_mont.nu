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
// Montgomery CIOS on nurl_mac (one widening multiply and an add-with-carry
// chain per limb product); exponentiation is a fixed 4-bit window whose
// table entry is picked by scanning all sixteen under a mask. For a given
// modulus size every operation runs the same instruction sequence whatever
// the key and the message: no branch and no memory index depends on a
// secret.
//
// The private operation uses the Chinese remainder theorem when the key
// carries its factors (a CRT key blob, below): two exponentiations at half
// the width, a quarter of the work each, recombined with Garner's formula.
// Two hardenings ride along:
//   * exponent blinding — each half exponentiates by d_p + r·(p − 1) for a
//     fresh 64-bit r, the same residue, so the exponent bits the hardware
//     sees change on every signature;
//   * a fault check — the signature is verified (s^e against the message,
//     mod p and mod q) before it is released, so a computation fault in one
//     half cannot leak a factor (the Bellcore attack).
//
// CRT key blob (what std/pkey.nu's RsaPriv carries as `crt`, and what the
// TLS listener passes as the private exponent): the 4-byte magic 00 'C'
// 'R' 'T', then p, q, d_p, d_q and q^-1 mod p, each as a 2-byte big-endian
// length and that many big-endian bytes. A plain private exponent never
// starts with a zero byte, so the two cannot be confused.
//
//   ( _rsa_is_crt_blob ( Vec u ) d )                      → b
//   ( _rsa_private ( Vec u ) n ( Vec u ) e ( Vec u ) d ( Vec u ) m i k )
//        → ( Vec u )   m^d mod n, k bytes big-endian; d is a plain private
//                      exponent or a CRT blob; [] if the fault check fails
//   ( _rsa_public ( Vec u ) n ( Vec u ) e ( Vec u ) s i k ) → ( Vec u )
//        s^e mod n, k bytes big-endian (e is public: variable time)

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/random.nu`

// ── context ─────────────────────────────────────────────────────────
//
// One modulus: its limbs, −m^-1 mod 2^64, R^2 mod m (R = 2^(64n)), 1 in
// Montgomery form, and the scratch the multiply works in (accumulator t,
// n + 2 limbs; difference d, n limbs). Built per operation; nothing in it
// is shared between threads.
: RsaMont { i n ( Vec i ) m i n0 ( Vec i ) r2 ( Vec i ) one ( Vec i ) t ( Vec i ) d }

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

// ── Montgomery multiply (FIOS) ──────────────────────────────────────
//
// dst = a·b·R^-1 mod m for a·b < m·R (true whenever a < R and b < m, or
// both < m). `dst` may alias a or b: the result is assembled in the
// context's t / d and written last.
//
// FIOS: each row folds the product a·b[r] and the reduction q·m into ONE
// pass over the accumulator — two carry chains side by side, one load and
// one store of t[j] per limb — instead of CIOS's two passes (multiply,
// then reduce), which read and wrote every accumulator limb twice. q is
// known before the pass: it only needs t[0] + a[0]·b[r].
@ _rm_mul_d RsaMont c ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : i n . c n
    : *i tp ( vec_data [i] . c t )
    : *i dp ( vec_data [i] . c d )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i mp ( vec_data [i] . c m )
    : u64 n0 # u64 . c n0
    : u64 a0 # u64 . ap 0
    : u64 m0 # u64 . mp 0
    : ~ i k 0
    ~ < k + n 2 { = . tp k 0 = k + k 1 }
    : ~ i r 0
    ~ < r n {
        : u64 bi # u64 . bp r
        : u64 t0 # u64 . tp 0
        : u64 s0 ( nurl_mac_lo a0 bi t0 0 )
        : ~ u64 c1 ( nurl_mac_hi a0 bi t0 0 )
        : u64 q * s0 n0
        // the low limb of s0 + q·m0 is 0 by construction: only its carry
        : ~ u64 c2 ( nurl_mac_hi q m0 s0 0 )
        : ~ i j 1
        ~ < j n {
            : u64 aj # u64 . ap j
            : u64 mj # u64 . mp j
            : u64 tj # u64 . tp j
            : u64 s1 ( nurl_mac_lo aj bi tj c1 )
            = c1 ( nurl_mac_hi aj bi tj c1 )
            : u64 s2 ( nurl_mac_lo q mj s1 c2 )
            = c2 ( nurl_mac_hi q mj s1 c2 )
            = . tp - j 1 # i s2
            = j + j 1
        }
        // t[n] + c1 + c2 → t[n-1], its carry above
        : u64 tn # u64 . tp n
        : u64 u1 ( nurl_addc_lo tn c1 0 )
        : u64 k1 ( nurl_addc_hi tn c1 0 )
        : u64 u2 ( nurl_addc_lo u1 c2 0 )
        : u64 k2 ( nurl_addc_hi u1 c2 0 )
        = . tp - n 1 # i u2
        = . tp n # i + k1 k2
        = r + r 1
    }
    // t < 2m: subtract m once, keep whichever is in range — by mask.
    : ~ u64 bb 0
    : ~ i j3 0
    ~ < j3 n {
        : u64 x # u64 . tp j3
        : u64 y # u64 . mp j3
        = . dp j3 # i ( nurl_subb_lo x y bb )
        = bb ( nurl_subb_hi x y bb )
        = j3 + j3 1
    }
    : i topb - . tp n # i bb
    : i mask ? < topb 0 0 - 0 1
    : i imask ^^ mask - 0 1
    : *i op ( vec_data [i] dst )
    = j3 0
    ~ < j3 n { = . op j3 | & mask . dp j3 & imask . tp j3 = j3 + j3 1 }
}

// dst = a + b mod m (a, b < m), constant time.
@ __rm_add_d RsaMont c ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : i n . c n
    : *i tp ( vec_data [i] . c t )
    : *i dp ( vec_data [i] . c d )
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
@ __rm_sub_d RsaMont c ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : i n . c n
    : *i tp ( vec_data [i] . c t )
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
@ __rm_dbl_d RsaMont c ( Vec i ) x → v {
    : i n . c n
    : *i xp ( vec_data [i] x )
    : *i tp ( vec_data [i] . c t )
    : *i mp ( vec_data [i] . c m )
    : ~ u64 hi 0
    : ~ i j 0
    ~ < j n {
        : u64 w # u64 . xp j
        = . tp j # i | << w 1 hi
        = hi >> w 63
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
    : RsaMont c @ RsaMont { n m n0 ( __rm_zeros n ) ( __rm_zeros n ) ( __rm_zeros + n 2 ) ( __rm_zeros n ) }
    // R^2 mod m. 64n = s·2^h with s odd: double 1 up to 2^(64n + s) mod m
    // — that is 2^s in Montgomery form — then h Montgomery squarings take
    // it to 2^(s·2^h) = 2^(64n) = R in Montgomery form, i.e. R^2 mod m.
    : ~ i s * 64 n
    : ~ i h 0
    ~ == & s 1 0 { = s >> s 1 = h + h 1 }
    // r2 and one are filled in place, through the context's own vectors.
    ( vec_put [i] . c r2 0 1 )
    : ~ i k 0
    ~ < k + * 64 n s { ( __rm_dbl_d c . c r2 ) = k + k 1 }
    = k 0
    ~ < k h { ( _rm_mul_d c . c r2 . c r2 . c r2 ) = k + k 1 }
    // 1 in Montgomery form: R^2·1·R^-1.
    : ( Vec i ) one1 ( __rm_zeros n )
    ( vec_put [i] one1 0 1 )
    ( _rm_mul_d c . c one . c r2 one1 )
    ^ c
}

// Plain x (any number of limbs) → Montgomery form mod m, by Horner over
// n-limb chunks from the top: acc = acc·R + chunk, each chunk entered as
// chunk·R^2·R^-1. Valid for any x, so a 2048-bit message reduces into a
// 1024-bit factor's domain directly.
@ _rm_enter RsaMont c ( Vec i ) x i xn → ( Vec i ) {
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
        ( _rm_mul_d c acc acc . c r2 )   // acc·R (in form: acc·R·R)
        ( _rm_mul_d c ch ch . c r2 )     // chunk in form
        ( __rm_add_d c acc acc ch )
        = q - q 1
    }
    ^ acc
}

// Montgomery form → plain.
@ _rm_leave RsaMont c ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) one1 ( __rm_zeros . c n )
    ( vec_put [i] one1 0 1 )
    : ( Vec i ) out ( __rm_zeros . c n )
    ( _rm_mul_d c out a one1 )
    ^ out
}

// base^e for a SECRET exponent: base in Montgomery form, e as en limbs
// (little-endian). Fixed 4-bit windows over all en limbs, table entry
// chosen by a masked scan of all sixteen: the same work for every e of
// that width. Result in Montgomery form.
@ _rm_pow_ct RsaMont c ( Vec i ) base ( Vec i ) e i en → ( Vec i ) {
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
    : ~ i w 2
    ~ < w 16 {
        = j 0
        ~ < j n { = . pp j . tb + * - w 1 n j = j + j 1 }
        ( _rm_mul_d c cur prev base )
        = j 0
        ~ < j n { = . tb + * w n j . cp j = j + j 1 }
        = w + w 1
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
            ( _rm_mul_d c acc acc acc )
            ( _rm_mul_d c acc acc acc )
            ( _rm_mul_d c acc acc acc )
            ( _rm_mul_d c acc acc acc )
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
            ( _rm_mul_d c acc acc sel )
            = nib - nib 1
        }
        = li - li 1
    }
    ^ acc
}

// base^e for a PUBLIC exponent (big-endian bytes): plain square-and-
// multiply, Montgomery form in and out.
@ _rm_pow_pub RsaMont c ( Vec i ) base ( Vec u ) e → ( Vec i ) {
    : ( Vec i ) acc ( __rm_zeros . c n )
    ( __rm_copy_d acc . c one . c n )
    : i len ( vec_len [u] e )
    : ~ i k 0
    ~ < k len {
        : i by ( __rm_get e k )
        : ~ i bit 7
        ~ >= bit 0 {
            ( _rm_mul_d c acc acc acc )
            ? != & >> by bit 1 0 { ( _rm_mul_d c acc acc base ) } {}
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

// ── CRT key blob ────────────────────────────────────────────────────

@ _rsa_is_crt_blob ( Vec u ) d → b {
    ? < ( vec_len [u] d ) 4 { ^ F } {}
    ^ & & == ( __rm_get d 0 ) 0 == ( __rm_get d 1 ) 67 & == ( __rm_get d 2 ) 82 == ( __rm_get d 3 ) 84
}

// Field `idx` (0 p, 1 q, 2 d_p, 3 d_q, 4 q^-1) of a CRT blob; [] if short.
@ __rm_blob_field ( Vec u ) blob i idx → ( Vec u ) {
    : i len ( vec_len [u] blob )
    : ~ i at 4
    : ~ i f 0
    ~ <= f idx {
        ? > + at 2 len { ^ ( vec_new [u] ) } {}
        : i fl | << ( __rm_get blob at ) 8 ( __rm_get blob + at 1 )
        ? > + + at 2 fl len { ^ ( vec_new [u] ) } {}
        ? == f idx { ^ ( bytes_slice blob + at 2 + + at 2 fl ) } {}
        = at + + at 2 fl
        = f + f 1
    }
    ^ ( vec_new [u] )
}

// d_x + r·(x − 1) for a fresh 64-bit r, as nx + 1 limbs: the same exponent
// modulo the group order x − 1, different bits every call.
@ __rm_blind_exp ( Vec u ) dx_be RsaMont cx → ( Vec i ) {
    : i n . cx n
    : ( Vec i ) out ( __rm_zeros + n 1 )
    : ( Vec i ) dx ( __rm_from_be dx_be n )
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
@ __rsa_crt ( Vec u ) blob ( Vec u ) e ( Vec i ) msg i msgn i k → ( Vec u ) {
    : ( Vec u ) pb ( __rm_blob_field blob 0 )
    : ( Vec u ) qb ( __rm_blob_field blob 1 )
    : ( Vec u ) dpb ( __rm_blob_field blob 2 )
    : ( Vec u ) dqb ( __rm_blob_field blob 3 )
    : ( Vec u ) qib ( __rm_blob_field blob 4 )
    ? | | == ( vec_len [u] pb ) 0 == ( vec_len [u] qb ) 0 | | == ( vec_len [u] dpb ) 0 == ( vec_len [u] dqb ) 0 == ( vec_len [u] qib ) 0 {
        ^ ( vec_new [u] )
    } {}
    : RsaMont cp ( _rm_ctx pb )
    : RsaMont cq ( _rm_ctx qb )
    : i np . cp n
    : i nq . cq n
    // the message in each half's domain
    : ( Vec i ) mp ( _rm_enter cp msg msgn )
    : ( Vec i ) mq ( _rm_enter cq msg msgn )
    : ( Vec i ) ep ( __rm_blind_exp dpb cp )
    : ( Vec i ) eq ( __rm_blind_exp dqb cq )
    : ( Vec i ) sp ( _rm_pow_ct cp mp ep + np 1 )   // Montgomery form mod p
    : ( Vec i ) sqm ( _rm_pow_ct cq mq eq + nq 1 )
    : ( Vec i ) sq ( _rm_leave cq sqm )             // plain, < q
    // Garner: h = (s_p − s_q)·q^-1 mod p ; s = s_q + q·h
    : ( Vec i ) sqp ( _rm_enter cp sq nq )
    : ( Vec i ) diff ( __rm_zeros np )
    ( __rm_sub_d cp diff sp sqp )
    : ( Vec i ) qinv ( __rm_from_be qib np )
    : ( Vec i ) h ( __rm_zeros np )
    ( _rm_mul_d cp h diff qinv )                    // (form)·plain → plain
    : ( Vec i ) ql ( __rm_from_be qb nq )
    : i sn + np nq
    : ( Vec i ) s ( __rm_zeros + sn 1 )
    : *i spp ( vec_data [i] s )
    : *i qp ( vec_data [i] ql )
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
    : ( Vec i ) chkp ( _rm_pow_pub cp ( _rm_enter cp s + sn 1 ) e )
    : ( Vec i ) chkq ( _rm_pow_pub cq ( _rm_enter cq s + sn 1 ) e )
    ? ! & ( __rm_eq chkp mp np ) ( __rm_eq chkq mq nq ) { ^ ( vec_new [u] ) } {}
    ^ ( __rm_to_be s + sn 1 k )
}

// m^d mod n, k bytes big-endian. d: a plain private exponent (one
// exponentiation at full width) or a CRT blob. [] when the CRT fault check
// fails.
@ _rsa_private ( Vec u ) n ( Vec u ) e ( Vec u ) d ( Vec u ) m i k → ( Vec u ) {
    : i mn ( __rm_limbs_for m )
    : ( Vec i ) ml ( __rm_from_be m mn )
    ? ( _rsa_is_crt_blob d ) { ^ ( __rsa_crt d e ml mn k ) } {}
    : RsaMont c ( _rm_ctx n )
    : i dn . c n
    : ( Vec i ) dl ( __rm_from_be d dn )
    : ( Vec i ) r ( _rm_pow_ct c ( _rm_enter c ml mn ) dl dn )
    ^ ( __rm_to_be ( _rm_leave c r ) dn k )
}

// s^e mod n, k bytes big-endian (public exponent: variable time).
@ _rsa_public ( Vec u ) n ( Vec u ) e ( Vec u ) s i k → ( Vec u ) {
    : RsaMont c ( _rm_ctx n )
    : i sn ( __rm_limbs_for s )
    : ( Vec i ) sl ( __rm_from_be s sn )
    : ( Vec i ) r ( _rm_pow_pub c ( _rm_enter c sl sn ) e )
    ^ ( __rm_to_be ( _rm_leave c r ) . c n k )
}
