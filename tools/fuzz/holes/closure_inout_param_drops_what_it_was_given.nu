// closure_inout_param_drops_what_it_was_given: a closure's `inout` parameter given a fresh value (`= y ( string_from … )`) dropped it when the closure returned: the parameter was registered as an owner of its own, so the caller's binding was left holding a freed buffer.
// Closed: an `inout` parameter is the caller's binding, in a closure as in a function: never registered for a drop, nor copied on entry.
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h347 | a closure's inout parameter given a fresh value dropped it on return: it was registered as an owner of its own; an inout parameter is the caller's binding, never an owner
$ `stdlib/core/string.nu`

@ apply ( @ v inout String ) f inout String x → v { ( f x ) }

@ main → i {
    : ~ String x ( string_from `the old value, long enough to own a buffer too` )
    ( apply \ inout String y → v { = y ( string_from `a fresh string long enough to own a buffer` ) } x )
    ( nurl_println ( string_data x ) )
    ^ 0
}
