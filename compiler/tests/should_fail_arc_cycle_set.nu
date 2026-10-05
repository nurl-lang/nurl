// should_fail_arc_cycle_set.nu — arc_set on an Arc whose payload can hold a
// handle back to it would close a cycle no count frees: rejected
// (docs/MEMORY.md §7.7).

$ `stdlib/std/arc.nu`

: TNode { i id ? ( Arc TNode ) next }

@ main → i {
    : ( Arc TNode ) a ( arc_new [TNode] @ TNode { 1 @ ?( Arc TNode ) { F } } )
    ( arc_set [TNode] a @ TNode { 1 @ ?( Arc TNode ) { T ( arc_clone [TNode] a ) } } )
    ^ 0
}
