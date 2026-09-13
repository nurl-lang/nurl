// Copied into a fresh consumer; every library import resolves from its registry deps.
$ `deps/grpc/src/grpc.nu`
$ `stdlib/ext/protobuf.nu`

@ registry_request → !( Vec u ) ProtoError {
    : ( Vec u ) data ( vec_new [u] )
    : String value ( string_from `registry grpc ä — roundtrip` )
    : !v ProtoError encoded ( proto_write_string data 1 value )
    ( string_free value )
    ?? encoded {
        T _ → ^ @ !( Vec u ) ProtoError { T data }
        F e → { ( vec_free [u] data ) ^ @ !( Vec u ) ProtoError { F e } }
    }
}

@ registry_check ( Vec u ) data → !b ProtoError {
    : ~ ProtoReader reader \ ( proto_reader data )
    : ProtoTag tag \ ( proto_read_tag reader )
    \ ( proto_expect tag 2 0 )
    : String value \ ( proto_read_string reader )
    : b same & == . tag number 1 & ! ( proto_more reader )
    != ( nurl_str_eq ( string_data value ) `official grpcio: registry grpc ä — roundtrip` ) 0
    ( string_free value )
    ^ @ !b ProtoError { T same }
}

@ main → i {
    : i port ( nurl_str_to_int ( nurl_argv_get 1 ) )
    : s encoding ( nurl_argv_get 2 )
    : GrpcClient client ?? ( grpc_client_connect_h2c `127.0.0.1` port ) {
        T value → value
        F e → { ( nurl_eprintln ( string_data . e message ) ) ( grpc_error_free e ) ^ 1 }
    }
    ; { ( grpc_client_close client ) }
    : ( Vec u ) request ?? ( registry_request ) {
        T bytes → bytes
        F e → { ( nurl_eprintln ( proto_error_name . e code ) ) ^ 2 }
    }
    ; { ( vec_free [u] request ) }
    : ( Vec Header ) metadata ( grpc_metadata_new )
    ; { ( grpc_metadata_free metadata ) }
    : ~ GrpcCallOptions options ( grpc_call_options )
    = . options timeout_ns 5000000000
    = . options encoding ? != ( nurl_str_eq encoding `gzip` ) 0 GRPC_GZIP GRPC_IDENTITY
    : GrpcUnaryResponse response ?? ( grpc_unary client `/registry.Echo/Unary` request metadata options ) {
        T value → value
        F e → { ( nurl_eprintln ( string_data . e message ) ) ( grpc_error_free e ) ^ 3 }
    }
    ; { ( grpc_unary_response_free response ) }
    ?? ( registry_check . response data ) {
        T same → {
            ? ! same { ( nurl_eprintln `protobuf response mismatch` ) ^ 4 } {}
        }
        F e → { ( nurl_eprintln ( proto_error_name . e code ) ) ^ 5 }
    }
    ( nurl_println `registry protobuf roundtrip passed` )
    ^ 0
}
