// diag_call_generic_float_arg.nu — the generic path must apply
// the same argument law after tparam substitution: `( gid [i] y )` with
// a float y is exactly the direct-call clash. Two separate holes hid
// this: the call-site checks skip generic callees by design, and a
// `[T]`-generic's parameter roster was silently ABANDONED because the
// tparam `T` lexes as a boolean literal and scan_skip_type refused it —
// so not even the width coercion saw the parameter list.
@ gid [T] T x → T { ^ x }

@ main → i {
    : f y 1.5
    : i z ( gid [i] y )
    ^ z
}
