// try_param_field_result_error: agora #202 — `: i v \ . p r`, r a parameter struct's `!i String` field: the failure handed the caller an error p still held (try_param_field_result_error).
// Closed: A try's failure that owns its error and is no binding's (a field, a join's pick) is copied for the caller: its owner keeps the original (agora #202).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h937 | agora #202: `: i v \ . p r`, r a parameter struct's `!i String` field: the failure handed the caller an error p still held
$ `stdlib/core/string.nu`

: P { ! i String r }

@ f P p → !i String {
    : i v \ . p r
    ^ @ !i String { T + v 1 }
}

@ main → i {
    : P p @ P { @ !i String { F ( string_from `an error string long enough for the heap` ) } }
    ?? ( f p ) { T x → ( nurl_println_int x ) F e → ( nurl_println ( string_data e ) ) }
    ^ 0
}
