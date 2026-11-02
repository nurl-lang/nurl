// closure_growing_its_string_parameter_ends_a_view: a closure that grows its own String parameter, called beside a view of its buffer.
// Closed: a closure literal is summarised from its own body as a function is (what it changes, moves or drops of its parameters, and the views it leaves between them), under its emitted name; a call through a binding that holds it is a call of the binding's summary node — the union of every literal and node bound to it — and a closure parameter's node is the union of what every caller passes there (agora #359, #403).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #359: a closure that grows its own String parameter, called beside a view of its buffer
$ `stdlib/core/string.nu`

@ main → i {
    : String b ( string_from `a string long enough to live in a heap buffer of its own` )
    : ( @ v String ) grow \ String x → v { ( string_push_str x `and a tail long enough to make the buffer move somewhere else entirely, surely` ) }
    : s v0 ( string_data b )
    ( grow b )
    ( nurl_println v0 )
    ^ 0
}
