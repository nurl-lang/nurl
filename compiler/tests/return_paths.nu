// Returning branches do not reach a later free or loop back-edge.
$ `stdlib/core/vec.nu`

@ loop_return b fail → i {
    : ( Vec u ) bytes ( vec_new [u] )
    : ~ i k 0
    ~ < k 3 {
        ? fail { ( vec_free [u] bytes ) ^ 10 } {}
        = k + k 1
    }
    ( vec_free [u] bytes )
    ^ k
}

@ nested_return b first b second → i {
    : ( Vec u ) bytes ( vec_new [u] )
    ? first {
        ( vec_free [u] bytes )
        ? second ^ 1 ^ 2
    } {}
    ( vec_free [u] bytes )
    ^ 3
}

@ match_return b first b second → i {
    : ( Vec u ) bytes ( vec_new [u] )
    ? first {
        ( vec_free [u] bytes )
        ?? second { T → ^ 1 F → ^ 2 }
    } {}
    ( vec_free [u] bytes )
    ^ 3
}

@ partial_return i which → i {
    ?? which { 0 → ^ 10 }
    ^ 20
}

@ main → i {
    ? != ( loop_return T ) 10 { ^ 1 } {}
    ? != ( loop_return F ) 3 { ^ 2 } {}
    ? != ( nested_return T T ) 1 { ^ 3 } {}
    ? != ( nested_return T F ) 2 { ^ 4 } {}
    ? != ( nested_return F F ) 3 { ^ 5 } {}
    ? != ( match_return T F ) 2 { ^ 6 } {}
    ? != ( match_return F F ) 3 { ^ 7 } {}
    ? != ( partial_return 0 ) 10 { ^ 8 } {}
    ? != ( partial_return 1 ) 20 { ^ 9 } {}
    ( nurl_print `return paths: ok\n` )
    ^ 0
}
