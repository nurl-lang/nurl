// H445: as h444, `@ RawBlock { `abc` 3 }`: RawBlock's `% Drop` freed the
// literal's address. Its comment called it sealed, but only a raw-pointer
// field sealed a struct, and its pointer is an `s`.
// Closed: as h444.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/mem.nu`

@ main → i {
    : RawBlock b @ RawBlock { `abc` 3 }
    ^ 0
}
