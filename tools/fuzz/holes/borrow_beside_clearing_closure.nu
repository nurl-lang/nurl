// borrow_beside_clearing_closure: an element borrow handed to an `in` parameter beside a closure that clears the element's Vec: the callee ran the closure and read the borrowed element, freed by the clear. ASan: heap-use-after-free.
// Closed: a closure that runs at a call — handed to it, or the closure value called — is a route to every binding it captured: when what its body passes a capture to may move that capture's buffer or drop its elements (by the callee's final summaries), no other argument of the call may reach the capture (the binding itself, a view or a borrow of it, a closure that captured it). The exclusive-call check of the borrow walk (`clox`, bck_clo_route_check).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h277 | element borrow passed beside a closure clearing its Vec
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ f String e ( @ v ) g → v {
    ( g )
    ( nurl_println_int ( string_len e ) )
}

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `a long element string on the heap` ) )
    : ( @ v ) wipe \ → v { ( vec_clear [String] xs ) }
    ?? ( vec_get [String] xs 0 ) { T e → { ( f e wipe ) } F → {} }
    ^ 0
}
