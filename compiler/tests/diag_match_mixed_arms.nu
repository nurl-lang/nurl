// diag_match_mixed_arms.nu — a `??` expression whose arms disagree is not
// an expression, and pretending otherwise printed pointers.
//
// The T-arm yields the option's payload (u), the F-arm an i literal. The
// lowered types differ, so the match cannot emit a phi — it used to degrade
// SILENTLY to a statement, hand `undef` to the enclosing cast / binding, and
// the program printed whatever was in the register (an address, usually).
// Found live: a WebSocket PCM16 decoder built exactly this shape and every
// audio sample came out 0 — the VAD heard an empty room forever and the
// server timed out. The failure was three layers away from the bug.
//
// Both consumers now refuse a valueless operand, and the message says WHY
// the value is missing and how to fix it (cast inside the arm).
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec u ) d ( vec_new [u] )
    ( vec_push [u] d 65 )
    // the cast consumer: '# i' over mixed u/i arms
    : i lo # i ?? ( vec_get [u] d 0 ) { T x → x F → 0 }
    // the binding consumer, no cast
    : i lo2 ?? ( vec_get [u] d 0 ) { T x → x F → 0 }
    ( vec_free [u] d )
    ^ + lo lo2
}
