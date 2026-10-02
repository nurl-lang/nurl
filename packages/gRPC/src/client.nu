// HTTP/2-backed gRPC calls. A client and all its calls have one owner/driver.
// A GrpcClient is a handle: every copy is the same client, and each call
// holds one, so the transport outlives every call on it. The last owner
// disconnects a transport the client opened (grpc_client_connect_*); one it
// was lent (grpc_client_from_h2) stays its owner's. A GrpcCall is released
// by its owner's drop, which cancels an unfinished call. Nothing here is
// released by hand: grpc_client_close / grpc_call_free / the *_free
// functions are optional early releases.
// Sending borrows protobuf bytes. Receiving transfers an owned GrpcMessage.
$ `stdlib/ext/http2_client.nu`
$ `stdlib/core/rcbox.nu`
$ `metadata.nu`

: GrpcClientImpl { H2Client transport String scheme String authority b owns_transport }

// A transport the client opened is disconnected with it; a lent one stays
// connected for whoever lent it. The fields (the transport handle, the
// strings) go with the value.
% Drop GrpcClientImpl {
    @ drop GrpcClientImpl c → v { ? . c owns_transport { ( h2_client_disconnect . c transport ) } {} }
}

: GrpcClient { s ctl }

@ GrpcClient_share GrpcClient h → GrpcClient { ^ @ GrpcClient { # s ( rcbox_share # i . h ctl ) } }

@ GrpcClient_drop sink GrpcClient h → v {
    ( mem_forget h )
    ( rcbox_release [GrpcClientImpl] # i . h ctl )
}

@ __GrpcClient_ptr GrpcClient h → *GrpcClientImpl { ^ ( rcbox_ptr [GrpcClientImpl] # i . h ctl ) }

: GrpcCallOptions { i timeout_ns i max_send_message i max_recv_message i max_metadata i encoding }
: GrpcCall {
    GrpcClient client  // a share: the transport stays up while the call lives
    i stream_id
    GrpcDecoder decoder
    i max_send_message
    i max_metadata
    i encoding
    b response_checked
    b status_checked
    GrpcStatus status
    ( Vec Header ) headers
    ( Vec Header ) trailers
}
: GrpcUnaryResponse { ( Vec u ) data ( Vec Header ) headers ( Vec Header ) trailers GrpcStatus status }

@ grpc_call_options → GrpcCallOptions {
    ^ @ GrpcCallOptions { 0 GRPC_DEFAULT_MAX_MESSAGE GRPC_DEFAULT_MAX_MESSAGE GRPC_DEFAULT_MAX_METADATA GRPC_IDENTITY }
}

// A client over a transport the caller keeps owning (and closes itself).
@ grpc_client_from_h2 H2Client transport s scheme s authority → GrpcClient {
    : i c__box ( rcbox_zero [GrpcClientImpl] )
    : *GrpcClientImpl c ( rcbox_ptr [GrpcClientImpl] c__box )
    = . c transport ( H2Client_share transport )  // the caller keeps its own copy
    = . c scheme ( string_from scheme )
    = . c authority ( string_from authority )
    = . c owns_transport F
    ^ @ GrpcClient { # s c__box }
}

@ __grpc_client_transport_error H2ClientErr error → GrpcError {
    : i code ?? error {
        H2CDeadline → GRPC_DEADLINE_EXCEEDED
        H2CBufferLimit → GRPC_RESOURCE_EXHAUSTED
        H2CWouldBlock → GRPC_RESOURCE_EXHAUSTED
        H2CIncomplete → GRPC_FAILED_PRECONDITION
        H2CProtocol → GRPC_INTERNAL
        H2CCompression → GRPC_INTERNAL
        H2CFlowControl → GRPC_INTERNAL
        H2CFrameSize → GRPC_INTERNAL
        H2CRstStream → GRPC_CANCELLED
        _ → GRPC_UNAVAILABLE
    }
    ^ ( grpc_error code ( h2_client_err_name error ) )
}

@ __grpc_client_connected sink H2Client transport s scheme s host i port → GrpcClient {
    : String authority ( string_new )
    : String host_text ( string_from host )
    ? & ( string_contains host_text `:` ) ! ( string_starts_with host_text `[` ) {
        ( string_push_char authority 91 ) ( string_push_str authority host ) ( string_push_char authority 93 )
    } { ( string_push_str authority host ) }
    ( string_push_char authority 58 ) ( string_push_int authority port )
    : i c__box ( rcbox_zero [GrpcClientImpl] )
    : *GrpcClientImpl c ( rcbox_ptr [GrpcClientImpl] c__box )
    = . c transport transport
    = . c scheme ( string_from scheme )
    = . c authority authority
    = . c owns_transport T
    ^ @ GrpcClient { # s c__box }
}

@ grpc_client_connect_h2c s host i port → !GrpcClient GrpcError {
    ^ ?? ( h2_client_connect_h2c host port ) {
        T transport → @ !GrpcClient GrpcError { T ( __grpc_client_connected transport `http` host port ) }
        F e → @ !GrpcClient GrpcError { F ( __grpc_client_transport_error e ) }
    }
}

@ grpc_client_connect_tls s host i port b verify → !GrpcClient GrpcError {
    ^ ?? ( h2_client_connect_tls host port verify ) {
        T transport → @ !GrpcClient GrpcError { T ( __grpc_client_connected transport `https` host port ) }
        F e → @ !GrpcClient GrpcError { F ( __grpc_client_transport_error e ) }
    }
}

// Let go of `client` now rather than at the end of its owner's scope (the
// transport closes when the last call on it is gone too).
@ grpc_client_close sink GrpcClient client → v {}

@ grpc_call_open GrpcClient client__h s path ( Vec Header ) metadata GrpcCallOptions opts → !GrpcCall GrpcError {
    : *GrpcClientImpl client ( __GrpcClient_ptr client__h )
    ? ! ( grpc_method_path path ) { ^ @ !GrpcCall GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid RPC method path` ) } } {}
    ? | | < . opts timeout_ns 0 <= . opts max_send_message 0 > . opts max_send_message 2147483647 {
        ^ @ !GrpcCall GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid call options` ) }
    } {}
    : GrpcDecoder decoder ?? ( grpc_decoder . opts max_recv_message + . opts max_recv_message 65540 GRPC_IDENTITY ) {
        T d → d F e → { ^ @ !GrpcCall GrpcError { F e } }
    }
    ? & != . opts encoding GRPC_IDENTITY != . opts encoding GRPC_GZIP {
        ^ @ !GrpcCall GrpcError { F ( grpc_error GRPC_UNIMPLEMENTED `unsupported request compression` ) }
    } {}
    : ( Vec Header ) headers ?? ( grpc_metadata_encode metadata . opts max_metadata ) {
        T hs → hs F e → { ^ @ !GrpcCall GrpcError { F e } }
    }
    ( vec_push [Header] headers ( header_new `content-type` `application/grpc` ) )
    ( vec_push [Header] headers ( header_new `te` `trailers` ) )
    ( vec_push [Header] headers ( header_new `grpc-accept-encoding` `identity,gzip` ) )
    ( vec_push [Header] headers ( header_new `grpc-encoding` ( grpc_encoding_name . opts encoding ) ) )
    : ~ i deadline 0
    ? > . opts timeout_ns 0 {
        = deadline ( grpc_deadline_after ( monotonic_ns ) . opts timeout_ns )
        : String timeout ( grpc_timeout_value . opts timeout_ns )
        ( vec_push [Header] headers ( header_new `grpc-timeout` ( string_data timeout ) ) )
    } {}
    ?? ( grpc_request_headers_check_size headers ( string_data . client scheme )
    ( string_data . client authority ) path . opts max_metadata ) {
        T _ → {}
        F e → {
            ^ @ !GrpcCall GrpcError { F e }
        }
    }
    : !i H2ClientErr opened ( h2_client_open_deadline . client transport `POST`
    ( string_data . client scheme ) ( string_data . client authority ) path headers deadline )
    : i sid ?? opened { T id → id F e → {
            ^ @ !GrpcCall GrpcError { F ( __grpc_client_transport_error e ) }
        } }
    ^ @ !GrpcCall GrpcError { T @ GrpcCall { ( GrpcClient_share client__h ) sid decoder
            . opts max_send_message . opts max_metadata . opts encoding F F
            ( grpc_status GRPC_UNKNOWN `status not received` )
            ( grpc_metadata_new ) ( grpc_metadata_new ) } }
}

@ grpc_call_cancel inout GrpcCall call → !v GrpcError {
    : *GrpcClientImpl cl ( __GrpcClient_ptr . call client )
    ^ ?? ( h2_client_cancel . cl transport . call stream_id ( h2_err_cancel ) ) {
        T _ → @ !v GrpcError { T 0 }
        F e → @ !v GrpcError { F ( __grpc_client_transport_error e ) }
    }
}

// Let go of `call` now rather than at the end of its owner's scope.
@ grpc_call_free sink GrpcCall call → v {}

// Always cancels unfinished calls so application early-return releases the
// peer's stream resources; the decoder, the metadata and the call's share
// of its client go with the drop glue.
% Drop GrpcCall {
    @ drop GrpcCall call → v {
        : *GrpcClientImpl cl ( __GrpcClient_ptr . call client )
        ?? ( h2_client_cancel . cl transport . call stream_id ( h2_err_cancel ) ) { T _ → {} F _ → {} }
        ?? ( h2_client_release_stream . cl transport . call stream_id ) { T _ → {} F _ → {} }
    }
}

// Queue one framed message. RESOURCE_EXHAUSTED/H2CWouldBlock leaves the
// borrowed input untouched: receive/pump existing messages before retrying.
@ grpc_call_send inout GrpcCall call ( Vec u ) message → !v GrpcError {
    : ( Vec u ) framed \ ( grpc_frame message . call encoding . call max_send_message )
    : *GrpcClientImpl cl ( __GrpcClient_ptr . call client )
    ^ ?? ( h2_client_send . cl transport . call stream_id framed F ) {
        T _ → @ !v GrpcError { T 0 }
        F e → @ !v GrpcError { F ( __grpc_client_transport_error e ) }
    }
}

@ grpc_call_half_close inout GrpcCall call → !v GrpcError {
    : *GrpcClientImpl cl ( __GrpcClient_ptr . call client )
    ^ ?? ( h2_client_send . cl transport . call stream_id ( vec_new [u] ) T ) {
        T _ → @ !v GrpcError { T 0 }
        F e → @ !v GrpcError { F ( __grpc_client_transport_error e ) }
    }
}

@ __grpc_call_fail inout GrpcCall call sink GrpcError error → !v GrpcError {
    ?? ( grpc_call_cancel call ) { T _ → {} F e → {} }
    ^ @ !v GrpcError { F error }
}

@ __grpc_call_response_protocol inout GrpcCall call ( Vec Header ) headers → !v GrpcError {
    : String content_type ( string_from ( grpc_header_value headers `content-type` ) )
    : b content_ok & == ( grpc_header_count headers `content-type` ) 1 ( grpc_content_type content_type )
    ? ! content_ok { ^ ( __grpc_call_fail call ( grpc_error GRPC_UNKNOWN `invalid gRPC content-type` ) ) } {}
    ? > ( grpc_header_count headers `grpc-encoding` ) 1 {
        ^ ( __grpc_call_fail call ( grpc_error GRPC_INTERNAL `duplicate grpc-encoding` ) )
    } {}
    : i encoding ?? ( grpc_encoding ( grpc_header_value headers `grpc-encoding` ) ) {
        T e → e F e → { ^ ( __grpc_call_fail call e ) }
    }
    = . . call decoder encoding encoding
    ^ @ !v GrpcError { T 0 }
}

// Move currently received bytes into the bounded message decoder and validate
// headers once. No socket read occurs here; this also supports shared drivers.
@ __grpc_call_update inout GrpcCall call → !v GrpcError {
    : *GrpcClientImpl cl ( __GrpcClient_ptr . call client )
    : H2CStream stream ?? ( h2_client_stream_state . cl transport . call stream_id ) {
        T s → s F _ → { ^ @ !v GrpcError { F ( grpc_error GRPC_FAILED_PRECONDITION `call already released` ) } }
    }
    ? . stream deadline_expired { ^ @ !v GrpcError { F ( grpc_error GRPC_DEADLINE_EXCEEDED `RPC deadline exceeded` ) } } {}
    ? >= . stream rst_code 0 { ^ @ !v GrpcError { F ( grpc_error ( grpc_reset_status . stream rst_code ) `HTTP/2 stream reset` ) } } {}
    ? & . stream headers_done ! . call response_checked {
        ?? ( grpc_headers_check_size . stream headers . call max_metadata ) {
            T _ → {} F e → { ^ ( __grpc_call_fail call e ) }
        }
        // HTTP error mappings are only a fallback when grpc-status is absent.
        // Preserve a non-200 response until its final status arrives; an
        // intermediary's HTML/text body must not override explicit RPC status.
        ? == . stream status 200 {
            \ ( __grpc_call_response_protocol call . stream headers )
        } {}
        : ( Vec Header ) metadata ?? ( grpc_metadata_decode . stream headers . call max_metadata ) {
            T m → m F e → { ^ ( __grpc_call_fail call e ) }
        }
        ( grpc_metadata_free . call headers )
        = . call headers metadata
        = . call response_checked T
        ? & ! . stream complete > ( grpc_header_count . stream headers `grpc-status` ) 0 {
            ^ ( __grpc_call_fail call ( grpc_error GRPC_INTERNAL `grpc-status in non-final initial headers` ) )
        } {}
    } {}
    : ( Vec u ) bytes ?? ( h2_client_take_data . cl transport . call stream_id ) {
        T b → b F e → { ^ @ !v GrpcError { F ( __grpc_client_transport_error e ) } }
    }
    : !v GrpcError fed ( grpc_decoder_feed . call decoder bytes )
    ?? fed { T _ → {} F e → { ^ ( __grpc_call_fail call e ) } }
    ^ @ !v GrpcError { T 0 }
}

@ grpc_call_pump inout GrpcCall call → !v GrpcError {
    : *GrpcClientImpl cl ( __GrpcClient_ptr . call client )
    ?? ( h2_client_pump_once . cl transport ) {
        T _ → {} F e → { ^ @ !v GrpcError { F ( __grpc_client_transport_error e ) } }
    }
    ^ ( __grpc_call_update call )
}

@ __grpc_call_status inout GrpcCall call H2CStream stream → !v GrpcError {
    ? . call status_checked { ^ @ !v GrpcError { T 0 } } {}
    : ( Vec Header ) final ? . stream trailers_done . stream trailers . stream headers
    ? & != . stream status 200 == ( grpc_header_count final `grpc-status` ) 0 {
        ^ @ !v GrpcError { F ( grpc_error ( grpc_http_status . stream status ) `unexpected HTTP status without grpc-status` ) }
    } {}
    // grpc-status in initial headers is valid only for a trailers-only
    // response: no DATA, no later trailing block.
    ? & ! . stream trailers_done != . stream received_bytes 0 {
        ^ @ !v GrpcError { F ( grpc_error GRPC_UNKNOWN `missing gRPC trailers` ) }
    } {}
    ? & . stream trailers_done != ( grpc_header_count . stream headers `grpc-status` ) 0 {
        ^ @ !v GrpcError { F ( grpc_error GRPC_INTERNAL `duplicate initial and trailing grpc-status` ) }
    } {}
    : GrpcStatus status \ ( grpc_status_parse final )
    : ( Vec Header ) metadata ?? ( grpc_metadata_decode final . call max_metadata ) {
        T m → m F e → { ^ @ !v GrpcError { F e } }
    }
    ( grpc_status_free . call status ) ( grpc_metadata_free . call trailers )
    = . call status status = . call trailers metadata = . call status_checked T
    ^ @ !v GrpcError { T 0 }
}

@ __grpc_call_finish inout GrpcCall call H2CStream stream → !v GrpcError {
    \ ( __grpc_call_status call stream )
    ? == . . call status code GRPC_OK { \ ( grpc_decoder_finish . call decoder ) } {}
    ^ @ !v GrpcError { T 0 }
}

// Receive one message, or present=false after successful final status. The
// same primitive supports unary and all three streaming RPC cardinalities.
@ grpc_call_receive inout GrpcCall call → !GrpcMessage GrpcError {
    : *GrpcClientImpl cl ( __GrpcClient_ptr . call client )
    ~ T {
        : !v GrpcError updated ( __grpc_call_update call )
        ?? updated { T _ → {} F e → { ^ @ !GrpcMessage GrpcError { F e } } }
        : H2CStream stream ?? ( h2_client_stream_state . cl transport . call stream_id ) {
            T s → s F _ → { ^ @ !GrpcMessage GrpcError { F ( grpc_error GRPC_FAILED_PRECONDITION `call already released` ) } }
        }
        : ~ b decode_ready T
        ? & . stream headers_done != . stream status 200 {
            = decode_ready . stream complete
            ? . stream complete {
                : !v GrpcError status ( __grpc_call_status call stream )
                ?? status { T _ → {} F e → { ^ @ !GrpcMessage GrpcError { F e } } }
                ? != . . call status code GRPC_OK {
                    ^ @ !GrpcMessage GrpcError { F ( grpc_error . . call status code ( string_data . . call status message ) ) }
                } {}
                : !v GrpcError protocol ( __grpc_call_response_protocol call . stream headers )
                ?? protocol { T _ → {} F e → { ^ @ !GrpcMessage GrpcError { F e } } }
            } {}
        } {}
        ? decode_ready {
            : GrpcMessage message ?? ( grpc_decoder_next . call decoder ) {
                T m → m F e → {
                    ?? ( grpc_call_cancel call ) { T _ → {} F ce → {} }
                    ^ @ !GrpcMessage GrpcError { F e }
                }
            }
            ? . message present { ^ @ !GrpcMessage GrpcError { T message } } {}
            ? . stream complete {
                : !v GrpcError finished ( __grpc_call_finish call stream )
                ?? finished { T _ → {} F e → { ^ @ !GrpcMessage GrpcError { F e } } }
                ? != . . call status code GRPC_OK {
                    ^ @ !GrpcMessage GrpcError { F ( grpc_error . . call status code ( string_data . . call status message ) ) }
                } {}
                ^ @ !GrpcMessage GrpcError { T @ GrpcMessage { F ( vec_new [u] ) } }
            } {}
        } {}
        : !v GrpcError pumped ( grpc_call_pump call )
        ?? pumped { T _ → {} F e → { ^ @ !GrpcMessage GrpcError { F e } } }
    }
    ^ @ !GrpcMessage GrpcError { F ( grpc_error GRPC_INTERNAL `unreachable receive state` ) }
}

// Let go of `response` now rather than at the end of its owner's scope.
@ grpc_unary_response_free sink GrpcUnaryResponse response → v {}

@ grpc_unary GrpcClient client s path ( Vec u ) request ( Vec Header ) metadata GrpcCallOptions opts → !GrpcUnaryResponse GrpcError {
    : ~ GrpcCall call \ ( grpc_call_open client path metadata opts )
    ?? ( grpc_call_send call request ) { T _ → {} F e → {
            ^ @ !GrpcUnaryResponse GrpcError { F e }
        } }
    ?? ( grpc_call_half_close call ) { T _ → {} F e → {
            ^ @ !GrpcUnaryResponse GrpcError { F e }
        } }
    : GrpcMessage first ?? ( grpc_call_receive call ) {
        T m → m F e → { ^ @ !GrpcUnaryResponse GrpcError { F e } }
    }
    ? ! . first present {
        ^ @ !GrpcUnaryResponse GrpcError { F ( grpc_error GRPC_INTERNAL `unary response has no message` ) }
    } {}
    : GrpcMessage last ?? ( grpc_call_receive call ) {
        T m → m F e → { ^ @ !GrpcUnaryResponse GrpcError { F e } }
    }
    ? . last present {
        ^ @ !GrpcUnaryResponse GrpcError { F ( grpc_error GRPC_INTERNAL `unary response has multiple messages` ) }
    } {}
    : GrpcStatus status @ GrpcStatus { . . call status code
        ( string_clone . . call status message ) ( vec_clone [u] . . call status details ) }
    : GrpcUnaryResponse response @ GrpcUnaryResponse { . first data
        ( grpc_metadata_clone . call headers ) ( grpc_metadata_clone . call trailers ) status }
    ^ @ !GrpcUnaryResponse GrpcError { T response }
}
