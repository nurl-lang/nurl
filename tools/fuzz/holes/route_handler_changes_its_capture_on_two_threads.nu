// route_handler_changes_its_capture_on_two_threads: a route handler that pushed to a Vec it captured, its router in an Arc dispatched by two threads at once: every copy of the router reaches one handler, whose environment both threads grew with no lock.
// Closed: what running a closure changes of a capture that does not synchronise itself is a `&` atom of its capture set, rejected where the closure is kept for several threads to run at once (an Arc, a handle asserted `% Sync`).
// v0.78.0: accepted; ASan reported double-free / heap-use-after-free in the captured Vec.
// map: §6.5 | A3 | rejected | h342 | a route handler pushing to a Vec it captured, its router in an Arc dispatched by two threads: one closure environment grown by both; what a closure several threads run changes of a capture must synchronise itself
$ `stdlib/ext/http_router.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

@ hit ( Arc Router ) a i n → v {
    : Router r ( arc_get [Router] a )
    : ~ i k 0
    ~ < k n {
        : HttpRequest req @ HttpRequest { ( string_from `GET` ) ( string_from `/` ) ( string_new ) ( string_from `HTTP/1.1` ) ( vec_new [Header] ) ( vec_new [u] ) }
        : HttpResponse resp ( router_handle r req )
        = k + k 1
    }
}

@ main → i {
    : ( Vec i ) seen ( vec_new [i] )
    : Router rt ( router_new )
    ( router_get rt `/` \ HttpRequest req Params p → HttpResponse {
        ( vec_push [i] seen 1 )
        ^ ( response_text 200 `x` )
    } )
    : ( Arc Router ) a ( arc_new [Router] rt )
    : ( Arc Router ) a2 ( arc_clone [Router] a )
    : !Thread ThreadErr t ( thread_spawn \ → v { ( hit a2 20000 ) } )
    ( hit a 20000 )
    ?? t { T th → { ( thread_join th ) } F _ → {} }
    ^ 0
}
