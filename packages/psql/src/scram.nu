// packages/psql/src/scram.nu — SCRAM-SHA-256 client (RFC 5802 / RFC 7677),
// the SASL mechanism PostgreSQL uses for password authentication.
//
// Pure NURL on top of the stdlib crypto (SHA-256 / HMAC / PBKDF2 / base64).
// Channel binding is not used ("n,," / "c=biws"), matching libpq's default
// SCRAM-SHA-256 (not the -PLUS variant).
//
//   ( scram_client_first_bare nonce )                 → String  "n=,r=<nonce>"
//   ( scram_compute password cfb server_first )       → ScramResult
//
// `password` is the raw password bytes (SASLprep is the identity map for
// the ASCII passwords overwhelmingly used in practice). `cfb` is the
// client-first-bare returned above; `server_first` is the server's
// SASLContinue payload. The result carries the client-final message to
// send and the base64 server signature to check against the SASLFinal.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/pbkdf2.nu`
$ `stdlib/std/encode.nu`

: ScramResult {
    b ok
    String client_final
    String server_sig
}

// raw C-string → byte vector
@ __sc_raw_bytes s raw → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( nurl_str_get raw k ) ) = k + k 1 }
    ^ v
}

// String → byte vector
@ __sc_str_bytes String s → ( Vec u ) {
    ^ ( __sc_raw_bytes ( string_data s ) )
}

@ __sc_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// XOR two equal-length byte vectors.
@ __sc_xor ( Vec u ) a ( Vec u ) b → ( Vec u ) {
    : i n ( vec_len [u] a )
    : ( Vec u ) out ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] out # u & ^^ ( __sc_bget a k ) ( __sc_bget b k ) 255 ) = k + k 1 }
    ^ out
}

// Does String `s` start with raw prefix `p`?
@ __sc_starts String s s p → b {
    : i pn ( nurl_str_len p )
    ? < ( string_len s ) pn { ^ F } {}
    : s sd ( string_data s )
    : ~ i k 0
    ~ < k pn {
        ? != ( nurl_str_get sd k ) ( nurl_str_get p k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Parse a non-negative decimal from a String.
@ __sc_atoi String s → i {
    : s d ( string_data s )
    : i n ( string_len s )
    : ~ i v 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get d k )
        ? & >= c 48 <= c 57 { = v + * v 10 - c 48 } {}
        = k + k 1
    }
    ^ v
}

// client-first-bare: PostgreSQL ignores the SCRAM username (it uses the
// startup username), so we send an empty `n=`.
@ scram_client_first_bare s nonce → String {
    : String out ( string_with_cap + 8 ( nurl_str_len nonce ) )
    ( string_push_str out `n=,r=` )
    ( string_push_str out nonce )
    ^ out
}

@ scram_compute ( Vec u ) password String cfb String server_first → ScramResult {
    // ── parse server-first: r=<combined nonce>, s=<salt b64>, i=<iters> ──
    : ( Vec String ) parts ( string_split server_first `,` )
    : ~ String combined ( string_with_cap 0 )
    : ~ String salt_b64 ( string_with_cap 0 )
    : ~ i iters 0
    : i np ( vec_len [String] parts )
    : ~ i pi 0
    ~ < pi np {
        : String f ?? ( vec_get [String] parts pi ) { T x → x F _ → ( string_with_cap 0 ) }
        : i fl ( string_len f )
        ? ( __sc_starts f `r=` ) { = combined ( string_substr f 2 - fl 2 ) } {}
        ? ( __sc_starts f `s=` ) { = salt_b64 ( string_substr f 2 - fl 2 ) } {}
        ? ( __sc_starts f `i=` ) { = iters ( __sc_atoi ( string_substr f 2 - fl 2 ) ) } {}
        = pi + pi 1
    }

    ? | == ( string_len combined ) 0 == iters 0 {
        ( vec_free_with [String] parts \ String s → v { ( string_free s ) } )
        ( string_free combined ) ( string_free salt_b64 )
        ^ @ ScramResult { F ( string_with_cap 0 ) ( string_with_cap 0 ) }
    } {}

    : ( Vec u ) salt ?? ( b64_decode_vec ( string_data salt_b64 ) ) { T v → v F _ → ( vec_new [u] ) }

    // ── SCRAM key derivation (RFC 5802 §3) ──
    : ( Vec u ) salted ( pbkdf2_hmac_sha256 password salt iters 32 )
    : ( Vec u ) ck_lbl ( __sc_raw_bytes `Client Key` )
    : ( Vec u ) sk_lbl ( __sc_raw_bytes `Server Key` )
    : ( Vec u ) client_key ( hmac_sha256_pure salted ck_lbl )
    : ( Vec u ) stored_key ( sha256_pure client_key )

    // client-final-without-proof
    : String cfwop ( string_with_cap + 16 ( string_len combined ) )
    ( string_push_str cfwop `c=biws,r=` )
    ( string_push_str cfwop ( string_data combined ) )

    // AuthMessage = client-first-bare , server-first , client-final-without-proof
    : String am_s ( string_with_cap + + ( string_len cfb ) ( string_len server_first ) ( string_len cfwop ) )
    ( string_push_str am_s ( string_data cfb ) )
    ( string_push_char am_s 44 )
    ( string_push_str am_s ( string_data server_first ) )
    ( string_push_char am_s 44 )
    ( string_push_str am_s ( string_data cfwop ) )
    : ( Vec u ) am ( __sc_str_bytes am_s )

    : ( Vec u ) client_sig ( hmac_sha256_pure stored_key am )
    : ( Vec u ) proof ( __sc_xor client_key client_sig )
    : String proof_b64 ( b64_encode_vec proof )

    : String client_final ( string_with_cap + + ( string_len cfwop ) 3 ( string_len proof_b64 ) )
    ( string_push_str client_final ( string_data cfwop ) )
    ( string_push_str client_final `,p=` )
    ( string_push_str client_final ( string_data proof_b64 ) )

    : ( Vec u ) server_key ( hmac_sha256_pure salted sk_lbl )
    : ( Vec u ) server_sig ( hmac_sha256_pure server_key am )
    : String server_sig_b64 ( b64_encode_vec server_sig )

    // free scratch byte vectors
    ( vec_free [u] salt ) ( vec_free [u] salted ) ( vec_free [u] ck_lbl ) ( vec_free [u] sk_lbl )
    ( vec_free [u] client_key ) ( vec_free [u] stored_key ) ( vec_free [u] am )
    ( vec_free [u] client_sig ) ( vec_free [u] proof ) ( vec_free [u] server_key ) ( vec_free [u] server_sig )
    // free scratch strings (client_final + server_sig_b64 are returned)
    ( vec_free_with [String] parts \ String s → v { ( string_free s ) } )
    ( string_free combined ) ( string_free salt_b64 ) ( string_free cfwop )
    ( string_free am_s ) ( string_free proof_b64 )

    ^ @ ScramResult { T client_final server_sig_b64 }
}
