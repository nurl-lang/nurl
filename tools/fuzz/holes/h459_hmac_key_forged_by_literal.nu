// H459: `@ HmacSha256 { ( sha256_init ) }` in safe code: a prepared HMAC
// key around a plain 144-word hasher, where the MAC steps read the
// midstates at words 144–160 and the HKDF scratch up to word 244.
// Closed: HmacSha256 is sealed (`raw :`); a literal of it is raw memory,
// which only an `unsafe` function may build — hmac_sha256_key makes the
// only one.
// v0.80.0: accepted; ran clean (the hasher's block happened to reach
// past word 160), the MAC read from words no key had written.
$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_sha256.nu`

@ main → i {
    : HmacSha256 k @ HmacSha256 { ( sha256_init ) }
    : ( Vec u ) m ( vec_new [u] )
    : ( Vec u ) o ( hmac_sha256_mac k m )
    ( nurl_println_int ( vec_len [u] o ) )
    ^ 0
}
