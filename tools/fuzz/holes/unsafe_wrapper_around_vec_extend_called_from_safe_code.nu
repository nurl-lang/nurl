// unsafe_wrapper_around_vec_extend_called_from_safe_code: an unsafe user function wrapping vec_extend, called from safe code.
// Closed: a callee whose walk makes no answer of views (trusted, `unsafe`) leaves each `inout` argument whose type holds views holding what any argument holds — A2's heldOfArgs in callPostAux; a view of an argument's own storage stays the author's word (MEMORY.md §3).
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | Family G review: an unsafe user function wrapping vec_extend, called from safe code
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

unsafe @ uext inout ( Vec s ) d ( Vec s ) t → v { ( vec_extend [s] d t ) }

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ~ ( Vec s ) t ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        ( vec_push [s] t ( string_data b ) )
        ( uext ws t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
