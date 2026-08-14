// diag_match_arm_not_a_variant.nu — a `??` arm must name something the
// scrutinee can actually BE.
//
// Nothing checked that, and the consequence was not a diagnostic. An
// unrecognised name fell through to the enum-variant path, which emits
// `load i64, i64* @<name>` for a global that was never defined, and the
// arm's payload binding got an empty type:
//
//     %r8  = alloca                      ← "Cannot allocate unsized type"
//     %r5  = load i64, i64* @Ok          ← a global that does not exist
//
// nurlc exited 0 and clang delivered the news, about generated IR rather
// than about the arm the writer has to change.
//
// The shape that surfaced it is the Rust habit, not a typo:
//
//     ?? ( int_parse `123` ) { Ok val → val  _ → -1 }
//
// so the message names the NURL spelling rather than only rejecting the
// wrong one — `T` and `F`, not `Ok`/`Err`/`Some`/`None`.
//
// Two functions, because recovery is per declaration: one error each,
// the option/result form and the named-enum form.

$ `stdlib/std/int`

: | Color { Red Green Blue }

@ rust_habit → i {
    ^ ?? ( int_parse `123` ) {
        Ok val → val
        _ → -1
    }
}

@ misspelled_variant Color c → i {
    ^ ?? c {
        Red → 1
        Purple → 2
        _ → 0
    }
}

@ main → i {
    : i a ( rust_habit )
    : i b ( misspelled_variant Red )
    ^ + a b
}
