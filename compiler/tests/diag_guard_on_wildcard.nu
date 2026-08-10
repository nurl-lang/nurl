// diag_guard_on_wildcard.nu — a guard on the wildcard arm.
: | E { A i B }

@ main → i {
    : E e @ E { A 1 }
    : i r ?? e { A v → v _ ? > 1 0 → 0 }
    ^ r
}
