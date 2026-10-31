// aes_gcm_hw_agree.nu — the hardware AES-GCM kernels (std/aes_gcm.nu:
// AES-NI + PCLMULQDQ on xmm, VAES + VPCLMULQDQ on ymm, the same on zmm
// under AVX-512) against the software one, in one process.
//
// Every message length from 0 to 1100 bytes walks every path through
// the kernels: the eight-block stitched loop (none, one, two steps), the
// single blocks after it and a short last block; the sixteen-block wide
// loops (none to four steps) and their pair-at-a-time tail of every
// length, odd block counts and short last pairs included. Then a few
// long messages: a counter whose low byte carries inside a step, a
// full TLS record (16384, and 16385 with the content-type byte), and
// twelve pseudorandom lengths below 64 KiB per key size. AAD
// runs from 0 to 37 bytes (none, a short block, more than two blocks),
// and both key sizes. The software key is the oracle — its own vectors
// are aes_gcm_vectors.nu — so a wrong carry in the reflected GHASH, a
// counter that does not wrap like inc32, a power table read off by one
// entry or a mis-sized tail shows up as a differing byte.
//
// One key per tier (_aes_gcm_key_tier: 1 AES-NI, 2 VAES, 3 AVX-512
// VAES, each capped at what the CPU has), so a machine runs every
// kernel it can, not only the one its own best key would take. Each
// sealed message is also opened by the software key and the software
// key's by each hardware one, and a flipped tag bit must fail on every
// key.
//
// Every kernel also runs with AAD past eight blocks (its GHASH run
// reduces in several groups) before message shapes up to 1100 bytes,
// and in place (aes_gcm_seal_in / aes_gcm_open_in, the TLS record
// layer's path: `op` is `inp`) at every length, against the software
// key's answer.
//
// requires: cpu-aes
//
// On a CPU without the crypto tier every key is software and the test
// still passes: it then proves nothing about the hardware path, which
// is why the golden records which path ran. (Which wide kernels ran is
// not in the golden — CI runners differ — and crypto_tier_ir.sh is
// what checks, on its host, that they did.)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/aes_gcm.nu`

// xorshift64: deterministic bytes, no dependency on a RNG module.
@ next u64 x → u64 {
    : ~ u64 y x
    = y ^^ y << y 13
    = y ^^ y >> y 7
    = y ^^ y << y 17
    ^ y
}

@ fill i n u64 seed → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ u64 s seed
    : ~ i k 0
    ~ < k n { = s ( next s ) ( vec_push [u] v # u & # i s 255 ) = k + k 1 }
    ^ v
}

@ same ( Vec u ) a ( Vec u ) b → b {
    ? != ( vec_len [u] a ) ( vec_len [u] b ) { ^ F } {}
    : ~ i k 0
    ~ < k ( vec_len [u] a ) { ? != ( vec_at [u] a k ) ( vec_at [u] b k ) { ^ F } {} = k + k 1 }
    ^ T
}

@ opens AesGcmKey k ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct ( Vec u ) pt → b {
    ?? ( aes_gcm_open k nonce aad ct ) { T p → ^ ( same p pt ) F _ → ^ F }
}

@ rejects AesGcmKey k ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct → b {
    ?? ( aes_gcm_open k nonce aad ct ) { T p → ^ F F _ → ^ T }
}

// One hardware key `hw` (tier `tier`) on one message against the
// software key's sealing `ref` of it; the number of failures.
@ check_key AesGcmKey hw AesGcmKey sw i tier ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt ( Vec u ) ref → i {
    : ~ i fails 0
    : ( Vec u ) c ( aes_gcm_seal hw nonce aad pt )
    ? ! ( same c ref ) {
        ( nurl_print `seal differs: tier ` ) ( nurl_print ( nurl_str_int tier ) )
        ( nurl_print ` n ` ) ( nurl_print ( nurl_str_int ( vec_len [u] pt ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    ? ! & ( opens sw nonce aad c pt ) ( opens hw nonce aad ref pt ) {
        ( nurl_print `open failed: tier ` ) ( nurl_print ( nurl_str_int tier ) )
        ( nurl_print ` n ` ) ( nurl_print ( nurl_str_int ( vec_len [u] pt ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    // In place, as the TLS record layer seals and opens: `aad ‖ pt` in
    // one buffer becomes `aad ‖ ct ‖ tag` where it lies, and back.
    : i alen ( vec_len [u] aad )
    : ( Vec u ) buf ( fill 0 0 )
    ( bytes_extend_bytes buf aad )
    ( bytes_extend_bytes buf pt )
    : ( Vec u ) want ( fill 0 0 )
    ( bytes_extend_bytes want aad )
    ( bytes_extend_bytes want ref )
    ? ! & ( aes_gcm_seal_in hw nonce 0 buf 0 alen ) ( same buf want ) {
        ( nurl_print `seal_in differs: tier ` ) ( nurl_print ( nurl_str_int tier ) )
        ( nurl_print ` n ` ) ( nurl_print ( nurl_str_int ( vec_len [u] pt ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    ? ( aes_gcm_open_in hw nonce 0 want 0 alen ( vec_len [u] want ) ) {
        : ~ i k 0
        : ~ b eq T
        ~ < k ( vec_len [u] pt ) { ? != ( vec_at [u] want + alen k ) ( vec_at [u] pt k ) { = eq F } {} = k + k 1 }
        ? ! eq {
            ( nurl_print `open_in differs: tier ` ) ( nurl_print ( nurl_str_int tier ) )
            ( nurl_print ` n ` ) ( nurl_print ( nurl_str_int ( vec_len [u] pt ) ) ) ( nurl_print `\n` )
            = fails + fails 1
        } {}
    } {
        ( nurl_print `open_in refused: tier ` ) ( nurl_print ( nurl_str_int tier ) )
        ( nurl_print ` n ` ) ( nurl_print ( nurl_str_int ( vec_len [u] pt ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    }
    // Flip one tag bit: the key must refuse it.
    : ( Vec u ) bad ( fill 0 0 )
    ( bytes_extend_bytes bad c )
    : i last - ( vec_len [u] bad ) 1
    ( vec_put [u] bad last # u ^^ # i ( vec_at [u] bad last ) 1 )
    ? ! ( rejects hw nonce aad bad ) {
        ( nurl_print `tamper accepted: tier ` ) ( nurl_print ( nurl_str_int tier ) )
        ( nurl_print ` n ` ) ( nurl_print ( nurl_str_int ( vec_len [u] pt ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    ^ fails
}

// One message of `n` bytes with `alen` of AAD through every key; the
// number of failures.
@ check_one AesGcmKey sw AesGcmKey k1 AesGcmKey k2 AesGcmKey k3 i n i alen u64 seed → i {
    : ( Vec u ) nonce ( fill 12 # u64 + 77 seed )
    : ( Vec u ) aad ( fill alen # u64 + 5000 seed )
    : ( Vec u ) pt ( fill n # u64 + 9000 seed )
    : ( Vec u ) ref ( aes_gcm_seal sw nonce aad pt )
    : ~ i fails 0
    = fails + fails ( check_key k1 sw 1 nonce aad pt ref )
    = fails + fails ( check_key k2 sw 2 nonce aad pt ref )
    = fails + fails ( check_key k3 sw 3 nonce aad pt ref )
    ? ! ( rejects sw nonce aad ( fill + n 16 # u64 + 7 seed ) ) {
        ( nurl_print `software key accepted noise: n ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    ^ fails
}

// The long lengths: a counter whose low byte carries inside a sixteen-
// block step (from 4096 bytes on, every sixteenth step), and a whole
// TLS record with and without its content-type byte.
@ big_len i b → i {
    ? == b 0 { ^ 4096 } {}
    ? == b 1 { ^ 4111 } {}
    ? == b 2 { ^ 4352 } {}
    ? == b 3 { ^ 8191 } {}
    ? == b 4 { ^ 16384 } {}
    ^ 16385
}

@ main → i {
    ? ( nurl_cpu_has_aes ) { ( nurl_print `path: hardware vs software\n` ) } { ( nurl_print `path: software vs software (no crypto tier)\n` ) }
    : ~ i fails 0
    : ~ i cases 0
    : ~ i klen 16
    ~ <= klen 32 {
        : ( Vec u ) key ( fill klen # u64 + 1000 klen )
        : AesGcmKey sw ( _aes_gcm_key_sw key )
        : AesGcmKey k1 ( _aes_gcm_key_tier key 1 )
        : AesGcmKey k2 ( _aes_gcm_key_tier key 2 )
        : AesGcmKey k3 ( _aes_gcm_key_tier key 3 )
        : ~ i n 0
        ~ <= n 1100 {
            = fails + fails ( check_one sw k1 k2 k3 n % * n 7 38 # u64 n )
            = cases + cases 1
            = n + n 1
        }
        : ~ i b 0
        ~ < b 6 {
            = fails + fails ( check_one sw k1 k2 k3 ( big_len b ) 13 # u64 + 3000 b )
            = cases + cases 1
            = b + b 1
        }
        // Pseudorandom lengths below 64 KiB with 0 to 40 bytes of AAD:
        // many wide steps, counters that carry several times, and tails
        // of every shape, at sizes past one record.
        : ~ u64 rs # u64 + 4242 klen
        : ~ i rk 0
        ~ < rk 12 {
            = rs ( next rs )
            : i rn & # i rs 65535
            : i ra % & # i >> rs 20 1023 41
            = fails + fails ( check_one sw k1 k2 k3 rn ra # u64 + 6000 rk )
            = cases + cases 1
            = rk + rk 1
        }
        // Long AAD — past eight blocks, so its GHASH run reduces in
        // several groups — before every message shape.
        : ~ i ln 0
        ~ <= ln 1100 {
            : ~ i alen 100
            ~ <= alen 420 {
                = fails + fails ( check_one sw k1 k2 k3 ln alen # u64 + 177 + ln alen )
                = cases + cases 1
                = alen + alen 29
            }
            = ln + ln 37
        }
        // One raw block (QUIC header protection) on every key.
        : ( Vec u ) blk ( fill 16 # u64 31337 )
        : ( Vec u ) want ( aes_block_encrypt sw blk )
        ? ! & & ( same ( aes_block_encrypt k1 blk ) want ) ( same ( aes_block_encrypt k2 blk ) want ) ( same ( aes_block_encrypt k3 blk ) want ) {
            ( nurl_print `block differs\n` ) = fails + fails 1
        } {}
        // The key every program gets is one of the four.
        : AesGcmKey own ( aes_gcm_key_new key )
        : ( Vec u ) nonce ( fill 12 # u64 99 )
        : ( Vec u ) pt ( fill 1000 # u64 98 )
        ? ! ( same ( aes_gcm_seal own nonce nonce pt ) ( aes_gcm_seal sw nonce nonce pt ) ) {
            ( nurl_print `aes_gcm_key_new differs\n` ) = fails + fails 1
        } {}
        = klen + klen 16
    }
    ( nurl_print `cases ` ) ( nurl_print ( nurl_str_int cases ) )
    ( nurl_print `, failures ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print `\n` )
    ^ fails
}
