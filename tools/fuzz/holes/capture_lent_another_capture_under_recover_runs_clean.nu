// map: §7.4 | A2 | runs-clean | - | AGORA-882: the closure run by recover gives capture o a lend of capture other - closed by AGORA-904: the capture is given its own copy
// AGORA-882, closed by AGORA-904: the by-pointer capture is given its own copy of what the call lends (the caller's frame cannot follow a lend of another capture); main 05206020: heap-use-after-free
// main 525613db: faults under ASan (found by AGORA-873's skeptic).
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ eat sink ? String a → v { ( show a ) }

@ passon sink ? String a → ?String { ^ a }

@ run i k → v {
    : ~ ? String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )

    : !v PanicInfo r ( recover \ → v { = o ( id other ) ? == k 1 { ( panic `boom` ) } {} } )
    ?? r { T _ → {} F p → { ( panic_info_free p ) } }
    = other ( mk `a replacement value long enough for the heap` )
    ( show o )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
