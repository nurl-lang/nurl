// H939: agora #202 — `: i v \ ( gete w )`, gete handing back `@ !i String { F . w s }` over the local `w`: the error went to the caller as its own and w released it (try_call_error_lent_from_local).
// Closed: A try's failure that owns its error goes to the caller as its own, so it is copied where it was lent: by the tried call (its bit), by a binding that does not own it (its flag), by anything else always (agora #202).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: W { String s }

@ gete W w → !i String { ^ @ !i String { F . w s } }

@ mkw → W { ^ @ W { ( string_from `an error string long enough for the heap` ) } }

@ f → !i String {
    : W w ( mkw )
    : i v \ ( gete w )
    ^ @ !i String { T + v 1 }
}

@ main → i {
    ?? ( f ) { T x → ( nurl_println_int x ) F e → ( nurl_println ( string_data e ) ) }
    ^ 0
}
