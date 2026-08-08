// should_fail_break_outside_loop.nu — `break` with nothing to break.
//
// A jump statement outside a `~` body has no target. Silently ignoring
// it would compile a program whose author believed it did something;
// the diagnostic names what is missing.
//
// Expected: COMPILE FAIL.

@ main → i {
    ? > 1 0 { break } {}
    ^ 0
}
