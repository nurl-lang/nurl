// option_given_a_lend_captured_by_a_returned_closure: agora #458 — `: ?String x ( maybe o k )` (a lend of o) captured by a returned closure
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: `: ?String x ( maybe o k )` (a lend of o) captured by a returned closure
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ cap i k → ( @ i ) {
    : ?String o ( mk `a local value long enough for the heap` )
    : ?String x ( maybe o k )
    ^ \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } }
}

@ run i k → v {
    : ( @ i ) c ( cap k )
    ( nurl_println_int ( c ) )
}

@ main → i {
    ( run 0 )
    ^ 0
}
