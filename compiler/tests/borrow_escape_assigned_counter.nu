// borrow_escape_assigned_counter.nu — a closure that assigns a `: ~`
// number captures it by pointer, so it may not outlive the frame.
//
// The classic counter closure returned from its maker would count into a
// dead frame; a thread that counts into its spawner's local races it and
// may outlive it. Both are refused: the state belongs in a heap-backed
// handle (an Atomic, a Locked). The negative control — the same closure
// run where it is made — is accepted (closure_capture_assigned.nu).

$ `stdlib/std/thread.nu`

@ make_counter → ( @ i ) {
    : ~ i n 0
    ^ \ → i { = n + n 1 ^ n }
}

@ count_in_a_thread → i {
    : ~ i n 0
    : !Thread ThreadErr r ( thread_spawn \ → v { = n + n 1 } )
    ?? r { T h → { ( thread_join h ) } F _ → {} }
    ^ n
}

@ main → i {
    : ( @ i ) c ( make_counter )
    ^ + ( c ) ( count_in_a_thread )
}
