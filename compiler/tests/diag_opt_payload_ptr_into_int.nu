// diag_opt_payload_ptr_into_int.nu — a string payload into an option
// declared over a NUMBER. The dangerous half of the pair; see
// diag_opt_payload_type_mismatch.nu for the other and for why the two
// cannot share a file.
//
// This one did not fail at clang. It compiled clean, linked, and ran:
// the address of the literal was folded into the i64 payload slot with
// `ptrtoint`, and the match arm read it back as an integer. The program
// below returned 4 — the low byte of a .rodata address — from a `^ v`
// the writer expected to be a number they had put there.
//
// The fold exists for a reason: a payload slot that is an untyped box
// stores pointers by design, and the `?? T p →` arm recovers them with
// one inttoptr. What was missing is that `? i` does not have a box in
// field 1, it has an `i64` that means a number — so the fold has to ask
// what the slot is before reinterpreting an address as arithmetic.

@ main → i {
    : ?i o @ ?i { T `x` }
    ?? o { T v → ^ v F → ^ 0 }
}
