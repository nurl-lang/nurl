// diag_immutable_const_inout_arg.nu — an immutable module constant handed
// as an `inout` argument: the callee would write through it, and every
// read of the constant is its value (an immediate, AGORA-855). Refused.
: i LIMIT 100

@ bump inout i x → v { = x + x 1 }

@ main → i {
    ( bump LIMIT )
    ^ LIMIT
}
