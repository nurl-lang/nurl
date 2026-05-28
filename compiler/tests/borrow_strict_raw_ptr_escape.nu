// borrow_strict_raw_ptr_escape.nu — BORROW.md Phase 5+ (strict mode):
// a `# *T <owned-binding>` cast hands the caller a raw pointer into
// a binding the compiler will auto-drop at scope exit. Even when the
// pattern is safe in this specific function, it bypasses the single-
// owner contract: any later reassignment, sink-pass, explicit free,
// or scope-exit drop of the source binding invalidates the pointer.
// Default `--borrowck` leaves this unchecked (the compiler has no
// data-flow tracking of where the pointer ends up); `--strict-borrowck`
// flags every `# *T <owned-ident>` and asks the user to either take
// a `*T` parameter or copy the bytes before the binding's region ends.
//
// One positive case + one negative control.

$ `stdlib/core/string.nu`

@ main → i {
    // Owned String. The compiler tracks it on the auto-drop list and
    // will emit `string_free` at function exit.
    : String s ( string_from `hello\n` )

    // POSITIVE — `# *u s` reaches inside the owned binding's heap
    // allocation. After scope exit `s` is dropped, so any pointer
    // derived from this cast outlives its referent.
    : *u p # *u ( string_data s )
    ( nurl_print ( string_data s ) )

    // CONTROL — a fresh malloc'd buffer is not on the auto-drop list
    // (the binding was never tagged owned). No diagnostic.
    : s raw # s ( malloc 8 )

    ^ 0
}
