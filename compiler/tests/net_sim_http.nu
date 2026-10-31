// net_sim_http.nu — the HttpApp facade serves over the simulated network
// (agora #240, DST 1/4). The app is built exactly as a program's main()
// builds it; the harness makes the listener on node 0 of a NetSim
// (stdlib/std/net_sim.nu) and hands it to http_app_serve, and a client on
// node 1 talks HTTP/1.1 to it over a keep-alive connection. Every byte
// crosses the sans-IO TCP/IP stack and the simulated bus; no operating
// system socket is opened (strace shows none).
//
// Then the link fails: a partition between the two nodes. The request
// written into it goes nowhere, and the client's read deadline reports
// NetTimeout — the error a real partition gives. The link heals, TCP's
// retransmit timer resends, and the same connection carries the answer:
// the request was neither lost nor answered twice.
//
// The server runs on its own thread (the facade's default single-threaded
// server); the harness stops it by closing its copy of the listener.
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/net_sim.nu`
$ `packages/http/src/http.nu`

: ~ i g_fail 0

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `ok` `FAIL` )
    ( nurl_print `\n` )
    ? ! ok { = g_fail + g_fail 1 } {}
}

// The app, as main() would build it.
@ build_app → HttpApp {
    : HttpApp a ( http_app_new )
    ( http_app_quiet a )
    ( http_app_get a `/hello/:name` \ HttpRequest req Params p → HttpResponse {
        : String out ( string_from `hello ` )
        ?? ( params_get p `name` ) {
            T nm → { ( string_push_str out ( string_data nm ) ) }
            F _ → {}
        }
        ^ ( response_text 200 ( string_data out ) )
    } )
    ^ a
}

// The index of "\r\n\r\n" in `b`, or -1.
@ head_end ( Vec u ) b → i {
    : i n ( vec_len [u] b )
    : ~ i k 0
    ~ <= + k 4 n {
        ? && && == ( vec_at [u] b k ) 13 == ( vec_at [u] b + k 1 ) 10 && == ( vec_at [u] b + k 2 ) 13 == ( vec_at [u] b + k 3 ) 10 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// The Content-Length a response head names (matched case-blind), or 0.
@ content_length ( Vec u ) b i end → i {
    : String head ( string_new )
    : ~ i k 0
    ~ < k end {
        : i ch # i ( vec_at [u] b k )
        ( string_push_char head ? && >= ch 65 <= ch 90 + ch 32 ch )
        = k + k 1
    }
    : s key `content-length:`
    ?? ( string_index_of head key ) {
        T at → {
            : i hn ( string_len head )
            : ~ i p + at ( nurl_str_len key )
            ~ & < p hn == ( string_get head p ) 32 { = p + p 1 }
            : ~ i v 0
            ~ & < p hn & >= ( string_get head p ) 48 <= ( string_get head p ) 57 {
                = v + * v 10 - ( string_get head p ) 48
                = p + p 1
            }
            ^ v
        }
        F → { ^ 0 }
    }
}

// Read one whole response off `c`: "<status> <body>", or the NetErr that
// ended the read ("NetTimeout", "NetClosed", …).
@ read_response TcpConn c → String {
    : ( Vec u ) acc ( vec_new [u] )
    ~ T {
        : i end ( head_end acc )
        ? >= end 0 {
            : i want + + end 4 ( content_length acc end )
            ? >= ( vec_len [u] acc ) want {
                : String out ( string_new )
                // "HTTP/1.1 200 OK" → the status code, then the body.
                : ~ i k 9
                ~ < k 12 { ( string_push_char out # i ( vec_at [u] acc k ) ) = k + k 1 }
                ( string_push_str out ` ` )
                = k + end 4
                ~ < k want { ( string_push_char out # i ( vec_at [u] acc k ) ) = k + k 1 }
                ^ out
            } {}
        } {}
        ?? ( tcp_read_into c acc 4096 ) {
            T _ → {}
            F e → { ^ ( string_from ( net_err_name e ) ) }
        }
    }
    ^ ( string_new )
}

@ request s name → String {
    : String r ( string_from `GET /hello/` )
    ( string_push_str r name )
    ( string_push_str r ` HTTP/1.1\r\nHost: sim\r\n\r\n` )
    ^ r
}

@ main → i {
    : NetSim net ( netsim_new 2 7 0 1 0 )
    : TcpListener l ?? ( netsim_listen net 0 80 ) {
        T x → x
        F _ → { ( check `listen on node 0: ` F ) ^ 1 }
    }
    // The harness keeps a copy: closing it stops the server.
    : TcpListener stopper ( TcpListener_share l )
    : Atomic rc_out ( atomic_new -1 )
    // The app is made on the thread that serves it (an HttpApp is a
    // single-thread handle); the listener moves there.
    // (A share of the listener goes in, not the capture itself: a thread
    // closure that consumes a capture currently frees every capture when
    // the thread ends — agora #247.)
    : !Thread ThreadErr srv ( thread_spawn \ → v { ( atomic_store rc_out ( http_app_serve ( build_app ) ( TcpListener_share l ) ) ) } )

    ?? ( netsim_connect net 1 `10.0.0.1` 80 2000 ) {
        F e → { ( check `the client connects over the bus: ` F ) }
        T c → {
            ( check `the client connects over the bus: ` T )
            // N requests on one keep-alive connection.
            : ~ i ok_count 0
            : ~ i k 0
            ~ < k 25 {
                : String name ( string_new )
                ( string_push_str name `n` )
                ( string_push_int name k )
                : String req ( request ( string_data name ) )
                ?? ( tcp_write_str c ( string_data req ) ) { T _ → {} F _ → {} }
                : String want ( string_from `200 hello ` )
                ( string_push_str want ( string_data name ) )
                : String got ( read_response c )
                ? == 0 ( nurl_str_cmp ( string_data got ) ( string_data want ) ) { = ok_count + ok_count 1 } {}
                = k + k 1
            }
            ( check `25 requests on one connection, 25 right answers: ` == ok_count 25 )

            // The link fails with a request on its way.
            ( netsim_partition net 0 1 )
            : String lost_req ( request `partitioned` )
            ( check `a write into the partition is accepted: ` ?? ( tcp_write_str c ( string_data lost_req ) ) { T _ → T F _ → F } )
            ( tcp_set_timeout c 300 )
            : String during ( read_response c )
            ( check `the read across the partition times out: ` == 0 ( nurl_str_cmp ( string_data during ) `NetTimeout` ) )
            ( check `and the bus dropped what was sent into it: ` > ( netsim_dropped net ) 0 )

            // It heals: TCP's retransmission carries the same request,
            // and the same connection answers it.
            ( netsim_heal net 0 1 )
            ( tcp_set_timeout c 10000 )
            : String after ( read_response c )
            ( check `after the heal the same request is answered: ` == 0 ( nurl_str_cmp ( string_data after ) `200 hello partitioned` ) )
            : String req2 ( request `again` )
            ?? ( tcp_write_str c ( string_data req2 ) ) { T _ → {} F _ → {} }
            : String next ( read_response c )
            ( check `and the connection keeps serving: ` == 0 ( nurl_str_cmp ( string_data next ) `200 hello again` ) )
        }
    }

    ( tcp_close_listener stopper )
    ?? srv { T t → { ( thread_join t ) } F _ → { ( check `server thread: ` F ) } }
    ( check `closing the listener stops http_app_serve cleanly: ` == ( atomic_load rc_out ) 0 )
    ( nurl_print ? == g_fail 0 `net_sim_http: all ok\n` `net_sim_http: FAILURES\n` )
    ^ ? == g_fail 0 0 1
}
