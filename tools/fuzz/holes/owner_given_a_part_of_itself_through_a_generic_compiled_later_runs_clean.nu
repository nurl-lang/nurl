// owner_given_a_part_of_itself_through_a_generic_compiled_later_runs_clean: `= o ( first o )`, first handing back `( vec_at [N] . x kids 0 )` (a generic instance compiled after main), directly, through a helper, on one path of two (the other fresh), and a part bound first (`: N ce ( vec_at [N] . e kids 0 )  = e ( tfwd ce )`).
// Closed (agora #450 A): where the callee's module-end `part` answer for o's position holds and the result is lent and not o's old value by its key, the result is copied, owned, and the old value goes (gen_assign, mem_ud_part_copy_cond).
// main ed73e478: heap-use-after-free (o's old value dropped with the element inside it).
// map: §7.6 | A2 | runs-clean | - | agora #450 A: an owner given a part of itself through a generic compiled later
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
