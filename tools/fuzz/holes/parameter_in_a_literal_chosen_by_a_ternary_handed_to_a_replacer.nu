// parameter_in_a_literal_chosen_by_a_ternary_handed_to_a_replacer: `: W w ? c @ W { h 1 } @ W { h 2 }` handed to a payload replacer
// Closed: a local a parameter that may share an Rc is put into by any of these spellings leads to the parameter in the function's summaries: a field store `= . w a h`, a join or a block that may be a literal, a container that is a field path, a kept field path or literal, a callee of the program keeping it into a later argument (agora #786).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #786: a parameter in a literal chosen by a ternary
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

: W { ( Rc ( Vec u ) ) a i n }

@ setw W w → v { ( rc_set [( Vec u )] . w a ( vec_new [u] ) ) }

@ ch ( Rc ( Vec u ) ) h i k → v { : W w ? > k 0 @ W { h 1 } @ W { h 2 } ( setw w ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch r 1 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
