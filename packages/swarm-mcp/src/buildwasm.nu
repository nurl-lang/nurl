// packages/swarm-mcp/src/buildwasm.nu — compile NURL source to a wasm module
// via the NURL build API, so the MCP server itself can accept a kernel as
// source (compute_submit_kernel) instead of requiring the caller to pre-compile.
//
// POST {source, filename} to <NURL_BUILD_API>/build_wasm. A direct nurlapi can
// answer with the raw wasm bytes; the public playground proxy answers with JSON
// carrying `wasm_base64` (and `nurlc_errors` on failure). Both are handled.
//
//   $NURL_BUILD_API   build service base URL (default https://play.nurl-lang.org)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_cli.nu`

@ build_api_url → String { ^ ( env_var_or `NURL_BUILD_API` `https://play.nurl-lang.org` ) }

// wasm magic: 00 61 73 6d
@ __is_wasm ( Vec u ) v → b {
    ? < ( vec_len [u] v ) 4 { ^ F } {}
    : i b0 ?? ( vec_get [u] v 0 ) { T x → # i x F → 1 }
    : i b1 ?? ( vec_get [u] v 1 ) { T x → # i x F → 1 }
    : i b2 ?? ( vec_get [u] v 2 ) { T x → # i x F → 1 }
    : i b3 ?? ( vec_get [u] v 3 ) { T x → # i x F → 1 }
    ^ & == b0 0 & == b1 97 & == b2 115 == b3 109
}

// A string field of a parsed JSON object (empty String if absent / not a string).
@ __json_field Json o s key → String {
    ^ ?? ( json_obj_get o key ) { T v → ( string_from ( json_str_data v ) ) F → ( string_new ) }
}

// Build a human-readable compile error from the build API's JSON body.
@ __build_error Json j → String {
    : ~ String msg ( __json_field j `message` )
    ? == ( string_len msg ) 0 { ( string_free msg ) = msg ( string_from `wasm build failed` ) } {}
    : ?Json ne ( json_obj_get j `nurlc_errors` )
    ?? ne { T v → { ( string_push_str msg ` ` ) ( string_push_str msg ( string_data ( json_stringify v ) ) ) } F → {} }
    : String cs ( __json_field j `clang_stderr` )
    ? > ( string_len cs ) 0 { ( string_push_str msg ` ` ) ( string_push_str msg ( string_data cs ) ) } {}
    ( string_free cs )
    ^ msg
}

// Compile NURL `source` to a wasm module. Ok = module bytes; Err = a
// human-readable transport/compile error (suitable to hand back to the model).
@ compile_to_wasm s source → !( Vec u ) String {
    : Json req ( json_obj_new )
    ( json_obj_set req `source` ( json_str_lit source ) )
    ( json_obj_set req `filename` ( json_str_lit `kernel.nu` ) )
    ( json_obj_set req `return_format` ( json_str_lit `binary` ) )
    : String body ( json_stringify req )
    ( json_free req )
    : String url ( string_concat ( build_api_url ) ( string_from `/build_wasm` ) )
    : String hb ( string_new )
    ( string_push_str hb `Content-Type: application/json\r\n` )
    ( string_push_str hb `Accept: application/wasm\r\n` )
    : !HttpcResp HttpcErr rr ( httpc_request `POST` ( string_data url ) ( string_data body ) ( string_data hb ) )
    ( string_free body ) ( string_free hb )
    : ~ ! ( Vec u ) String out @ !( Vec u ) String { F ( string_from `internal` ) }
    ?? rr {
        F e → { = out @ !( Vec u ) String { F ( string_concat ( string_from `could not reach the build API at ` ) url ) } }
        T resp → {
            : ( Vec u ) rb ( httpc_body_bytes resp )
            ( httpc_resp_free resp )
            ? ( __is_wasm rb ) {
                = out @ !( Vec u ) String { T rb }
            } {
                : String txt ( bytes_to_str rb )
                : !Json JsonError jr ( json_parse ( string_data txt ) )
                ?? jr {
                    F je → { = out @ !( Vec u ) String { F ( string_from `build API returned an unreadable response` ) } }
                    T j → {
                        : String b64 ( __json_field j `wasm_base64` )
                        ? > ( string_len b64 ) 0 {
                            : !( Vec u ) ParseErr dr ( b64_decode_vec ( string_data b64 ) )
                            ?? dr {
                                T wasm → { = out @ !( Vec u ) String { T wasm } }
                                F pe → { = out @ !( Vec u ) String { F ( string_from `build API returned invalid base64` ) } }
                            }
                        } {
                            = out @ !( Vec u ) String { F ( __build_error j ) }
                        }
                        ( string_free b64 )
                        ( json_free j )
                    }
                }
                ( string_free txt )
                ( vec_free [u] rb )
            }
        }
    }
    ( string_free url )
    ^ out
}
