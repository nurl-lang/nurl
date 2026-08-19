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
$ `stdlib/std/hash_sha3x4.nu`
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

// ── Four hashes at a time ──────────────────────────────────────────
//
// Everything below the top-level API is built out of F, H and PRF —
// SHAKE256 over pkseed ‖ ADRS ‖ value, one rate block in, n bytes out —
// and the structure hands them out in independent groups: a WOTS+ key
// is `len` chains that never read each other, a FORS tree is 2^a
// leaves that never read each other. A 128f signature computes ~90,000
// of these hashes, ~150 at a time in independent batches.
//
// So the hot paths stage four inputs side by side and run
// shake256x4_block: one four-way permutation, no sponge struct, no
// allocation. The scratch lives in one context created per public-API
// call and threaded down the call chain — per-call state, so two
// threads signing concurrently never share it.
//
// Where a batch is not a multiple of four, the spare lanes REDO the
// last real unit and the result is discarded: the permutation runs on
// all four lanes regardless, so a duplicated lane costs nothing, and
// there is no scalar tail path to keep in agreement with this one.

: SlhCtx {
    ( Vec u64 ) st  // 100 interleaved lanes — shake256x4_block state
    ( Vec u64 ) scr  // its ping-pong partner
    ( Vec u64 ) rc
    ( Vec u ) in0  // four staging buffers, one rate block each
    ( Vec u ) in1
    ( Vec u ) in2
    ( Vec u ) in3
    ( Vec u ) val  // four 32-byte lane values, way w at offset w*32
}

@ __sx_buf i len → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] len )
    : b _l ( vec_set_len [u] v len )
    ^ v
}

@ __slhx4_new → *SlhCtx {
    : *SlhCtx c # *SlhCtx ( nurl_alloc Z SlhCtx )
    = . c st ( __sx_buf_u64 100 )
    = . c scr ( __sx_buf_u64 100 )
    = . c rc ( keccak_round_constants )
    = . c in0 ( __sx_buf 136 )
    = . c in1 ( __sx_buf 136 )
    = . c in2 ( __sx_buf 136 )
    = . c in3 ( __sx_buf 136 )
    = . c val ( __sx_buf 128 )
    ^ c
}

@ __sx_buf_u64 i len → ( Vec u64 ) {
    : ( Vec u64 ) v ( vec_with_cap [u64] len )
    : b _l ( vec_set_len [u64] v len )
    ^ v
}

@ __slhx4_free * SlhCtx c → v {
    ( vec_free [u64] . c st )
    ( vec_free [u64] . c scr )
    ( vec_free [u64] . c rc )
    ( vec_free [u] . c in0 )
    ( vec_free [u] . c in1 )
    ( vec_free [u] . c in2 )
    ( vec_free [u] . c in3 )
    ( vec_free [u] . c val )
    ( nurl_free # s c )
}

@ __sx_in * SlhCtx c i w → *u {
    ? == w 0 { ^ ( vec_data [u] . c in0 ) } {}
    ? == w 1 { ^ ( vec_data [u] . c in1 ) } {}
    ? == w 2 { ^ ( vec_data [u] . c in2 ) } {}
    ^ ( vec_data [u] . c in3 )
}

// Stage lane w with pkseed ‖ adrs ‖ value — the byte order __slh_shake
// absorbs, so the four-way and one-way spellings of the same hash are
// the same bytes. `value` is a raw pointer because it is usually a lane
// of ctx.val; the vecs it can also come from hand over vec_data.
@ __sx_stage * SlhCtx c i w ( Vec u ) pkseed ( Vec u ) adrs * u value i vlen → i {
    : i n ( vec_len [u] pkseed )
    : *u dst ( __sx_in c w )
    ( nurl_memcpy # s dst # s ( vec_data [u] pkseed ) n )
    ( nurl_memcpy # s + # i dst n # s ( vec_data [u] adrs ) 32 )
    ( nurl_memcpy # s + # i dst + n 32 # s value vlen )
    ^ + + n 32 vlen
}

// One four-way hash over the staged inputs, n bytes back into each
// lane of ctx.val.
@ __sx_run * SlhCtx c i inlen i n → v {
    : *u vp ( vec_data [u] . c val )
    ( shake256x4_block ( vec_data [u64] . c st ) ( vec_data [u64] . c scr )
    ( vec_data [u64] . c rc )
    ( __sx_in c 0 ) ( __sx_in c 1 ) ( __sx_in c 2 ) ( __sx_in c 3 )
    inlen
    vp # *u + # i vp 32 # *u + # i vp 64 # *u + # i vp 96 n )
}

// Four WOTS+ chains in lockstep: lane w walks chain `cw_w`, F applied
// `steps` times from step `start`. Values live in ctx.val on entry and
// exit. All four lanes take the same number of steps — the callers
// with per-chain step counts (sign, verify) stay on the scalar path,
// where the count is data-dependent and small.
@ __chains_x4 * SlhCtx c ( Vec u ) pkseed ( Vec u ) adrs i c0 i c1 i c2 i c3 i start i steps i n → v {
    : *u vp ( vec_data [u] . c val )
    : ~ i j start
    ~ < j + start steps {
        ( __adrs_set_hash adrs j )
        ( __adrs_set_chain adrs c0 )
        : i l0 ( __sx_stage c 0 pkseed adrs vp n )
        ( __adrs_set_chain adrs c1 )
        : i l1 ( __sx_stage c 1 pkseed adrs # *u + # i vp 32 n )
        ( __adrs_set_chain adrs c2 )
        : i l2 ( __sx_stage c 2 pkseed adrs # *u + # i vp 64 n )
        ( __adrs_set_chain adrs c3 )
        : i l3 ( __sx_stage c 3 pkseed adrs # *u + # i vp 96 n )
        ( __sx_run c l0 n )
        = j + j 1
    }
}

// Four chains with PER-LANE starting points, in lockstep on the hash
// index. Verification walks chain w from step m_w to 15, so the lanes
// share their END but not their start: lane w joins at j = start_w and
// keeps its value untouched before that. Every lane is staged every
// step — an idle lane hashes its frozen value and the result is
// discarded — because the permutation runs on all four lanes either
// way, and a data-dependent staging skip would be a branch per lane
// per step for no work saved.
//
// `vals` is a caller-owned 4×32 buffer (lane w at w*32): unlike the
// equal-start runner the values cannot live in ctx.val, because a
// discarded lane must KEEP its old value across the run that would
// have overwritten it.
@ __chains_var_x4 * SlhCtx c ( Vec u ) pkseed ( Vec u ) adrs i c0 i c1 i c2 i c3 i s0 i s1 i s2 i s3 * u vals i n → v {
    : *u vp ( vec_data [u] . c val )
    // Start at the earliest lane's entry point: steps before it would
    // stage four frozen values and discard four results — a permutation
    // for nothing, and for a high-digit group (all starts at 15, which
    // a real message produces regularly) that was all fifteen of them.
    : ~ i jmin s0
    ? < s1 jmin { = jmin s1 } {}
    ? < s2 jmin { = jmin s2 } {}
    ? < s3 jmin { = jmin s3 } {}
    : ~ i j jmin
    ~ < j 15 {
        ( __adrs_set_hash adrs j )
        ( __adrs_set_chain adrs c0 )
        : i l0 ( __sx_stage c 0 pkseed adrs vals n )
        ( __adrs_set_chain adrs c1 )
        : i l1 ( __sx_stage c 1 pkseed adrs # *u + # i vals 32 n )
        ( __adrs_set_chain adrs c2 )
        : i l2 ( __sx_stage c 2 pkseed adrs # *u + # i vals 64 n )
        ( __adrs_set_chain adrs c3 )
        : i l3 ( __sx_stage c 3 pkseed adrs # *u + # i vals 96 n )
        ( __sx_run c l0 n )
        ? >= j s0 { ( nurl_memcpy # s vals # s vp n ) } {}
        ? >= j s1 { ( nurl_memcpy # s + # i vals 32 # s # *u + # i vp 32 n ) } {}
        ? >= j s2 { ( nurl_memcpy # s + # i vals 64 # s # *u + # i vp 64 n ) } {}
        ? >= j s3 { ( nurl_memcpy # s + # i vals 96 # s # *u + # i vp 96 n ) } {}
        = j + j 1
    }
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

// The hottest function in the scheme: a 128f signature calls this ~150
// times, and each call is len chains × (1 PRF + 15 F). All chains run
// the same 15 steps, so they go four at a time; a group past the end
// duplicates the last chain and drops the extra lanes.
@ __wots_pkgen * SlhCtx c ( Vec u ) skseed ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : i n . p n
    : i len . p len
    : ( Vec u ) skadrs ( __adrs_copy adrs )
    ( __adrs_set_type skadrs 5 )
    ( __adrs_set_kp skadrs ( __adrs_get_kp adrs ) )
    : ( Vec u ) tmp ( __sx_buf * len n )
    : *u tp ( vec_data [u] tmp )
    : *u vp ( vec_data [u] . c val )
    : *u ssp ( vec_data [u] skseed )
    : ~ i g 0
    ~ < g len {
        : i c0 + g 0
        : i c1 ? < + g 1 len + g 1 - len 1
        : i c2 ? < + g 2 len + g 2 - len 1
        : i c3 ? < + g 3 len + g 3 - len 1
        // sk_w ← PRF(pkseed, skadrs(chain=c_w), skseed), four ways.
        ( __adrs_set_chain skadrs c0 )
        : i l0 ( __sx_stage c 0 pkseed skadrs ssp n )
        ( __adrs_set_chain skadrs c1 )
        : i l1 ( __sx_stage c 1 pkseed skadrs ssp n )
        ( __adrs_set_chain skadrs c2 )
        : i l2 ( __sx_stage c 2 pkseed skadrs ssp n )
        ( __adrs_set_chain skadrs c3 )
        : i l3 ( __sx_stage c 3 pkseed skadrs ssp n )
        ( __sx_run c l0 n )
        // 15 F steps in lockstep.
        ( __chains_x4 c pkseed adrs c0 c1 c2 c3 0 15 n )
        : ~ i w 0
        ~ & < w 4 < + g w len {
            ( nurl_memcpy # s + # i tp * + g w n # s + # i vp * w 32 n )
            = w + w 1
        }
        = g + g 4
    }
    : ( Vec u ) pkadrs ( __adrs_copy adrs )
    ( __adrs_set_type pkadrs 1 )
    ( __adrs_set_kp pkadrs ( __adrs_get_kp adrs ) )
    : ( Vec u ) out ( __slh_f pkseed pkadrs tmp n )
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

@ __wots_pk_from_sig * SlhCtx c ( Vec u ) sig ( Vec u ) m ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : i n . p n
    : i len . p len
    : ( Vec i ) msg ( __wots_msg m p )
    : *i mp ( vec_data [i] msg )
    : *u sp ( vec_data [u] sig )
    : ( Vec u ) tmp ( __sx_buf * len n )
    : *u tp ( vec_data [u] tmp )
    : ( Vec u ) vals ( __sx_buf 128 )
    : *u va ( vec_data [u] vals )
    : ~ i g 0
    ~ < g len {
        : i c0 + g 0
        : i c1 ? < + g 1 len + g 1 - len 1
        : i c2 ? < + g 2 len + g 2 - len 1
        : i c3 ? < + g 3 len + g 3 - len 1
        ( nurl_memcpy # s va # s # *u + # i sp * c0 n n )
        ( nurl_memcpy # s + # i va 32 # s # *u + # i sp * c1 n n )
        ( nurl_memcpy # s + # i va 64 # s # *u + # i sp * c2 n n )
        ( nurl_memcpy # s + # i va 96 # s # *u + # i sp * c3 n n )
        ( __chains_var_x4 c pkseed adrs c0 c1 c2 c3
        # i . mp c0 # i . mp c1 # i . mp c2 # i . mp c3 va n )
        : ~ i w 0
        ~ & < w 4 < + g w len {
            ( nurl_memcpy # s + # i tp * + g w n # s + # i va * w 32 n )
            = w + w 1
        }
        = g + g 4
    }
    ( vec_free [u] vals )
    : ( Vec u ) pkadrs ( __adrs_copy adrs )
    ( __adrs_set_type pkadrs 1 )
    ( __adrs_set_kp pkadrs ( __adrs_get_kp adrs ) )
    : ( Vec u ) out ( __slh_f pkseed pkadrs tmp n )
    ( vec_free [u] tmp ) ( vec_free [u] pkadrs ) ( vec_free [i] msg )
    ^ out
}

// ── XMSS (§6) ──────────────────────────────────────────────────────

// The Merkle root over 2^z WOTS+ public keys, computed by recursion.
//
// This is where an `s` parameter set spends its time: h' = 9 means
// every one of the d layers rebuilds 512 WOTS+ key pairs per signature.
@ __xmss_node * SlhCtx c ( Vec u ) skseed i i2 i z ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    ? == z 0 {
        ( __adrs_set_type adrs 0 )
        ( __adrs_set_kp adrs i2 )
        ^ ( __wots_pkgen c skseed pkseed adrs p )
    } {}
    : ( Vec u ) l ( __xmss_node c skseed * 2 i2 - z 1 pkseed adrs p )
    : ( Vec u ) r ( __xmss_node c skseed + * 2 i2 1 - z 1 pkseed adrs p )
    ( __adrs_set_type adrs 2 )
    ( __adrs_set_height adrs z )
    ( __adrs_set_index adrs i2 )
    : ( Vec u ) both ( bytes_slice l 0 ( vec_len [u] l ) )
    ( bytes_extend_bytes both r )
    : ( Vec u ) out ( __slh_f pkseed adrs both . p n )
    ( vec_free [u] both ) ( vec_free [u] r ) ( vec_free [u] l )
    ^ out
}

@ __xmss_sign * SlhCtx c ( Vec u ) m ( Vec u ) skseed i idx ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : ( Vec u ) auth ( vec_new [u] )
    : ~ i j 0
    ~ < j . p hp {
        : i kk ^^ >> idx j 1
        : ( Vec u ) a2 ( __adrs_copy adrs )
        : ( Vec u ) nd ( __xmss_node c skseed kk j pkseed a2 p )
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

@ __xmss_pk_from_sig * SlhCtx c i idx ( Vec u ) sigx ( Vec u ) m ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : i wl * . p len . p n
    ( __adrs_set_type adrs 0 )
    ( __adrs_set_kp adrs idx )
    : ( Vec u ) wsig ( bytes_slice sigx 0 wl )
    : ~ ( Vec u ) node ( __wots_pk_from_sig c wsig m pkseed adrs p )
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

@ __ht_sign * SlhCtx c ( Vec u ) m ( Vec u ) skseed ( Vec u ) pkseed i idx_tree i idx_leaf SlhParams p → ( Vec u ) {
    : ~ i it idx_tree
    : ~ i il idx_leaf
    : ( Vec u ) adrs ( __adrs_new )
    ( __adrs_set_layer adrs 0 )
    ( __adrs_set_tree adrs it )
    : ( Vec u ) sig0 ( __xmss_sign c m skseed il pkseed adrs p )
    : ~ ( Vec u ) out ( bytes_slice sig0 0 ( vec_len [u] sig0 ) )
    : ( Vec u ) a0 ( __adrs_new )
    ( __adrs_set_layer a0 0 )
    ( __adrs_set_tree a0 it )
    : ~ ( Vec u ) root ( __xmss_pk_from_sig c il sig0 m pkseed a0 p )
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
        : ( Vec u ) sj ( __xmss_sign c root skseed il pkseed aj p )
        ( bytes_extend_bytes out sj )
        ? < j - . p d 1 {
            : ( Vec u ) a2 ( __adrs_new )
            ( __adrs_set_layer a2 j )
            ( __adrs_set_tree a2 it )
            : ( Vec u ) nr ( __xmss_pk_from_sig c il sj root pkseed a2 p )
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

@ __ht_verify * SlhCtx c ( Vec u ) m ( Vec u ) sight ( Vec u ) pkseed i idx_tree i idx_leaf ( Vec u ) pkroot SlhParams p → b {
    : i xl * + . p hp . p len . p n
    : ~ i it idx_tree
    : ~ i il idx_leaf
    : ( Vec u ) a0 ( __adrs_new )
    ( __adrs_set_layer a0 0 )
    ( __adrs_set_tree a0 it )
    : ( Vec u ) s0 ( bytes_slice sight 0 xl )
    : ~ ( Vec u ) node ( __xmss_pk_from_sig c il s0 m pkseed a0 p )
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
        : ( Vec u ) nn ( __xmss_pk_from_sig c il sj node pkseed aj p )
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

// One FORS tree, built bottom-up: all 2^a leaves, then each level
// packed in place. The recursion this replaces recomputed the sibling
// subtree of every auth level separately — the same total hash count,
// but one leaf at a time; here the leaves go four at a time (PRF and F
// both), the internal levels pack four pairs at a time, and the auth
// path falls out of the one build for free.
//
// The level packing is in place at the front of `buf`: parents at
// [0, half) are written from children at [2·pi, 2·pi+2). Within a group
// of four, all stagings copy their input bytes before the first result
// is written back, and a later group reads children at indices at least
// twice its parent index — always ahead of every parent written so far.
//
// Returns the root; appends sk(selected leaf) ‖ auth[0..a) to `sig`,
// which is exactly the per-tree slice of a FORS signature.
@ __fors_tree * SlhCtx c ( Vec u ) skseed ( Vec u ) pkseed ( Vec u ) adrs i tree i sel ( Vec u ) sig SlhParams p → ( Vec u ) {
    : i n . p n
    : i a . p a
    : i nleaf << 1 a
    : i base * tree nleaf
    : *u vp ( vec_data [u] . c val )

    // The revealed secret: sk of the selected leaf, first in the sig.
    : ( Vec u ) skadrs ( __adrs_copy adrs )
    ( __adrs_set_type skadrs 6 )
    ( __adrs_set_kp skadrs ( __adrs_get_kp adrs ) )
    ( __adrs_set_index skadrs + base sel )
    : ( Vec u ) sksel ( __slh_prf pkseed skadrs skseed n )
    ( bytes_extend_bytes sig sksel )
    ( vec_free [u] sksel )

    : ( Vec u ) buf ( __sx_buf * nleaf n )
    : *u bp ( vec_data [u] buf )
    : *u ssp ( vec_data [u] skseed )

    // Leaves, four at a time: sk_w ← PRF(idx), leaf_w ← F(sk_w).
    : ~ i li 0
    ~ < li nleaf {
        : i i0 + base + li 0
        : i i1 + base ? < + li 1 nleaf + li 1 - nleaf 1
        : i i2 + base ? < + li 2 nleaf + li 2 - nleaf 1
        : i i3 + base ? < + li 3 nleaf + li 3 - nleaf 1
        ( __adrs_set_index skadrs i0 )
        : i l0 ( __sx_stage c 0 pkseed skadrs ssp n )
        ( __adrs_set_index skadrs i1 )
        : i l1 ( __sx_stage c 1 pkseed skadrs ssp n )
        ( __adrs_set_index skadrs i2 )
        : i l2 ( __sx_stage c 2 pkseed skadrs ssp n )
        ( __adrs_set_index skadrs i3 )
        : i l3 ( __sx_stage c 3 pkseed skadrs ssp n )
        ( __sx_run c l0 n )
        ( __adrs_set_height adrs 0 )
        ( __adrs_set_index adrs i0 )
        : i f0 ( __sx_stage c 0 pkseed adrs vp n )
        ( __adrs_set_index adrs i1 )
        : i f1 ( __sx_stage c 1 pkseed adrs # *u + # i vp 32 n )
        ( __adrs_set_index adrs i2 )
        : i f2 ( __sx_stage c 2 pkseed adrs # *u + # i vp 64 n )
        ( __adrs_set_index adrs i3 )
        : i f3 ( __sx_stage c 3 pkseed adrs # *u + # i vp 96 n )
        ( __sx_run c f0 n )
        : ~ i w 0
        ~ & < w 4 < + li w nleaf {
            ( nurl_memcpy # s + # i bp * + li w n # s + # i vp * w 32 n )
            = w + w 1
        }
        = li + li 4
    }

    // Pack upward. Before each level is consumed, its auth node — the
    // sibling of the selected leaf's ancestor — is still in buf.
    : ~ i cur nleaf
    : ~ i h 0
    ~ < h a {
        : i sib ^^ >> sel h 1
        : ( Vec u ) an ( bytes_slice buf * sib n * + sib 1 n )
        ( bytes_extend_bytes sig an )
        ( vec_free [u] an )
        : i half / cur 2
        : i hh + h 1
        ( __adrs_set_height adrs hh )
        : ~ i pi 0
        ~ < pi half {
            : i p0 + pi 0
            : i p1 ? < + pi 1 half + pi 1 - half 1
            : i p2 ? < + pi 2 half + pi 2 - half 1
            : i p3 ? < + pi 3 half + pi 3 - half 1
            ( __adrs_set_index adrs + * tree half p0 )
            : i l0 ( __sx_stage c 0 pkseed adrs # *u + # i bp * * 2 p0 n * 2 n )
            ( __adrs_set_index adrs + * tree half p1 )
            : i l1 ( __sx_stage c 1 pkseed adrs # *u + # i bp * * 2 p1 n * 2 n )
            ( __adrs_set_index adrs + * tree half p2 )
            : i l2 ( __sx_stage c 2 pkseed adrs # *u + # i bp * * 2 p2 n * 2 n )
            ( __adrs_set_index adrs + * tree half p3 )
            : i l3 ( __sx_stage c 3 pkseed adrs # *u + # i bp * * 2 p3 n * 2 n )
            ( __sx_run c l0 n )
            : ~ i w 0
            ~ & < w 4 < + pi w half {
                ( nurl_memcpy # s + # i bp * + pi w n # s + # i vp * w 32 n )
                = w + w 1
            }
            = pi + pi 4
        }
        = cur half
        = h hh
    }

    : ( Vec u ) root ( bytes_slice buf 0 n )
    ( vec_free [u] buf ) ( vec_free [u] skadrs )
    ^ root
}

@ __fors_sign * SlhCtx c ( Vec u ) md ( Vec u ) skseed ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : ( Vec i ) idx ( __base_2b md . p a . p k )
    : ( Vec u ) sig ( vec_new [u] )
    : ~ i i 0
    ~ < i . p k {
        : i ii ?? ( vec_get [i] idx i ) { T x → { x } F → { 0 } }
        : ( Vec u ) root ( __fors_tree c skseed pkseed adrs i ii sig p )
        ( vec_free [u] root )
        = i + i 1
    }
    ( vec_free [i] idx )
    ^ sig
}

// FORS verification, four trees at a time. The k root recomputations
// are independent and identical in shape — one leaf F, then `a` levels
// of H walking the auth path — so lane w walks tree g+w in lockstep.
// Only the concatenation order inside a level is per-lane data (the
// bit of ii_w that says whether the node is a left or right child),
// and that is staging bytes, not control flow the lanes would have to
// agree on.
@ __fors_pk_from_sig * SlhCtx c ( Vec u ) sigf ( Vec u ) md ( Vec u ) pkseed ( Vec u ) adrs SlhParams p → ( Vec u ) {
    : i n . p n
    : i a . p a
    : i k . p k
    : ( Vec i ) idx ( __base_2b md a k )
    : *i xp ( vec_data [i] idx )
    : i step * + 1 a n
    : *u sfp ( vec_data [u] sigf )
    : ( Vec u ) roots ( __sx_buf * k n )
    : *u rp ( vec_data [u] roots )
    : *u vp ( vec_data [u] . c val )
    : ( Vec u ) vals ( __sx_buf 128 )
    : *u va ( vec_data [u] vals )
    // Per-lane 2n concatenation scratch for the H levels.
    : ( Vec u ) both ( __sx_buf 256 )
    : *u bo ( vec_data [u] both )

    : ~ i g 0
    ~ < g k {
        : i t0 + g 0
        : i t1 ? < + g 1 k + g 1 - k 1
        : i t2 ? < + g 2 k + g 2 - k 1
        : i t3 ? < + g 3 k + g 3 - k 1
        : i i0 # i . xp t0
        : i i1 # i . xp t1
        : i i2 # i . xp t2
        : i i3 # i . xp t3
        : ~ i u0 + * t0 << 1 a i0
        : ~ i u1 + * t1 << 1 a i1
        : ~ i u2 + * t2 << 1 a i2
        : ~ i u3 + * t3 << 1 a i3

        // Leaf: node_w ← F(pkseed, adrs(h=0, idx=u_w), sk_w).
        ( __adrs_set_height adrs 0 )
        ( __adrs_set_index adrs u0 )
        : i l0 ( __sx_stage c 0 pkseed adrs # *u + # i sfp * t0 step n )
        ( __adrs_set_index adrs u1 )
        : i l1 ( __sx_stage c 1 pkseed adrs # *u + # i sfp * t1 step n )
        ( __adrs_set_index adrs u2 )
        : i l2 ( __sx_stage c 2 pkseed adrs # *u + # i sfp * t2 step n )
        ( __adrs_set_index adrs u3 )
        : i l3 ( __sx_stage c 3 pkseed adrs # *u + # i sfp * t3 step n )
        ( __sx_run c l0 n )
        ( nurl_memcpy # s va # s vp n )
        ( nurl_memcpy # s + # i va 32 # s # *u + # i vp 32 n )
        ( nurl_memcpy # s + # i va 64 # s # *u + # i vp 64 n )
        ( nurl_memcpy # s + # i va 96 # s # *u + # i vp 96 n )

        : ~ i j 0
        ~ < j a {
            ( __adrs_set_height adrs + j 1 )
            // Lane w: parent index and node ‖ auth vs auth ‖ node from
            // bit j of ii_w; the level's auth node sits after sk and j
            // earlier auth nodes in this tree's signature slice.
            : ~ i w 0
            ~ < w 4 {
                : i tw ? == w 0 t0 ? == w 1 t1 ? == w 2 t2 t3
                : i iw ? == w 0 i0 ? == w 1 i1 ? == w 2 i2 i3
                : *u ap # *u + # i sfp + + * tw step n * j n
                : *u bw # *u + # i bo * w 64
                ? == % >> iw j 2 0 {
                    ( nurl_memcpy # s bw # s # *u + # i va * w 32 n )
                    ( nurl_memcpy # s + # i bw n # s ap n )
                } {
                    ( nurl_memcpy # s bw # s ap n )
                    ( nurl_memcpy # s + # i bw n # s # *u + # i va * w 32 n )
                }
                = w + w 1
            }
            = u0 ? == % >> i0 j 2 0 / u0 2 / - u0 1 2
            = u1 ? == % >> i1 j 2 0 / u1 2 / - u1 1 2
            = u2 ? == % >> i2 j 2 0 / u2 2 / - u2 1 2
            = u3 ? == % >> i3 j 2 0 / u3 2 / - u3 1 2
            ( __adrs_set_index adrs u0 )
            : i h0 ( __sx_stage c 0 pkseed adrs bo * 2 n )
            ( __adrs_set_index adrs u1 )
            : i h1 ( __sx_stage c 1 pkseed adrs # *u + # i bo 64 * 2 n )
            ( __adrs_set_index adrs u2 )
            : i h2 ( __sx_stage c 2 pkseed adrs # *u + # i bo 128 * 2 n )
            ( __adrs_set_index adrs u3 )
            : i h3 ( __sx_stage c 3 pkseed adrs # *u + # i bo 192 * 2 n )
            ( __sx_run c h0 n )
            ( nurl_memcpy # s va # s vp n )
            ( nurl_memcpy # s + # i va 32 # s # *u + # i vp 32 n )
            ( nurl_memcpy # s + # i va 64 # s # *u + # i vp 64 n )
            ( nurl_memcpy # s + # i va 96 # s # *u + # i vp 96 n )
            = j + j 1
        }
        : ~ i w 0
        ~ & < w 4 < + g w k {
            ( nurl_memcpy # s + # i rp * + g w n # s + # i va * w 32 n )
            = w + w 1
        }
        = g + g 4
    }
    ( vec_free [u] both ) ( vec_free [u] vals )
    : ( Vec u ) fa ( __adrs_copy adrs )
    ( __adrs_set_type fa 4 )
    ( __adrs_set_kp fa ( __adrs_get_kp adrs ) )
    : ( Vec u ) out ( __slh_f pkseed fa roots n )
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
    : *SlhCtx c ( __slhx4_new )
    : ( Vec u ) root ( __xmss_node c skseed 0 . p hp pkseed adrs p )
    ( __slhx4_free c )
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
    : *SlhCtx c ( __slhx4_new )
    : ( Vec u ) sigf ( __fors_sign c md skseed pkseed adrs p )
    : ( Vec u ) pkf ( __fors_pk_from_sig c sigf md pkseed adrs p )
    : ( Vec u ) sigh ( __ht_sign c pkf skseed pkseed it il p )
    ( __slhx4_free c )

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
    : *SlhCtx c ( __slhx4_new )
    : ( Vec u ) pkf ( __fors_pk_from_sig c sigf md pkseed adrs p )
    : b ok ( __ht_verify c pkf sigh pkseed it il pkroot p )
    ( __slhx4_free c )

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
