// stdlib/std/slhdsa.nu — SLH-DSA (FIPS 205) in pure NURL, SHAKE family.
//
// The third and last of NIST's post-quantum standards, and the one that
// assumes least. ML-KEM and ML-DSA rest on lattice problems; SLH-DSA
// rests on nothing but the hash function. If a break lands on lattices,
// this is what still stands — which is why it exists alongside ML-DSA
// rather than instead of it.
//
// The price is size and speed. A signature is 7 856 bytes at the
// smallest parameter set, against ML-DSA-44's 2 420, and signing walks
// a hypertree of Merkle trees rather than doing algebra. Use ML-DSA by
// default; use this where a signature is rare, long-lived, and must
// outlast an assumption — firmware images, root certificates, software
// releases.
//
//   set            pk    sk    signature   security
//   128s           32    64        7856    AES-128, small signatures
//   128f           32    64       17088    AES-128, fast signing
//   192s           48    96       16224    AES-192
//   192f           48    96       35664    AES-192, fast signing
//   256s           64   128       29792    AES-256
//   256f           64   128       49856    AES-256, fast signing
//
// The `s`/`f` axis is a direct trade: `s` signs slowly and produces a
// small signature, `f` the other way round. Verification is fast in
// both.
//
// API:
//   ( slhdsa_keygen i set )                          → *SlhKeys
//   ( slhdsa_sign i set ( Vec u ) sk
//                 ( Vec u ) msg ( Vec u ) ctx )      → ( Vec u )
//   ( slhdsa_verify i set ( Vec u ) pk ( Vec u ) msg
//                   ( Vec u ) ctx ( Vec u ) sig )    → b
//
// Deterministic and internal forms, which FIPS 205 defines and NIST's
// ACVP vectors exercise:
//   ( slhdsa_keygen_derand set skseed skprf pkseed ) → *SlhKeys
//   ( slhdsa_sign_internal set sk msg addrnd )       → ( Vec u )
//   ( slhdsa_verify_internal set pk msg sig )        → b
//
// Sets are named by the integers 128, 129, 192, 193, 256, 257 — the
// even value is the `s` variant and the odd one its `f` sibling; see
// `slhdsa_set_*` below rather than memorising that.
//
// Only the SHAKE instantiation is implemented. FIPS 205 also defines a
// SHA-2 family with the same structure and different hash plumbing;
// those parameter sets are not available here and the ACVP gate reports
// them as skipped.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha3.nu`
$ `stdlib/std/random.nu`

// ── Parameters ─────────────────────────────────────────────────────
//
// n   hash output and node size in bytes
// h   total hypertree height
// d   number of hypertree layers  (h' = h/d is one XMSS tree's height)
// a   FORS tree height, k FORS trees
// m   H_msg output length

: SlhParams {
    i n
    i h
    i d
    i hp
    i a
    i k
    i m
    i len  // WOTS+ chains per key: 2n + 3
}

@ slhdsa_set_128s → i { ^ 128 }

@ slhdsa_set_128f → i { ^ 129 }

@ slhdsa_set_192s → i { ^ 192 }

@ slhdsa_set_192f → i { ^ 193 }

@ slhdsa_set_256s → i { ^ 256 }

@ slhdsa_set_256f → i { ^ 257 }

@ __slh_params i set → SlhParams {
    ? == set 129 { ^ @ SlhParams { 16 66 22 3 6 33 34 35 } } {}
    ? == set 192 { ^ @ SlhParams { 24 63 7 9 14 17 39 51 } } {}
    ? == set 193 { ^ @ SlhParams { 24 66 22 3 8 33 42 51 } } {}
    ? == set 256 { ^ @ SlhParams { 32 64 8 8 14 22 47 67 } } {}
    ? == set 257 { ^ @ SlhParams { 32 68 17 4 9 35 49 67 } } {}
    ^ @ SlhParams { 16 63 7 9 12 14 30 35 }  // 128s
}

@ slhdsa_pk_len i set → i {
    : SlhParams p ( __slh_params set )
    ^ * 2 . p n
}

@ slhdsa_sk_len i set → i {
    : SlhParams p ( __slh_params set )
    ^ * 4 . p n
}

@ slhdsa_sig_len i set → i {
    : SlhParams p ( __slh_params set )
    ^ * . p n + + + 1 * . p k + 1 . p a . p h * . p d . p len
}

// ── Addresses (FIPS 205 §4.2) ──────────────────────────────────────
//
// Every hash call is domain-separated by a 32-byte address saying
// exactly where in the structure it sits: which hypertree layer, which
// tree, what kind of node, and which position. Two hashes anywhere in
// the scheme therefore never collide by accident, and that is the whole
// argument for its security — so the field layout below is not
// bookkeeping, it is the proof obligation.
//
//   [0..4)   layer      [4..16)  tree index (12 bytes, big-endian)
//   [16..20) type       [20..24) key pair / word 1
//   [24..28) chain or tree height  [28..32) hash or tree index

@ __adrs_new → ( Vec u ) {
    : ( Vec u ) a ( vec_with_cap [u] 32 )
    : b _l ( vec_set_len [u] a 32 )
    : *u p ( vec_data [u] a )
    : ~ i i 0
    ~ < i 32 { = . p i # u 0 = i + i 1 }
    ^ a
}

@ __adrs_copy ( Vec u ) a → ( Vec u ) {
    ^ ( bytes_slice a 0 32 )
}

// Write a big-endian integer into `len` bytes at `off`.
//
// Byte k needs `v >> 8k`, and the tree field is 12 bytes wide while `v`
// is 64 bits — so k reaches 8 and the shift count reaches 64. x86 takes
// shift counts modulo 64, which would wrap and write the low bytes
// again into the high ones. Those bytes are zero by construction, so
// the loop stops shifting at 8 and zero-fills the rest.
@ __adrs_put * u p i off i len i v → v {
    : ~ i k 0
    ~ < k len {
        : i byte ? < k 8 & # i >> # u64 v # u64 * 8 k 255 0
        = . p + off - - len 1 k # u byte
        = k + k 1
    }
}

@ __adrs_set_layer ( Vec u ) a i l → v { ( __adrs_put ( vec_data [u] a ) 0 4 l ) }

@ __adrs_set_tree ( Vec u ) a i t → v { ( __adrs_put ( vec_data [u] a ) 4 12 t ) }

@ __adrs_set_kp ( Vec u ) a i i2 → v { ( __adrs_put ( vec_data [u] a ) 20 4 i2 ) }

@ __adrs_set_chain ( Vec u ) a i i2 → v { ( __adrs_put ( vec_data [u] a ) 24 4 i2 ) }

@ __adrs_set_hash ( Vec u ) a i i2 → v { ( __adrs_put ( vec_data [u] a ) 28 4 i2 ) }

@ __adrs_set_height ( Vec u ) a i i2 → v { ( __adrs_put ( vec_data [u] a ) 24 4 i2 ) }

@ __adrs_set_index ( Vec u ) a i i2 → v { ( __adrs_put ( vec_data [u] a ) 28 4 i2 ) }

// Setting the type zeroes the three words after it, per §4.2 — the
// subsequent setters refill whichever ones that type uses.
@ __adrs_set_type ( Vec u ) a i y → v {
    : *u p ( vec_data [u] a )
    ( __adrs_put p 16 4 y )
    : ~ i k 20
    ~ < k 32 { = . p k # u 0 = k + k 1 }
}

@ __adrs_get_kp ( Vec u ) a → i {
    : *u p ( vec_data [u] a )
    ^ | | | << # i . p 20 24 << # i . p 21 16 << # i . p 22 8 # i . p 23
}

@ __adrs_get_index ( Vec u ) a → i {
    : *u p ( vec_data [u] a )
    ^ | | | << # i . p 28 24 << # i . p 29 16 << # i . p 30 8 # i . p 31
}

// ── The SHAKE instantiation (FIPS 205 §11.1) ───────────────────────
//
// Every one of these is SHAKE256 over a concatenation; the differences
// are which pieces go in and how many bytes come out.

@ __slh_shake ( Vec u ) a ( Vec u ) b ( Vec u ) c i outlen → ( Vec u ) {
    : *Sha3 h ( shake256_init )
    ( sha3_absorb h a )
    ( sha3_absorb h b )
    ( sha3_absorb h c )
    : ( Vec u ) o ( sha3_squeeze h outlen )
    ( sha3_free h )
    ^ o
}

@ __slh_prf ( Vec u ) pkseed ( Vec u ) adrs ( Vec u ) skseed i n → ( Vec u ) {
    ^ ( __slh_shake pkseed adrs skseed n )
}

@ __slh_f ( Vec u ) pkseed ( Vec u ) adrs ( Vec u ) m i n → ( Vec u ) {
    ^ ( __slh_shake pkseed adrs m n )
}

// ── base-2^b decomposition (Algorithm 1) ───────────────────────────

@ __base_2b ( Vec u ) x i b i outlen → ( Vec i ) {
    : ( Vec i ) out ( vec_with_cap [i] ? > outlen 0 outlen 1 )
    : b _l ( vec_set_len [i] out ? > outlen 0 outlen 1 )
    : *i op ( vec_data [i] out )
    : *u xp ( vec_data [u] x )
    : ~ i pos 0
    : ~ i bits 0
    : ~ i total 0
    : ~ i j 0
    ~ < j outlen {
        ~ < bits b {
            = total + << total 8 # i . xp pos
            = pos + pos 1
            = bits + bits 8
        }
        = bits - bits b
        = . op j & >> total bits - << 1 b 1
        = j + j 1
    }
    ^ out
}

// ── WOTS+ (§5) ─────────────────────────────────────────────────────

// Iterate F from step `i` for `s` steps. The chain length is what a
// WOTS+ signature reveals: publishing the value at step m lets anyone
// walk forward to w-1, and nobody walk back.
@ __wots_chain ( Vec u ) x i start i steps ( Vec u ) pkseed ( Vec u ) adrs i n → ( Vec u ) {
    : ~ ( Vec u ) tmp ( bytes_slice x 0 ( vec_len [u] x ) )
    : ~ i j start
    ~ < j + start steps {
        ( __adrs_set_hash adrs j )
        : ( Vec u ) nxt ( __slh_f pkseed adrs tmp n )
        ( vec_free [u] tmp )
        = tmp nxt
        = j + j 1
    }
    ^ tmp
}

// The message expanded to `len` base-w digits, with the checksum digits
// appended. The checksum is what stops an attacker walking a chain
// forward to forge a larger digit: raising any digit lowers the
// checksum, which can only be raised.
@ __wots_msg ( Vec u ) m SlhParams p → ( Vec i ) {
    : i len1 * 2 . p n
    : ( Vec i ) msg ( __base_2b m 4 len1 )
    : ~ i csum 0
    : ~ i i 0
    ~ < i len1 {
        = csum + csum - 15 ?? ( vec_get [i] msg i ) { T x → { x } F → { 0 } }
        = i + i 1
    }
    // len2 = 3 digits of 4 bits = 12 bits, left-shifted into 2 bytes.
    = csum << csum 4
    : ( Vec u ) cb ( vec_with_cap [u] 2 )
    ( vec_push [u] cb # u & >> csum 8 255 )
    ( vec_push [u] cb # u & csum 255 )
    : ( Vec i ) cs ( __base_2b cb 4 3 )
    = i 0
    ~ < i 3 { ( vec_push [i] msg ?? ( vec_get [i] cs i ) { T x → { x } F → { 0 } } ) = i + i 1 }
    ( vec_free [i] cs )
    ( vec_free [u] cb )
    ^ msg
}

@ __wots_pkgen ( Vec u ) skseed ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : ( Vec u ) skadrs ( __adrs_copy adrs )
    ( __adrs_set_type skadrs 5 )
    ( __adrs_set_kp skadrs ( __adrs_get_kp adrs ) )
    : ( Vec u ) tmp ( vec_new [u] )
    : ~ i i 0
    ~ < i . p len {
        ( __adrs_set_chain skadrs i )
        : ( Vec u ) sk ( __slh_prf pkseed skadrs skseed . p n )
        ( __adrs_set_chain adrs i )
        : ( Vec u ) ch ( __wots_chain sk 0 15 pkseed adrs . p n )
        ( bytes_extend_bytes tmp ch )
        ( vec_free [u] ch )
        ( vec_free [u] sk )
        = i + i 1
    }
    : ( Vec u ) pkadrs ( __adrs_copy adrs )
    ( __adrs_set_type pkadrs 1 )
    ( __adrs_set_kp pkadrs ( __adrs_get_kp adrs ) )
    : ( Vec u ) out ( __slh_f pkseed pkadrs tmp . p n )
    ( vec_free [u] tmp ) ( vec_free [u] pkadrs ) ( vec_free [u] skadrs )
    ^ out
}

@ __wots_sign ( Vec u ) m ( Vec u ) skseed ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : ( Vec i ) msg ( __wots_msg m p )
    : ( Vec u ) skadrs ( __adrs_copy adrs )
    ( __adrs_set_type skadrs 5 )
    ( __adrs_set_kp skadrs ( __adrs_get_kp adrs ) )
    : ( Vec u ) sig ( vec_new [u] )
    : ~ i i 0
    ~ < i . p len {
        ( __adrs_set_chain skadrs i )
        : ( Vec u ) sk ( __slh_prf pkseed skadrs skseed . p n )
        ( __adrs_set_chain adrs i )
        : i steps ?? ( vec_get [i] msg i ) { T x → { x } F → { 0 } }
        : ( Vec u ) ch ( __wots_chain sk 0 steps pkseed adrs . p n )
        ( bytes_extend_bytes sig ch )
        ( vec_free [u] ch ) ( vec_free [u] sk )
        = i + i 1
    }
    ( vec_free [u] skadrs ) ( vec_free [i] msg )
    ^ sig
}

@ __wots_pk_from_sig ( Vec u ) sig ( Vec u ) m ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : ( Vec i ) msg ( __wots_msg m p )
    : ( Vec u ) tmp ( vec_new [u] )
    : ~ i i 0
    ~ < i . p len {
        ( __adrs_set_chain adrs i )
        : i mi ?? ( vec_get [i] msg i ) { T x → { x } F → { 0 } }
        : ( Vec u ) si ( bytes_slice sig * i . p n * + i 1 . p n )
        : ( Vec u ) ch ( __wots_chain si mi - 15 mi pkseed adrs . p n )
        ( bytes_extend_bytes tmp ch )
        ( vec_free [u] ch ) ( vec_free [u] si )
        = i + i 1
    }
    : ( Vec u ) pkadrs ( __adrs_copy adrs )
    ( __adrs_set_type pkadrs 1 )
    ( __adrs_set_kp pkadrs ( __adrs_get_kp adrs ) )
    : ( Vec u ) out ( __slh_f pkseed pkadrs tmp . p n )
    ( vec_free [u] tmp ) ( vec_free [u] pkadrs ) ( vec_free [i] msg )
    ^ out
}

// ── XMSS (§6) ──────────────────────────────────────────────────────

// The Merkle root over 2^z WOTS+ public keys, computed by recursion.
//
// This is where an `s` parameter set spends its time: h' = 9 means
// every one of the d layers rebuilds 512 WOTS+ key pairs per signature.
@ __xmss_node ( Vec u ) skseed i i2 i z ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    ? == z 0 {
        ( __adrs_set_type adrs 0 )
        ( __adrs_set_kp adrs i2 )
        ^ ( __wots_pkgen skseed pkseed adrs p )
    } {}
    : ( Vec u ) l ( __xmss_node skseed * 2 i2 - z 1 pkseed adrs p )
    : ( Vec u ) r ( __xmss_node skseed + * 2 i2 1 - z 1 pkseed adrs p )
    ( __adrs_set_type adrs 2 )
    ( __adrs_set_height adrs z )
    ( __adrs_set_index adrs i2 )
    : ( Vec u ) both ( bytes_slice l 0 ( vec_len [u] l ) )
    ( bytes_extend_bytes both r )
    : ( Vec u ) out ( __slh_f pkseed adrs both . p n )
    ( vec_free [u] both ) ( vec_free [u] r ) ( vec_free [u] l )
    ^ out
}

@ __xmss_sign ( Vec u ) m ( Vec u ) skseed i idx ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : ( Vec u ) auth ( vec_new [u] )
    : ~ i j 0
    ~ < j . p hp {
        : i kk ^^ >> idx j 1
        : ( Vec u ) a2 ( __adrs_copy adrs )
        : ( Vec u ) nd ( __xmss_node skseed kk j pkseed a2 p )
        ( bytes_extend_bytes auth nd )
        ( vec_free [u] nd ) ( vec_free [u] a2 )
        = j + j 1
    }
    ( __adrs_set_type adrs 0 )
    ( __adrs_set_kp adrs idx )
    : ( Vec u ) sig ( __wots_sign m skseed pkseed adrs p )
    ( bytes_extend_bytes sig auth )
    ( vec_free [u] auth )
    ^ sig
}

@ __xmss_pk_from_sig i idx ( Vec u ) sigx ( Vec u ) m ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : i wl * . p len . p n
    ( __adrs_set_type adrs 0 )
    ( __adrs_set_kp adrs idx )
    : ( Vec u ) wsig ( bytes_slice sigx 0 wl )
    : ~ ( Vec u ) node ( __wots_pk_from_sig wsig m pkseed adrs p )
    ( vec_free [u] wsig )
    ( __adrs_set_type adrs 2 )
    ( __adrs_set_index adrs idx )
    : ~ i k 0
    ~ < k . p hp {
        ( __adrs_set_height adrs + k 1 )
        : ( Vec u ) ak ( bytes_slice sigx + wl * k . p n + wl * + k 1 . p n )
        : i cur ( __adrs_get_index adrs )
        : ~ ( Vec u ) both ( vec_new [u] )
        ? == % >> idx k 2 0 {
            ( __adrs_set_index adrs / cur 2 )
            ( bytes_extend_bytes both node )
            ( bytes_extend_bytes both ak )
        } {
            ( __adrs_set_index adrs / - cur 1 2 )
            ( bytes_extend_bytes both ak )
            ( bytes_extend_bytes both node )
        }
        : ( Vec u ) nn ( __slh_f pkseed adrs both . p n )
        ( vec_free [u] both ) ( vec_free [u] ak ) ( vec_free [u] node )
        = node nn
        = k + k 1
    }
    ^ node
}

// ── Hypertree (§7) ─────────────────────────────────────────────────

@ __ht_sign ( Vec u ) m ( Vec u ) skseed ( Vec u ) pkseed i idx_tree i idx_leaf SlhParams p → ( Vec u ) {
    : ~ i it idx_tree
    : ~ i il idx_leaf
    : ( Vec u ) adrs ( __adrs_new )
    ( __adrs_set_layer adrs 0 )
    ( __adrs_set_tree adrs it )
    : ( Vec u ) sig0 ( __xmss_sign m skseed il pkseed adrs p )
    : ~ ( Vec u ) out ( bytes_slice sig0 0 ( vec_len [u] sig0 ) )
    : ( Vec u ) a0 ( __adrs_new )
    ( __adrs_set_layer a0 0 )
    ( __adrs_set_tree a0 it )
    : ~ ( Vec u ) root ( __xmss_pk_from_sig il sig0 m pkseed a0 p )
    ( vec_free [u] a0 ) ( vec_free [u] sig0 ) ( vec_free [u] adrs )

    : ~ i j 1
    ~ < j . p d {
        // Masked and logically shifted, not `%` and `>>`: for
        // SLH-DSA-256f the tree index fills all 64 bits, so as a signed
        // `i` it can be negative, and both of those operators would then
        // carry the sign into the next layer's index.
        = il & it - << 1 . p hp 1
        = it # i >> # u64 it # u64 . p hp
        : ( Vec u ) aj ( __adrs_new )
        ( __adrs_set_layer aj j )
        ( __adrs_set_tree aj it )
        : ( Vec u ) sj ( __xmss_sign root skseed il pkseed aj p )
        ( bytes_extend_bytes out sj )
        ? < j - . p d 1 {
            : ( Vec u ) a2 ( __adrs_new )
            ( __adrs_set_layer a2 j )
            ( __adrs_set_tree a2 it )
            : ( Vec u ) nr ( __xmss_pk_from_sig il sj root pkseed a2 p )
            ( vec_free [u] root )
            = root nr
            ( vec_free [u] a2 )
        } {}
        ( vec_free [u] sj ) ( vec_free [u] aj )
        = j + j 1
    }
    ( vec_free [u] root )
    ^ out
}

@ __ht_verify ( Vec u ) m ( Vec u ) sight ( Vec u ) pkseed i idx_tree i idx_leaf ( Vec u ) pkroot SlhParams p → b {
    : i xl * + . p hp . p len . p n
    : ~ i it idx_tree
    : ~ i il idx_leaf
    : ( Vec u ) a0 ( __adrs_new )
    ( __adrs_set_layer a0 0 )
    ( __adrs_set_tree a0 it )
    : ( Vec u ) s0 ( bytes_slice sight 0 xl )
    : ~ ( Vec u ) node ( __xmss_pk_from_sig il s0 m pkseed a0 p )
    ( vec_free [u] s0 ) ( vec_free [u] a0 )
    : ~ i j 1
    ~ < j . p d {
        // Masked and logically shifted, not `%` and `>>`: for
        // SLH-DSA-256f the tree index fills all 64 bits, so as a signed
        // `i` it can be negative, and both of those operators would then
        // carry the sign into the next layer's index.
        = il & it - << 1 . p hp 1
        = it # i >> # u64 it # u64 . p hp
        : ( Vec u ) aj ( __adrs_new )
        ( __adrs_set_layer aj j )
        ( __adrs_set_tree aj it )
        : ( Vec u ) sj ( bytes_slice sight * j xl * + j 1 xl )
        : ( Vec u ) nn ( __xmss_pk_from_sig il sj node pkseed aj p )
        ( vec_free [u] node )
        = node nn
        ( vec_free [u] sj ) ( vec_free [u] aj )
        = j + j 1
    }
    : b ok ( bytes_eq node pkroot )
    ( vec_free [u] node )
    ^ ok
}

// ── FORS (§8) ──────────────────────────────────────────────────────
//
// Forest Of Random Subsets: k trees of 2^a leaves, of which the message
// digest selects one leaf per tree. It is a *few-time* signature — the
// hypertree above exists precisely so that no FORS key is ever used
// twice.

@ __fors_skgen ( Vec u ) skseed ( Vec u ) pkseed ( Vec u ) adrs i idx SlhParams p → ( Vec u ) {
    : ( Vec u ) sk ( __adrs_copy adrs )
    ( __adrs_set_type sk 6 )
    ( __adrs_set_kp sk ( __adrs_get_kp adrs ) )
    ( __adrs_set_index sk idx )
    : ( Vec u ) out ( __slh_prf pkseed sk skseed . p n )
    ( vec_free [u] sk )
    ^ out
}

@ __fors_node ( Vec u ) skseed i i2 i z ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    ? == z 0 {
        : ( Vec u ) sk ( __fors_skgen skseed pkseed adrs i2 p )
        ( __adrs_set_height adrs 0 )
        ( __adrs_set_index adrs i2 )
        : ( Vec u ) out ( __slh_f pkseed adrs sk . p n )
        ( vec_free [u] sk )
        ^ out
    } {}
    : ( Vec u ) l ( __fors_node skseed * 2 i2 - z 1 pkseed adrs p )
    : ( Vec u ) r ( __fors_node skseed + * 2 i2 1 - z 1 pkseed adrs p )
    ( __adrs_set_height adrs z )
    ( __adrs_set_index adrs i2 )
    : ( Vec u ) both ( bytes_slice l 0 ( vec_len [u] l ) )
    ( bytes_extend_bytes both r )
    : ( Vec u ) out ( __slh_f pkseed adrs both . p n )
    ( vec_free [u] both ) ( vec_free [u] r ) ( vec_free [u] l )
    ^ out
}

@ __fors_sign ( Vec u ) md ( Vec u ) skseed ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : ( Vec i ) idx ( __base_2b md . p a . p k )
    : ( Vec u ) sig ( vec_new [u] )
    : ~ i i 0
    ~ < i . p k {
        : i ii ?? ( vec_get [i] idx i ) { T x → { x } F → { 0 } }
        : ( Vec u ) sk ( __fors_skgen skseed pkseed adrs + * i << 1 . p a ii p )
        ( bytes_extend_bytes sig sk )
        ( vec_free [u] sk )
        : ~ i j 0
        ~ < j . p a {
            : i s ^^ >> ii j 1
            : ( Vec u ) nd ( __fors_node skseed + * i << 1 - . p a j s j pkseed adrs p )
            ( bytes_extend_bytes sig nd )
            ( vec_free [u] nd )
            = j + j 1
        }
        = i + i 1
    }
    ( vec_free [i] idx )
    ^ sig
}

@ __fors_pk_from_sig ( Vec u ) sigf ( Vec u ) md ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : ( Vec i ) idx ( __base_2b md . p a . p k )
    : i step * + 1 . p a . p n
    : ( Vec u ) roots ( vec_new [u] )
    : ~ i i 0
    ~ < i . p k {
        : i ii ?? ( vec_get [i] idx i ) { T x → { x } F → { 0 } }
        : ( Vec u ) sk ( bytes_slice sigf * i step + * i step . p n )
        ( __adrs_set_height adrs 0 )
        ( __adrs_set_index adrs + * i << 1 . p a ii )
        : ~ ( Vec u ) node ( __slh_f pkseed adrs sk . p n )
        ( vec_free [u] sk )
        : ~ i j 0
        ~ < j . p a {
            : ( Vec u ) aj ( bytes_slice sigf + + * i step . p n * j . p n + + * i step . p n * + j 1 . p n )
            ( __adrs_set_height adrs + j 1 )
            : i cur ( __adrs_get_index adrs )
            : ~ ( Vec u ) both ( vec_new [u] )
            ? == % >> ii j 2 0 {
                ( __adrs_set_index adrs / cur 2 )
                ( bytes_extend_bytes both node )
                ( bytes_extend_bytes both aj )
            } {
                ( __adrs_set_index adrs / - cur 1 2 )
                ( bytes_extend_bytes both aj )
                ( bytes_extend_bytes both node )
            }
            : ( Vec u ) nn ( __slh_f pkseed adrs both . p n )
            ( vec_free [u] both ) ( vec_free [u] aj ) ( vec_free [u] node )
            = node nn
            = j + j 1
        }
        ( bytes_extend_bytes roots node )
        ( vec_free [u] node )
        = i + i 1
    }
    : ( Vec u ) fa ( __adrs_copy adrs )
    ( __adrs_set_type fa 4 )
    ( __adrs_set_kp fa ( __adrs_get_kp adrs ) )
    : ( Vec u ) out ( __slh_f pkseed fa roots . p n )
    ( vec_free [u] fa ) ( vec_free [u] roots ) ( vec_free [i] idx )
    ^ out
}

// ── Keys, signing, verification ────────────────────────────────────

: SlhKeys {
    ( Vec u ) pk
    ( Vec u ) sk
}

@ slhdsa_pk * SlhKeys h → ( Vec u ) { ^ . h pk }

@ slhdsa_sk * SlhKeys h → ( Vec u ) { ^ . h sk }

@ slhdsa_keys_free * SlhKeys h → v {
    ( vec_free [u] . h pk )
    ( vec_free [u] . h sk )
    ( nurl_free # s h )
}

@ slhdsa_keygen_derand i set ( Vec u ) skseed ( Vec u ) skprf ( Vec u ) pkseed → *SlhKeys {
    : SlhParams p ( __slh_params set )
    : ( Vec u ) adrs ( __adrs_new )
    ( __adrs_set_layer adrs - . p d 1 )
    : ( Vec u ) root ( __xmss_node skseed 0 . p hp pkseed adrs p )
    ( vec_free [u] adrs )
    : ( Vec u ) pk ( bytes_slice pkseed 0 . p n )
    ( bytes_extend_bytes pk root )
    : ( Vec u ) sk ( bytes_slice skseed 0 . p n )
    ( bytes_extend_bytes sk skprf )
    ( bytes_extend_bytes sk pkseed )
    ( bytes_extend_bytes sk root )
    ( vec_free [u] root )
    : *SlhKeys h # *SlhKeys ( nurl_alloc Z SlhKeys )
    = . h pk pk
    = . h sk sk
    ^ h
}

@ slhdsa_keygen i set → *SlhKeys {
    : SlhParams p ( __slh_params set )
    : ( Vec u ) a ( rand_bytes . p n )
    : ( Vec u ) b2 ( rand_bytes . p n )
    : ( Vec u ) c ( rand_bytes . p n )
    : *SlhKeys h ( slhdsa_keygen_derand set a b2 c )
    ( vec_free [u] c ) ( vec_free [u] b2 ) ( vec_free [u] a )
    ^ h
}

// Split H_msg's output into the FORS digest and the two tree indices.
@ __slh_idx_tree ( Vec u ) digest SlhParams p → i {
    : i ka / + * . p k . p a 7 8
    : i hd - . p h / . p h . p d
    : i tb / + hd 7 8
    : *u dp ( vec_data [u] digest )
    : ~ i v 0
    : ~ i i 0
    ~ < i tb { = v + << v 8 # i . dp + ka i = i + i 1 }
    // `1 << hd` is not a usable mask when hd is 64 — x86 takes shift
    // counts modulo 64, so it yields 1 and the mask becomes 0, which
    // pins every tree index to zero. SLH-DSA-256f is the one parameter
    // set where h − h/d reaches 64 exactly, and it was the only one
    // that failed its vectors. All ones is the right mask there.
    ? >= hd 64 { ^ v } {}
    ^ & v - << 1 hd 1
}

@ __slh_idx_leaf ( Vec u ) digest SlhParams p → i {
    : i ka / + * . p k . p a 7 8
    : i hd - . p h / . p h . p d
    : i tb / + hd 7 8
    : i hq / . p h . p d
    : i lb / + hq 7 8
    : *u dp ( vec_data [u] digest )
    : ~ i v 0
    : ~ i i 0
    ~ < i lb { = v + << v 8 # i . dp + + ka tb i = i + i 1 }
    ^ & v - << 1 hq 1
}

@ slhdsa_sign_internal i set ( Vec u ) sk ( Vec u ) msg ( Vec u ) addrnd → ( Vec u ) {
    : SlhParams p ( __slh_params set )
    : i n . p n
    : ( Vec u ) skseed ( bytes_slice sk 0 n )
    : ( Vec u ) skprf ( bytes_slice sk n * 2 n )
    : ( Vec u ) pkseed ( bytes_slice sk * 2 n * 3 n )
    : ( Vec u ) pkroot ( bytes_slice sk * 3 n * 4 n )

    : ( Vec u ) r ( __slh_shake skprf addrnd msg n )
    : ( Vec u ) hin ( bytes_slice pkseed 0 n )
    ( bytes_extend_bytes hin pkroot )
    : ( Vec u ) digest ( __slh_shake r hin msg . p m )
    ( vec_free [u] hin )

    : i ka / + * . p k . p a 7 8
    : ( Vec u ) md ( bytes_slice digest 0 ka )
    : i it ( __slh_idx_tree digest p )
    : i il ( __slh_idx_leaf digest p )
    ( vec_free [u] digest )

    : ( Vec u ) adrs ( __adrs_new )
    ( __adrs_set_tree adrs it )
    ( __adrs_set_type adrs 3 )
    ( __adrs_set_kp adrs il )
    : ( Vec u ) sigf ( __fors_sign md skseed pkseed adrs p )
    : ( Vec u ) pkf ( __fors_pk_from_sig sigf md pkseed adrs p )
    : ( Vec u ) sigh ( __ht_sign pkf skseed pkseed it il p )

    : ( Vec u ) out ( bytes_slice r 0 n )
    ( bytes_extend_bytes out sigf )
    ( bytes_extend_bytes out sigh )

    ( vec_free [u] sigh ) ( vec_free [u] pkf ) ( vec_free [u] sigf )
    ( vec_free [u] adrs ) ( vec_free [u] md ) ( vec_free [u] r )
    ( vec_free [u] pkroot ) ( vec_free [u] pkseed )
    ( vec_free [u] skprf ) ( vec_free [u] skseed )
    ^ out
}

@ slhdsa_verify_internal i set ( Vec u ) pk ( Vec u ) msg ( Vec u ) sig → b {
    : SlhParams p ( __slh_params set )
    : i n . p n
    ? != ( vec_len [u] pk ) * 2 n { ^ F } {}
    ? != ( vec_len [u] sig ) ( slhdsa_sig_len set ) { ^ F } {}
    : ( Vec u ) pkseed ( bytes_slice pk 0 n )
    : ( Vec u ) pkroot ( bytes_slice pk n * 2 n )
    : i fl * * . p k + 1 . p a n
    : ( Vec u ) r ( bytes_slice sig 0 n )
    : ( Vec u ) sigf ( bytes_slice sig n + n fl )
    : ( Vec u ) sigh ( bytes_slice sig + n fl ( vec_len [u] sig ) )

    : ( Vec u ) hin ( bytes_slice pkseed 0 n )
    ( bytes_extend_bytes hin pkroot )
    : ( Vec u ) digest ( __slh_shake r hin msg . p m )
    ( vec_free [u] hin )
    : i ka / + * . p k . p a 7 8
    : ( Vec u ) md ( bytes_slice digest 0 ka )
    : i it ( __slh_idx_tree digest p )
    : i il ( __slh_idx_leaf digest p )
    ( vec_free [u] digest )

    : ( Vec u ) adrs ( __adrs_new )
    ( __adrs_set_tree adrs it )
    ( __adrs_set_type adrs 3 )
    ( __adrs_set_kp adrs il )
    : ( Vec u ) pkf ( __fors_pk_from_sig sigf md pkseed adrs p )
    : b ok ( __ht_verify pkf sigh pkseed it il pkroot p )

    ( vec_free [u] pkf ) ( vec_free [u] adrs ) ( vec_free [u] md )
    ( vec_free [u] sigh ) ( vec_free [u] sigf ) ( vec_free [u] r )
    ( vec_free [u] pkroot ) ( vec_free [u] pkseed )
    ^ ok
}

// ── The external interface (§10.2) ─────────────────────────────────
//
// M' = 0x00 ‖ |ctx| ‖ ctx ‖ M, the same shape ML-DSA uses.

@ __slh_mprime ( Vec u ) msg ( Vec u ) ctx → ( Vec u ) {
    : ( Vec u ) m ( vec_new [u] )
    ( vec_push [u] m # u 0 )
    ( vec_push [u] m # u ( vec_len [u] ctx ) )
    ( bytes_extend_bytes m ctx )
    ( bytes_extend_bytes m msg )
    ^ m
}

// Hedged: a fresh n-byte draw goes into the randomiser. FIPS 205's
// deterministic variant uses PK.seed instead, which is
// `slhdsa_sign_deterministic`.
@ slhdsa_sign i set ( Vec u ) sk ( Vec u ) msg ( Vec u ) ctx → ( Vec u ) {
    ? > ( vec_len [u] ctx ) 255 { ^ ( vec_new [u] ) } {}
    : SlhParams p ( __slh_params set )
    : ( Vec u ) mp ( __slh_mprime msg ctx )
    : ( Vec u ) rnd ( rand_bytes . p n )
    : ( Vec u ) sig ( slhdsa_sign_internal set sk mp rnd )
    ( vec_free [u] rnd ) ( vec_free [u] mp )
    ^ sig
}

@ slhdsa_sign_deterministic i set ( Vec u ) sk ( Vec u ) msg ( Vec u ) ctx → ( Vec u ) {
    ? > ( vec_len [u] ctx ) 255 { ^ ( vec_new [u] ) } {}
    : SlhParams p ( __slh_params set )
    : ( Vec u ) mp ( __slh_mprime msg ctx )
    : ( Vec u ) rnd ( bytes_slice sk * 2 . p n * 3 . p n )
    : ( Vec u ) sig ( slhdsa_sign_internal set sk mp rnd )
    ( vec_free [u] rnd ) ( vec_free [u] mp )
    ^ sig
}

@ slhdsa_verify i set ( Vec u ) pk ( Vec u ) msg ( Vec u ) ctx ( Vec u ) sig → b {
    ? > ( vec_len [u] ctx ) 255 { ^ F } {}
    : ( Vec u ) mp ( __slh_mprime msg ctx )
    : b ok ( slhdsa_verify_internal set pk mp sig )
    ( vec_free [u] mp )
    ^ ok
}
