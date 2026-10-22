// net_listen_opts.nu — TcpListenOpts (agora #50): SO_REUSEPORT and the
// accept-queue length.
//   * two listeners on one address both bind when each asks for
//     reuse_port, and a client connects through them;
//   * without it the second bind fails (NetBind), as before;
//   * the default backlog is 4096 (the kernel clamps it to somaxconn);
//   * server_run_async with several accept fibers on one listener serves
//     every one of 40 sequential connections, then stops.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`

: ~ i answered 0

@ main → i {
    ( nurl_print `default backlog: ` ) ( nurl_println ( nurl_str_int ( tcp_listen_default_backlog ) ) )
    : TcpListenOpts rp @ TcpListenOpts { 64 T }
    ?? ( tcp_listen_with `127.0.0.1` 18961 rp ) {
        T a → {
            ?? ( tcp_listen_with `127.0.0.1` 18961 rp ) {
                T b → {
                    ( nurl_println `reuse_port: both bound` )
                    ?? ( tcp_connect `127.0.0.1` 18961 ) {
                        T c → { ( nurl_println `reuse_port: connect ok` ) ( tcp_close_conn c ) }
                        F _ → { ( nurl_println `reuse_port: connect FAIL` ) }
                    }
                    ( tcp_close_listener b )
                }
                F e → { ( nurl_print `reuse_port: second FAIL ` ) ( nurl_println ( net_err_name e ) ) }
            }
            ( tcp_close_listener a )
        }
        F e → { ( nurl_print `reuse_port: first FAIL ` ) ( nurl_println ( net_err_name e ) ) }
    }
    ?? ( tcp_listen `127.0.0.1` 18962 ) {
        T a → {
            ?? ( tcp_listen `127.0.0.1` 18962 ) {
                T b → { ( nurl_println `plain: second bound (unexpected)` ) ( tcp_close_listener b ) }
                F e → { ( nurl_print `plain: second refused ` ) ( nurl_println ( net_err_name e ) ) }
            }
            ( tcp_close_listener a )
        }
        F _ → { ( nurl_println `plain: FAIL` ) }
    }
    // Several accept fibers on one listener.
    ( runtime_init 3 )
    ?? ( tcp_listen `127.0.0.1` 18963 ) {
        T l → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( response_text 200 `ok\n` ) }
            : HttpServer srv ( server_new l h )
            ( server_set_acceptors srv 3 )
            : ( @ v ) client \ → v {
                ( sleep_ms 150 )
                : ~ i k 0
                ~ < k 40 {
                    ?? ( tcp_connect `127.0.0.1` 18963 ) {
                        T c → {
                            ?? ( tcp_write_all c ( bytes_from_str `GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n` ) ) { T _ → {} F _ → {} }
                            ?? ( tcp_read_chunk c 4096 ) {
                                T v → { : String s ( bytes_to_str v ) ? >= ( nurl_str_find ( string_data s ) `200 OK` ) 0 { = answered + answered 1 } {} }
                                F _ → {}
                            }
                            ( tcp_close_conn c )
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( server_stop srv )
            }
            : !Thread ThreadErr ct ( thread_spawn client )
            ?? ( server_run_async srv ) { T _ → {} F _ → {} }
            ?? ct { T t → { ( thread_join t ) } F _ → {} }
            ( nurl_print `3 acceptors answered: ` ) ( nurl_println ( nurl_str_int answered ) )
        }
        F _ → { ( nurl_println `async listen FAIL` ) }
    }
    ( runtime_shutdown )
    ^ 0
}
