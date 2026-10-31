// temporary_it_cannot_copy_never_dropped: a call's result that cannot be copied (a `% Drop` value with no clone, or a struct holding one) thrown away as a statement — `( mk )` — or read for one field — `. ( mkh ) n` — was never dropped: the value and everything it owned leaked. A String or Vec result was dropped; this one had no owner at all.
// Closed: such a temporary is dropped where it is discarded, and the rest of a call's struct whose field that owns nothing is read is dropped there too — exactly when the call handed it over.
// main (before this PR): LSan detected memory leaks.
// map: §7.1 | A2 | runs-clean | h232 | discarded %Drop temporary / field-read temporary never dropped: leak
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

@ mk → Res {
    ^ @ Res { ( vec_new [i] ) }
}

@ mkh → Hold {
    ^ @ Hold { ( mk ) 7 }
}

@ main → i {
    ( mk )
    : i k . ( mkh ) n
    ( nurl_println_int k )
    ^ 0
}
