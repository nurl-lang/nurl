// diag_orpattern_bool_arm.nu — an or-pattern mixing an option arm 'T'
// with a named variant.
//
// Note which program reaches this: NOT 'T | F', which the message names.
// 'F' is a bool token, not an ident, so 'T | F' dies one check earlier
// with "expected a variant name after '|'". The message is reachable
// only through a mixed alternative like 'T | A', so its rule is right
// and its example describes a case it never sees.
: | E { A B }

@ main → i {
    : ?i o @ ?i { T 5 }
    : i r ?? o { T | A → 1 _ → 0 }
    ^ r
}
