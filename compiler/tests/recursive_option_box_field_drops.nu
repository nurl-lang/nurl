// recursive_option_box_field_drops.nu — a struct that holds itself through
// an option of a Box (`?( Box LNode ) next`) compiles, and a list of it is
// dropped node by node, each field once, in field order (agora #640).
//
// Whether LNode owns anything asks what the option's payload is; that asked
// whether `( Box LNode )` copies, which asked whether LNode owns anything —
// worked out afresh each time round, until the compiler's stack ran out
// (a segmentation fault, no diagnostic). A plain `( Box LNode ) next` never
// asked. The Box's answer is memoised with an in-progress mark now.
//
// The `% Drop` fields before and after the recursive one print from their
// destructors: a.b, then the rest of the list (b.b, c.b, c.e, b.e), then a.e.
// The second list has no destructor of its own and is copied whole, out of
// a Vec that keeps it.

$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `drop ` ) ( nurl_println ( string_data . b tag ) ) } }

: LNode { Bomb b ? ( Box LNode ) next String s Bomb e }

: Plain { String s ? ( Box Plain ) next }

@ bomb s tag s part → Bomb { ^ @ Bomb { ( string_from ( nurl_str_cat tag part ) ) 0 } }

@ node s tag ? ( Box LNode ) next → LNode {
    ^ @ LNode { ( bomb tag `.b` ) next ( string_from tag ) ( bomb tag `.e` ) }
}

@ len LNode n → i { ^ + 1 ?? . n next { T b → ( len ( box_get [LNode] b ) ) F → 0 } }

@ plain s tag ? ( Box Plain ) next → Plain { ^ @ Plain { ( string_from tag ) next } }

@ chars Plain n → i { ^ + ( string_len . n s ) ?? . n next { T b → ( chars ( box_get [Plain] b ) ) F → 0 } }

@ main → i {
    : LNode c ( node `c` @ ?( Box LNode ) { F } )
    : LNode b ( node `b` @ ?( Box LNode ) { T ( box_new [LNode] c ) } )
    : LNode a ( node `a` @ ?( Box LNode ) { T ( box_new [LNode] b ) } )
    ( nurl_print `nodes ` ) ( nurl_println_int ( len a ) )
    : Plain r ( plain `r` @ ?( Box Plain ) { F } )
    : Plain q ( plain `qq` @ ?( Box Plain ) { T ( box_new [Plain] r ) } )
    : Plain p ( plain `ppp` @ ?( Box Plain ) { T ( box_new [Plain] q ) } )
    : ( Vec Plain ) kept ( vec_new [Plain] )
    ( vec_push [Plain] kept p )
    : ( Vec Plain ) copies ( vec_new [Plain] )
    ( vec_push [Plain] copies ( vec_at [Plain] kept 0 ) )
    ( nurl_print `chars ` ) ( nurl_println_int + ( chars ( vec_at [Plain] kept 0 ) ) ( chars ( vec_at [Plain] copies 0 ) ) )
    ( nurl_println `end of main` )
    ^ 0
}
