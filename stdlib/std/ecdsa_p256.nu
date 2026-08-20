// stdlib/std/ecdsa_p256.nu — pure-NURL ECDSA verification on the NIST
// P-256 (secp256r1) curve. No OpenSSL. Built on BigInt; points are held
// in Jacobian coordinates so the double-and-add ladder needs only one
// field inversion at the very end.
//
//   ( ecdsa_p256_verify point r s hash ) → b
//
// point = 65-byte uncompressed public key (0x04 || X || Y).
// r, s   = signature integers (big-endian bytes).
// hash   = the message digest (SHA-256 → 32 bytes).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bigint.nu`
$ `stdlib/std/hash_sha256.nu`  // hmac_sha256_pure for the RFC 6979 nonce
$ `stdlib/std/p256_field.nu`  // fully constant-time scalar mult (secret path)
$ `stdlib/std/p256_scalar.nu`  // fixed-width GF(n) for the signing scalar arithmetic

// ── curve constants (hex → BigInt) ────────────────────────────────
@ __hx s h → BigInt {
    : ( Vec u ) v ?? ( bytes_from_hex h ) { T x → x F _ → ( vec_new [u] ) }
    : BigInt r ( bigint_from_bytes_be v )
    ( vec_free [u] v )
    ^ r
}

@ __p256_p → BigInt { ^ ( __hx `ffffffff00000001000000000000000000000000ffffffffffffffffffffffff` ) }

@ __p256_n → BigInt { ^ ( __hx `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551` ) }

@ __p256_gx → BigInt { ^ ( __hx `6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296` ) }

@ __p256_gy → BigInt { ^ ( __hx `4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5` ) }

@ __p384_p → BigInt { ^ ( __hx `fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff` ) }

@ __p384_n → BigInt { ^ ( __hx `ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973` ) }

@ __p384_gx → BigInt { ^ ( __hx `aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7` ) }

@ __p384_gy → BigInt { ^ ( __hx `3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f` ) }

// Curve b coefficients (y² = x³ − 3x + b), for on-curve validation (M3).
@ __p256_b → BigInt { ^ ( __hx `5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b` ) }

@ __p384_b → BigInt { ^ ( __hx `b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef` ) }

// ── field arithmetic mod p ────────────────────────────────────────
@ __fmul BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_mul a b )
    : BigInt r ( bigint_rem t p )
    ( bigint_free t )
    ^ r
}

@ __fadd BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_add a b )
    : BigInt r ( bigint_rem t p )
    ( bigint_free t )
    ^ r
}

@ __fsub BigInt a BigInt b BigInt p → BigInt {
    : BigInt t1 ( bigint_add a p )
    : BigInt t2 ( bigint_sub t1 b )
    : BigInt r ( bigint_rem t2 p )
    ( bigint_free t1 )
    ( bigint_free t2 )
    ^ r
}

@ __fsqr BigInt a BigInt p → BigInt { ^ ( __fmul a a p ) }

@ __f2 BigInt a BigInt p → BigInt { ^ ( __fadd a a p ) }

@ __f3 BigInt a BigInt p → BigInt {
    : BigInt d ( __f2 a p )
    : BigInt r ( __fadd d a p )
    ( bigint_free d )
    ^ r
}

@ __f4 BigInt a BigInt p → BigInt {
    : BigInt d ( __f2 a p )
    : BigInt r ( __f2 d p )
    ( bigint_free d )
    ^ r
}

@ __f8 BigInt a BigInt p → BigInt {
    : BigInt d ( __f4 a p )
    : BigInt r ( __f2 d p )
    ( bigint_free d )
    ^ r
}
// a^(p-2) mod p — multiplicative inverse.
@ __finv BigInt a BigInt p → BigInt {
    : BigInt two ( bigint_from_i 2 )
    : BigInt pm2 ( bigint_sub p two )
    : BigInt r ( bigint_modpow a pm2 p )
    ( bigint_free two )
    ( bigint_free pm2 )
    ^ r
}

// ── Jacobian point ────────────────────────────────────────────────
: Jac { BigInt x BigInt y BigInt z b inf }

@ __jinf → Jac {
    ^ @ Jac { ( bigint_from_i 1 ) ( bigint_from_i 1 ) ( bigint_from_i 0 ) T }
}

@ _jfree Jac q → v {
    ( bigint_free . q x )
    ( bigint_free . q y )
    ( bigint_free . q z )
}

@ __jclone Jac q → Jac {
    ^ @ Jac { ( bigint_clone . q x ) ( bigint_clone . q y ) ( bigint_clone . q z ) . q inf }
}

// Point doubling (a = -3 form).
@ __jdouble Jac q BigInt p → Jac {
    ? . q inf { ^ ( __jclone q ) } {}
    ? ( bigint_is_zero . q y ) { ^ ( __jinf ) } {}
    : BigInt A ( __fsqr . q y p )
    : BigInt xa ( __fmul . q x A p )
    : BigInt B ( __f4 xa p )
    : BigInt a2 ( __fsqr A p )
    : BigInt C ( __f8 a2 p )
    : BigInt zsq ( __fsqr . q z p )
    : BigInt xm ( __fsub . q x zsq p )
    : BigInt xp ( __fadd . q x zsq p )
    : BigInt dm ( __fmul xm xp p )
    : BigInt D ( __f3 dm p )
    : BigInt dsq ( __fsqr D p )
    : BigInt b2 ( __f2 B p )
    : BigInt X3 ( __fsub dsq b2 p )
    : BigInt bx ( __fsub B X3 p )
    : BigInt dbx ( __fmul D bx p )
    : BigInt Y3 ( __fsub dbx C p )
    : BigInt yz ( __fmul . q y . q z p )
    : BigInt Z3 ( __f2 yz p )
    ( bigint_free A ) ( bigint_free xa ) ( bigint_free B ) ( bigint_free a2 )
    ( bigint_free C ) ( bigint_free zsq ) ( bigint_free xm ) ( bigint_free xp )
    ( bigint_free dm ) ( bigint_free D ) ( bigint_free dsq ) ( bigint_free b2 )
    ( bigint_free bx ) ( bigint_free dbx ) ( bigint_free yz )
    ^ @ Jac { X3 Y3 Z3 F }
}

// Point addition (general Jacobian + Jacobian).
@ __jadd Jac p1 Jac p2 BigInt p → Jac {
    ? . p1 inf { ^ ( __jclone p2 ) } {}
    ? . p2 inf { ^ ( __jclone p1 ) } {}
    : BigInt z1sq ( __fsqr . p1 z p )
    : BigInt z2sq ( __fsqr . p2 z p )
    : BigInt u1 ( __fmul . p1 x z2sq p )
    : BigInt u2 ( __fmul . p2 x z1sq p )
    : BigInt z2cu ( __fmul . p2 z z2sq p )
    : BigInt z1cu ( __fmul . p1 z z1sq p )
    : BigInt s1 ( __fmul . p1 y z2cu p )
    : BigInt s2 ( __fmul . p2 y z1cu p )
    : i ucmp ( bigint_cmp u1 u2 )
    : i scmp ( bigint_cmp s1 s2 )
    ? == ucmp 0 {
        ( bigint_free z1sq ) ( bigint_free z2sq ) ( bigint_free u1 ) ( bigint_free u2 )
        ( bigint_free z2cu ) ( bigint_free z1cu ) ( bigint_free s1 ) ( bigint_free s2 )
        ? == scmp 0 { ^ ( __jdouble p1 p ) } { ^ ( __jinf ) }
    } {}
    : BigInt H ( __fsub u2 u1 p )
    : BigInt R ( __fsub s2 s1 p )
    : BigInt hsq ( __fsqr H p )
    : BigInt hcu ( __fmul H hsq p )
    : BigInt u1hsq ( __fmul u1 hsq p )
    : BigInt rsq ( __fsqr R p )
    : BigInt t1 ( __fsub rsq hcu p )
    : BigInt u1hsq2 ( __f2 u1hsq p )
    : BigInt X3 ( __fsub t1 u1hsq2 p )
    : BigInt t2 ( __fsub u1hsq X3 p )
    : BigInt rt2 ( __fmul R t2 p )
    : BigInt s1hcu ( __fmul s1 hcu p )
    : BigInt Y3 ( __fsub rt2 s1hcu p )
    : BigInt z1z2 ( __fmul . p1 z . p2 z p )
    : BigInt Z3 ( __fmul H z1z2 p )
    ( bigint_free z1sq ) ( bigint_free z2sq ) ( bigint_free u1 ) ( bigint_free u2 )
    ( bigint_free z2cu ) ( bigint_free z1cu ) ( bigint_free s1 ) ( bigint_free s2 )
    ( bigint_free H ) ( bigint_free R ) ( bigint_free hsq ) ( bigint_free hcu )
    ( bigint_free u1hsq ) ( bigint_free rsq ) ( bigint_free t1 ) ( bigint_free u1hsq2 )
    ( bigint_free t2 ) ( bigint_free rt2 ) ( bigint_free s1hcu ) ( bigint_free z1z2 )
    ^ @ Jac { X3 Y3 Z3 F }
}

// Constant-time select of one of two Jacobian points: `a` if bit==1 else `b`,
// with no branch on `bit` (each coordinate via bigint_cselect; the inf flag
// is a plain conditional move). Returns a fresh point.
@ __jcselect i bit Jac a Jac b → Jac {
    : BigInt nx ( bigint_cselect bit . a x . b x )
    : BigInt ny ( bigint_cselect bit . a y . b y )
    : BigInt nz ( bigint_cselect bit . a z . b z )
    : b ninf ? != 0 bit . a inf . b inf
    ^ @ Jac { nx ny nz ninf }
}

// k · P over the bits of k (big-endian byte view), MSB to LSB. Branchless
// (Coron always-add): every bit performs BOTH a double and an add, then a
// constant-time point select keeps the add iff the bit was set. This is the
// PUBLIC-scalar path used only by ECDSA verify (P-256/P-384) — its scalars
// are public, so the operand-time-dependent BigInt field ops are harmless.
// The SECRET path (signing nonce, ECDHE) uses the fully constant-time
// std/p256_field scalar multiply instead (see __p256_mul_affine).
@ _jmul ( Vec u ) k Jac base BigInt p → Jac {
    : ~ Jac acc ( __jinf )
    : i n ( vec_len [u] k )
    : ~ i bi 0
    ~ < bi n {
        : i byte ?? ( vec_get [u] k bi ) { T x → # i x F _ → 0 }
        : ~ i bit 7
        ~ >= bit 0 {
            : Jac d ( __jdouble acc p )
            ( _jfree acc )
            = acc d
            : i b1 & 1 >> byte bit
            : Jac t ( __jadd acc base p )
            : Jac sel ( __jcselect b1 t acc )
            ( _jfree t )
            ( _jfree acc )
            = acc sel
            = bit - bit 1
        }
        = bi + bi 1
    }
    ^ acc
}

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
        ( bigint_free x2 ) ( bigint_free x3 ) ( bigint_free three )
        ( bigint_free tx ) ( bigint_free rhs0 ) ( bigint_free rhs ) ( bigint_free lhs )
    } {}
    ( bigint_free zero )
    ^ ok
}

// Affine x-coordinate of a Jacobian point: X / Z^2 mod p.
@ _jaffine_x Jac q BigInt p → BigInt {
    : BigInt zsq ( __fsqr . q z p )
    : BigInt zinv ( __finv zsq p )
    : BigInt x ( __fmul . q x zinv p )
    ( bigint_free zsq )
    ( bigint_free zinv )
    ^ x
}

// Affine y-coordinate of a Jacobian point: Y / Z^3 mod p.
@ _jaffine_y Jac q BigInt p → BigInt {
    : BigInt zsq ( __fsqr . q z p )
    : BigInt zcb ( __fmul zsq . q z p )
    : BigInt zinv ( __finv zcb p )
    : BigInt y ( __fmul . q y zinv p )
    ( bigint_free zsq )
    ( bigint_free zcb )
    ( bigint_free zinv )
    ^ y
}

// bigint (0 ≤ x < p, ≤ 256 bits) → 8 little-endian 32-bit plain limbs.
@ __big_to_limbs8 BigInt x → ( Vec i ) {
    : ( Vec u ) be ( bigint_to_bytes_be x 32 )
    : ( Vec i ) out ( vec_with_cap [i] 8 )
    : ~ i k 0
    ~ < k 8 {
        : i b0 ?? ( vec_get [u] be - 31 * 4 k ) { T b → # i b F _ → 0 }
        : i b1 ?? ( vec_get [u] be - 30 * 4 k ) { T b → # i b F _ → 0 }
        : i b2 ?? ( vec_get [u] be - 29 * 4 k ) { T b → # i b F _ → 0 }
        : i b3 ?? ( vec_get [u] be - 28 * 4 k ) { T b → # i b F _ → 0 }
        ( vec_push [i] out | | | b0 << b1 8 << b2 16 << b3 24 )
        = k + k 1
    }
    ( vec_free [u] be )
    ^ out
}

// scalar · (affine base) → 64 bytes X‖Y, FULLY constant-time: the dedicated
// fixed-limb Montgomery field (std/p256_field) + RCB complete addition +
// branchless always-add ladder. This is the secret-path scalar multiply
// (ECDSA signing nonce, ECDHE private scalar) — no operand-time-dependent
// BigInt, no secret-dependent branch, so no scalar blinding is needed (the
// op is leak-free by construction). Identity result → 64 zero bytes.
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

// 32 big-endian bytes at offset `off` → eight little-endian 2^32 limbs.
@ __p256_be32_to_limbs ( Vec u ) src i off → ( Vec i ) {
    : ( Vec i ) out ( vec_with_cap [i] 8 )
    : ~ i k 0
    ~ < k 8 {
        : i b0 ?? ( vec_get [u] src + off - 31 * 4 k ) { T b → # i b F _ → 0 }
        : i b1 ?? ( vec_get [u] src + off - 30 * 4 k ) { T b → # i b F _ → 0 }
        : i b2 ?? ( vec_get [u] src + off - 29 * 4 k ) { T b → # i b F _ → 0 }
        : i b3 ?? ( vec_get [u] src + off - 28 * 4 k ) { T b → # i b F _ → 0 }
        ( vec_push [i] out | | | b0 << b1 8 << b2 16 << b3 24 )
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
    : P256Pt tmp ( _p256_pt_mag )
    : ~ i t 0
    ~ < t 2 {
        : ( Vec i ) tbl ( _magn 384 )
        ( _p256_set_identity_d scr tmp )
        ( _p256_tbl_put tbl 0 tmp )
        : ~ i s 1
        ~ < s 16 {
            // T1 points sit at blob offsets 0‥14·64, T2 at 15·64‥29·64.
            : i off * + * t 15 - s 1 64
            : ( Vec i ) xl ( __p256_be32_to_limbs tbytes off )
            : ( Vec i ) yl ( __p256_be32_to_limbs tbytes + off 32 )
            ( _p256_to_mont_d scr . tmp x xl )
            ( _p256_to_mont_d scr . tmp y yl )
            ( _p256_one_mont_d scr . tmp z )
            ( _p256_tbl_put tbl s tmp )
            ( vec_free [i] xl ) ( vec_free [i] yl )
            = s + s 1
        }
        ? == t 0 { = g_p256_comb_tbl # i . tbl ctl } { = g_p256_comb_tbl2 # i . tbl ctl }
        = t + t 1
    }
    ( vec_free [u] tbytes )
    ( p256pt_free tmp )
    ( _p256_scr_free scr )
}

@ __p256_comb_tbl_mont → ( Vec i ) {
    ? == g_p256_comb_tbl 0 { ( __p256_comb_build ) } {}
    ^ @ ( Vec i ) { # s g_p256_comb_tbl }
}

@ __p256_comb_tbl2_mont → ( Vec i ) {
    ? == g_p256_comb_tbl2 0 { ( __p256_comb_build ) } {}
    ^ @ ( Vec i ) { # s g_p256_comb_tbl2 }
}

// scalar · G → 64 bytes X‖Y, constant-time fixed-base comb.
@ p256ct_scalarmult_base ( Vec u ) kbytes → ( Vec u ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) aplain ( _p256_a_plain )
    : ( Vec i ) am ( _p256_to_mont_s scr aplain ) ( vec_free [i] aplain )
    : ( Vec i ) b3plain ( _p256_b3_plain )
    : ( Vec i ) b3m ( _p256_to_mont_s scr b3plain ) ( vec_free [i] b3plain )
    // Shared, lazily-built tables of G multiples — BORROWED from the
    // global cache; must not be freed here.
    : ( Vec i ) tbl1 ( __p256_comb_tbl_mont )
    : ( Vec i ) tbl2 ( __p256_comb_tbl2_mont )
    : P256Pt acc ( _p256_pt_mag )
    ( _p256_set_identity_d scr acc )
    : P256Pt selp ( _p256_pt_mag )
    // Eight-tooth Lim–Lee comb as two 4-tooth halves: iteration i
    // (31‥0) doubles once, then adds T1[bits i,i+32,i+64,i+96] and
    // T2[bits i+128,…,i+224]. 32 doublings + 64 additions, against the
    // 4-tooth layout's 64 + 64 — the doubling half of the work gone
    // for one more 3 KB public table. Same constant-time properties:
    // fixed trip count, masked table scans, complete additions (digit
    // 0 reads the identity, which the formula absorbs).
    : ~ i i 31
    ~ >= i 0 {
        ( p256ct_padd_d scr acc acc acc am b3m )
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
        ( _p256_tbl_get_d selp tbl1 idx1 )
        ( p256ct_padd_d scr acc acc selp am b3m )
        ( _p256_tbl_get_d selp tbl2 idx2 )
        ( p256ct_padd_d scr acc acc selp am b3m )
        = i - i 1
    }
    : ( Vec i ) zinv ( _mag8 )
    ( _p256_inv_d scr zinv . acc z )
    ( _p256_mul_d scr . acc x . acc x zinv )
    ( _p256_mul_d scr . acc y . acc y zinv )
    ( _p256_from_mont_d scr . acc x . acc x )
    ( _p256_from_mont_d scr . acc y . acc y )
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( _p256_limbs_to_be out . acc x )
    ( _p256_limbs_to_be out . acc y )
    ( p256pt_free acc ) ( p256pt_free selp )
    ( vec_free [i] am ) ( vec_free [i] b3m ) ( vec_free [i] zinv )
    ( _p256_scr_free scr )
    ^ out
}

@ __p256_mul_affine ( Vec u ) scalar BigInt bx BigInt by → ( Vec u ) {
    : ( Vec i ) bxl ( __big_to_limbs8 bx )
    : ( Vec i ) byl ( __big_to_limbs8 by )
    : ( Vec u ) out ( p256ct_scalarmult scalar bxl byl )
    ( vec_free [i] bxl ) ( vec_free [i] byl )
    ^ out
}

// ── ECDHE over NIST P-256 (secp256r1) ─────────────────────────────
// The TLS 1.3 secp256r1 group (RFC 8446 §4.2.8.2 / RFC 8422): the
// public key is an uncompressed point 0x04 || X(32) || Y(32), and the
// shared secret is the 32-byte big-endian X of scalar·peer. `scalar` is
// the 32-byte ephemeral private key. Reuses the curve arithmetic above.

// Private scalar → 65-byte uncompressed public point.
@ p256_ecdh_keygen ( Vec u ) scalar → ( Vec u ) {
    // scalar·G — fixed-base comb (G is the generator).
    : ( Vec u ) xy ( p256ct_scalarmult_base scalar )
    : ( Vec u ) out ( vec_with_cap [u] 65 )
    ( vec_push [u] out # u 4 )
    ( bytes_extend_bytes out xy )
    ( vec_free [u] xy )
    ^ out
}

// scalar · peer-point → 32-byte shared X. Returns [] on a malformed peer.
@ p256_ecdh_shared ( Vec u ) scalar ( Vec u ) peer → ( Vec u ) {
    ? != ( vec_len [u] peer ) 65 { ^ ( vec_new [u] ) } {}
    ? != ?? ( vec_get [u] peer 0 ) { T x → # i x F _ → 0 } 4 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) qxb ( bytes_slice peer 1 33 )
    : ( Vec u ) qyb ( bytes_slice peer 33 65 )
    : BigInt qx ( bigint_from_bytes_be qxb )
    : BigInt qy ( bigint_from_bytes_be qyb )
    : BigInt p ( __p256_p )
    : BigInt n ( __p256_n )
    : BigInt b ( __p256_b )
    // M3: reject an off-curve / out-of-field peer point (invalid-curve attack)
    // before scalar-multiplying our private key into it.
    ? ! ( __on_curve qx qy p b ) {
        ( vec_free [u] qxb ) ( vec_free [u] qyb )
        ( bigint_free qx ) ( bigint_free qy )
        ( bigint_free p ) ( bigint_free n ) ( bigint_free b )
        ^ ( vec_new [u] )
    } {}
    // Constant-time scalar · peer; take the 32-byte X (first half of X‖Y).
    : ( Vec u ) xy ( __p256_mul_affine scalar qx qy )
    : ( Vec u ) out ( bytes_slice xy 0 32 )
    ( vec_free [u] qxb ) ( vec_free [u] qyb )
    ( bigint_free qx ) ( bigint_free qy )
    ( bigint_free p ) ( bigint_free n ) ( bigint_free b ) ( vec_free [u] xy )
    ^ out
}

// ── verify ────────────────────────────────────────────────────────
// Both NIST P-256 and P-384 use a = -3, so the Jacobian point ops above
// are curve-independent; this core takes the curve constants and the
// coordinate byte length. It consumes p / nn / gx / gy.
@ __ecdsa_verify BigInt p BigInt nn BigInt gx BigInt gy BigInt cb i clen ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ? != ( vec_len [u] point ) + 1 * 2 clen {
        ( bigint_free p ) ( bigint_free nn ) ( bigint_free gx ) ( bigint_free gy ) ( bigint_free cb )
        ^ F
    } {}
    ? != ?? ( vec_get [u] point 0 ) { T x → # i x F _ → 0 } 4 {
        ( bigint_free p ) ( bigint_free nn ) ( bigint_free gx ) ( bigint_free gy ) ( bigint_free cb )
        ^ F
    } {}

    : ( Vec u ) qxb ( bytes_slice point 1 + 1 clen )
    : ( Vec u ) qyb ( bytes_slice point + 1 clen + 1 * 2 clen )
    : BigInt qx ( bigint_from_bytes_be qxb )
    : BigInt qy ( bigint_from_bytes_be qyb )
    ( vec_free [u] qxb )
    ( vec_free [u] qyb )
    // M3: reject a public key that is off-curve or out of field range.
    ? ! ( __on_curve qx qy p cb ) {
        ( bigint_free qx ) ( bigint_free qy )
        ( bigint_free p ) ( bigint_free nn ) ( bigint_free gx ) ( bigint_free gy ) ( bigint_free cb )
        ^ F
    } {}

    : BigInt br ( bigint_from_bytes_be r )
    : BigInt bs ( bigint_from_bytes_be s )
    : BigInt z ( bigint_from_bytes_be hash )
    : BigInt one ( bigint_from_i 1 )

    : ~ b ok T
    // r,s must be in [1, n-1]
    ? < ( bigint_cmp br one ) 0 { = ok F } {}
    ? < ( bigint_cmp bs one ) 0 { = ok F } {}
    ? >= ( bigint_cmp br nn ) 0 { = ok F } {}
    ? >= ( bigint_cmp bs nn ) 0 { = ok F } {}

    : ~ b result F
    ? ok {
        : BigInt zr ( bigint_rem z nn )
        : BigInt w ( __finv bs nn )  // s^-1 mod n
        : BigInt u1m ( bigint_mul zr w )
        : BigInt u1 ( bigint_rem u1m nn )
        : BigInt u2m ( bigint_mul br w )
        : BigInt u2 ( bigint_rem u2m nn )
        : ( Vec u ) u1b ( bigint_to_bytes_be u1 0 )
        : ( Vec u ) u2b ( bigint_to_bytes_be u2 0 )

        : Jac G @ Jac { gx gy ( bigint_from_i 1 ) F }
        : Jac Q @ Jac { qx qy ( bigint_from_i 1 ) F }
        : Jac p1 ( _jmul u1b G p )
        : Jac p2 ( _jmul u2b Q p )
        : Jac R ( __jadd p1 p2 p )
        ? . R inf { = result F } {
            : BigInt rx ( _jaffine_x R p )
            : BigInt rxn ( bigint_rem rx nn )
            = result == ( bigint_cmp rxn br ) 0
            ( bigint_free rx )
            ( bigint_free rxn )
        }
        ( _jfree G ) ( _jfree Q ) ( _jfree p1 ) ( _jfree p2 ) ( _jfree R )
        ( bigint_free zr ) ( bigint_free w ) ( bigint_free u1m ) ( bigint_free u1 )
        ( bigint_free u2m ) ( bigint_free u2 ) ( vec_free [u] u1b ) ( vec_free [u] u2b )
    } {
        ( bigint_free qx )
        ( bigint_free qy )
        ( bigint_free gx )
        ( bigint_free gy )
    }
    ( bigint_free p ) ( bigint_free nn ) ( bigint_free br ) ( bigint_free bs )
    ( bigint_free z ) ( bigint_free one ) ( bigint_free cb )
    ^ result
}

@ ecdsa_p256_verify ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ^ ( __ecdsa_verify ( __p256_p ) ( __p256_n ) ( __p256_gx ) ( __p256_gy ) ( __p256_b ) 32 point r s hash )
}

@ ecdsa_p384_verify ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ^ ( __ecdsa_verify ( __p384_p ) ( __p384_n ) ( __p384_gx ) ( __p384_gy ) ( __p384_b ) 48 point r s hash )
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

// V ‖ sep ‖ priv32 ‖ b2o32  (the RFC 6979 HMAC input blocks)
@ __ec_hmac_msg ( Vec u ) V i sep ( Vec u ) priv32 ( Vec u ) b2o → ( Vec u ) {
    : ( Vec u ) m ( vec_new [u] )
    ( bytes_extend_bytes m V )
    ( vec_push [u] m # u sep )
    ( bytes_extend_bytes m priv32 )
    ( bytes_extend_bytes m b2o )
    ^ m
}

@ ecdsa_p256_sign ( Vec u ) priv ( Vec u ) hash → ( Vec u ) {
    : BigInt n ( __p256_n )
    : BigInt p ( __p256_p )
    : BigInt x ( bigint_from_bytes_be priv )
    : BigInt z ( bigint_from_bytes_be hash )
    : BigInt zmod ( bigint_rem z n )
    : ( Vec u ) priv32 ( bigint_to_bytes_be x 32 )
    : ( Vec u ) b2o ( bigint_to_bytes_be zmod 32 )
    ( bigint_free zmod )

    // RFC 6979 §3.2 step b/c/d/e/f: V=0x01.., K=0x00.., two HMAC mixes.
    : ~ ( Vec u ) V ( __ec_bytes_fill 1 32 )
    : ~ ( Vec u ) K ( __ec_bytes_fill 0 32 )
    : ( Vec u ) m1 ( __ec_hmac_msg V 0 priv32 b2o )
    : ( Vec u ) k1 ( hmac_sha256_pure K m1 )
    ( vec_free [u] K ) ( vec_free [u] m1 ) = K k1
    : ( Vec u ) v1 ( hmac_sha256_pure K V ) ( vec_free [u] V ) = V v1
    : ( Vec u ) m2 ( __ec_hmac_msg V 1 priv32 b2o )
    : ( Vec u ) k2 ( hmac_sha256_pure K m2 )
    ( vec_free [u] K ) ( vec_free [u] m2 ) = K k2
    : ( Vec u ) v2 ( hmac_sha256_pure K V ) ( vec_free [u] V ) = V v2

    : BigInt one ( bigint_from_i 1 )
    : ~ ( Vec u ) sig ( vec_new [u] )
    : ~ b done F
    ~ ! done {
        // T = HMAC(K, V); qlen == hlen == 256 so one block IS the candidate.
        : ( Vec u ) vt ( hmac_sha256_pure K V ) ( vec_free [u] V ) = V vt
        : BigInt k ( bigint_from_bytes_be V )
        : ~ b valid T
        ? < ( bigint_cmp k one ) 0 { = valid F } {}
        ? >= ( bigint_cmp k n ) 0 { = valid F } {}
        ? valid {
            // k·G — fixed-base comb (G is the generator), constant-time.
            : ( Vec u ) Rxy ( p256ct_scalarmult_base V )
            : ( Vec u ) Rxb ( bytes_slice Rxy 0 32 )
            ( vec_free [u] Rxy )
            // r = R.x mod n, and the scalar arithmetic s = k⁻¹·(z + r·d)
            // mod n, all on the fixed-width Montgomery GF(n) field
            // (stdlib/std/p256_scalar.nu) rather than the generic bigint —
            // the k⁻¹ Fermat inverse alone was ~half a handshake's crypto.
            // priv32 is d, b2o is z mod n (both 32-byte big-endian).
            : ( Vec u ) r ( p256n_reduce_be Rxb )
            ( vec_free [u] Rxb )
            // identity result → X = 0 → r ≡ 0, retried below (no inf branch).
            ? ( __ec_zero32 r ) {
                = valid F
                ( vec_free [u] r )
            } {
                : ( Vec u ) kinv ( p256n_inv_be V )
                : ( Vec u ) rd ( p256n_mulmod_be r priv32 )
                : ( Vec u ) zrd ( p256n_addmod_be b2o rd )
                : ( Vec u ) s ( p256n_mulmod_be kinv zrd )
                ( vec_free [u] kinv ) ( vec_free [u] rd ) ( vec_free [u] zrd )
                ? ( __ec_zero32 s ) {
                    = valid F
                    ( vec_free [u] r ) ( vec_free [u] s )
                } {
                    ( bytes_extend_bytes sig r ) ( bytes_extend_bytes sig s )
                    ( vec_free [u] r ) ( vec_free [u] s )
                    = done T
                }
            }
        } {}
        ? ! done {
            // K = HMAC(K, V‖0x00); V = HMAC(K, V) — advance the generator.
            : ( Vec u ) mz ( vec_new [u] )
            ( bytes_extend_bytes mz V )
            ( vec_push [u] mz # u 0 )
            : ( Vec u ) kn ( hmac_sha256_pure K mz )
            ( vec_free [u] K ) ( vec_free [u] mz ) = K kn
            : ( Vec u ) vn ( hmac_sha256_pure K V ) ( vec_free [u] V ) = V vn
        } {}
        ( bigint_free k )
    }

    ( bigint_free n ) ( bigint_free p ) ( bigint_free x ) ( bigint_free z )
    ( bigint_free one )
    ( vec_free [u] V ) ( vec_free [u] K ) ( vec_free [u] priv32 ) ( vec_free [u] b2o )
    ^ sig
}
