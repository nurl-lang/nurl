// diag_try_in_plain_return.nu — '\' in a function whose return type
// cannot carry the failure.
//
// The grammar: '\' "immediately returns the same shape from the enclosing
// function, propagating the error value unchanged". A return type that is
// neither an option nor a result has no such shape, and the fail path fell
// to the `zeroinitializer` default — which is not propagation. It discards
// what the callee reported and hands the caller a zero of the declared
// type.
//
// For `→ i` that is 0, an ordinary answer nothing can distinguish from a
// real one. For `→ s` it is `ret i8* zeroinitializer`, and printing the
// result is a null dereference: this file's earlier form compiled cleanly,
// linked cleanly and segfaulted.
//
// The error-type check next to this one (T8) has compared the two error
// types for years — but only when the enclosing function returns a result.
// When it returned anything else there was nothing to compare against and
// nothing said so. stdlib/core/result.nu already names the alternative in
// so many words: at "a site that cannot '\'-propagate (a `→ i` main, a
// callback with a fixed signature)", res_expect / res_unwrap take the
// payload or PANIC.
@ lookup i a → !i i {
    ^ @ !i i { F 42 }
}

@ describe → s {
    : i v \ ( lookup 1 )
    ^ `found`
}

@ main → i {
    ( nurl_print ( describe ) )
    ^ 0
}
