// diag_cmp_enum_payload.nu — '==' on a payload-carrying enum. Tag
// equality would silently ignore the payloads (`Num 1.5` == `Num 2.5`
// would be "true"); the compare must be written as a '??' match on
// what the variants carry.
: | E {
    Num f
    Nothing
}

@ main → i {
    : E a @ E { Num 1.5 }
    : E b @ E { Num 2.5 }
    ? == a b { ^ 1 } {}
    ^ 0
}
