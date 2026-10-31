// net_sim_http_async.nu — the HttpApp facade's fiber server
// (http_app_async) over the simulated network (agora #240). Same seam as
// net_sim_http.nu, the other half of what "context-aware" means there: the
// server's accept and connection fibers PARK on the network
// (nurl_fiber_park_with_mutex_ms) while the clients, plain threads, BLOCK
// on its condition variable — and each side wakes the other by moving
// frames. Four clients on four nodes, each with its own keep-alive
// connection, at once.
// requires: fibers
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/net_sim.nu`
$ `packages/http/src/http.nu`

@ build_app → HttpApp {
    : HttpApp a ( http_app_new )
    ( http_app_quiet a )
    ( http_app_async a 2 )
    ( http_app_get a `/sq/:n` \ HttpRequest req Params p → HttpResponse {
        : ~ i v 0
        ?? ( params_get p `n` ) {
            T s → { ?? ( string_to_int s ) { T x → { = v x } F _ → {} } }
            F _ → {}
        }
        : String out ( string_new )
        ( string_push_int out * v v )
        ^ ( response_text 200 ( string_data out ) )
    } )
    ^ a
}

// The body of one response read off `c` (head skipped by its blank line,
// body to the end of what Content-Length says), or "" on an error.
@ read_answer TcpConn c → String {
    : ( Vec u ) acc ( vec_new [u] )
    ~ T {
        : String all ( string_new )
        : i n ( vec_len [u] acc )
        : ~ i k 0
        ~ < k n { ( string_push_char all # i ( vec_at [u] acc k ) ) = k + k 1 }
        ?? ( string_index_of all `\r\n\r\n` ) {
            T end → {
                : ~ i want 0
                ?? ( string_index_of all `Content-Length: ` ) {
                    T at → {
                        : ~ i p + at 16
                        ~ & < p end & >= ( string_get all p ) 48 <= ( string_get all p ) 57 {
                            = want + * want 10 - ( string_get all p ) 48
                            = p + p 1
                        }
                    }
                    F → {}
                }
                ? >= n + + end 4 want { ^ ( string_substr all + end 4 want ) } {}
            }
            F → {}
        }
        ?? ( tcp_read_into c acc 4096 ) { T _ → {} F _ → { ^ ( string_new ) } }
    }
    ^ ( string_new )
}

@ main → i {
    : NetSim net ( netsim_new 5 11 0 1 1 )
    : TcpListener l ?? ( netsim_listen net 0 80 ) {
        T x → x
        F _ → { ( nurl_print `listen: FAIL\n` ) ^ 1 }
    }
    : TcpListener stopper ( TcpListener_share l )
    : Atomic rc_out ( atomic_new -1 )
    // (A share goes in, not the capture: agora #247.)
    : !Thread ThreadErr srv ( thread_spawn \ → v { ( atomic_store rc_out ( http_app_serve ( build_app ) ( TcpListener_share l ) ) ) } )

    // Four clients, nodes 1..4, ten requests each on one connection.
    : Atomic right ( atomic_new 0 )
    : ( Vec Thread ) clients ( vec_new [Thread] )
    : ~ i node 1
    ~ <= node 4 {
        : i me node
        : NetSim nn ( NetSim_share net )
        : Atomic rr ( Atomic_share right )
        ?? ( thread_spawn \ → v {
            ?? ( netsim_connect nn me `10.0.0.1` 80 5000 ) {
                T c → {
                    : ~ i k 0
                    ~ < k 10 {
                        : i x + * me 100 k
                        : String req ( string_from `GET /sq/` )
                        ( string_push_int req x )
                        ( string_push_str req ` HTTP/1.1\r\nHost: sim\r\n\r\n` )
                        ?? ( tcp_write_str c ( string_data req ) ) { T _ → {} F _ → {} }
                        : String want ( string_new )
                        ( string_push_int want * x x )
                        : String got ( read_answer c )
                        ? ( string_eq got want ) { : i _a ( atomic_add rr 1 ) } {}
                        = k + k 1
                    }
                }
                F _ → {}
            }
        } ) {
            T t → { ( vec_push [Thread] clients t ) }
            F _ → {}
        }
        = node + node 1
    }
    : ~ i j 0
    ~ < j ( vec_len [Thread] clients ) {
        ?? ( vec_get [Thread] clients j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    ( nurl_print `40 requests from 4 nodes at once, right answers: ` )
    ( nurl_print_int ( atomic_load right ) )
    ( nurl_print `\n` )

    ( tcp_close_listener stopper )
    ?? srv { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_print ? == ( atomic_load rc_out ) 0 `the fiber server stops cleanly: ok\n` `the fiber server stops cleanly: FAIL\n` )
    ^ ? & == ( atomic_load right ) 40 == ( atomic_load rc_out ) 0 0 1
}
