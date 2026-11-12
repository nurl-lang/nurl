// borrow_closure_run_through_a_copy.nu — a closure that grows what it
// captured, run under another name than the one its literal was bound to:
// an alias, an alias of an alias, an assignment, a `?` / `??` / block
// value, a literal chosen by a ternary or match arm, one assigned in an arm
// or below the run in a loop (the next round runs it), or handed to a
// function that runs it. Each ends the views of the capture as `( c )`
// does, with its message (Agora #686). The effects of a closure followed
// only the name its literal was bound to; they now follow the closure node,
// which already follows each of these copies.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ run ( @ v ) f → v { ( f ) }

@ via_alias → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ v ) d c
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_alias_of_alias → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ v ) d c
    : ( @ v ) e d
    ( e )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_alias_handed_to_a_runner → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ v ) d c
    ( run d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_assigned → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ~ ( @ v ) d c0
    = d c
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_ternary → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ v ) d ? k c c0
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_block → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ v ) d { c }
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_ternary_literal → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ v ) d ? k \ → v { ( vec_reserve [u] xs 4096 ) } c0
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_match_literal → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ v ) d ?? o { T q → \ → v { ( vec_reserve [u] xs 4096 ) } F → c0 }
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_assigned_in_an_arm → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ~ ( @ v ) d c0
    ? k { = d \ → v { ( vec_reserve [u] xs 4096 ) } } {}
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_assigned_below_in_a_loop → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ~ ( @ v ) d c0
    : ~ i j 0
    ~ < j 2 {
        ( d )
        = d \ → v { ( vec_reserve [u] xs 4096 ) }
        = j + j 1
    }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ via_assigned_below_in_a_loop_handed_to_a_runner → v {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }
    : ( @ v ) c0 \ → v {}
    : b k T
    : ?i o @ ?i { T 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ~ ( @ v ) d c0
    : ~ i j 0
    ~ < j 2 {
        ( run d )
        = d \ → v { ( vec_reserve [u] xs 4096 ) }
        = j + j 1
    }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
}

@ main → i { ^ 0 }
