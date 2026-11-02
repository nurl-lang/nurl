// holder_given_a_new_value_on_every_path_drops_its_dependency: agora #389 — guard: the holder given a new value on both arms of the ? views nothing of the source past the join
// Runs clean: both arms clear the dependency, so the join holds none (agora #389).
// main: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #389: guard: the holder given a new value on both arms of the ? views nothing of the source past the join
$ `stdlib/core/string.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ main → i {
    : ~ W a @ W { `x` }
    : ~ i n 1
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( k a t )
        ? > n 5 { = a @ W { `lit` } } { = a @ W { `other` } }
    }
    ( nurl_println . a v )
    ^ 0
}
