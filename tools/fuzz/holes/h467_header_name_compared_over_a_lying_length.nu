// H467: `( _header_name_eq_ci_n name raw lb )` compared `lb` bytes of
// `raw`, the length its callers measure once per header scan; given a
// two-byte string and the 78-byte name's length it read past the string.
// Closed: the helper is `raw` (its contract: `raw` has `lb` bytes), so
// only an `unsafe` caller may call it; `_header_name_eq_ci` measures.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/string.nu`
$ `stdlib/ext/http_response.nu`

@ main → i {
    : String nm ( string_from `abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz` )
    : String raw ( string_from `ab` )
    : b r ( _header_name_eq_ci_n nm ( string_data raw ) ( string_len nm ) )
    ( nurl_println_int ? r 1 0 )
    ^ 0
}
