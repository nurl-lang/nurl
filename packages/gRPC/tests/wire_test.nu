$ `../src/metadata.nu`

@ check b condition s message → v {
    ? ! condition { ( nurl_print message ) ( nurl_print `\n` ) ( nurl_exit 1 ) } {}
}

@ bytes s hex → ( Vec u ) {
    ^ ?? ( bytes_from_hex hex ) { T b → b F _ → { ( nurl_exit 2 ) ( vec_new [u] ) } }
}

@ error_code ! v GrpcError result i wanted → v {
    ?? result {
        T _ → { ( nurl_print `expected error\n` ) ( nurl_exit 3 ) }
        F e → { ( check == . e code wanted `error code` ) ( grpc_error_free e ) }
    }
}

@ framing → !v GrpcError {
    : ( Vec u ) payload ( bytes `0800120300ff7f` )
    : ( Vec u ) encoded \ ( grpc_frame payload GRPC_IDENTITY 1024 )
    : ( Vec u ) expected ( bytes `00000000070800120300ff7f` )
    ( check ( bytes_eq encoded expected ) `wire format` )
    : ~ i split 0
    ~ <= split ( vec_len [u] encoded ) {
        : ~ GrpcDecoder decoder \ ( grpc_decoder 1024 2048 GRPC_IDENTITY )
        : ( Vec u ) first ( vec_new [u] )
        ( vec_extend_range [u] first encoded 0 split )
        \ ( grpc_decoder_feed decoder first )
        : GrpcMessage partial \ ( grpc_decoder_next decoder )
        ? < split ( vec_len [u] encoded ) {
            ( check ! . partial present `fragment emitted early` )
            : ( Vec u ) rest ( vec_new [u] )
            ( vec_extend_range [u] rest encoded split - ( vec_len [u] encoded ) split )
            \ ( grpc_decoder_feed decoder rest )
            : GrpcMessage complete \ ( grpc_decoder_next decoder )
            ( check & . complete present ( bytes_eq . complete data payload ) `fragment reassembly` )
            ( grpc_message_free complete )
            ( vec_free [u] rest )
        } { ( check & . partial present ( bytes_eq . partial data payload ) `whole message` ) }
        ( grpc_message_free partial )
        \ ( grpc_decoder_finish decoder )
        ( grpc_decoder_free decoder )
        ( vec_free [u] first )
        = split + split 1
    }
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) empty_frame \ ( grpc_frame empty GRPC_IDENTITY 1024 )
    : ~ GrpcDecoder combined \ ( grpc_decoder 1024 2048 GRPC_IDENTITY )
    \ ( grpc_decoder_feed combined empty_frame )
    \ ( grpc_decoder_feed combined encoded )
    : GrpcMessage one \ ( grpc_decoder_next combined )
    : GrpcMessage two \ ( grpc_decoder_next combined )
    : GrpcMessage none \ ( grpc_decoder_next combined )
    ( check & . one present == ( vec_len [u] . one data ) 0 `empty message exists` )
    ( check & . two present ( bytes_eq . two data payload ) `coalesced messages` )
    ( check ! . none present `no message` )
    ( check == ( vec_len [u] . combined pending ) 0 `drained decoder has no retained payload` )
    ( check <= ( vec_cap [u] . combined pending ) 16 `drained decoder releases capacity` )
    \ ( grpc_decoder_finish combined )
    ( grpc_message_free one ) ( grpc_message_free two ) ( grpc_message_free none )
    ( grpc_decoder_free combined )
    ( vec_free [u] empty ) ( vec_free [u] empty_frame )
    ( vec_free [u] payload ) ( vec_free [u] encoded ) ( vec_free [u] expected )
    ^ @ !v GrpcError { T 0 }
}

@ malformed s hex i want → !v GrpcError {
    : ~ GrpcDecoder decoder \ ( grpc_decoder 1024 2048 GRPC_IDENTITY )
    : ( Vec u ) input ( bytes hex )
    \ ( grpc_decoder_feed decoder input )
    ?? ( grpc_decoder_next decoder ) {
        F e → { ( check == . e code want `malformed code` ) ( grpc_error_free e ) }
        T msg → { ( grpc_message_free msg ) ( error_code ( grpc_decoder_finish decoder ) want ) }
    }
    ( vec_free [u] input )
    ( grpc_decoder_free decoder )
    ^ @ !v GrpcError { T 0 }
}

@ compression → !v GrpcError {
    : ( Vec u ) input ( bytes `080012050000ffffff` )
    : ( Vec u ) encoded \ ( grpc_frame input GRPC_GZIP 1024 )
    : ~ GrpcDecoder d \ ( grpc_decoder 1024 2048 GRPC_GZIP )
    \ ( grpc_decoder_feed d encoded )
    : GrpcMessage message \ ( grpc_decoder_next d )
    ( check & . message present ( bytes_eq . message data input ) `gzip roundtrip` )
    \ ( grpc_decoder_finish d )
    ( grpc_message_free message ) ( grpc_decoder_free d )
    ( vec_free [u] encoded ) ( vec_free [u] input )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) empty_frame \ ( grpc_frame empty GRPC_GZIP 1024 )
    ( check > ( vec_len [u] empty_frame ) 5 `compressed empty must have gzip framing` )
    : ~ GrpcDecoder de \ ( grpc_decoder 1024 2048 GRPC_GZIP )
    \ ( grpc_decoder_feed de empty_frame )
    : GrpcMessage e \ ( grpc_decoder_next de )
    ( check & . e present == ( vec_len [u] . e data ) 0 `gzip empty roundtrip` )
    ( grpc_message_free e ) ( grpc_decoder_free de )
    ( vec_free [u] empty_frame ) ( vec_free [u] empty )
    ^ @ !v GrpcError { T 0 }
}

@ metadata → !v GrpcError {
    : ( Vec Header ) meta ( grpc_metadata_new )
    \ ( grpc_metadata_add meta `authorization` `Bearer token` )
    \ ( grpc_metadata_add meta `x-repeat` `one` )
    \ ( grpc_metadata_add meta `x-repeat` `two` )
    : ( Vec u ) binary ( bytes `0001ff` )
    \ ( grpc_metadata_add_binary meta `trace-bin` binary )
    : ( Vec Header ) wire \ ( grpc_metadata_encode meta 8192 )
    ( check != ( nurl_str_eq ( grpc_header_value wire `trace-bin` ) `AAH/` ) 0 `binary encoding` )
    : ( Vec Header ) decoded \ ( grpc_metadata_decode wire 8192 )
    ( check == ( vec_len [Header] decoded ) 4 `metadata count` )
    ( check == ( grpc_header_count decoded `x-repeat` ) 2 `duplicates preserved` )
    : Header bh . ( vec_data [Header] decoded ) 3
    ( check == ( string_len . bh value ) 3 `binary NUL preserved` )
    ( check == ( string_get . bh value 2 ) 255 `binary high byte` )
    ( error_code ( grpc_metadata_add meta `grpc-status` `0` ) GRPC_INVALID_ARGUMENT )
    ( error_code ( grpc_metadata_add meta `Bad` `x` ) GRPC_INVALID_ARGUMENT )
    ( error_code ( grpc_headers_check_size wire 5 ) GRPC_RESOURCE_EXHAUSTED )
    : ( Vec Header ) request_headers ( grpc_metadata_new )
    ( vec_push [Header] request_headers ( header_new `content-type` `application/grpc` ) )
    // Four pseudoheaders total 196 bytes; content-type adds another 60.
    \ ( grpc_request_headers_check_size request_headers `https` `example.com:443` `/test.Echo/Ping` 256 )
    ( error_code ( grpc_request_headers_check_size request_headers `https` `example.com:443` `/test.Echo/Ping` 255 ) GRPC_RESOURCE_EXHAUSTED )
    ( error_code ( grpc_request_headers_check_size request_headers `https` `example.com:443` `/test.Echo/Ping` 196 ) GRPC_RESOURCE_EXHAUSTED )
    ( grpc_metadata_free request_headers )
    : ( Vec Header ) response_headers ( grpc_metadata_new )
    ( vec_push [Header] response_headers ( header_new `:status` `200` ) )
    ( vec_push [Header] response_headers ( header_new `content-type` `application/grpc` ) )
    \ ( grpc_headers_check_size response_headers 102 )
    ( error_code ( grpc_headers_check_size response_headers 101 ) GRPC_RESOURCE_EXHAUSTED )
    ( grpc_metadata_free response_headers )
    : ( Vec Header ) joined ( grpc_metadata_new )
    ( vec_push [Header] joined ( header_new `values-bin` `Zg==, Zm8,` ) )
    : ( Vec Header ) expanded \ ( grpc_metadata_decode joined 8192 )
    ( check == ( vec_len [Header] expanded ) 3 `joined binary metadata` )
    ( check != ( nurl_str_eq ( grpc_header_value expanded `values-bin` ) `f` ) 0 `binary decode` )
    ( grpc_metadata_free expanded ) ( grpc_metadata_free joined )
    : ( Vec Header ) split ( grpc_metadata_new )
    ( vec_push [Header] split ( header_new `x-bin` `,,` ) )
    // Three empty decoded values cost 3*(32+5), despite a 39-byte wire field.
    : ( Vec Header ) at_limit \ ( grpc_metadata_decode split 111 )
    ( check == ( vec_len [Header] at_limit ) 3 `decoded budget exact boundary` )
    ( grpc_metadata_free at_limit )
    ?? ( grpc_metadata_decode split 110 ) {
        T unexpected → { ( grpc_metadata_free unexpected ) ( check F `decoded budget overflow` ) }
        F error → { ( check == . error code GRPC_RESOURCE_EXHAUSTED `decoded metadata limit` ) ( grpc_error_free error ) }
    }
    ( grpc_metadata_free split )
    : String long_key ( string_new )
    : String commas ( string_new )
    : ~ i k 0
    ~ < k 4000 { ( string_push_char long_key 97 ) ( string_push_char commas 44 ) = k + k 1 }
    ( string_push_str long_key `-bin` )
    : ( Vec Header ) amplified ( grpc_metadata_new )
    ( vec_push [Header] amplified @ Header { long_key commas } )
    ?? ( grpc_metadata_decode amplified 8192 ) {
        T unexpected → { ( grpc_metadata_free unexpected ) ( check F `metadata amplification` ) }
        F error → { ( check == . error code GRPC_RESOURCE_EXHAUSTED `amplification budget` ) ( grpc_error_free error ) }
    }
    ( grpc_metadata_free amplified )
    : ( Vec Header ) encode_limit ( grpc_metadata_new )
    ( vec_push [Header] encode_limit ( header_new `x-bin` `foo` ) )
    : ( Vec Header ) encoded_limit \ ( grpc_metadata_encode encode_limit 41 )
    ( grpc_metadata_free encoded_limit )
    ?? ( grpc_metadata_encode encode_limit 40 ) {
        T unexpected → { ( grpc_metadata_free unexpected ) ( check F `encoded budget overflow` ) }
        F error → { ( check == . error code GRPC_RESOURCE_EXHAUSTED `encoded metadata limit` ) ( grpc_error_free error ) }
    }
    ( grpc_metadata_free encode_limit )
    ( grpc_metadata_free decoded ) ( grpc_metadata_free wire ) ( grpc_metadata_free meta )
    ( vec_free [u] binary )
    ^ @ !v GrpcError { T 0 }
}

@ statuses → !v GrpcError {
    : String text ( string_from `50% / ä\n` )
    : String encoded ( grpc_message_encode text )
    : String decoded ( grpc_message_decode encoded )
    ( check ( string_eq text decoded ) `status message encoding` )
    : String broken ( string_from `%Qx%2%20` )
    : String kept ( grpc_message_decode broken )
    ( check != ( nurl_str_eq ( string_data kept ) `%Qx%2 ` ) 0 `bad escapes preserved` )
    ( string_free text ) ( string_free encoded ) ( string_free decoded )
    ( string_free broken ) ( string_free kept )
    : ( Vec Header ) meta ( grpc_metadata_new )
    : ~ GrpcStatus status ( grpc_status GRPC_RESOURCE_EXHAUSTED `full` )
    ?? ( proto_write_int32 . status details 1 # i32 8 ) { T _ → {} F _ → ( nurl_exit 6 ) }
    : ( Vec Header ) headers \ ( grpc_status_headers status meta 8192 )
    : GrpcStatus parsed \ ( grpc_status_parse headers )
    ( check & == . parsed code 8 ( bytes_eq . parsed details . status details ) `rich status` )
    ( grpc_status_free parsed ) ( grpc_metadata_free headers )
    = . status code 3
    ?? ( grpc_status_headers status meta 8192 ) {
        T unexpected → { ( grpc_metadata_free unexpected ) ( nurl_exit 4 ) }
        F e → { ( check == . e code 3 `mismatched details` ) ( grpc_error_free e ) }
    }
    ?? ( grpc_status_parse meta ) {
        T unexpected → { ( grpc_status_free unexpected ) ( nurl_exit 5 ) }
        F e → { ( check == . e code GRPC_UNKNOWN `missing status` ) ( grpc_error_free e ) }
    }
    ( grpc_status_free status ) ( grpc_metadata_free meta )
    : ( Vec Header ) omitted_code ( grpc_metadata_new )
    ( vec_push [Header] omitted_code ( header_new `grpc-status` `3` ) )
    // google.rpc.Status { message: "x" } has code=0 by proto3 default.
    ( vec_push [Header] omitted_code ( header_new `grpc-status-details-bin` `EgF4` ) )
    ?? ( grpc_status_parse omitted_code ) {
        T unexpected → { ( grpc_status_free unexpected ) ( nurl_exit 7 ) }
        F e → { ( check == . e code GRPC_INTERNAL `missing details code defaults to zero` ) ( grpc_error_free e ) }
    }
    ( grpc_metadata_free omitted_code )
    : GrpcStatus omitted_out ( grpc_status GRPC_INVALID_ARGUMENT `x` )
    : ( Vec u ) details ( bytes `120178` )
    ( vec_extend [u] . omitted_out details details )
    ( vec_free [u] details )
    : ( Vec Header ) empty_meta ( grpc_metadata_new )
    ?? ( grpc_status_headers omitted_out empty_meta 8192 ) {
        T unexpected → { ( grpc_metadata_free unexpected ) ( nurl_exit 8 ) }
        F e → { ( check == . e code GRPC_INVALID_ARGUMENT `outbound details code default` ) ( grpc_error_free e ) }
    }
    ( grpc_status_free omitted_out ) ( grpc_metadata_free empty_meta )
    : ( Vec Header ) boundary_meta ( grpc_metadata_new )
    : GrpcStatus ok ( grpc_status GRPC_OK `` )
    // grpc-status: 32+11+1, grpc-message: 32+12+0.
    : ( Vec Header ) exact_empty \ ( grpc_status_headers ok boundary_meta 88 )
    ( grpc_metadata_free exact_empty )
    ?? ( grpc_status_headers ok boundary_meta 87 ) {
        T unexpected → { ( grpc_metadata_free unexpected ) ( check F `empty status budget overflow` ) }
        F e → { ( check == . e code GRPC_RESOURCE_EXHAUSTED `empty status metadata limit` ) ( grpc_error_free e ) }
    }
    ( grpc_status_free ok )
    : GrpcStatus double_digit ( grpc_status GRPC_UNAUTHENTICATED `` )
    : ( Vec Header ) exact_double \ ( grpc_status_headers double_digit boundary_meta 89 )
    ( grpc_metadata_free exact_double )
    ?? ( grpc_status_headers double_digit boundary_meta 88 ) {
        T unexpected → { ( grpc_metadata_free unexpected ) ( check F `two-digit status budget overflow` ) }
        F e → { ( check == . e code GRPC_RESOURCE_EXHAUSTED `two-digit status metadata limit` ) ( grpc_error_free e ) }
    }
    ( grpc_status_free double_digit )
    : ( Vec u ) boundary_binary ( bytes `666f6f` )
    \ ( grpc_metadata_add_binary boundary_meta `x-bin` boundary_binary )
    ( vec_free [u] boundary_binary )
    : GrpcStatus boundary_status ( grpc_status GRPC_INVALID_ARGUMENT `x%\nä` )
    ?? ( proto_write_int32 . boundary_status details 1 # i32 3 ) { T _ → {} F _ → ( nurl_exit 9 ) }
    // 44 status + 57 escaped message + 58 Base64 details + 41 metadata.
    : ( Vec Header ) exact_status \ ( grpc_status_headers boundary_status boundary_meta 200 )
    ( check != ( nurl_str_eq ( grpc_header_value exact_status `grpc-message` ) `x%25%0A%C3%A4` ) 0 `status escaped size` )
    ( check != ( nurl_str_eq ( grpc_header_value exact_status `grpc-status-details-bin` ) `CAM` ) 0 `status unpadded details size` )
    ( grpc_metadata_free exact_status )
    ?? ( grpc_status_headers boundary_status boundary_meta 199 ) {
        T unexpected → { ( grpc_metadata_free unexpected ) ( check F `rich status budget overflow` ) }
        F e → { ( check == . e code GRPC_RESOURCE_EXHAUSTED `rich status metadata limit` ) ( grpc_error_free e ) }
    }
    ( check == ( string_len . boundary_status message ) 5 `status input remains owned` )
    ( check == ( vec_len [u] . boundary_status details ) 2 `details input remains owned` )
    ( check != ( nurl_str_eq ( grpc_header_value boundary_meta `x-bin` ) `foo` ) 0 `metadata input remains owned` )
    ( grpc_status_free boundary_status ) ( grpc_metadata_free boundary_meta )
    ( check == ( grpc_http_status 401 ) GRPC_UNAUTHENTICATED `HTTP fallback` )
    ( check == ( grpc_http_status 503 ) GRPC_UNAVAILABLE `HTTP unavailable` )
    ^ @ !v GrpcError { T 0 }
}

@ timeout s input i expected → !v GrpcError {
    : String value ( string_from input )
    : i actual \ ( grpc_timeout_ns value )
    ( check == actual expected `timeout parse` )
    ( string_free value )
    ^ @ !v GrpcError { T 0 }
}

@ protocol → !v GrpcError {
    \ ( timeout `1n` 1 )
    \ ( timeout `1u` 1000 )
    \ ( timeout `1m` 1000000 )
    \ ( timeout `1S` 1000000000 )
    \ ( timeout `1M` 60000000000 )
    \ ( timeout `1H` 3600000000000 )
    \ ( timeout `99999999H` 9223372036854775807 )
    \ ( timeout `0n` 0 )
    : String largest ( grpc_timeout_value 9223372036854775807 )
    : i duration \ ( grpc_timeout_ns largest )
    ( check == duration 9223372036854775807 `timeout round up saturation` )
    ( string_free largest )
    : String rounded ( grpc_timeout_value 999999991 )
    : i back \ ( grpc_timeout_ns rounded )
    ( check >= back 999999991 `timeout never shortened` )
    ( string_free rounded )
    : String proto ( string_from `application/grpc+proto` )
    : String grpc ( string_from `application/grpc` )
    : String web ( string_from `application/grpc-web` )
    ( check ( grpc_content_type proto ) `proto content type` )
    ( check ( grpc_content_type grpc ) `grpc content type` )
    ( check ! ( grpc_content_type web ) `grpc-web is distinct` )
    ( check ( grpc_method_path `/test.Echo/Ping` ) `method path` )
    ( check ! ( grpc_method_path `/test/Echo/Ping` ) `bad method path` )
    ( string_free proto ) ( string_free grpc ) ( string_free web )
    ^ @ !v GrpcError { T 0 }
}

@ run → !v GrpcError {
    \ ( framing )
    \ ( malformed `02` GRPC_INTERNAL )
    \ ( malformed `ff` GRPC_INTERNAL )
    \ ( malformed `0100000000` GRPC_INTERNAL )
    \ ( malformed `00ffffffff` GRPC_RESOURCE_EXHAUSTED )
    \ ( malformed `00000000` GRPC_INTERNAL )
    \ ( malformed `0000000002ff` GRPC_INTERNAL )
    \ ( compression )
    \ ( metadata )
    \ ( statuses )
    \ ( protocol )
    ^ @ !v GrpcError { T 0 }
}

@ main → i {
    ?? ( run ) {
        T _ → { ( nurl_print `gRPC wire tests passed\n` ) ^ 0 }
        F e → { ( nurl_print ( string_data . e message ) ) ( nurl_print `\n` ) ( grpc_error_free e ) ^ 1 }
    }
}
