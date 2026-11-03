// recursion_building_owned_copies_runs_clean: a recursive builder of owned copies outlives its String argument.
// The shape the fix must keep: a self-call answering "may" stays precise where the result owns its data.
// main 4d57d596: runs clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a recursive builder of owned copies outlives its String argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ build String s i n → ( Vec String ) {
    ? == n 0 { ^ ( vec_new [String] ) } {}
    : ( Vec String ) v ( build s - n 1 )
    ( vec_push [String] v ( string_from ( string_data s ) ) )
    ^ v
}
@ main → i {
    : ~ ( Vec String ) hold ( vec_new [String] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( build s 3 )
    }
    ( nurl_println ( string_data ( vec_at [String] hold 0 ) ) )
    ^ 0
}
