// diag_tilde_complement_void.nu — a '~' complement with no value to
// complement.
//
// `~` is two things: a LOOP (`~ cond { body }`) and a bitwise complement
// (`~ mask`). With the condition deleted, the BODY becomes the operand
// of the complement — and a block yields no value, so the compiler
// emitted `xor void undef, -1`, invalid IR with status 0.
//
// The loop form checks its condition ("this condition produces no
// value"); the complement form did not. Found by deleting the `more`
// from `~ more {` in fat_fs.nu.

@ main → i {
    ~ {}
    ^ 0
}
