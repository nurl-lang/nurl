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
// The companion `should_fail_free_in_closure.nu` locks the other half:
// the rule reaches INSIDE a closure body too. It did not always — while
// only one of a closure's two exits ran the drop epilogue, a body that
// fell off its end dropped nothing and the hand-written free was what
// kept its binding from leaking, so the shape had to stay accepted
// there. Since #1032 both exits free what they registered, and the
// accepting companion (`free_in_closure_ok.nu`) is gone with the reason
// for it.

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
