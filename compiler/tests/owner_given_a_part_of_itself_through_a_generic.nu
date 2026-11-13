// owner_given_a_part_of_itself_through_a_generic.nu — `= o ( first o )`
// where first hands back an element of o's own Vec field through a generic
// instance compiled after the caller (Agora #450, part A).
//
// At the `=` first's lends are not final, so nurlc could not tell that the
// result may be a part of o: o's old value was dropped with the element in
// it, and o held freed memory. The callee's module-end `part` answer for o's
// position now decides: a lent result that is not o's old value is copied,
// o owns the copy, and the old value goes. A run that hands back a fresh
// value (`firstor d 0`) is not copied.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: N { String name ( Vec N ) kids }

@ first N x → N { ^ ( vec_at [N] . x kids 0 ) }

@ kid0 ( Vec N ) ks → N { ^ ( vec_at [N] ks 0 ) }

@ firstk N x → N { ^ ( kid0 . x kids ) }

@ firstor N x i k → N { ? == k 1 { ^ ( vec_at [N] . x kids 0 ) } {} ^ @ N { ( string_from `fresh name, long enough for a heap buffer` ) ( vec_new [N] ) } }

@ tfwd N x → N { ^ x }

@ tor N x i k → N { ? == k 1 { ^ x } {} ^ @ N { ( string_from `fresh name, long enough for a heap buffer` ) ( vec_new [N] ) } }

@ tree → N {
    : ~ ( Vec N ) ks ( vec_new [N] )
    ( vec_push [N] ks @ N { ( string_from `kid name, long enough for a heap buffer` ) ( vec_new [N] ) } )
    ^ @ N { ( string_from `root name, long enough for a heap buffer` ) ks }
}

@ main → i {
    : ~ N a ( tree ) = a ( first a ) ( nurl_println ( string_data . a name ) )
    : ~ N b ( tree ) = b ( firstk b ) ( nurl_println ( string_data . b name ) )
    : ~ N c ( tree ) = c ( firstor c 1 ) ( nurl_println ( string_data . c name ) )
    : ~ N d ( tree ) = d ( firstor d 0 ) ( nurl_println ( string_data . d name ) )
    // A part bound first, then handed back through a callee: ce is a lend out
    // of e's Vec field (its roots, `e.kids`).
    : ~ N e ( tree )
    : N ce ( vec_at [N] . e kids 0 )
    = e ( tfwd ce )
    ( nurl_println ( string_data . e name ) )
    : ~ N f ( tree )
    : N cf ( vec_at [N] . f kids 0 )
    = f ( tor cf 0 )
    ( nurl_println ( string_data . f name ) )
    ^ 0
}
