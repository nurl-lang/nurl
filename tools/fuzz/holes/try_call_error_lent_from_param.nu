// try_call_error_lent_from_param: agora #202 — the same over a parameter `w`: the caller got its own argument's field as a second owner (try_call_error_lent_from_param).
// Closed: A try's failure that owns its error goes to the caller as its own, so it is copied where it was lent: by the tried call (its bit), by a binding that does not own it (its flag), by anything else always (agora #202).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h940 | agora #202: the same over a parameter `w`: the caller got its own argument's field as a second owner
$ `stdlib/core/string.nu`

: W { String s }

@ gete W w → !i String { ^ @ !i String { F . w s } }

@ mkw → W { ^ @ W { ( string_from `an error string long enough for the heap` ) } }

@ f W w → !i String {
    : i v \ ( gete w )
    ^ @ !i String { T + v 1 }
}

@ main → i {
    : W w ( mkw )
    ?? ( f w ) { T x → ( nurl_println_int x ) F e → ( nurl_println ( string_data e ) ) }
    ( nurl_println_int ( string_len . w s ) )
    ^ 0
}
