// borrow_escape_assigned_handle.nu — a closure that assigns a captured
// `: ~` binding holds the binding's address, so it may not outlive it.
//
// The greeter returned from its maker would write a String into a dead
// frame. (Before the binding was captured by reference the write landed
// on a per-call snapshot and was lost, with a warning; now it is refused
// where it would dangle.) Run where it is made, the same closure is fine
// (closure_snapshot_assign_released.nu).

$ `stdlib/core/string.nu`

@ make_greeter → ( @ i ) {
    : ~ String last ( string_from `none` )
    ^ \ → i { = last ( string_from `seen it` ) ^ ( string_len last ) }
}

@ main → i {
    : ( @ i ) c ( make_greeter )
    ^ ( c )
}
