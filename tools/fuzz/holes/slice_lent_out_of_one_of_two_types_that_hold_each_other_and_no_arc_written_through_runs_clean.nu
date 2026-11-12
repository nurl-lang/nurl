// slice_lent_out_of_one_of_two_types_that_hold_each_other_and_no_arc_written_through_runs_clean: `: B { ( Vec A ) parts ( Vec u ) data }` and `: A { ( Vec B ) bs i n }` hold each other and neither holds an `Arc`; a function taking an `A` comes first, then a helper taking a `B` lends a `Slice` over its bytes, and the caller writes through it and reads the bytes back.
// main: accepted — and so it stays: the holder walk over a cycle with no `Arc` in it ends, answers "holds none" for both types, and the lend is an ordinary one the caller may write through.
// map: RhsT.arcGet | A3 | runs-clean | - | a helper handed one of two types that hold each other, with no Arc anywhere in them, lends a Slice the caller writes through: the holder walk over a cycle ends and refuses nothing (agora #711)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: B { ( Vec A ) parts ( Vec u ) data }
: A { ( Vec B ) bs i n }

@ count A x → i { ^ + . x n ( vec_len [B] . x bs ) }

@ holder_bytes B h → ( Slice u ) {
    ^ ( slice_from_vec [u] . h data )
}

@ main → i {
    : A x @ A { ( vec_new [B] ) 3 }
    : i n0 ( count x )
    : ( Vec A ) parts ( vec_new [A] )
    ( vec_push [A] parts x )
    : B h @ B { parts ( vec_zeroed [u] 64 ) }
    : ( Slice u ) s ( holder_bytes h )
    : ~ i k 0
    ~ < k 64 { ( slice_put [u] s k # u & + k 1 255 ) = k + k 1 }
    : ~ i sum 0
    = k 0
    ~ < k 64 { = sum + sum ( slice_byte s k ) = k + k 1 }
    ^ - + sum n0 2083
}
