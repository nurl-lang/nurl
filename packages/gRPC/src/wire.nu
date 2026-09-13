// gRPC message framing and protocol values. Inputs are borrowed; returned
// buffers and GrpcError messages are owned. No protobuf schema is assumed.
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/compress.nu`

: i GRPC_OK 0
: i GRPC_CANCELLED 1
: i GRPC_UNKNOWN 2
: i GRPC_INVALID_ARGUMENT 3
: i GRPC_DEADLINE_EXCEEDED 4
: i GRPC_NOT_FOUND 5
: i GRPC_ALREADY_EXISTS 6
: i GRPC_PERMISSION_DENIED 7
: i GRPC_RESOURCE_EXHAUSTED 8
: i GRPC_FAILED_PRECONDITION 9
: i GRPC_ABORTED 10
: i GRPC_OUT_OF_RANGE 11
: i GRPC_UNIMPLEMENTED 12
: i GRPC_INTERNAL 13
: i GRPC_UNAVAILABLE 14
: i GRPC_DATA_LOSS 15
: i GRPC_UNAUTHENTICATED 16
: i GRPC_IDENTITY 0
: i GRPC_GZIP 1
: i GRPC_DEFAULT_MAX_MESSAGE 4194304
: i GRPC_DEFAULT_MAX_METADATA 8192

: GrpcError { i code String message }

@ grpc_error i code s message → GrpcError {
    ^ @ GrpcError { code ( string_from message ) }
}

@ grpc_error_free sink GrpcError e → v { ( string_free . e message ) }

@ grpc_code_name i code → s {
    ^ ?? code {
        0 → `OK`
        1 → `CANCELLED`
        2 → `UNKNOWN`
        3 → `INVALID_ARGUMENT`
        4 → `DEADLINE_EXCEEDED`
        5 → `NOT_FOUND`
        6 → `ALREADY_EXISTS`
        7 → `PERMISSION_DENIED`
        8 → `RESOURCE_EXHAUSTED`
        9 → `FAILED_PRECONDITION`
        10 → `ABORTED`
        11 → `OUT_OF_RANGE`
        12 → `UNIMPLEMENTED`
        13 → `INTERNAL`
        14 → `UNAVAILABLE`
        15 → `DATA_LOSS`
        16 → `UNAUTHENTICATED`
        _ → `UNKNOWN`
    }
}

@ grpc_http_status i status → i {
    ^ ?? status {
        400 → GRPC_INTERNAL
        401 → GRPC_UNAUTHENTICATED
        403 → GRPC_PERMISSION_DENIED
        404 → GRPC_UNIMPLEMENTED
        429 → GRPC_UNAVAILABLE
        502 → GRPC_UNAVAILABLE
        503 → GRPC_UNAVAILABLE
        504 → GRPC_UNAVAILABLE
        _ → GRPC_UNKNOWN
    }
}

@ grpc_reset_status i code → i {
    ^ ?? code {
        7 → GRPC_UNAVAILABLE
        8 → GRPC_CANCELLED
        11 → GRPC_RESOURCE_EXHAUSTED
        12 → GRPC_PERMISSION_DENIED
        _ → GRPC_INTERNAL
    }
}

@ grpc_encoding_name i encoding → s {
    ^ ? == encoding GRPC_GZIP `gzip` `identity`
}

@ grpc_encoding s name → !i GrpcError {
    ? | == ( nurl_str_len name ) 0 != ( nurl_str_eq name `identity` ) 0 {
        ^ @ !i GrpcError { T GRPC_IDENTITY }
    } {}
    ? != ( nurl_str_eq name `gzip` ) 0 { ^ @ !i GrpcError { T GRPC_GZIP } } {}
    ^ @ !i GrpcError { F ( grpc_error GRPC_UNIMPLEMENTED `unsupported grpc-encoding` ) }
}

@ grpc_content_type String value → b {
    ? ! ( string_starts_with value `application/grpc` ) { ^ F } {}
    : i n ( string_len value )
    ? == n 16 { ^ T } {}
    ? > n 17 { ^ == ( string_get value 16 ) 43 } {}
    ^ F
}

@ grpc_method_path s path → b {
    : i n ( nurl_str_len path )
    ? < n 4 { ^ F } {}
    : *u p # *u path
    ? != # i . p 0 47 { ^ F } {}
    : ~ i slash 0
    : ~ i k 1
    ~ < k n {
        : i c # i . p k
        ? == c 47 {
            ? | != slash 0 | == k 1 == k - n 1 { ^ F } {}
            = slash k
        } {
            ? ! | | & >= c 65 <= c 90 & >= c 97 <= c 122 | & >= c 48 <= c 57 | == c 95 == c 46 { ^ F } {}
        }
        = k + k 1
    }
    ^ > slash 0
}

// Timeout parsing is strict, uses every defined unit, and saturates instead
// of overflowing for the protocol's largest (99,999,999 hour) duration.
@ grpc_timeout_ns String value → !i GrpcError {
    : i n ( string_len value )
    ? | < n 2 > n 9 { ^ @ !i GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid grpc-timeout` ) } } {}
    : ~ i amount 0
    : ~ i k 0
    ~ < k - n 1 {
        : i c ( string_get value k )
        ? | < c 48 > c 57 { ^ @ !i GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid grpc-timeout` ) } } {}
        = amount + * amount 10 - c 48
        = k + k 1
    }
    : i factor ?? ( string_get value - n 1 ) {
        72 → 3600000000000
        77 → 60000000000
        83 → 1000000000
        109 → 1000000
        117 → 1000
        110 → 1
        _ → 0
    }
    ? == factor 0 { ^ @ !i GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid grpc-timeout unit` ) } } {}
    ? > amount / 9223372036854775807 factor { ^ @ !i GrpcError { T 9223372036854775807 } } {}
    ^ @ !i GrpcError { T * amount factor }
}

// Round up so the wire timeout never expires before the caller's duration.
@ grpc_timeout_value i duration_ns → String {
    : ~ i amount ? > duration_ns 0 duration_ns 0
    : ~ i unit 110
    ? > amount 99999999 { = amount + / amount 1000 ? > % amount 1000 0 1 0 = unit 117 } {}
    ? > amount 99999999 { = amount + / amount 1000 ? > % amount 1000 0 1 0 = unit 109 } {}
    ? > amount 99999999 { = amount + / amount 1000 ? > % amount 1000 0 1 0 = unit 83 } {}
    ? > amount 99999999 { = amount + / amount 60 ? > % amount 60 0 1 0 = unit 77 } {}
    ? > amount 99999999 { = amount + / amount 60 ? > % amount 60 0 1 0 = unit 72 } {}
    : String out ( string_new )
    ( string_push_int out amount )
    ( string_push_char out unit )
    ^ out
}

@ grpc_deadline_after i now_ns i duration_ns → i {
    ? <= duration_ns 0 { ^ now_ns } {}
    ? > duration_ns - 9223372036854775807 now_ns { ^ 9223372036854775807 } {}
    ^ + now_ns duration_ns
}

@ __grpc_compression_error CompressErr e → GrpcError {
    ^ ?? e {
        CompressBufTooSmall → ( grpc_error GRPC_RESOURCE_EXHAUSTED `decompressed message exceeds limit` )
        _ → ( grpc_error GRPC_INTERNAL `invalid compressed message` )
    }
}

// Both compressed and uncompressed sizes are bounded. Each message gets its
// own compression context, including the empty protobuf message.
@ grpc_frame ( Vec u ) message i encoding i max_message → !( Vec u ) GrpcError {
    ? | <= max_message 0 > max_message 2147483647 {
        ^ @ !( Vec u ) GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid message limit` ) }
    } {}
    ? > ( vec_len [u] message ) max_message {
        ^ @ !( Vec u ) GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `message exceeds limit` ) }
    } {}
    ? == encoding GRPC_GZIP {
        ?? ( gzip_compress message ) {
            F e → ^ @ !( Vec u ) GrpcError { F ( __grpc_compression_error e ) }
            T compressed → {
                ? > ( vec_len [u] compressed ) max_message {
                    ( vec_free [u] compressed )
                    ^ @ !( Vec u ) GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `compressed message exceeds limit` ) }
                } {}
                : ( Vec u ) out ( vec_new [u] )
                ( vec_push [u] out # u 1 )
                ( bytes_push_u32_be out # u32 ( vec_len [u] compressed ) )
                ( vec_extend [u] out compressed )
                ( vec_free [u] compressed )
                ^ @ !( Vec u ) GrpcError { T out }
            }
        }
    } {}
    ? != encoding GRPC_IDENTITY { ^ @ !( Vec u ) GrpcError { F ( grpc_error GRPC_UNIMPLEMENTED `unsupported grpc-encoding` ) } } {}
    : ( Vec u ) out ( vec_new [u] )
    ( vec_push [u] out # u 0 )
    ( bytes_push_u32_be out # u32 ( vec_len [u] message ) )
    ( vec_extend [u] out message )
    ^ @ !( Vec u ) GrpcError { T out }
}

: GrpcMessage { b present ( Vec u ) data }
: GrpcDecoder { ( Vec u ) pending i pos i max_message i max_buffer i encoding }

@ grpc_message_free sink GrpcMessage message → v { ( vec_free [u] . message data ) }

@ grpc_decoder i max_message i max_buffer i encoding → !GrpcDecoder GrpcError {
    ? | | <= max_message 0 > max_message 2147483647 < max_buffer + max_message 5 {
        ^ @ !GrpcDecoder GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid decoder limits` ) }
    } {}
    ? & != encoding GRPC_IDENTITY != encoding GRPC_GZIP {
        ^ @ !GrpcDecoder GrpcError { F ( grpc_error GRPC_UNIMPLEMENTED `unsupported grpc-encoding` ) }
    } {}
    ^ @ !GrpcDecoder GrpcError { T @ GrpcDecoder { ( vec_new [u] ) 0 max_message max_buffer encoding } }
}

@ grpc_decoder_free sink GrpcDecoder d → v { ( vec_free [u] . d pending ) }

// Atomic on error. Call next repeatedly after each feed until present=false.
@ grpc_decoder_feed inout GrpcDecoder d ( Vec u ) bytes → !v GrpcError {
    : i remaining - ( vec_len [u] . d pending ) . d pos
    ? > ( vec_len [u] bytes ) - . d max_buffer remaining {
        ^ @ !v GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `receive queue exceeds limit` ) }
    } {}
    ? > . d pos 0 {
        : ( Vec u ) compact ( vec_new [u] )
        ( vec_extend_range [u] compact . d pending . d pos remaining )
        ( vec_free [u] . d pending )
        = . d pending compact
        = . d pos 0
    } {}
    ( vec_extend [u] . d pending bytes )
    ^ @ !v GrpcError { T 0 }
}

// Consumed messages must also release their backing allocation. Otherwise
// many idle streams retain a previous maximum-sized message indefinitely
// while the connection's active-byte accounting reports an empty queue.
@ __grpc_decoder_consume inout GrpcDecoder d i count → v {
    = . d pos + . d pos count
    ? == . d pos ( vec_len [u] . d pending ) {
        ( vec_free [u] . d pending )
        = . d pending ( vec_new [u] )
        = . d pos 0
    } {}
}

@ grpc_decoder_next inout GrpcDecoder d → !GrpcMessage GrpcError {
    : i available - ( vec_len [u] . d pending ) . d pos
    ? == available 0 { ^ @ !GrpcMessage GrpcError { T @ GrpcMessage { F ( vec_new [u] ) } } } {}
    : *u p ( vec_data [u] . d pending )
    : i flag # i . p . d pos
    ? > flag 1 { ^ @ !GrpcMessage GrpcError { F ( grpc_error GRPC_INTERNAL `invalid compressed flag` ) } } {}
    ? & == flag 1 == . d encoding GRPC_IDENTITY {
        ^ @ !GrpcMessage GrpcError { F ( grpc_error GRPC_INTERNAL `compressed message without grpc-encoding` ) }
    } {}
    ? < available 5 { ^ @ !GrpcMessage GrpcError { T @ GrpcMessage { F ( vec_new [u] ) } } } {}
    : ~ i length 0
    : ~ i k 1
    ~ < k 5 { = length + * length 256 # i . p + . d pos k = k + k 1 }
    ? > length . d max_message { ^ @ !GrpcMessage GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `message exceeds limit` ) } } {}
    ? < - available 5 length { ^ @ !GrpcMessage GrpcError { T @ GrpcMessage { F ( vec_new [u] ) } } } {}
    : ( Vec u ) body ( vec_new [u] )
    ( vec_extend_range [u] body . d pending + . d pos 5 length )
    ? == flag 1 {
        : !( Vec u ) CompressErr decoded ( gzip_decompress_max body . d max_message )
        ( vec_free [u] body )
        ?? decoded {
            F e → ^ @ !GrpcMessage GrpcError { F ( __grpc_compression_error e ) }
            T bytes → {
                ( __grpc_decoder_consume d + 5 length )
                ^ @ !GrpcMessage GrpcError { T @ GrpcMessage { T bytes } }
            }
        }
    } {}
    ( __grpc_decoder_consume d + 5 length )
    ^ @ !GrpcMessage GrpcError { T @ GrpcMessage { T body } }
}

// Called after draining messages when the HTTP/2 receive side ends.
@ grpc_decoder_finish GrpcDecoder d → !v GrpcError {
    ? != . d pos ( vec_len [u] . d pending ) {
        ^ @ !v GrpcError { F ( grpc_error GRPC_INTERNAL `truncated gRPC message` ) }
    } {}
    ^ @ !v GrpcError { T 0 }
}
