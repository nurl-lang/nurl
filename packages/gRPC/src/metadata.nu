// Metadata uses Vec[Header]. Application -bin values are raw, binary-safe
// Strings; wire conversion performs Base64 and preserves duplicate order.
$ `wire.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/protobuf.nu`

@ grpc_metadata_new → ( Vec Header ) { ^ ( vec_new [Header] ) }

@ grpc_metadata_free sink ( Vec Header ) metadata → v {
    ( vec_free_with [Header] metadata \ Header h → v { ( header_free h ) } )
}

@ grpc_header_count ( Vec Header ) headers s name → i {
    : ~ i count 0
    : ~ i header_index 0
    ~ < header_index ( vec_len [Header] headers ) {
        : Header h . ( vec_data [Header] headers ) header_index
        = header_index + header_index 1 ? != ( nurl_str_eq ( string_data . h name ) name ) 0 { = count + count 1 } {} }
    ^ count
}

// Borrowed until headers are freed. Use count to distinguish absent/empty.
@ grpc_header_value ( Vec Header ) headers s name → s {
    : ~ i header_index 0
    ~ < header_index ( vec_len [Header] headers ) {
        : Header h . ( vec_data [Header] headers ) header_index
        = header_index + header_index 1 ? != ( nurl_str_eq ( string_data . h name ) name ) 0 { ^ ( string_data . h value ) } {} }
    ^ ``
}

@ grpc_header_clone Header header → Header {
    ^ @ Header { ( string_clone . header name ) ( string_clone . header value ) }
}

@ grpc_metadata_clone ( Vec Header ) headers → ( Vec Header ) {
    ^ ( vec_clone_with [Header] headers \ Header h → Header { ^ ( grpc_header_clone h ) } )
}

@ grpc_metadata_key String key → b {
    : i n ( string_len key )
    ? == n 0 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( string_get key k )
        ? ! | | & >= c 97 <= c 122 & >= c 48 <= c 57 | | == c 45 == c 95 == c 46 { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ grpc_metadata_reserved String key → b {
    ? | ( string_starts_with key `grpc-` ) ( string_starts_with key `:` ) { ^ T } {}
    : s p ( string_data key )
    ^ | | | != ( nurl_str_eq p `content-type` ) 0 != ( nurl_str_eq p `te` ) 0
    | != ( nurl_str_eq p `content-length` ) 0 != ( nurl_str_eq p `user-agent` ) 0
    | | != ( nurl_str_eq p `connection` ) 0 != ( nurl_str_eq p `keep-alive` ) 0
    | != ( nurl_str_eq p `transfer-encoding` ) 0 != ( nurl_str_eq p `upgrade` ) 0
}

@ grpc_metadata_ascii String value → b {
    : ~ i k 0
    ~ < k ( string_len value ) {
        : i c ( string_get value k )
        ? | < c 32 > c 126 { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ grpc_metadata_add ( Vec Header ) metadata s key s value → !v GrpcError {
    : Header h ( header_new key value )
    ? | ! ( grpc_metadata_key . h name ) ( grpc_metadata_reserved . h name ) {
        ( header_free h )
        ^ @ !v GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid or reserved metadata key` ) }
    } {}
    ? | ( string_ends_with . h name `-bin` ) ! ( grpc_metadata_ascii . h value ) {
        ( header_free h )
        ^ @ !v GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `use grpc_metadata_add_binary for binary metadata` ) }
    } {}
    ( vec_push [Header] metadata h )
    ^ @ !v GrpcError { T 0 }
}

@ grpc_metadata_add_binary ( Vec Header ) metadata s key ( Vec u ) value → !v GrpcError {
    : String name ( string_from key )
    ? | | ! ( grpc_metadata_key name ) ( grpc_metadata_reserved name ) ! ( string_ends_with name `-bin` ) {
        ( string_free name )
        ^ @ !v GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `binary metadata requires a nonreserved -bin key` ) }
    } {}
    ( vec_push [Header] metadata @ Header { name ( bytes_to_str value ) } )
    ^ @ !v GrpcError { T 0 }
}

@ __grpc_metadata_charge inout i remaining i name_size i value_size → !v GrpcError {
    ? | < remaining 32 | < name_size 0 < value_size 0 {
        ^ @ !v GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `metadata exceeds limit` ) }
    } {}
    = remaining - remaining 32
    ? > name_size remaining { ^ @ !v GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `metadata exceeds limit` ) } } {}
    = remaining - remaining name_size
    ? > value_size remaining { ^ @ !v GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `metadata exceeds limit` ) } } {}
    = remaining - remaining value_size
    ^ @ !v GrpcError { T 0 }
}

@ grpc_headers_check_size ( Vec Header ) headers i limit → !v GrpcError {
    ? <= limit 0 { ^ @ !v GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid metadata limit` ) } } {}
    : ~ i remaining limit
    : ~ i header_index 0
    ~ < header_index ( vec_len [Header] headers ) {
        : Header h . ( vec_data [Header] headers ) header_index
        = header_index + header_index 1
        \ ( __grpc_metadata_charge remaining ( string_len . h name ) ( string_len . h value ) )
    }
    ^ @ !v GrpcError { T 0 }
}

// The HTTP/2 client adds these four pseudoheaders when opening a POST stream.
// Include their decoded sizes in the same budget as application metadata.
@ grpc_request_headers_check_size ( Vec Header ) headers s scheme s authority s path i limit → !v GrpcError {
    ? <= limit 0 { ^ @ !v GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid metadata limit` ) } } {}
    : i method_size + 32 + ( nurl_str_len `:method` ) ( nurl_str_len `POST` )
    : i scheme_size + 32 + ( nurl_str_len `:scheme` ) ( nurl_str_len scheme )
    : i authority_size + 32 + ( nurl_str_len `:authority` ) ( nurl_str_len authority )
    : i path_size + 32 + ( nurl_str_len `:path` ) ( nurl_str_len path )
    : i pseudo_size + + method_size scheme_size + authority_size path_size
    ? >= pseudo_size limit {
        ? & == pseudo_size limit == ( vec_len [Header] headers ) 0 { ^ @ !v GrpcError { T 0 } } {}
        ^ @ !v GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `metadata exceeds limit` ) }
    } {}
    ^ ( grpc_headers_check_size headers - limit pseudo_size )
}

@ __grpc_base64 String value → String {
    : String padded ( b64_encode_len ( string_data value ) ( string_len value ) )
    : ~ i n ( string_len padded )
    ~ & > n 0 == ( string_get padded - n 1 ) 61 { = n - n 1 }
    : String result ( string_substr padded 0 n )
    ( string_free padded )
    ^ result
}

@ grpc_metadata_encode ( Vec Header ) metadata i limit → !( Vec Header ) GrpcError {
    \ ( grpc_headers_check_size metadata limit )
    : ( Vec Header ) out ( grpc_metadata_new )
    : ~ i remaining limit
    : ~ i header_index 0
    ~ < header_index ( vec_len [Header] metadata ) {
        : Header h . ( vec_data [Header] metadata ) header_index
        = header_index + header_index 1
        ? | ! ( grpc_metadata_key . h name ) ( grpc_metadata_reserved . h name ) {
            ( grpc_metadata_free out )
            ^ @ !( Vec Header ) GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid or reserved metadata key` ) }
        } {}
        : b binary ( string_ends_with . h name `-bin` )
        : ~ i wire_size ( string_len . h value )
        ? binary {
            // Reject before Base64 allocates; compute unpadded size without
            // overflow even when the caller supplies an unusually large cap.
            : i groups / wire_size 3
            ? > groups / remaining 4 {
                ( grpc_metadata_free out )
                ^ @ !( Vec Header ) GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `metadata exceeds limit` ) }
            } {}
            : i tail % wire_size 3
            = wire_size + * groups 4 ? == tail 0 0 + tail 1
        } {}
        ?? ( __grpc_metadata_charge remaining ( string_len . h name ) wire_size ) {
            T _ → {}
            F e → { ( grpc_metadata_free out ) ^ @ !( Vec Header ) GrpcError { F e } }
        }
        ? binary {
            ( vec_push [Header] out @ Header { ( string_clone . h name ) ( __grpc_base64 . h value ) } )
        } {
            ? ! ( grpc_metadata_ascii . h value ) {
                ( grpc_metadata_free out )
                ^ @ !( Vec Header ) GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `non-ASCII metadata value` ) }
            } {}
            ( vec_push [Header] out ( grpc_header_clone h ) )
        }
    }
    ^ @ !( Vec Header ) GrpcError { T out }
}

@ __grpc_decode_binary ( Vec Header ) out Header h inout i remaining → !v GrpcError {
    : ~ i start 0
    : ~ i k 0
    : i n ( string_len . h value )
    ~ <= k n {
        ? | == k n == ( string_get . h value k ) 44 {
            : i overhead + ( string_len . h name ) 32
            ? > overhead remaining {
                ^ @ !v GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `decoded metadata exceeds limit` ) }
            } {}
            : ~ i a start
            : ~ i z k
            ~ & < a z | == ( string_get . h value a ) 32 == ( string_get . h value a ) 9 { = a + a 1 }
            ~ & > z a | == ( string_get . h value - z 1 ) 32 == ( string_get . h value - z 1 ) 9 { = z - z 1 }
            : String part ( string_substr . h value a - z a )
            // HTTP field validation excludes NUL; make that explicit here for
            // direct callers so a C-string decoder cannot truncate metadata.
            ? != ( string_len part ) ( nurl_str_len ( string_data part ) ) {
                ( string_free part )
                ^ @ !v GrpcError { F ( grpc_error GRPC_INTERNAL `invalid binary metadata` ) }
            } {}
            : !String ParseErr decoded ( b64_decode ( string_data part ) )
            ( string_free part )
            ?? decoded {
                F _ → ^ @ !v GrpcError { F ( grpc_error GRPC_INTERNAL `invalid binary metadata` ) }
                T value → {
                    ? > ( string_len value ) - remaining overhead {
                        ( string_free value )
                        ^ @ !v GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `decoded metadata exceeds limit` ) }
                    } {}
                    = remaining - remaining + overhead ( string_len value )
                    ( vec_push [Header] out @ Header { ( string_clone . h name ) value } )
                }
            }
            = start + k 1
        } {}
        = k + k 1
    }
    ^ @ !v GrpcError { T 0 }
}

@ grpc_metadata_decode ( Vec Header ) headers i limit → !( Vec Header ) GrpcError {
    \ ( grpc_headers_check_size headers limit )
    : ( Vec Header ) out ( grpc_metadata_new )
    : ~ i remaining limit
    : ~ i header_index 0
    ~ < header_index ( vec_len [Header] headers ) {
        : Header h . ( vec_data [Header] headers ) header_index
        = header_index + header_index 1
        ? & ! ( grpc_metadata_reserved . h name ) ( grpc_metadata_key . h name ) {
            ? ( string_ends_with . h name `-bin` ) {
                ?? ( __grpc_decode_binary out h remaining ) {
                    F e → { ( grpc_metadata_free out ) ^ @ !( Vec Header ) GrpcError { F e } }
                    T _ → {}
                }
            } {
                // The gRPC protocol permits dropping non-ASCII HTTP values.
                ? ( grpc_metadata_ascii . h value ) {
                    : i size + + ( string_len . h name ) ( string_len . h value ) 32
                    ? > size remaining {
                        ( grpc_metadata_free out )
                        ^ @ !( Vec Header ) GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `decoded metadata exceeds limit` ) }
                    } {}
                    = remaining - remaining size
                    ( vec_push [Header] out ( grpc_header_clone h ) )
                } {}
            }
        } {}
    }
    ^ @ !( Vec Header ) GrpcError { T out }
}

@ grpc_message_encode String message → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k ( string_len message ) {
        : i c ( string_get message k )
        ? | | < c 32 > c 126 == c 37 {
            ( string_push_char out 37 )
            ( string_push_char out ( nurl_str_get `0123456789ABCDEF` >> c 4 ) )
            ( string_push_char out ( nurl_str_get `0123456789ABCDEF` & c 15 ) )
        } { ( string_push_char out c ) }
        = k + k 1
    }
    ^ out
}

// Malformed percent escapes are preserved as required by the wire protocol.
@ grpc_message_decode String message → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k ( string_len message ) {
        : ~ i c ( string_get message k )
        ? & == c 37 < + k 2 ( string_len message ) {
            : i hi ( hex_val ( string_get message + k 1 ) )
            : i lo ( hex_val ( string_get message + k 2 ) )
            ? & >= hi 0 >= lo 0 { = c + * hi 16 lo = k + k 2 } {}
        } {}
        ( string_push_char out c )
        = k + k 1
    }
    ^ out
}

: GrpcStatus { i code String message ( Vec u ) details }

@ grpc_status i code s message → GrpcStatus {
    ^ @ GrpcStatus { code ( string_from message ) ( vec_new [u] ) }
}

@ grpc_status_free sink GrpcStatus status → v {
    ( string_free . status message )
    ( vec_free [u] . status details )
}

@ __grpc_details_validate i code ( Vec u ) details → !v ProtoError {
    : ~ ProtoReader r \ ( proto_reader details )
    : ~ i found_code 0
    ~ ( proto_more r ) {
        : i offset ( proto_offset r )
        : ProtoTag tag \ ( proto_read_tag r )
        ? == . tag number 1 {
            \ ( proto_expect tag 0 offset )
            = found_code # i \ ( proto_read_int32 r )
        } { \ ( proto_skip r tag ) }
    }
    // An omitted proto3 scalar has value zero. Missing code is therefore
    // inconsistent with every non-OK grpc-status, not an unchecked detail.
    ? != code found_code {
        ^ @ !v ProtoError { F @ ProtoError { ProtoBadRange 0 } }
    } {}
    ^ @ !v ProtoError { T 0 }
}

// headers must be the final trailer block, or END_STREAM initial headers
// for a trailers-only response. The transport decides which block is final.
@ grpc_status_parse ( Vec Header ) headers → !GrpcStatus GrpcError {
    ? | | != ( grpc_header_count headers `grpc-status` ) 1 > ( grpc_header_count headers `grpc-message` ) 1 > ( grpc_header_count headers `grpc-status-details-bin` ) 1 {
        ^ @ !GrpcStatus GrpcError { F ( grpc_error GRPC_UNKNOWN `missing or duplicate grpc-status trailers` ) }
    } {}
    : s raw ( grpc_header_value headers `grpc-status` )
    : i n ( nurl_str_len raw )
    ? | | == n 0 > n 2 & > n 1 == ( nurl_str_get raw 0 ) 48 {
        ^ @ !GrpcStatus GrpcError { F ( grpc_error GRPC_UNKNOWN `invalid grpc-status` ) }
    } {}
    : ~ i code 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get raw k )
        ? | < c 48 > c 57 { ^ @ !GrpcStatus GrpcError { F ( grpc_error GRPC_UNKNOWN `invalid grpc-status` ) } } {}
        = code + * code 10 - c 48
        = k + k 1
    }
    ? > code 16 { = code GRPC_UNKNOWN } {}
    : String encoded ( string_from ( grpc_header_value headers `grpc-message` ) )
    : String message ( grpc_message_decode encoded )
    ( string_free encoded )
    ? == ( grpc_header_count headers `grpc-status-details-bin` ) 1 {
        ? == code GRPC_OK {
            ( string_free message )
            ^ @ !GrpcStatus GrpcError { F ( grpc_error GRPC_INTERNAL `OK status cannot carry error details` ) }
        } {}
        ?? ( b64_decode_vec ( grpc_header_value headers `grpc-status-details-bin` ) ) {
            F _ → {
                ( string_free message )
                ^ @ !GrpcStatus GrpcError { F ( grpc_error GRPC_INTERNAL `invalid status details` ) }
            }
            T details → {
                ?? ( __grpc_details_validate code details ) {
                    F _ → {
                        ( string_free message ) ( vec_free [u] details )
                        ^ @ !GrpcStatus GrpcError { F ( grpc_error GRPC_INTERNAL `status details disagree with grpc-status` ) }
                    }
                    T _ → ^ @ !GrpcStatus GrpcError { T @ GrpcStatus { code message details } }
                }
            }
        }
    } {}
    ^ @ !GrpcStatus GrpcError { T @ GrpcStatus { code message ( vec_new [u] ) } }
}

// Reserve protocol fields before percent/Base64 encoding or copying details.
// The returned budget belongs entirely to application metadata. Counting stops
// at the configured limit, even if the caller supplies a very large message.
@ __grpc_status_metadata_budget GrpcStatus status i limit → !i GrpcError {
    ? <= limit 0 { ^ @ !i GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid metadata limit` ) } } {}
    : ~ i remaining limit
    \ ( __grpc_metadata_charge remaining ( nurl_str_len `grpc-status` ) ? < . status code 10 1 2 )
    \ ( __grpc_metadata_charge remaining ( nurl_str_len `grpc-message` ) 0 )
    : i length ( string_len . status message )
    ? > length remaining { ^ @ !i GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `metadata exceeds limit` ) } } {}
    : ~ i k 0
    ~ < k length {
        : i c ( string_get . status message k )
        : i count ? | | < c 32 > c 126 == c 37 3 1
        ? > count remaining { ^ @ !i GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `metadata exceeds limit` ) } } {}
        = remaining - remaining count
        = k + k 1
    }
    : i details_size ( vec_len [u] . status details )
    ? > details_size 0 {
        : i groups / details_size 3
        ? > groups / remaining 4 { ^ @ !i GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `metadata exceeds limit` ) } } {}
        : i tail % details_size 3
        : i encoded_size + * groups 4 ? == tail 0 0 + tail 1
        \ ( __grpc_metadata_charge remaining ( nurl_str_len `grpc-status-details-bin` ) encoded_size )
    } {}
    ^ @ !i GrpcError { T remaining }
}

@ grpc_status_headers GrpcStatus status ( Vec Header ) metadata i limit → !( Vec Header ) GrpcError {
    ? | | < . status code 0 > . status code 16 & == . status code GRPC_OK > ( vec_len [u] . status details ) 0 {
        ^ @ !( Vec Header ) GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `invalid gRPC status` ) }
    } {}
    : i metadata_limit \ ( __grpc_status_metadata_budget status limit )
    ? & == metadata_limit 0 > ( vec_len [Header] metadata ) 0 {
        ^ @ !( Vec Header ) GrpcError { F ( grpc_error GRPC_RESOURCE_EXHAUSTED `metadata exceeds limit` ) }
    } {}
    ? > ( vec_len [u] . status details ) 0 {
        ?? ( __grpc_details_validate . status code . status details ) {
            F _ → ^ @ !( Vec Header ) GrpcError { F ( grpc_error GRPC_INVALID_ARGUMENT `status details disagree with grpc-status` ) }
            T _ → {}
        }
    } {}
    : ~ ( Vec Header ) out ( grpc_metadata_new )
    ? > ( vec_len [Header] metadata ) 0 {
        ?? ( grpc_metadata_encode metadata metadata_limit ) {
            T encoded → { ( grpc_metadata_free out ) = out encoded }
            F e → { ( grpc_metadata_free out ) ^ @ !( Vec Header ) GrpcError { F e } }
        }
    } {}
    : String code ( string_new )
    ( string_push_int code . status code )
    ( vec_push [Header] out @ Header { ( string_from `grpc-status` ) code } )
    ( vec_push [Header] out @ Header { ( string_from `grpc-message` ) ( grpc_message_encode . status message ) } )
    ? > ( vec_len [u] . status details ) 0 {
        : String bytes ( bytes_to_str . status details )
        ( vec_push [Header] out @ Header { ( string_from `grpc-status-details-bin` ) ( __grpc_base64 bytes ) } )
        ( string_free bytes )
    } {}
    ?? ( grpc_headers_check_size out limit ) {
        F e → { ( grpc_metadata_free out ) ^ @ !( Vec Header ) GrpcError { F e } }
        T _ → ^ @ !( Vec Header ) GrpcError { T out }
    }
}
