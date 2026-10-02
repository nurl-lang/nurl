// diag_returned_closure_lends_local.nu — a closure that borrows a value
// cannot be returned past the scope that drops the value.
//
// A closure that captures a parameter its function does not take over
// (`@ first ( Vec i ) v → ( @ i ) { ^ \ → i { … v … } }`) only views the
// caller's value — the documented lend (docs/MEMORY.md §4). Returned on
// past the caller's own local (`^ ( first v )`), it read freed memory once
// `v` was dropped, and nothing said so (stdlib's mcp_server_http_dispatch
// has this shape; packages/mermaid-server hid it with mem_forget). Now an
// error, through a call, a binding, a helper that lends on, and an
// implicit return alike. The controls compile: a `sink` parameter the
// closure owns, a parameter lent on to the caller, a use inside the scope.

$ `stdlib/core/vec.nu`

@ first ( Vec i ) v → ( @ i ) { ^ \ → i { ^ ( vec_len [i] v ) } }

@ owned sink ( Vec i ) v → ( @ i ) { ^ \ → i { ^ ( vec_len [i] v ) } }

@ mk → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ^ v
}

// ERROR — returned through the call
@ through_call → ( @ i ) {
    : ( Vec i ) v ( mk )
    ^ ( first v )
}

// ERROR — through a binding
@ through_binding → ( @ i ) {
    : ( Vec i ) v ( mk )
    : ( @ i ) c ( first v )
    ^ c
}

// CONTROL — lent on: this function's caller is checked instead
@ pass ( Vec i ) v → ( @ i ) { ^ ( first v ) }

// ERROR — through a helper that lends on
@ through_helper → ( @ i ) {
    : ( Vec i ) v ( mk )
    ^ ( pass v )
}

// ERROR — implicit return
@ implicit_tail → ( @ i ) {
    : ( Vec i ) v ( mk )
    ( first v )
}

// CONTROL — the closure owns a `sink` argument
@ sunk → ( @ i ) {
    : ( Vec i ) v ( mk )
    ^ ( owned v )
}

// CONTROL — used inside the scope that owns `v`
@ inside → i {
    : ( Vec i ) v ( mk )
    : ( @ i ) c ( first v )
    ^ ( c )
}

@ main → i {
    : ( @ i ) a ( sunk )
    ^ + ( a ) ( inside )
}
