// diag_arc_cycle_set.nu — the thread-shared-cycle diagnostic, located.
// arc_set on an Arc whose payload can point back to it is refused while
// arc_set's body is instantiated; the report used to be headed
// `thread-shared cycle: error: …`, with no file, line or column. It is
// anchored at the check in the instantiated template now, and the
// bracketed context names the instantiation and the call site that made
// it (spec §10.2, re-parsed contexts). should_fail_arc_cycle_set.nu
// keeps the plain rejection.

$ `stdlib/std/arc.nu`

: TNode { i id ? ( Arc TNode ) next }

unsafe @ main → i {
    : ( Arc TNode ) a ( arc_new [TNode] @ TNode { 1 @ ?( Arc TNode ) { F } } )
    ( arc_set [TNode] a @ TNode { 1 @ ?( Arc TNode ) { T ( arc_clone [TNode] a ) } } )
    ^ 0
}
