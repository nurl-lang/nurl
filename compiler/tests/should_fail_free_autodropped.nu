// should_fail_free_autodropped.nu — freeing what auto-drop already frees.
//
// `nurl_str_slice` hands back a fresh allocation, so the `: s` binding
// carries a compiler-emitted drop at scope exit (docs/MEMORY.md §1). A
// hand-written `nurl_free` on top of that frees the same pointer twice.
// The rule is documented in prose; this locks it as a diagnostic.
//
// The cast spelling is the one that matters: every FFI pointer is freed as
// `( nurl_free # s x )`, and a check keyed on the argument's first token
// would see the cast rather than the binding and wave it through.
//
// The companion `free_in_closure_ok.nu` locks the other half: inside a
// closure body the same shape must stay ACCEPTED, because a closure that
// falls off its end drops nothing and the hand-written free is what keeps
// its binding from leaking.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

@ take s label → v {
    : s piece ( nurl_str_slice label 0 3 )
    ( nurl_print piece )
    ( nurl_free # s piece )
}

@ main → i {
    ( take `abcdef` )
    ^ 0
}
