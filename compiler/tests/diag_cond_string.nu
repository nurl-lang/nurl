// diag_cond_string.nu — a pointer/string condition; same class
// as the float condition (`icmp ne i8* %r, 0` is invalid IR — a pointer
// compares against 'null', and NURL has no pointer truthiness anyway).
// The cure names both tests the user might have meant: emptiness via
// nurl_str_len, null-ness via '# i'.
@ main → i {
    : s y `hi`
    ? y { ^ 1 } {}
    ^ 0
}
