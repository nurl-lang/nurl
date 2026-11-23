// diag_immutable_const_assigned.nu — an immutable module constant is its
// value at every read (an immediate, AGORA-855), so nothing may write it:
// `=` of a `: i`, `: f` or `: b` constant is refused at the write.
: i LIMIT 100
: f SCALE 2.5
: b ON T

@ set_limit → i {
    = LIMIT 5
    ^ LIMIT
}

@ set_scale → f {
    = SCALE 1.0
    ^ SCALE
}

@ set_on → b {
    = ON F
    ^ ON
}

@ main → i {
    ^ ( set_limit )
}
