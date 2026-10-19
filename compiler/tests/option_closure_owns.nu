// option_closure_owns.nu — an option or a result of a closure owns the
// closure's env, as a struct field of one does (docs/MEMORY.md §7.5): built
// in a function and handed back bare, in a struct or as a result (h281,
// h282, h284 — the frame used to free the env under it), a field the struct
// drops, and a loop-local option dropped each iteration.

$ `stdlib/core/string.nu`

: H { i id ? ( @ i i ) cb }

@ mk_opt String a → ?( @ i i ) {
    : ( @ i i ) f \ i x → i { ^ + x ( string_len a ) }
    : ?( @ i i ) o @ ?( @ i i ) { T f }
    ^ o
}

@ mk_direct String a → ?( @ i i ) {
    : ( @ i i ) f \ i x → i { ^ * x ( string_len a ) }
    ^ @ ?( @ i i ) { T f }
}

@ mk_struct String a → H {
    : ( @ i i ) f \ i x → i { ^ - x ( string_len a ) }
    ^ @ H { 1 @ ?( @ i i ) { T f } }
}

@ mk_res String a b ok → !( @ i i ) s {
    : ( @ i i ) f \ i x → i { ^ + x ( string_len a ) }
    ? ok { ^ @ !( @ i i ) s { T f } } {}
    ^ @ !( @ i i ) s { F `no closure` }
}

@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz` )
    : ?( @ i i ) o ( mk_opt a )
    ?? o { T g → { ( nurl_println_int ( g 1 ) ) } F → {} }
    ?? ( mk_direct a ) { T g → { ( nurl_println_int ( g 2 ) ) } F → {} }
    : H h ( mk_struct a )
    ?? . h cb { T g → { ( nurl_println_int ( g 3 ) ) } F → {} }
    ?? ( mk_res a T ) { T g → { ( nurl_println_int ( g 4 ) ) } F e → { ( nurl_println e ) } }
    ?? ( mk_res a F ) { T g → { ( nurl_println_int ( g 4 ) ) } F e → { ( nurl_println e ) } }
    : ~ i k 0
    ~ < k 3 {
        : ( @ i i ) f \ i x → i { ^ + x ( string_len a ) }
        : ?( @ i i ) lo @ ?( @ i i ) { T f }
        ?? lo { T g → { ( nurl_println_int ( g k ) ) } F → {} }
        = k + k 1
    }
    ^ 0
}
