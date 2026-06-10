// should_fail_immutable_local.nu
// A local introduced with `:` (no `~`) is immutable. Reassigning it
// with `= x …` must be a COMPILE ERROR. The fix for this lives in
// gen_assign — mutability is opt-in via `: ~`.
@ main → i {
    : i x 10
    = x + x 1
    ^ x
}
