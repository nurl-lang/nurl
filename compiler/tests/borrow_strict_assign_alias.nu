// borrow_strict_assign_alias.nu — `= dst src` hands `src`'s handle to
// `dst`. gen_assign recorded that only as a lint note, so the borrow
// checker never saw it and freeing through both names compiled clean.
//
// It is a MAYBE-move rather than the definite move the `: T dst src`
// form gets, and that is a statement about the analysis, not the code:
// the handover is certain, but the old name stays a legal way to READ
// the still-live buffer. CONTROL 2 is the stdlib's HKDF shape, where
// reading through the moved-from name after the handover is correct —
// a definite move would flag those reads and reject working code.
// Deciding which is which needs liveness this checker does not have, so
// it declines to guess: reads are never flagged, only a second CONSUME.
//
// One positive + two controls.

$ `stdlib/core/vec.nu`

@ main → i {
    // CONTROL 1 — the RHS is a CALL, not an alias: `cursor` gets a
    // fresh Vec each time and nothing is shared.
    : ~ ( Vec i ) cursor ( vec_new [i] )
    ( vec_free [i] cursor )
    = cursor ( vec_new [i] )
    ( vec_free [i] cursor )

    // CONTROL 2 — the HKDF shape: hand the handle over, then keep
    // READING through the old name while the buffer is still alive.
    // Exactly one free, through the new owner.
    : ~ ( Vec i ) prev ( vec_new [i] )
    : ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 7 )
    ( vec_free [i] prev )
    = prev t
    : i seen ( vec_len [i] t )
    ? > seen 99 { ( nurl_print `many\n` ) } {}
    ( vec_free [i] prev )

    // POSITIVE — hand the handle over, then free through BOTH names.
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    : ~ ( Vec i ) z ( vec_new [i] )
    ( vec_free [i] z )
    = z a
    ( vec_free [i] z )
    ( vec_free [i] a )

    ^ 0
}
