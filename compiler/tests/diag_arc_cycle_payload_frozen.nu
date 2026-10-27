// diag_arc_cycle_payload_frozen.nu — an Arc whose payload can hold a handle
// back to it is read through a lend, as every Arc is: what arc_get lends is
// frozen, so the store that would close the cycle — the Arc pushed into its
// own payload's child list — is rejected, through a binding as on the
// field itself. (arc_get once handed such a payload out as a copy, which a
// trait object or any type with a `% Drop` and no clone cannot be.)
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: Node { i v ( Vec ( Arc Node ) ) kids }

@ main → i {
    : ( Arc Node ) a ( arc_new [Node] @ Node { 1 ( vec_new [( Arc Node )] ) } )
    ( vec_push [( Arc Node )] . ( arc_get [Node] a ) kids ( arc_clone [Node] a ) )
    : Node n ( arc_get [Node] a )
    : ( Vec ( Arc Node ) ) ks . n kids
    ( vec_push [( Arc Node )] ks ( arc_clone [Node] a ) )
    ^ 0
}
