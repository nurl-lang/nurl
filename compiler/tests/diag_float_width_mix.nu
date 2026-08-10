// diag_float_width_mix.nu — f32 and f in one operator. Both directions
// of the cure are named, since which one is right depends on whether
// the caller can afford the narrowing.
@ main → i {
    : f32 a 1.5
    : f b 2.5
    : f r + a b
    ^ 0
}
