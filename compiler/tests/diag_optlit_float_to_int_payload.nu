// diag_optlit_float_to_int_payload.nu — a float payload in an option
// literal whose declared payload type is integer. '@ ?i { T 1.5 }'
// used to bitcast 1.5's BITS into the i64 slot — the '??' match arm
// then read 4609434218613702656, silently.
@ main → i {
    : ?i o @ ?i { T 1.5 }
    ^ 0
}
