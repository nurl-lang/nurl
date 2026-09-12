// diag_ffi_empty_library.nu — an FFI declaration whose library name is
// the empty string.
//
// The library name is the whole reason the '&' form names one: it is what
// turns a missing dev package into a compile error instead of a link
// error, through the `stdlib/runtime.<lib>` sentinel. The sentinel check
// ran under `? > llen 0`, so an empty name did not PASS the gate — it
// skipped it, silently, which is the one outcome a gate must never have.
//
// The '$' import surface has rejected an empty path for the same reason:
// a string that names nothing is a typo, not a declaration of "nothing".
& `` @ xhelp i a → i

@ main → i {
    : i r ( xhelp 1 )
    ( nurl_print `unreachable\n` )
    ^ r
}
