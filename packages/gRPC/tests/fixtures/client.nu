$ `../../src/client.nu`
$ `stdlib/core/io.nu`

@ check b condition s message → v {
    ? ! condition { ( nurl_eprintln message ) ( nurl_exit 10 ) } {}
}

@ call GrpcClient client s path s mode GrpcCallOptions opts ( Vec Header ) metadata ( Vec u ) request → !v GrpcError {
    ? != ( nurl_str_eq mode `unary` ) 0 {
        : GrpcUnaryResponse response \ ( grpc_unary client path request metadata opts )
        ( check ( bytes_eq request . response data ) `unary payload` )
        ( check == ( grpc_header_count . response headers `trace-bin` ) 1 `initial binary metadata` )
        ( check != ( nurl_str_eq ( grpc_header_value . response trailers `finished` ) `yes` ) 0 `trailing metadata` )
        ( grpc_unary_response_free response )
        ^ @ !v GrpcError { T 0 }
    } {}
    : ~ GrpcCall stream \ ( grpc_call_open client path metadata opts )
    ; { ( grpc_call_free stream ) }
    : ~ i count 0
    ? != ( nurl_str_eq mode `bidi` ) 0 {
        : ~ i k 0
        ~ < k 3 {
            \ ( grpc_call_send stream request )
            : GrpcMessage response \ ( grpc_call_receive stream )
            ( check & . response present ( bytes_eq request . response data ) `bidi before half-close` )
            ( grpc_message_free response )
            = k + k 1
            = count + count 1
        }
    } {
        \ ( grpc_call_send stream request )
        ? != ( nurl_str_eq mode `client-stream` ) 0 {
            \ ( grpc_call_send stream request )
            \ ( grpc_call_send stream request )
        } {}
    }
    \ ( grpc_call_half_close stream )
    : ~ b done F
    ~ ! done {
        ?? ( grpc_call_receive stream ) {
            F e → { ^ @ !v GrpcError { F e } }
            T response → {
                ? . response present {
                    ? != ( nurl_str_eq mode `client-stream` ) 0 {
                        : ( Vec u ) expected ( vec_new [u] )
                        ( vec_extend [u] expected request ) ( vec_extend [u] expected request ) ( vec_extend [u] expected request )
                        ( check ( bytes_eq expected . response data ) `client streaming aggregation` )
                        ( vec_free [u] expected )
                    } { ( check ( bytes_eq request . response data ) `streaming payload` ) }
                    = count + count 1
                } { = done T }
                ( grpc_message_free response )
            }
        }
    }
    : i expected_count ? | != ( nurl_str_eq mode `server-stream` ) 0 != ( nurl_str_eq mode `bidi` ) 0 3 1
    ( check == count expected_count `streaming message count` )
    ^ @ !v GrpcError { T 0 }
}

@ cancelled GrpcClient client GrpcCallOptions opts ( Vec Header ) metadata ( Vec u ) request → !v GrpcError {
    : ~ GrpcCall stream \ ( grpc_call_open client `/test.Echo/Slow` metadata opts )
    ; { ( grpc_call_free stream ) }
    \ ( grpc_call_send stream request )
    \ ( grpc_call_half_close stream )
    \ ( grpc_call_pump stream )
    \ ( grpc_call_cancel stream )
    ?? ( grpc_call_receive stream ) {
        T message → { ( grpc_message_free message ) ( check F `cancel must fail receive` ) }
        F error → { ( check == . error code GRPC_CANCELLED `local cancellation status` ) ( grpc_error_free error ) }
    }
    ^ @ !v GrpcError { T 0 }
}

@ finish_one inout GrpcCall stream ( Vec u ) request → !v GrpcError {
    : GrpcMessage first \ ( grpc_call_receive stream )
    ( check & . first present ( bytes_eq . first data request ) `multiplex reply` )
    ( grpc_message_free first )
    : GrpcMessage end \ ( grpc_call_receive stream )
    ( check ! . end present `multiplex end` )
    ( grpc_message_free end )
    ^ @ !v GrpcError { T 0 }
}

@ multiplex GrpcClient client GrpcCallOptions opts ( Vec Header ) metadata ( Vec u ) request → !v GrpcError {
    : ( Vec GrpcCall ) calls ( vec_new [GrpcCall] )
    ; { ( vec_free_with [GrpcCall] calls \ GrpcCall call → v { ( grpc_call_free call ) } ) }
    : ~ i k 0
    ~ < k 12 {
        : GrpcCall opened \ ( grpc_call_open client `/test.Echo/Unary` metadata opts )
        ( vec_push [GrpcCall] calls opened )
        : ~ * GrpcCall p ( vec_data [GrpcCall] calls )
        \ ( grpc_call_send . p k request )
        \ ( grpc_call_half_close . p k )
        = k + k 1
    }
    = k 0
    ~ < k 12 {
        : ~ * GrpcCall p ( vec_data [GrpcCall] calls )
        \ ( finish_one . p k request )
        = k + k 1
    }
    ^ @ !v GrpcError { T 0 }
}

@ scenario GrpcClient client s path s mode GrpcCallOptions opts ( Vec Header ) metadata ( Vec u ) request → !v GrpcError {
    ? != ( nurl_str_eq mode `cancel-reuse` ) 0 {
        \ ( cancelled client opts metadata request )
        ^ ( call client `/test.Echo/Unary` `unary` opts metadata request )
    } {}
    ? != ( nurl_str_eq mode `multiplex` ) 0 { ^ ( multiplex client opts metadata request ) } {}
    ^ ( call client path mode opts metadata request )
}

@ main → i {
    : s port_text ( nurl_argv_get 1 )
    : s path ( nurl_argv_get 2 )
    : s mode ( nurl_argv_get 3 )
    : s compression ( nurl_argv_get 4 )
    : s tls ( nurl_argv_get 5 )
    : s expected_text ( nurl_argv_get 6 )
    : s size_text ( nurl_argv_get 7 )
    : i expected ( nurl_str_to_int expected_text )
    : i size ( nurl_str_to_int size_text )
    : !GrpcClient GrpcError connected ? != ( nurl_str_eq tls `tls` ) 0
    ( grpc_client_connect_tls `localhost` ( nurl_str_to_int port_text ) T )
    ( grpc_client_connect_h2c `127.0.0.1` ( nurl_str_to_int port_text ) )
    ?? connected {
        F e → { ( nurl_eprintln ( string_data . e message ) ) ( grpc_error_free e ) ^ 1 }
        T client → {
            : ~ GrpcCallOptions opts ( grpc_call_options )
            = . opts encoding ? != ( nurl_str_eq compression `gzip` ) 0 GRPC_GZIP GRPC_IDENTITY
            = . opts timeout_ns ? == expected GRPC_DEADLINE_EXCEEDED 100000000 10000000000
            : ( Vec Header ) metadata ( grpc_metadata_new )
            : ( Vec u ) binary ( vec_new [u] )
            ( vec_push [u] binary # u 0 ) ( vec_push [u] binary # u 255 )
            ?? ( grpc_metadata_add_binary metadata `trace-bin` binary ) { T _ → {} F e → ( grpc_error_free e ) }
            ( vec_free [u] binary )
            : ( Vec u ) request ( vec_new [u] )
            : ~ i k 0
            ~ < k size { ( vec_push [u] request # u % k 256 ) = k + k 1 }
            : !v GrpcError result ( scenario client path mode opts metadata request )
            ( vec_free [u] request ) ( grpc_metadata_free metadata )
            ( grpc_client_close client )
            ?? result {
                T _ → { ( check == expected 0 `expected non-OK status` ) ( nurl_print `client passed\n` ) ^ 0 }
                F e → {
                    : i code . e code
                    ? != code expected { ( nurl_eprintln ( string_data . e message ) ) } {}
                    ( grpc_error_free e )
                    ( check == code expected `wrong gRPC status` )
                    ( nurl_print `client passed\n` )
                    ^ 0
                }
            }
        }
    }
}
