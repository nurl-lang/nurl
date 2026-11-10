// inout_struct_of_views_field_kept_in_a_second_holder: agora #466 — the same with a field of an inout struct of views, `( vec_push [s] h . w v )`
// main c4d36651: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #466: the same with a field of an inout struct of views, `( vec_push [s] h . w v )`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ put inout ( Vec s ) first inout ( Vec s ) h inout W w → v { ( vec_push [s] h . w v ) }

@ main → i {
    : ~ ( Vec s ) other ( vec_new [s] )
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String m ( string_from `a heap string long enough to be on the heap for sure` )
        : ~ W w @ W { ( string_data m ) }
        ( put other hold w )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
