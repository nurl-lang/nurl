// diag_orpattern_guard.nu — a guard on an or-pattern. It would have to
// hold for both variants and the compiler cannot tell which matched.
: | D { N S E W }

@ main → i {
    : D d @ D { N }
    : i r ?? d { N | S ? T → 1 E → 2 W → 3 }
    ^ r
}
