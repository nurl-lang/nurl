// diag_match_guard_no_arrow.nu — a guarded arm whose '→' was forgotten.
//
// The guard scan ran until the next '→' at paren depth 0, and braces do
// not affect that depth — so it swallowed this arm's body AND the whole
// next variant, and the failure surfaced as "non-exhaustive match on
// enum 'E' — no arm covers variant 'A'" about the arm the writer had
// just written. A guard is one expression and never contains a brace at
// depth 0, so a '{' there is the missing arrow and nothing else.
: | E { A i B }

@ main → i {
    : E e @ E { A 1 }
    : i r ?? e { A v ? > v 0 { ^ v } B → 0 }
    ^ r
}
