// closure_join_frees_assigned_binding: a closure-valued ?? (or ?) statement took its arm's value — an assignment, `= base ( wrap base )` — for an owned temporary of the join and freed it when the statement ended, under the binding that now held it (packages/http's HTTP/3 Alt-Svc wrapper: the TLS server crashed at startup).
// Closed: a join nothing takes owns nothing — each arm drops a temporary it made, and an assigned closure stays its binding's; a join whose value is taken gets an owned copy from every arm.
// main's compiler: heap-use-after-free.
// map: §2.11 | A2 | runs-clean | h259 | closure assigned in a ?? arm freed as join temporary while binding holds it
$ `stdlib/core/io.nu`

: Srv { ( @ i i ) h }

@ srv_new ( @ i i ) h → Srv { ^ @ Srv { h } }

@ wrap ( @ i i ) inner → ( @ i i ) {
    ^ \ i x → i { ^ + ( inner x ) 1 }
}

@ run → i {
    : i k 7
    : ~ ( @ i i ) base \ i x → i { ^ + x k }

    : Srv s ( srv_new base )
    ?? @ ?i { T 4 } { T t → { = base ( wrap base ) } F → {} }
    : ( @ i i ) h1 . s h
    ^ + ( base 1 ) ( h1 1 )
}

@ main → i {
    ( nurl_println_int ( run ) )
    ^ 0
}
