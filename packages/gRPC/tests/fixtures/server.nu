// Independent gRPC runtimes drive this one-connection fixture. Exiting after
// peer shutdown lets the harness check complete connection cleanup with LSan.
$ `../../src/server.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/io.nu`

: TestCall { i id String method ( Vec u ) aggregate i count }

@ find_call ( Vec TestCall ) calls i id → i {
    : ~ i k 0
    ~ < k ( vec_len [TestCall] calls ) {
        : TestCall call ( vec_at [TestCall] calls k )
        ? == . call id id { ^ k } {}
        = k + k 1
    }
    ^ -1
}

@ handle inout GrpcServer server ( Vec TestCall ) calls GrpcServerEvent event i encoding → !v GrpcError {
    : i id . event stream_id
    : ( Vec Header ) empty ( grpc_metadata_new )
    ? == . event kind ( grpc_server_event_open ) {
        : s method ( string_data . event method )
        ? != ( nurl_str_eq method `/test.Echo/Error` ) 0 {
            : GrpcStatus status ( grpc_status GRPC_INVALID_ARGUMENT `bad % ä` )
            ?? ( proto_write_int32 . status details 1 # i32 3 ) { T _ → {} F _ → ( nurl_exit 8 ) }
            : !v GrpcError result ( grpc_server_finish server id status empty )
            ^ result
        } {}
        ? ! | | != ( nurl_str_eq method `/test.Echo/Unary` ) 0 != ( nurl_str_eq method `/test.Echo/ServerStream` ) 0
        | != ( nurl_str_eq method `/test.Echo/ClientStream` ) 0
        | != ( nurl_str_eq method `/test.Echo/Bidi` ) 0 != ( nurl_str_eq method `/test.Echo/Slow` ) 0 {
            : GrpcStatus status ( grpc_status GRPC_UNIMPLEMENTED `unknown method` )
            : !v GrpcError result ( grpc_server_finish server id status empty )
            ^ result
        } {}
        \ ( grpc_server_send_metadata server id . event metadata encoding )
        ( vec_push [TestCall] calls @ TestCall { id ( string_clone . event method ) ( vec_new [u] ) 0 } )
    } {}
    : i index ( find_call calls id )
    ? < index 0 { ^ @ !v GrpcError { T 0 } } {}
    // The call is checked out of the table while it is handled; it goes
    // back unless it is over.
    : ~ TestCall call ?? ( vec_remove [TestCall] calls index ) { T c → c F → { ^ @ !v GrpcError { T 0 } } }
    : String method ( string_clone . call method )
    : s m ( string_data method )
    ? == . event kind ( grpc_server_event_message ) {
        = . call count + . call count 1
        ? != ( nurl_str_eq m `/test.Echo/ClientStream` ) 0 {
            ( vec_extend [u] . call aggregate . event message )
        } {
            ? == ( nurl_str_eq m `/test.Echo/Slow` ) 0 {
                : i repeats ? != ( nurl_str_eq m `/test.Echo/ServerStream` ) 0 3 1
                : ~ i k 0
                ~ < k repeats {
                    : !v GrpcError sent ( grpc_server_send server id . event message )
                    ?? sent { T _ → {} F e → { ( vec_push [TestCall] calls call ) ^ @ !v GrpcError { F e } } }
                    = k + k 1
                }
            } {}
        }
    } {}
    ? == . event kind ( grpc_server_event_half_close ) {
        ? != ( nurl_str_eq m `/test.Echo/Slow` ) 0 { ( vec_push [TestCall] calls call ) ^ @ !v GrpcError { T 0 } } {}
        ? != ( nurl_str_eq m `/test.Echo/ClientStream` ) 0 { \ ( grpc_server_send server id . call aggregate ) } {}
        : GrpcStatus status ( grpc_status GRPC_OK `` )
        \ ( grpc_metadata_add empty `finished` `yes` )
        // The call is over: it is dropped with `call`.
        ^ ( grpc_server_finish server id status empty )
    } {}
    ? == . event kind ( grpc_server_event_cancelled ) { ^ @ !v GrpcError { T 0 } } {}
    ( vec_push [TestCall] calls call )
    ^ @ !v GrpcError { T 0 }
}

@ serve TcpConn tcp i encoding → i {
    : !GrpcServer GrpcError made ( grpc_server_new tcp ( grpc_server_limits ) )
    ?? made {
        F e → { ^ 1 }
        T value → {
            : ~ GrpcServer server value
            : ( Vec TestCall ) calls ( vec_new [TestCall] )
            : ~ b done F
            : ~ i result 0
            ~ ! done {
                ?? ( grpc_server_next server ) {
                    F e → { ( nurl_eprintln ( string_data . e message ) ) = result 1 = done T }
                    T event → {
                        ? == . event kind ( grpc_server_event_closed ) { = done T } {
                            ?? ( handle server calls event encoding ) {
                                F e → { ( nurl_eprintln ( string_data . e message ) ) = result 1 = done T }
                                T _ → {}
                            }
                        }
                    }
                }
            }
            ^ result
        }
    }
}

@ main → i {
    : s compression ( nurl_argv_get 1 )
    : i encoding ? != ( nurl_str_eq compression `gzip` ) 0 GRPC_GZIP GRPC_IDENTITY
    : s cert ( nurl_argv_get 2 )
    : s key ( nurl_argv_get 3 )
    : !TcpListener NetErr listening ? > ( nurl_str_len cert ) 0
    ( tcp_listen_tls_with_alpn `127.0.0.1` 0 16 cert key `h2` )
    ( tcp_listen `127.0.0.1` 0 )
    ?? listening {
        F _ → ^ 2
        T listener → {
            : String address ( tcp_local_addr listener )
            ( nurl_print ( string_data address ) ) ( nurl_print `\n` ) ( flush )
            : ~ i result 0
            ?? ( tcp_accept listener ) {
                T tcp → { = result ( serve tcp encoding ) }  // `serve` closes it with its connection
                F _ → { = result 3 }
            }
            ( tcp_close_listener listener )
            ^ result
        }
    }
}
