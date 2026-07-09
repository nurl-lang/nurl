// diag_did_you_mean.nu — unknown-function and undefined-identifier
// diagnostics must suggest the closest known name (Levenshtein cap 2,
// cap 1 for names up to 4 chars): a typo'd user function, a typo'd
// builtin, and a typo'd local binding each get a "did you mean" hint;
// nothing close stays hint-free (pinned by the plain message text).
// Also exercises multi-error: all four report in one run.

@ compute i a → i {
    ^ * a 2
}

@ f1 → i {
    ^ ( comptue 3 )
}

@ f2 → i {
    ( nurl_pritn `x` )
    ^ 0
}

@ f3 → i {
    : i count 5
    ^ cuont
}

@ f4 → i {
    ^ ( zzqqxxyy 1 )
}

@ main → i {
    ^ + + ( f1 ) ( f2 ) + ( f3 ) ( f4 )
}
