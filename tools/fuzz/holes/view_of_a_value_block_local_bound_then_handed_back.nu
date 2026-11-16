// view_of_a_value_block_local_bound_then_handed_back: `: s d { : String t … : s x ( string_data t ) x }  ^ d` — the unblocked `: String t … : s d ( string_data t )  ^ d` is refused.
// Closed: a value block's bindings are the enclosing scope's to the walk as they are to codegen — its `vblock` row ends their names at the `}`, not their lives, which end where the enclosing scope does (agora #846).
// main 525613d: accepted; AddressSanitizer: heap-use-after-free.
// map: §1 | A2 | rejected | - | agora #846: a view of a value block's binding, handed back after its `}`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

@ f i k → s { : s d { : String t ( string_from `hello world, a heap string` ) : s x ( string_data t ) x } ^ d }

@ main → i {
    : s r ( f 1 )
    ( nurl_println r )
    ^ 0
}
