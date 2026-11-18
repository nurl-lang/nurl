// map: §2.12 | A2 | runs-clean | - | AGORA-840: `: ~ H c h  = . c name ( string_from … )  @ W { c }` - a String field replaced through the cursor, then the cursor stored
// AGORA-869: runs clean under ASan/LSan with the default compile (main 3358873a: faulted); the ticket's other shapes stay open.
$ `stdlib/core/string.nu`

: H { String name i n }
: W { H h i m }

@ main → i {
    : ~ H h @ H { ( string_from `a heap string long enough to own a buffer on the heap, surely` ) 0 }
    : ~ H c h
    = . c name ( string_from `a replacement string, also long enough for the heap` )
    : W w @ W { c 0 }
    ( nurl_println ( string_data . . w h name ) )
    ^ 0
}
