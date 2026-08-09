// diag_cast_ptr_to_bool.nu — '# b' of a string/pointer as a would-be
// null test. A pointer converts to a 64-bit integer only; the narrower
// target fell through every cast branch and emitted a nonsense cast
// only clang rejected, location-free. The cure spells out the actual
// null test.
@ main → i {
    : s t `x`
    : b z # b t
    ^ 0
}
