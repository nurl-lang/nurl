// map: §2.10 | A2 | rejected | - | AGORA-557: `: e ?? oh { T x → ( vec_at . x a 0 ) … }` then `?? oh { T x → ( vec_clear . x a ) … }`
// AGORA-557 (this shape): refused on main 4db4cf5b by both nurlc and tools/ncore - closed by earlier work (AGORA-842's payload-cursor owners, AGORA-580, AGORA-428's copies); moved out of the open probes
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }

@ mkh → H {
    : ( Vec S ) a ( vec_new [S] )
    ( vec_push [S] a @ S { ( string_from `a heap string long enough to own a buffer on the heap, surely` ) 1 } )
    : ( Vec S ) b ( vec_new [S] )
    ( vec_push [S] b @ S { ( string_from `a heap string long enough to own a buffer on the heap, surely` ) 2 } )
    ^ @ H { a b }
}

@ main → i {
    : ~ ? H oh @ ?H { T ( mkh ) }
    : ~ H h ( mkh )
    : S e ?? oh { T x → ( vec_at [S] . x a 0 ) F → ( vec_at [S] . h a 0 ) }
    : String f . e name
    ?? oh { T x → { ( vec_clear [S] . x a ) } F → {} }
    ( nurl_println ( string_data f ) )
    ^ 0
}
