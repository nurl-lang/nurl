// diag_enum_payload_ptr_into_int.nu — a user enum's payload slot is a
// numeric word, and a pointer folded into it is read back as arithmetic.
//
// The option/result form of this was fixed in #901; the user-enum side
// kept the hole. `@ E { A `s` }` where A declares an `i` payload
// compiled clean, linked, ran, and returned 96 — the low byte of a
// .rodata address — from an arm the writer expected to yield a number.
//
// docs/MEMORY.md has carried a "user enums: SCALAR payloads only"
// gotcha for exactly this. A gotcha in prose is what a compiler says
// when it has no diagnostic; this is the diagnostic.
//
// Found by tools/metamorph's invalid-input class, whose IR-validity
// invariant did NOT catch it — the emitted module verifies fine. It is
// a wrong VALUE, not malformed IR, which is why the class enumerates
// plausible-wrong inputs as well as checking what gets lowered.

: | E { A i B }

@ main → i {
    : E e @ E { A `s` }
    ^ ?? e { A v → v B → 0 }
}
