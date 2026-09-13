// Independent gRPC runtimes drive this one-connection fixture. Exiting after
// peer shutdown lets the harness check complete connection cleanup with LSan.
$ `../../src/server.nu`
$ `stdlib/core/io.nu`

: TestCall { i id String method ( Vec u ) aggregate i count }

@ test_call_free sink TestCall call → v {
    ( string_free . call method )
    ( vec_free [u] . call aggregate )
}

@ find_call ( Vec TestCall ) calls i id → i {
    : ~ i k 0
    ~ < k ( vec_len [TestCall] calls ) {
        : TestCall call . ( vec_data [TestCall] calls ) k
        ? == . call id id { ^ k } {}
        = k + k 1
    }
    ^ -1
}

@ handle inout GrpcServer server ( Vec TestCall ) calls GrpcServerEvent event i encoding → !v GrpcError {
    : i id . event stream_id
    : ( Vec Header ) empty ( grpc_metadata_new )
    ; { ( grpc_metadata_free empty ) }
    ? == . event kind ( grpc_server_event_open ) {
        : s method ( string_data . event method )
        ? != ( nurl_str_eq method `/test.Echo/Error` ) 0 {
            : GrpcStatus status ( grpc_status GRPC_INVALID_ARGUMENT `bad % ä` )
            ?? ( proto_write_int32 . status details 1 # i32 3 ) { T _ → {} F _ → ( nurl_exit 8 ) }
            : !v GrpcError result ( grpc_server_finish server id status empty )
            ( grpc_status_free status )
            ^ result
        } {}
        ? ! | | != ( nurl_str_eq method `/test.Echo/Unary` ) 0 != ( nurl_str_eq method `/test.Echo/ServerStream` ) 0
        | != ( nurl_str_eq method `/test.Echo/ClientStream` ) 0
        | != ( nurl_str_eq method `/test.Echo/Bidi` ) 0 != ( nurl_str_eq method `/test.Echo/Slow` ) 0 {
            : GrpcStatus status ( grpc_status GRPC_UNIMPLEMENTED `unknown method` )
            : !v GrpcError result ( grpc_server_finish server id status empty )
            ( grpc_status_free status )
            ^ result
        } {}
        \ ( grpc_server_send_metadata server id . event metadata encoding )
        ( vec_push [TestCall] calls @ TestCall { id ( string_clone . event method ) ( vec_new [u] ) 0 } )
    } {}
    : i index ( find_call calls id )
    ? < index 0 { ^ @ !v GrpcError { T 0 } } {}
    : ~ TestCall call . ( vec_data [TestCall] calls ) index
    : s method ( string_data . call method )
    ? == . event kind ( grpc_server_event_message ) {
        = . call count + . call count 1
        ? != ( nurl_str_eq method `/test.Echo/ClientStream` ) 0 {
            ( vec_extend [u] . call aggregate . event message )
        } {
            ? == ( nurl_str_eq method `/test.Echo/Slow` ) 0 {
                : i repeats ? != ( nurl_str_eq method `/test.Echo/ServerStream` ) 0 3 1
                : ~ i k 0
                ~ < k repeats { \ ( grpc_server_send server id . event message ) = k + k 1 }
            } {}
        }
        ( vec_set [TestCall] calls index call )
    } {}
    ? == . event kind ( grpc_server_event_half_close ) {
        ? != ( nurl_str_eq method `/test.Echo/Slow` ) 0 { ^ @ !v GrpcError { T 0 } } {}
        ? != ( nurl_str_eq method `/test.Echo/ClientStream` ) 0 { \ ( grpc_server_send server id . call aggregate ) } {}
        : GrpcStatus status ( grpc_status GRPC_OK `` )
        \ ( grpc_metadata_add empty `finished` `yes` )
        : !v GrpcError result ( grpc_server_finish server id status empty )
        ( grpc_status_free status )
        ( test_call_free call )
        ( vec_remove [TestCall] calls index )
        ^ result
    } {}
    ? == . event kind ( grpc_server_event_cancelled ) {
        ( test_call_free call )
        ( vec_remove [TestCall] calls index )
    } {}
    ^ @ !v GrpcError { T 0 }
}

@ serve TcpConn tcp i encoding → i {
    : !GrpcServer GrpcError made ( grpc_server_new tcp ( grpc_server_limits ) )
    ?? made {
        F e → { ( grpc_error_free e ) ^ 1 }
        T value → {
            : ~ GrpcServer server value
            : ( Vec TestCall ) calls ( vec_new [TestCall] )
            : ~ b done F
            : ~ i result 0
            ~ ! done {
                ?? ( grpc_server_next server ) {
                    F e → { ( nurl_eprintln ( string_data . e message ) ) ( grpc_error_free e ) = result 1 = done T }
                    T event → {
                        ? == . event kind ( grpc_server_event_closed ) { = done T } {
                            ?? ( handle server calls event encoding ) {
                                F e → { ( nurl_eprintln ( string_data . e message ) ) ( grpc_error_free e ) = result 1 = done T }
                                T _ → {}
                            }
                        }
                        ( grpc_server_event_free event )
                    }
                }
            }
            ( vec_free_with [TestCall] calls \ TestCall call → v { ( test_call_free call ) } )
            ( grpc_server_free server )
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
            ( string_free address )
            : ~ i result 0
            ?? ( tcp_accept listener ) {
                T tcp → { = result ( serve tcp encoding ) ( tcp_close_conn tcp ) }
                F _ → { = result 3 }
            }
            ( tcp_close_listener listener )
            ^ result
        }
    }
}
