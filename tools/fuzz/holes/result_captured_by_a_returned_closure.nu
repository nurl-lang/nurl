// result_captured_by_a_returned_closure: agora #458 — a local `!String i` captured by a returned closure
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: a local `!String i` captured by a returned closure
$ `stdlib/core/string.nu`

@ mk i k → !String i { ? == k 0 { ^ @ !String i { F 7 } } {} ^ @ !String i { T ( string_from `a result payload long enough for the heap` ) } }

@ cap i k → ( @ i ) {
    : !String i x ( mk k )
    ^ \ → i { ?? x { T s → { ^ ( string_len s ) } F e → { ^ e } } }
}

@ main → i {
    : ( @ i ) c ( cap 1 )
    ( nurl_println_int ( c ) )
    : ( @ i ) d ( cap 0 )
    ( nurl_println_int ( d ) )
    ^ 0
}
