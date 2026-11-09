// defer_reads_a_holder_viewing_a_local_bound_after_it_at_a_try_exit: a defer reads an inout holder that views a local String bound after the defer; a `\` hands the failure back (PO b07).
// Closed: a value bound after the last defer drops at the exit before the defers run (spec §5.3), and the walk now ends it there first, so the defer's read through the holder is a read of a released value (agora #408).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #408: a defer reads an inout holder that views a local String bound after the defer; a `\` hands the failure back (PO b07)
$ `stdlib/core/string.nu`

: W { s v }
: | E { Bad i }

@ may i k → !i E {
    ? > k 0 { ^ @ !i E { F @ E { Bad k } } } {}
    ^ @ !i E { T k }
}

@ fill inout W w i k → !i E {
    ; { ( nurl_println . w v ) = w @ W { `literal from the defer` } }
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    : i x \ ( may k )
    = w @ W { `literal` }
    ^ @ !i E { T x }
}

@ main → i {
    : ~ W w @ W { `start` }
    ?? ( fill w 1 ) { T _ → {} F _ → {} }
    ( nurl_println . w v )
    ^ 0
}
