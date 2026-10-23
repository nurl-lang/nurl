// stdlib/std/ecdsa_p256.nu — pure-NURL ECDSA on the NIST P-256
// (secp256r1) and P-384 (secp384r1) curves. No OpenSSL.
//
//   ( ecdsa_p256_verify point r s hash ) → b
//   ( ecdsa_p384_verify point r s hash ) → b
//   ( ecdsa_p256_sign priv hash )       → ( Vec u )
//
// point = uncompressed public key (0x04 || X || Y, 65 / 97 bytes).
// r, s   = signature integers (big-endian bytes).
// hash   = the message digest; a digest longer than the curve is
//          truncated to its leftmost bits per FIPS 186-5 §6.4.1.
//
// The SECRET paths (signing nonce, ECDH) run on the constant-time
// fixed-limb Montgomery field (std/p256_field); verification — public
// data, one per certificate in a TLS chain, one per JWT-authenticated
// request — runs on the same fixed-limb fields variable-time-free of
// BigInt (P-384 core: std/p384_field). BigInt remains for parsing and
// the cheap validation arithmetic only.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bigint.nu`
$ `stdlib/std/hash_sha256.nu`  // prepared HMAC keys for the RFC 6979 nonce
$ `stdlib/std/p256_field.nu`  // fully constant-time scalar mult (secret path)
$ `stdlib/std/p256_scalar.nu`  // fixed-width GF(n) for the signing scalar arithmetic
$ `stdlib/std/p384_field.nu`  // fixed-width P-384 verify core (public path)

// ── curve constants (hex → BigInt) ────────────────────────────────
@ __hx s h → BigInt {
    : ( Vec u ) v ?? ( bytes_from_hex h ) { T x → x F _ → ( vec_new [u] ) }
    : BigInt r ( bigint_from_bytes_be v )
    ^ r
}

@ __p384_p → BigInt { ^ ( __hx `fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff` ) }

@ __p384_n → BigInt { ^ ( __hx `ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973` ) }

@ __p384_b → BigInt { ^ ( __hx `b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef` ) }

// ── field arithmetic mod p ────────────────────────────────────────
@ __fmul BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_mul a b )
    : BigInt r ( bigint_rem t p )
    ^ r
}

@ __fadd BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_add a b )
    : BigInt r ( bigint_rem t p )
    ^ r
}

@ __fsub BigInt a BigInt b BigInt p → BigInt {
    : BigInt t1 ( bigint_add a p )
    : BigInt t2 ( bigint_sub t1 b )
    : BigInt r ( bigint_rem t2 p )
    ^ r
}

@ __fsqr BigInt a BigInt p → BigInt { ^ ( __fmul a a p ) }

// On-curve + in-field validation of an affine point (M3): 0 ≤ x,y < p,
// (x,y) ≠ O, and y² ≡ x³ − 3x + b (mod p). P-256/P-384 have cofactor 1, so
// this is a full subgroup membership check.
@ __on_curve BigInt x BigInt y BigInt p BigInt b → b {
    : BigInt zero ( bigint_zero )
    : ~ b ok T
    ? >= ( bigint_cmp x p ) 0 { = ok F } {}
    ? >= ( bigint_cmp y p ) 0 { = ok F } {}
    ? < ( bigint_cmp x zero ) 0 { = ok F } {}
    ? < ( bigint_cmp y zero ) 0 { = ok F } {}
    ? & ( bigint_is_zero x ) ( bigint_is_zero y ) { = ok F } {}
    ? ok {
        : BigInt x2 ( __fsqr x p )
        : BigInt x3 ( __fmul x2 x p )
        : BigInt three ( bigint_from_i 3 )
        : BigInt tx ( __fmul three x p )
        : BigInt rhs0 ( __fsub x3 tx p )
        : BigInt rhs ( __fadd rhs0 b p )
        : BigInt lhs ( __fsqr y p )
        = ok == ( bigint_cmp lhs rhs ) 0
    } {}
    ^ ok
}

// ── fixed-base comb for the generator G (ECDSA k·G, ECDH keygen) ──────
// k·G with G the P-256 generator is a FIXED-base multiply, so most of the
// point doublings the variable-base window ladder pays can be precomputed
// away. This is a 4-tooth Lim–Lee comb: the 256-bit scalar is four 64-bit
// blocks, and `__p256_comb_tbl` holds the 15 non-trivial sums
// b0·G + b1·2^64·G + b2·2^128·G + b3·2^192·G (T[0] = identity). The main
// loop is then 64 iterations of one doubling + one constant-time 16-way
// table select + one complete addition — ~64 D + 64 A against the window
// path's ~256 D + 64 A. Still fully constant-time: the same masked table
// scan the secret-path window ladder uses.
//
// The table is affine (x‖y, 32-byte big-endian each), converted to
// Montgomery projective once per call. Verified against k·G in Python.
@ __p256_comb_tbl_hex → s { ^ `6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f57fe36b40af22af8921656b32262c71da1ab919365c65dfb63a5a9e22185a5943e697d45825b636249f09f40407dca6f174b3d5867b8af212d50d152c699ca101e35798220cedc02a608548c24aa7358f830895e4fccc3ac216fc51ff8101e6e4700f948e1f433a2df3e4b396768a3299f0570bedc523e6efaad2b99852c392c30fa822bc2811aaa58492592e326e25de29493baaad651f7e90e75cb48e14db63bff44ae8f5dba80d6f4ad4bcb3df188b34b1a65050fe82f5e41124545f462ee7300a4bbc89d6726fb257c0de95e02789e96c98fd0d35f1fa93391ce2097992af72aac7e0d09b46447f1ddb25ff1e3c6f5bb1eeada9d806a5aa54a291c08127a014cb5692606a4a62a9cad33b680a7daae0d3eb336c224571d6e260f8ee4039a053098cfa3e1e4663878487ed997a9a3b5205ef8d8039927cfe93d3159d83bc01a5ab9e10958f1608c22c48c5ffea17c1585a137ef5c4ad4230368cb6d945111ed3ebc6118b1aa09a629e17ebad0648f446ed771c49a10f77c34a47b8785b4ed94a5b506612a677a657880b3a18a2e902e9a521b074ca0141a84aa9397512218eeb13461ceac089f1c42604fbe1627d40626db15419e26d9d0beada7a4c4f3840418d68dea064219700d1a0a5fd208dfb48f9c1875e98c12dc761c1fecc0497865d7b26f6a5ba6dd4435639622ef8d32017429c50c16caad0481eef5551b507590781b8291c6a220ac342967aa815c8575e52c4144103ecbcf9faed0927a43281690cde8df015159397b2a14f1291643488f80eeee54a05e35a8343ceeac55f8057f62eeca7b5d4fb54a0fe5274647ebe82d789a6dd561becc52c00cae38e38205e5ff8bf89bfe2ad60e9c067efea8f480d300594ec356dceaa60759d48f8146091c821d488e9843c27035d2627caa74754d5dad9289944395920d7b0fa3289d5db7aecc78f879f44919adc3734938dac7b7df6ea0408ebade130dead9aa8a56606f0afdb90422d81c9c6f5415bf70c35eddf9c6c7e1c792ebc499ee7c6fae6d777f9e8f73f9804c47bab8955dde6464641a7cf1aaf7ae617214f0ad04dbc747abc07bb82d6536c0292052d44bcdf6567f0698ff75e4ec9655d01a765c96900d8eb165f9c1d90902aa17bf29fc7b19a1e635f210ec2e7ba735fe58ccf83762c71e018aaa22086a46c269843f16b47957bd86848c84760c41eaf972b45f2159928383f4db07f10ee50f2fe8863ba0dbc83d36d88b34fed7bb921a0332299698420447d739beedb5e67fb982fd588c6766efc35ff7dc297eac357c84fc9d789bd852d4825ab834131eee12e9d953a4aaff73d349b95a7fae5000c7e33c972e25b328a535f566ec73617f5622df4373713269e4c35874afdf43aaee9c75df7f82f2a0455c08468b08bd737e02819085a92bfcde533864c8c7669c5f9a0ac223094b7ff25f55a2c214cd923fe7442010729acef8bf285dfd6c3f34193640bfbb7f12d94f114d38a40510000c15ba774a58d771a08ebc72ab82b74d77bf411f30f0fc8a6d39677a78492762736ff8344315fc596439591a3c6b94a6cf20ffb313728be674f84749b0b881666b8babd2d27ecdf824a920c2284059bf2bab833c357f5f468f344af6b317466efe0a423083e49f343a0a28c42ba792fe96a79fb3e72ad0c31b9c405f8540a20604ed93c24d67ff3668bfc2271f5c626cdfe17db3fb24d4a0ac9835f0e6155faeb3df8bf9d6b4a9b60ff39edff736545270a098d637d797dd6882b263d00d534d8ac7b195c6872b2fa24f7333fe89b0850c04b69640bc0e96a25fb201b4084ce8a404541b1f23d69561d30f51dc2d82e7b3068d03765581e5a0aebfc19cfb424f5763393d06a40071e15941a5cf443d550180e1b6020632968f6b8542783dfeeeb5b06e70ce08ffefd75f3fa01876bd86a703f10e895df07cbe1feba92e40ce6fbc8044dfda45028cf5293d2f310bf7f90c76f8a78712655bd6058b07b81568e83fb2d63c62cd05550d19d86abc96fedcc38452ef202481af78e1fbef8467e379ee514e409ef7dd9c51419ed83f257d4628271f170737bb6e51f547c5972a107b422d1e7bd6f85147ed031a0e45c2258eee44b35702476b51c309a2b25bb1387a62f98b3a9fe9a068ca922ee097c184ea25bcd6fc9cf343d86699898a60bcd7758e0a73c3879d7d86da147f00d75821e9baf4d7aaac4170ac0d84aeca4b075f432ca235d2af12355428dede80187f877ae7cd4da598a46ebfb0249aa28a8a8fbb7fbe79e03e042ea3478e062311cb1f3dceafeb7328fb9ef172f46339c5fbc3e48e514e109aa13a20e540e9f3d15281350b4bb44b8ee1b8bebc3d35e8855a59acbbd5f2012ca3c26846730ad139ad48c2ffbcf19dc0b10615290bec161ce30304b3c37853fe325890da658f5f8f4be3a18644a975b93e742a176c395ae64d73870e00c7531905283d7768c940d8a6fb01e3081abb7f6be1f9ebdec88947b45f151ab984b9feeea5c087565ce611fe5069e5850bc1fa3578c681d6be2b2567ac59de1e8e76080e0f8dadf6dcec6ad55f11bcb36a57bca0bc11dfcab92c48087f3263f2166cf14e1b02a6a766ee58790f1deb1edd4763f4fcb` }

// 32 big-endian bytes at offset `off` → four little-endian 2^64 limbs.
@ __p256_be32_to_limbs ( Vec u ) src i off → ( Vec i ) {
    : ( Vec i ) out ( vec_with_cap [i] 4 )
    : ~ i k 0
    ~ < k 4 {
        // limb k = bytes [off + 24−8k … off + 31−8k], big-endian.
        : i base + off - 24 * 8 k
        : ~ u64 acc 0
        : ~ i j 0
        ~ < j 8 {
            : u64 bj # u64 ?? ( vec_get [u] src + base j ) { T b → # i b F _ → 0 }
            = acc | << acc 8 bj
            = j + j 1
        }
        ( vec_push [i] out # i acc )
        = k + k 1
    }
    ^ out
}

// One-time (per process) Montgomery-form comb tables, cached in two
// globals. Building them — the hex parse plus 60 to-Montgomery
// multiplies plus the limb conversions — used to run on EVERY
// p256ct_scalarmult_base call, i.e. every ECDSA sign and every P-256
// ECDH keygen: measurable as bytes_from_hex showing up inside the TLS
// handshake profile. The tables are public constants (multiples of G),
// so caching leaks no secret. Benign init race: two first callers may
// both build; one pointer wins each global, the losing copy leaks 3 KB
// once — an acceptable one-time cost against a lock on every
// signature.
//
// Two tables because the comb has EIGHT teeth split as two 4-tooth
// halves (see p256ct_scalarmult_base): T1 covers scalar bits
// {i, i+32, i+64, i+96}, T2 covers {i+128, …, i+224}.
: ~ i g_p256_comb_tbl 0
: ~ i g_p256_comb_tbl2 0

@ __p256_comb_build → v {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec u ) tbytes ?? ( bytes_from_hex ( __p256_comb_tbl_hex ) ) { T v → v F _ → ( vec_new [u] ) }
    : ( Vec i ) mx ( _mag4 )
    : ( Vec i ) my ( _mag4 )
    : ~ i t 0
    ~ < t 2 {
        // AFFINE Montgomery entries (x‖y, 8 limbs) — the Jacobian comb's
        // mixed addition wants Z = 1 implicitly. Entry 0 stays all-zero
        // (never committed; see _p256_jmadd_d's keep mask).
        : ( Vec i ) tbl ( _magn 128 )
        : *i zp ( vec_data [i] tbl )
        = . zp 0 0 = . zp 1 0 = . zp 2 0 = . zp 3 0
        = . zp 4 0 = . zp 5 0 = . zp 6 0 = . zp 7 0
        : ~ i s 1
        ~ < s 16 {
            // T1 points sit at blob offsets 0‥14·64, T2 at 15·64‥29·64.
            : i off * + * t 15 - s 1 64
            : ( Vec i ) xl ( __p256_be32_to_limbs tbytes off )
            : ( Vec i ) yl ( __p256_be32_to_limbs tbytes + off 32 )
            ( _p256_to_mont_d scr mx xl )
            ( _p256_to_mont_d scr my yl )
            ( _p256_atbl_put tbl s mx my )
            = s + s 1
        }
        // Two first callers may both build: publish-once slots 5 / 6 pick
        // one table each, and the other copy is dropped (slot registry:
        // stdlib/std/tls_server.nu). The winner lives for the rest of the
        // program, through the global.
        : i won ( vec_publish_once [i] + 5 t tbl )
        ? == t 0 { = g_p256_comb_tbl won } { = g_p256_comb_tbl2 won }
        = t + t 1
    }
}

@ __p256_comb_tbl_mont → ( Vec i ) {
    ? == g_p256_comb_tbl 0 { ( __p256_comb_build ) } {}
    ^ @ ( Vec i ) { # s g_p256_comb_tbl }
}

@ __p256_comb_tbl2_mont → ( Vec i ) {
    ? == g_p256_comb_tbl2 0 { ( __p256_comb_build ) } {}
    ^ @ ( Vec i ) { # s g_p256_comb_tbl2 }
}

// scalar · G → 64 bytes X‖Y, constant-time fixed-base comb on JACOBIAN
// coordinates with affine table entries: 32 × (3M+5S) doublings +
// 64 × (8M+3S) mixed additions, against the projective complete
// formula's 14 multiplies for every one of those 96 operations. The
// exceptional cases the complete formula absorbed are handled by
// constant-time masks — see the Jacobian-layer header in
// std/p256_field.nu for the case analysis and the ~2⁻²²⁴ bound on the
// one it (deliberately, like ecp_nistz256) does not cover.
@ p256ct_scalarmult_base ( Vec u ) kbytes → ( Vec u ) {
    : P256Scratch scr ( _p256_scr_new )
    // Shared, lazily-built tables of G multiples — BORROWED from the
    // global cache; must not be freed here.
    : ( Vec i ) tbl1 ( __p256_comb_tbl_mont )
    : ( Vec i ) tbl2 ( __p256_comb_tbl2_mont )
    : ( Vec i ) onem ( _p256_one_mont_s scr )
    : ( Vec i ) ex ( _mag4 )
    : ( Vec i ) ey ( _mag4 )
    // acc = ∞: Z = 0 (X/Y values are irrelevant while Z = 0; the
    // doubling keeps Z at 0 and the first committed add replaces all
    // three coordinates via the ∞ mask).
    : P256Pt acc ( _p256_pt_mag )
    ( _p256_set_identity_d scr acc )
    // Eight-tooth Lim–Lee comb as two 4-tooth halves: iteration i
    // (31‥0) doubles once, then adds T1[bits i,i+32,i+64,i+96] and
    // T2[bits i+128,…,i+224]. Constant-time: fixed trip count, masked
    // table scans, masked exceptional-case commits.
    : ~ i i 31
    ~ >= i 0 {
        ( _p256_jdbl_d scr acc )
        : ~ i idx1 0
        : ~ i idx2 0
        : ~ i j 0
        ~ < j 4 {
            : i bp1 + * 32 j i
            : i by1 - 31 >> bp1 3
            : i b1 & 1 >> ?? ( vec_get [u] kbytes by1 ) { T b → # i b F _ → 0 } & bp1 7
            = idx1 | idx1 << b1 j
            : i bp2 + 128 bp1
            : i by2 - 31 >> bp2 3
            : i b2 & 1 >> ?? ( vec_get [u] kbytes by2 ) { T b → # i b F _ → 0 } & bp2 7
            = idx2 | idx2 << b2 j
            = j + j 1
        }
        // keep-mask: −1 exactly when the digit is 0 (branch-free).
        : i k1 - # i >> # u64 | idx1 - 0 idx1 63 1
        : i k2 - # i >> # u64 | idx2 - 0 idx2 63 1
        ( _p256_atbl_get_d ex ey tbl1 idx1 )
        ( _p256_jmadd_d scr acc ex ey onem k1 )
        ( _p256_atbl_get_d ex ey tbl2 idx2 )
        ( _p256_jmadd_d scr acc ex ey onem k2 )
        = i - i 1
    }
    // Jacobian → affine: x = X/Z², y = Y/Z³ (Z = 0 → zinv = 0 → the
    // all-zero identity output, as before).
    : ( Vec i ) zinv ( _mag4 )
    ( _p256_inv_d scr zinv . acc z )
    ( _p256_sqr_d scr . acc z zinv )
    ( _p256_mul_d scr . acc x . acc x . acc z )
    ( _p256_mul_d scr . acc z . acc z zinv )
    ( _p256_mul_d scr . acc y . acc y . acc z )
    ( _p256_from_mont_d scr . acc x . acc x )
    ( _p256_from_mont_d scr . acc y . acc y )
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( _p256_limbs_to_be out . acc x )
    ( _p256_limbs_to_be out . acc y )
    ^ out
}

// ── public points ─────────────────────────────────────────────────
// A peer's ECDH share and a verifier's public key arrive as the
// uncompressed SEC1 encoding 0x04 ‖ X(32) ‖ Y(32). Both are decoded and
// validated on the fixed-width field — canonical coordinates (x, y < p)
// and the curve equation (M3: an off-curve point would let a peer pull
// our scalar out through an invalid-curve attack). P-256's cofactor is 1,
// so an on-curve point other than ∞ (which has no affine encoding) has
// order n.

// Four limbs at `src` into `dst`.
@ __ec_set4 ( Vec i ) dst * i src → v {
    : *i dp ( vec_data [i] dst )
    = . dp 0 . src 0 = . dp 1 . src 1 = . dp 2 . src 2 = . dp 3 . src 3
}

// Decode and validate into plain limbs (xl, yl); F if the encoding is not
// a point of the curve.
@ __p256_decode_point ( Vec u ) pt ( Vec i ) xl ( Vec i ) yl → b {
    ? != ( vec_len [u] pt ) 65 { ^ F } {}
    ? != ?? ( vec_get [u] pt 0 ) { T x → # i x F _ → 0 } 4 { ^ F } {}
    ( __ec_set4 xl ( vec_data [i] ( __p256_be32_to_limbs pt 1 ) ) )
    ( __ec_set4 yl ( vec_data [i] ( __p256_be32_to_limbs pt 33 ) ) )
    ? ! & ( _p256_lt_p xl ) ( _p256_lt_p yl ) { ^ F } {}
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) xm ( _p256_to_mont_s scr xl )
    : ( Vec i ) ym ( _p256_to_mont_s scr yl )
    ^ ( _p256_on_curve scr xm ym )
}

// ── ECDHE over NIST P-256 (secp256r1) ─────────────────────────────
// The TLS 1.3 secp256r1 group (RFC 8446 §4.2.8.2 / RFC 8422): the
// public key is an uncompressed point 0x04 || X(32) || Y(32), and the
// shared secret is the 32-byte big-endian X of scalar·peer. `scalar` is
// the 32-byte ephemeral private key.

// Private scalar → 65-byte uncompressed public point.
@ p256_ecdh_keygen ( Vec u ) scalar → ( Vec u ) {
    // scalar·G — fixed-base comb (G is the generator).
    : ( Vec u ) xy ( p256ct_scalarmult_base scalar )
    : ( Vec u ) out ( vec_with_cap [u] 65 )
    ( vec_push [u] out # u 4 )
    ( bytes_extend_bytes out xy )
    ^ out
}

// scalar · peer-point → 32-byte shared X. Returns [] on a malformed or
// off-curve peer point. The multiply is p256ct_scalarmult: constant-time
// in the scalar and complete for every scalar.
@ p256_ecdh_shared ( Vec u ) scalar ( Vec u ) peer → ( Vec u ) {
    : ( Vec i ) xl ( _mag4 )
    : ( Vec i ) yl ( _mag4 )
    ? ! ( __p256_decode_point peer xl yl ) { ^ ( vec_new [u] ) } {}
    : ( Vec u ) xy ( p256ct_scalarmult scalar xl yl )
    ^ ( bytes_slice xy 0 32 )
}

// ── verify ────────────────────────────────────────────────────────
// Signature verification runs entirely over PUBLIC data (a certificate's
// key, the signature's r/s, a message digest), so it needs no
// operand-independent timing — it needs speed, because a TLS client pays
// one verify per certificate in the chain and a JWT server one per
// request. P-256 computes u1·G + u2·Q as ONE Straus–Shamir pass: the 256
// doublings are shared, and each 4-bit window adds a digit of u1 from an
// affine table of G (built once per process) and a digit of u2 from an
// affine table of Q (built per verify, one batch inversion). Digit 0
// adds nothing.
//
// The scalars come out of r and s, which an attacker chooses, so the
// additions must be right for every relation between the accumulator
// and the entry — equal, negated, either at infinity. Public data lets
// _p256_jmadd_vt simply branch on each case. Nothing here touches BigInt.
// (P-384 keeps its own core below.)

: ~ i g_p256_gtbl 0

// 0, G, 2G, …, 15G as an affine Montgomery table; built on first use and
// shared through publish-once slot 11 (registry: stdlib/std/tls_server.nu).
// G is a public constant, so caching it leaks nothing.
@ __p256_g_tbl → ( Vec i ) {
    ? == g_p256_gtbl 0 {
        : P256Scratch scr ( _p256_scr_new )
        : ( Vec u ) tbytes ?? ( bytes_from_hex ( __p256_comb_tbl_hex ) ) { T v → v F _ → ( vec_new [u] ) }
        // The comb blob's first point is G itself (tooth pattern 0001).
        : ( Vec i ) gx ( _p256_to_mont_s scr ( __p256_be32_to_limbs tbytes 0 ) )
        : ( Vec i ) gy ( _p256_to_mont_s scr ( __p256_be32_to_limbs tbytes 32 ) )
        : ( Vec i ) onem ( _p256_one_mont_s scr )
        : ( Vec i ) tbl ( _p256_affine_multiples scr gx gy onem )
        = g_p256_gtbl ( vec_publish_once [i] 11 tbl )
    } {}
    ^ @ ( Vec i ) { # s g_p256_gtbl }
}

// Nibble `w` (0 = most significant) of a 32-byte big-endian scalar.
@ __p256_nib ( Vec u ) k i w → i {
    : i bv ?? ( vec_get [u] k / w 2 ) { T b → # i b F _ → 0 }
    ^ ? == % w 2 0 & 15 >> bv 4 & 15 bv
}

// Entry `d` of an affine table into (ex, ey).
@ __p256_atbl_at ( Vec i ) ex ( Vec i ) ey ( Vec i ) tbl i d → v {
    : *i tp ( vec_data [i] tbl )
    ( __ec_set4 ex # *i + # i tp * * d 8 8 )
    ( __ec_set4 ey # *i + # i tp * + * d 8 4 8 )
}

// The P-256 verify core: u1 = z·s⁻¹, u2 = r·s⁻¹ over GF(n), R = u1·G +
// u2·Q, accept iff R ≠ ∞ and x(R) ≡ r (mod n). zb, rb, sb are 32-byte
// big-endian with r, s already in [1, n−1]; (qxl, qyl) is a validated
// public key, plain limbs.
@ __p256_verify_core ( Vec u ) zb ( Vec u ) rb ( Vec u ) sb ( Vec i ) qxl ( Vec i ) qyl → b {
    : ( Vec u ) w ( p256n_inv_be sb )
    : ( Vec u ) u1 ( p256n_mulmod_be zb w )
    : ( Vec u ) u2 ( p256n_mulmod_be rb w )
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) onem ( _p256_one_mont_s scr )
    : ( Vec i ) gtbl ( __p256_g_tbl )
    : ( Vec i ) qx ( _p256_to_mont_s scr qxl )
    : ( Vec i ) qy ( _p256_to_mont_s scr qyl )
    : ( Vec i ) qtbl ( _p256_affine_multiples scr qx qy onem )
    : P256Pt acc ( _p256_pt_mag )
    ( _p256_set_identity_d scr acc )
    : ( Vec i ) ex ( _mag4 )
    : ( Vec i ) ey ( _mag4 )
    : ~ i wi 0
    ~ < wi 64 {
        ? == ( _p256_zmask . acc z ) 0 {
            ( _p256_jdbl_d scr acc ) ( _p256_jdbl_d scr acc )
            ( _p256_jdbl_d scr acc ) ( _p256_jdbl_d scr acc )
        } {}
        : i d1 ( __p256_nib u1 wi )
        ? != d1 0 {
            ( __p256_atbl_at ex ey gtbl d1 )
            ( _p256_jmadd_vt scr acc ex ey onem )
        } {}
        : i d2 ( __p256_nib u2 wi )
        ? != d2 0 {
            ( __p256_atbl_at ex ey qtbl d2 )
            ( _p256_jmadd_vt scr acc ex ey onem )
        } {}
        = wi + wi 1
    }
    ? != ( _p256_zmask . acc z ) 0 { ^ F } {}
    // x(R) = X / Z², compared with r mod n.
    : ( Vec i ) zinv ( _mag4 )
    ( _p256_inv_d scr zinv . acc z )
    ( _p256_sqr_d scr zinv zinv )
    ( _p256_mul_d scr . acc x . acc x zinv )
    ( _p256_from_mont_d scr . acc x . acc x )
    : ( Vec u ) xb ( vec_with_cap [u] 32 )
    ( _p256_limbs_to_be xb . acc x )
    ^ ( bytes_eq ( p256n_reduce_be xb ) rb )
}

// A DER-decoded integer (big-endian, any leading zeros) as exactly 32
// bytes; [] when its value needs more.
@ __p256_fixed32 ( Vec u ) v → ( Vec u ) {
    : i n ( vec_len [u] v )
    : ~ i lead 0
    ~ & < lead n == ?? ( vec_get [u] v lead ) { T x → # i x F _ → 1 } 0 { = lead + lead 1 }
    : i sig - n lead
    ? > sig 32 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) out ( vec_zeroed [u] - 32 sig )
    ( bytes_extend_bytes out ( bytes_slice v lead n ) )
    ^ out
}

@ ecdsa_p256_verify ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    : ( Vec i ) qxl ( _mag4 )
    : ( Vec i ) qyl ( _mag4 )
    ? ! ( __p256_decode_point point qxl qyl ) { ^ F } {}
    : ( Vec u ) rb ( __p256_fixed32 r )
    : ( Vec u ) sb ( __p256_fixed32 s )
    ? | == ( vec_len [u] rb ) 0 == ( vec_len [u] sb ) 0 { ^ F } {}
    // r, s ∈ [1, n−1]
    ? ! & ( p256n_in_range_be rb ) ( p256n_in_range_be sb ) { ^ F } {}
    // z = the LEFTMOST 32 bytes of the digest (FIPS 186-5 §6.4.1: a longer
    // digest is truncated to the order's bit length, not reduced), a
    // shorter one left-padded.
    : i hlen ( vec_len [u] hash )
    : i m ? < hlen 32 hlen 32
    : ( Vec u ) zb ( vec_zeroed [u] - 32 m )
    ( bytes_extend_bytes zb ( bytes_slice hash 0 m ) )
    ^ ( __p256_verify_core zb rb sb qxl qyl )
}

// P-384's verifier: BigInt parsing, range checks and on-curve validation
// (a = -3, as for P-256), then std/p384_field's double-scalar core. It
// takes the curve constants and the coordinate byte length, and consumes
// p / nn / cb.
@ __ecdsa_verify BigInt p BigInt nn BigInt cb i clen ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ? != ( vec_len [u] point ) + 1 * 2 clen {
        ^ F
    } {}
    ? != ?? ( vec_get [u] point 0 ) { T x → # i x F _ → 0 } 4 {
        ^ F
    } {}

    : ( Vec u ) qxb ( bytes_slice point 1 + 1 clen )
    : ( Vec u ) qyb ( bytes_slice point + 1 clen + 1 * 2 clen )
    : BigInt qx ( bigint_from_bytes_be qxb )
    : BigInt qy ( bigint_from_bytes_be qyb )
    // M3: reject a public key that is off-curve or out of field range.
    ? ! ( __on_curve qx qy p cb ) {
        ^ F
    } {}

    : BigInt br ( bigint_from_bytes_be r )
    : BigInt bs ( bigint_from_bytes_be s )
    : BigInt one ( bigint_from_i 1 )

    : ~ b ok T
    // r,s must be in [1, n-1]
    ? < ( bigint_cmp br one ) 0 { = ok F } {}
    ? < ( bigint_cmp bs one ) 0 { = ok F } {}
    ? >= ( bigint_cmp br nn ) 0 { = ok F } {}
    ? >= ( bigint_cmp bs nn ) 0 { = ok F } {}

    : ~ b result F
    ? ok {
        // z = the LEFTMOST clen bytes of the digest (FIPS 186-5 §6.4.1:
        // a digest longer than the group order is truncated to its
        // leftmost qlen bits — NOT reduced as a full-width integer,
        // which accepts a different value whenever the digest is longer
        // than the curve, e.g. SHA-384 with P-256). A shorter digest is
        // left-padded: same integer, fixed width.
        : i hlen ( vec_len [u] hash )
        : i m ? < hlen clen hlen clen
        : ( Vec u ) zb ( vec_with_cap [u] clen )
        : ~ i k m
        ~ < k clen { ( vec_push [u] zb # u 0 ) = k + k 1 }
        : ~ i j 0
        ~ < j m {
            ( vec_push [u] zb ?? ( vec_get [u] hash j ) { T x → x F _ → # u 0 } )
            = j + j 1
        }
        : ( Vec u ) rb ( bigint_to_bytes_be br clen )
        : ( Vec u ) sb ( bigint_to_bytes_be bs clen )
        = result ( p384_ecdsa_verify_core zb rb sb qxb qyb )
    } {}
    ^ result
}

@ ecdsa_p384_verify ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ^ ( __ecdsa_verify ( __p384_p ) ( __p384_n ) ( __p384_b ) 48 point r s hash )
}

// ── ECDSA P-256 signing (RFC 6979 deterministic nonce) ──────────────
//
// `ecdsa_p256_sign priv hash` → 64-byte raw signature r‖s (each 32 B BE).
//   priv = 32-byte big-endian private scalar.
//   hash = the message digest (SHA-256 → 32 bytes).
// The nonce k is generated deterministically per RFC 6979 (HMAC-SHA-256),
// so signing needs no RNG and can never reuse a nonce — and the output is
// reproducible, hence KAT-testable. Verify with `ecdsa_p256_verify`.

@ __ec_bytes_fill i val i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u val ) = k + k 1 }
    ^ v
}

// True iff all 32 bytes are zero (an r or s of 0 must be retried). OR-fold
// so the scan is data-independent, like the rest of the signing path.
@ __ec_zero32 ( Vec u ) v → b {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 32 { = acc | acc ?? ( vec_get [u] v k ) { T x → # i x F _ → 0 } = k + k 1 }
    ^ == acc 0
}

// `v` as exactly 32 big-endian bytes: its LEFTMOST 32 when longer (a
// digest's bits2int, FIPS 186-5 §6.4.1 / RFC 6979 §2.3.2 — the same
// truncation verify applies), left zero-padded when shorter.
@ __ec_be32 ( Vec u ) v → ( Vec u ) {
    : i n ( vec_len [u] v )
    : ( Vec u ) o ( vec_zeroed [u] 32 )
    : i m ? < n 32 n 32
    ? > m 0 { ( nurl_memcpy # s + # i ( vec_data [u] o ) - 32 m # s ( vec_data [u] v ) m ) } {}
    ^ o
}

// V ‖ sep ‖ priv32 ‖ b2o32  (the RFC 6979 HMAC input blocks)
@ __ec_hmac_msg ( Vec u ) V i sep ( Vec u ) priv32 ( Vec u ) b2o → ( Vec u ) {
    : ( Vec u ) m ( vec_with_cap [u] 97 )
    ( bytes_extend_bytes m V )
    ( vec_push [u] m # u sep )
    ( bytes_extend_bytes m priv32 )
    ( bytes_extend_bytes m b2o )
    ^ m
}

// Every scalar stays a fixed 32 bytes on the fixed-width GF(n) field
// (stdlib/std/p256_scalar.nu) — no variable-length integer, no heap
// magnitude per step — and each HMAC key of RFC 6979 is prepared once
// (hmac_sha256_key) for the MACs made under it.
@ ecdsa_p256_sign ( Vec u ) priv ( Vec u ) hash → ( Vec u ) {
    : ( Vec u ) priv32 ( __ec_be32 priv )
    // z = bits2int(hash), and b2o = int2octets(z mod n): z < 2^256 < 2n,
    // so one conditional subtraction reduces it.
    : ( Vec u ) z32 ( __ec_be32 hash )
    : ( Vec u ) b2o ( p256n_reduce_be z32 )

    // RFC 6979 §3.2 steps b–g: V = 0x01.., K = 0x00.., two HMAC mixes.
    : ~ ( Vec u ) V ( __ec_bytes_fill 1 32 )
    : ( Vec u ) k0 ( __ec_bytes_fill 0 32 )
    : HmacSha256 h0 ( hmac_sha256_key k0 )
    : ( Vec u ) k1 ( hmac_sha256_mac h0 ( __ec_hmac_msg V 0 priv32 b2o ) )
    : HmacSha256 h1 ( hmac_sha256_key k1 )
    = V ( hmac_sha256_mac h1 V )
    : ( Vec u ) k2 ( hmac_sha256_mac h1 ( __ec_hmac_msg V 1 priv32 b2o ) )
    : ~ HmacSha256 hk ( hmac_sha256_key k2 )
    = V ( hmac_sha256_mac hk V )

    : ~ ( Vec u ) sig ( vec_new [u] )
    : ~ b done F
    ~ ! done {
        // T = HMAC(K, V); qlen == hlen == 256 so one block IS the candidate.
        = V ( hmac_sha256_mac hk V )
        ? ( p256n_in_range_be V ) {
            // k·G — fixed-base comb (G is the generator), constant-time.
            : ( Vec u ) Rxy ( p256ct_scalarmult_base V )
            : ( Vec u ) Rxb ( bytes_slice Rxy 0 32 )
            // r = R.x mod n; s = k⁻¹·(z + r·d) mod n.
            : ( Vec u ) r ( p256n_reduce_be Rxb )
            // identity result → X = 0 → r ≡ 0, retried below (no inf branch).
            ? ! ( __ec_zero32 r ) {
                : ( Vec u ) kinv ( p256n_inv_be V )
                : ( Vec u ) rd ( p256n_mulmod_be r priv32 )
                : ( Vec u ) zrd ( p256n_addmod_be b2o rd )
                : ( Vec u ) s ( p256n_mulmod_be kinv zrd )
                ? ! ( __ec_zero32 s ) {
                    ( bytes_extend_bytes sig r ) ( bytes_extend_bytes sig s )
                    = done T
                } {}
            } {}
        } {}
        ? ! done {
            // K = HMAC(K, V‖0x00); V = HMAC(K, V) — advance the generator.
            : ( Vec u ) mz ( vec_with_cap [u] 33 )
            ( bytes_extend_bytes mz V )
            ( vec_push [u] mz # u 0 )
            : ( Vec u ) kn ( hmac_sha256_mac hk mz )
            = hk ( hmac_sha256_key kn )
            = V ( hmac_sha256_mac hk V )
        } {}
    }

    ^ sig
}
