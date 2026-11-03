// unsafe_wrapper_around_vec_extend_whose_strings_outlive_runs_clean: the same unsafe wrapper, the strings outliving the holder.
// Kept: a callee whose walk makes no answer of views (trusted, `unsafe`) leaves each `inout` argument whose type holds views holding what any argument holds — A2's heldOfArgs in callPostAux; a view of an argument's own storage stays the author's word (MEMORY.md §3).
// main 836c0e9: accepted; ran clean.
// map: §2.7 | A2 | runs-clean | - | Family G review: the same unsafe wrapper, the strings outliving the holder
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

unsafe @ uext inout ( Vec s ) d ( Vec s ) t → v { ( vec_extend [s] d t ) }

@ main → i {
    : String b ( string_from `a string freed at the end of its block` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ~ ( Vec s ) t ( vec_new [s] )
    {
        ( vec_push [s] t ( string_data b ) )
        ( uext ws t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
