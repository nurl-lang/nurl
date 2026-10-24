// tools/rsa_sign_gate.nu — the RSA private-key paths, for
// tools/tests/test_rsa_sign.py.
//
//   rsa_sign_gate <key.pem> <sha256-hex> <salt-hex>
//
// Signs the digest with RSASSA-PSS-SHA256 twice — with the key prepared in
// its CRT form (std/pkey.nu rsa_priv_sign_key → std/rsa_mont.nu, two
// blinded half-width exponentiations) and through the plain private
// exponent d (one full-width exponentiation) — and prints both signatures as hex, one per line, then
// whether std/rsa.nu's own verify accepts the first. With the salt fixed,
// PSS is deterministic, so the two lines must be identical; the Python side
// also has OpenSSL verify them.

$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/rsa.nu`

@ __hex s raw → ( Vec u ) { ^ ?? ( bytes_from_hex raw ) { T v → v F _ → ( vec_new [u] ) } }

@ main → i {
    ? < ( nurl_argv_count ) 4 {
        ( nurl_eprintln `usage: rsa_sign_gate <key.pem> <sha256-hex> <salt-hex>` )
        ^ 2
    } {}
    : String pem ?? ( read_file ( nurl_argv_get 1 ) ) {
        T p → p
        F _ → { ( nurl_eprintln `cannot read the key` ) ^ 2 }
    }
    : RsaPriv k ?? ( rsa_priv_from_pem ( string_data pem ) ) {
        T x → x
        F _ → { ( nurl_eprintln `cannot parse the key` ) ^ 2 }
    }
    ? == ( vec_len [u] . k p ) 0 { ( nurl_eprintln `key carries no CRT parameters` ) ^ 2 } {}
    : RsaKey sk ?? ( rsa_priv_sign_key k ) {
        T x → x
        F → { ( nurl_eprintln `the key's CRT parameters are unusable` ) ^ 2 }
    }
    : ( Vec u ) mh ( __hex ( nurl_argv_get 2 ) )
    : ( Vec u ) salt ( __hex ( nurl_argv_get 3 ) )
    : ( Vec u ) s_crt ( rsa_pss_sign_sha256_key sk mh salt )
    : ( Vec u ) s_d ( rsa_pss_sign_sha256 . k n . k e . k d mh salt )
    ( nurl_println ( string_data ( bytes_to_hex s_crt ) ) )
    ( nurl_println ( string_data ( bytes_to_hex s_d ) ) )
    ( nurl_println ? ( rsa_pss_verify_sha256 . k n . k e s_crt mh ) `verify ok` `verify FAILED` )
    ^ 0
}
