// struct_fields_vec_looped_over_past_a_callee_growing_it: a `~` loop over `. w xs` (Strings) calling a callee that pushes into `. p xs` through a local
// Closed: a callee whose summary says a buffer at a field path of its parameter may move (g_fn_ifreallocs: a handle it read out of the parameter, not an element of a container there, grown) ends the caller's views of the argument's field paths' own buffers (agora #647).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #647: a loop over a struct's Vec field past a callee growing that field
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: W { ( Vec String ) xs String name }

@ pushx W p → v { : ( Vec String ) v . p xs : ~ i k 0 ~ < k 64 { ( vec_push [String] v ( string_from `a string long enough to live on the heap for sure` ) ) = k + k 1 } }

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `a string long enough to live on the heap for sure` ) )
    ( vec_push [String] xs ( string_from `a string long enough to live on the heap for sure` ) )
    : W w @ W { xs ( string_from `a name` ) }
    : ~ i n 0
    ~ x . w xs { ( pushx w ) = n + n ( string_len x ) ? > n 1000 { ^ 0 } {} }
    ( nurl_println_int n )
    ^ 0
}
