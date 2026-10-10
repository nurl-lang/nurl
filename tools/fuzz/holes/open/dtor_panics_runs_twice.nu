// OPEN in 0.72.0 — a `% Drop` impl that panics is run a second time by the unwind, over a field it released.
// Note's impl releases `. h text` with string_free and then panics (n = 1); `recover` catches it. The
// value whose impl is running is still registered in the unwind journal, so the drain drops it again
// and releases the same String a second time. With n = 0 (no panic) the same program runs clean.
// ASan: heap-use-after-free in nurl_vec_drop, under __jdrop_Note <- nurl__jrnl_drain <- nurl_panic.
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: Note { String text i n }

% Drop Note { @ drop sink Note h → v {
        ( puts `hook` )
        ( string_free . h text )
        ? == . h n 1 { ( panic `in hook` ) } {}
    } }

@ f → v {
    : Note x @ Note { ( string_from `orig` ) 1 }
}

@ main → i {
    : !v PanicInfo pr ( recover \ → v { ( f ) } )
    ( puts `ran` )
    ^ 0
}
