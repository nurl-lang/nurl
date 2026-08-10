// diag_match_arm_no_arrow.nu — a match arm that goes straight from the
// payload binding to the body, with no '→'.
: | E { A i B }

@ main → i {
    : E e @ E { A 1 }
    : i r ?? e { A v { ^ v } B → 0 }
    ^ r
}
