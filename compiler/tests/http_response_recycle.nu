// http_response_recycle.nu — responses recycled through the per-thread
// stash (response_recycle, stdlib/runtime_core.c §9a′), and what that
// buys the keep-alive server.
//
// Part 1 pins the recycling itself: a response built after one was
// recycled starts empty — no header, body byte or capture of its
// predecessor shows through — however its headers grow or shrink; a
// body past the keep limit is given back rather than kept; a borrowed
// body parks as an empty owned one, its source untouched; a router
// dispatch sees only its own captures.
//
// Part 2 counts allocations on the plaintext hello path in steady state:
// the server (thread mode, then fiber mode) answers 300 requests on one
// keep-alive connection, and the handler samples the process-wide
// allocation counter at the 100th and the 300th. The client sends one
// prebuilt request and reads into one reused buffer, allocating nothing
// per request itself, so the difference is the server's: it was 11 per
// request before the response, its header Strings, the router's Params,
// the handler's closure and the recover closure were recycled or built
// once per connection; the bound is 2.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`

& `libc` @ nurl_alloc_count → i

unsafe @ allocs → i { ^ ( nurl_alloc_count ) }

@ wire HttpResponse r → v {
    : ( Vec u ) out ( vec_new [u] )
    ( response_serialize_to r out )
    : String s ( bytes_to_str out )
    ( nurl_print ( string_data s ) )
    ( nurl_print `|\n` )
}

// `unsafe`: it keeps the borrowed-body contract (`src` outlives `view`).
unsafe @ part1 → v {
    // A response with three headers and a body, recycled.
    : HttpResponse a ( response_text 200 `first body` )
    ( response_set_header a `X-Long-Header-Name` `a-fairly-long-header-value` )
    ( response_add_header a `Set-Cookie` `k=v` )
    ( response_recycle a )
    // Its successor: one short header, a shorter body.
    : HttpResponse b ( response_new 201 )
    ( nurl_print `fresh headers=` ) ( nurl_print ( nurl_str_int ( vec_len [Header] . b headers ) ) )
    ( nurl_print ` body=` ) ( nurl_println ( nurl_str_int ( vec_len [u] . b body ) ) )
    ( response_set_header b `X` `1` )
    ( response_set_body_str b `ok` )
    ( wire b )
    ( response_recycle b )
    // More headers than the recycled ones, longer values than before.
    : HttpResponse c ( response_new 404 )
    ( response_set_header c `Content-Type` `text/plain; charset=utf-8` )
    ( response_set_header c `X-One` `value-number-one-that-is-longer-than-before` )
    ( response_set_header c `X-Two` `2` )
    ( response_set_header c `x-one` `replaced` )
    ( response_set_body_str c `missing` )
    ( wire c )
    ( response_recycle c )

    // A body past the 16 KiB keep limit goes back to the allocator.
    : HttpResponse big ( response_new 200 )
    : ~ i k 0
    ~ < k 20000 { ( vec_push [u] . big body # u 120 ) = k + k 1 }
    ( response_recycle big )
    : HttpResponse after_big ( response_new 200 )
    ( nurl_print `big body kept: ` )
    ( nurl_println ? >= ( vec_cap [u] . after_big body ) 20000 `yes` `no` )
    ( response_set_body_str after_big `small` )
    ( response_recycle after_big )
    : HttpResponse after_small ( response_new 200 )
    ( nurl_print `small body kept: ` )
    ( nurl_println ? >= ( vec_cap [u] . after_small body ) 5 `yes` `no` )
    ( response_recycle after_small )

    // A borrowed body parks as an empty owned one; its source is untouched.
    : ( Vec u ) src ( bytes_from_str `borrowed-bytes` )
    : HttpResponse view ( response_new 200 )
    ( response_set_body_borrowed_bytes view src )
    ( wire view )
    ( response_recycle view )
    : HttpResponse next ( response_new 200 )
    ( response_set_body_str next `own` )
    ( wire next )
    : String ss ( bytes_to_str src )
    ( nurl_print `source after: ` ) ( nurl_println ( string_data ss ) )
    ( response_recycle next )

    // The router's Params: each dispatch sees only its own captures.
    : Router rt ( router_new )
    ( router_get rt `/u/:id/:tab` \ HttpRequest req Params p → HttpResponse {
        : String out ( string_from `n=` )
        ( string_push_int out ( params_count p ) )
        ?? ( params_get p `id` ) { T v → { ( string_push_str out ` id=` ) ( string_append out v ) } F → {} }
        ?? ( params_get p `tab` ) { T v → { ( string_push_str out ` tab=` ) ( string_append out v ) } F → {} }
        ^ ( response_text 200 ( string_data out ) )
    } )
    ( router_get rt `/v/:only` \ HttpRequest req Params p → HttpResponse {
        : String out ( string_from `n=` )
        ( string_push_int out ( params_count p ) )
        ^ ( response_text 200 ( string_data out ) )
    } )
    : HttpRequest r1 ( request_new )
    ( string_push_str . r1 method `GET` ) ( string_push_str . r1 path `/u/7/home` ) ( string_push_str . r1 version `HTTP/1.1` )
    : HttpResponse o1 ( router_handle rt r1 )
    ( wire o1 )
    ( response_recycle o1 )
    : HttpRequest r2 ( request_new )
    ( string_push_str . r2 method `GET` ) ( string_push_str . r2 path `/v/x` ) ( string_push_str . r2 version `HTTP/1.1` )
    : HttpResponse o2 ( router_handle rt r2 )
    ( wire o2 )
}

// ── Part 2 ────────────────────────────────────────────────────────────

: ~ i served 0
: ~ i a_first 0
: ~ i a_last 0

@ hello HttpRequest req → HttpResponse {
    = served + served 1
    ? == served 100 { = a_first ( allocs ) } {}
    ? == served 300 { = a_last ( allocs ) } {}
    ^ ( response_text 200 `Hello, World!\n` )
}

// One prebuilt request, one reused read buffer; a response is complete
// once its 14-byte body has arrived after the head.
@ client_run i port i total → v {
    ( sleep_ms 150 )
    ?? ( tcp_connect `127.0.0.1` port ) {
        T c → {
            : ( Vec u ) req ( bytes_from_str `GET / HTTP/1.1\r\nHost: localhost\r\n\r\n` )
            : ( Vec u ) buf ( vec_with_cap [u] 4096 )
            : ~ i k 0
            : ~ b ok T
            ~ & ok < k total {
                ?? ( tcp_write_all c req ) { T _ → {} F _ → { = ok F } }
                ( vec_clear [u] buf )
                : ~ b more ok
                ~ more {
                    ?? ( tcp_read_into c buf 4096 ) {
                        T n → { ? <= n 0 { = more F = ok F } {} }
                        F _ → { = more F = ok F }
                    }
                    : i len ( vec_len [u] buf )
                    ? & more >= len 18 {
                        ?? ( vec_get [u] buf - len 1 ) { T b → { ? == 10 # i b { = more F } {} } F → {} }
                    } {}
                }
                = k + k 1
            }
            ( tcp_close_conn c )
        }
        F _ → { ( nurl_print `connect FAIL\n` ) }
    }
}

@ run_case s name i port b fiber → v {
    = served 0
    ?? ( tcp_listen `127.0.0.1` port ) {
        T l → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( hello req ) }
            : HttpServer srv ( server_new l h )
            : ( @ v ) client \ → v {
                ( client_run port 300 )
                ( server_stop srv )
            }
            : !Thread ThreadErr ct ( thread_spawn client )
            ? fiber {
                ?? ( server_run_async srv ) { T _ → {} F _ → {} }
            } {
                ?? ( server_run srv ) { T _ → {} F _ → {} }
            }
            ?? ct { T t → { ( thread_join t ) } F _ → {} }
            : i per / - a_last a_first 200
            ( nurl_print name )
            ( nurl_print ` served=` ) ( nurl_print ( nurl_str_int served ) )
            ( nurl_print ` allocations per request <= 2: ` )
            ? <= per 2 { ( nurl_println `T` ) } {
                ( nurl_print `F (` ) ( nurl_print ( nurl_str_int per ) ) ( nurl_println `)` )
            }
        }
        F _ → { ( nurl_print `listen FAIL\n` ) }
    }
}

@ main → i {
    ( part1 )
    ( run_case `thread` 18981 F )
    ( runtime_init 2 )
    ( run_case `fiber` 18982 T )
    ( runtime_shutdown )
    ^ 0
}
