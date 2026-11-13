// borrow_closure_replacing_a_binding_it_is_handed.nu — a closure that gives
// its capture `o` a new value, handed `o` (or what reaches it) by any route
// (Agora #445). Inside the call the parameter and the capture are one
// value: the assignment releases what the parameter still is. `( c o )`
// was refused (#339). Through a function that calls one with the other,
// a literal passed inline, or an argument that is an element, a view or a
// payload of the binding, the call compiled and the closure read freed
// memory. Each function below is refused. (A nested closure doing the
// assignment is refused by #339's own check, now that the closure that
// runs it says it assigns `o`: the probe
// closure_running_a_closure_that_replaces_the_binding_it_is_handed_is_refused.)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ run1 ( @ v String ) f String x → v {
    ( f x )
}

// Handed to a function that calls the closure with the binding.
@ through_a_function → v {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    : ( @ v String ) c \ String p → v { = o ( string_from `new` ) ( nurl_println ( string_data p ) ) }
    ( run1 c o )
}

// …the closure a literal written in the call.
@ an_inline_literal → v {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    ( run1 \ String p → v { = o ( string_from `new` ) ( nurl_println ( string_data p ) ) } o )
}

// An element of the binding.
@ an_element → v {
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `the owner string long enough for the heap` ) )
    : ( @ v String ) c \ String p → v { = vs ( vec_new [String] ) ( nurl_println ( string_data p ) ) }
    ( c ( vec_at [String] vs 0 ) )
}

// A view of the binding.
@ a_view → v {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    : ( @ v s ) c \ s p → v { = o ( string_from `new` ) ( nurl_println p ) }
    ( c ( string_data o ) )
}

// A `??` payload read in place out of the binding.
@ a_payload → v {
    : ~ ? String o @ ?String { T ( string_from `the owner string long enough for the heap` ) }
    : ( @ v String ) c \ String p → v { = o @ ?String { F } ( nurl_println ( string_data p ) ) }
    ?? o { T e → { ( c e ) } F → {} }
}

@ main → i {
    ^ 0
}
