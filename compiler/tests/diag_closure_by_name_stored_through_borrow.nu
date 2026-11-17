// diag_closure_by_name_stored_through_borrow.nu — the refused neighbour
// of closure_beside_view_stored_through_borrow.nu (AGORA-901). A closure
// that captures a stack binding by name (`cnt`, assigned in its body) is
// stored with a view beside it through a borrow (`( vec_at vv 0 )`). The
// escape rule refuses it before the store: the Vec would outlive the
// frame the capture points into. The formal model admits more (a by-name
// capture the owners already hold, `StmtT.editBV`); this pins that nurlc
// still refuses every by-name capture into a Vec.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Slice i ) s ( @ v ) f }

@ main → i {
    : ~ ( Vec i ) buf ( vec_new [i] )
    ( vec_push [i] buf 3 )
    : ( Slice i ) sl ( slice_from_vec [i] buf )
    : ~ i cnt 0
    : ( Vec ( Vec S ) ) vv ( vec_new [( Vec S )] )
    ( vec_push [( Vec S )] vv ( vec_new [S] ) )
    : ( Vec S ) b ( vec_at [( Vec S )] vv 0 )
    ( vec_push [S] b @ S { sl \ → v { = cnt + cnt 1 } } )
    ( nurl_println_int cnt )
    ^ 0
}
