// hash_sha256_large_input.nu — `sha256_hex` over a large input must be
// LINEAR. Its `s` → `( Vec u )` converter used to push byte by byte
// through `nurl_str_get`, which re-runs strlen on every call, so the
// public hash API was O(n²): a 383 KB file took 3.5 s, of which the
// SHA-256 transform itself was 8 ms. Every caller paid it — webhook
// signatures, content-addressed caches, wasmbuilder's runtime object key.
//
// The guard is a wall-clock budget with a three-orders-of-magnitude
// margin, not a golden number: 512 KB is ~2 ms linear and ~6 s quadratic
// on any machine that can run this suite at all.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash.nu`
$ `stdlib/std/time.nu`

@ main → i {
    : String data ( string_new )
    : ~ i k 0
    ~ < k 8192 {
        ( string_push_str data `0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef` )
        = k + k 1
    }
    ( nurl_print_int ( string_len data ) ) ( nurl_print ` bytes\n` )
    : i t0 ( monotonic_ns )
    : String h ( sha256_hex ( string_data data ) )
    : i ms / - ( monotonic_ns ) t0 1000000
    ( nurl_print ( string_data h ) ) ( nurl_print `\n` )
    ? > ms 2000 {
        ( nurl_print `TOO SLOW: ` ) ( nurl_print_int ms ) ( nurl_print ` ms — the converter is quadratic again\n` )
        ^ 1
    } {}
    ( nurl_print `linear\n` )
    ^ 0
}
