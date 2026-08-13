// packages/swarm-mcp/src/buildwasm.nu — compile NURL source to a wasm module
// so the MCP server itself can accept a kernel as source
// (compute_submit_kernel / compute_submit_cuda) instead of requiring the
// caller to pre-compile.
//
// LOCAL-FIRST: the wasmbuilder package (deps/wasmbuilder) compiles the
// kernel in-process — nurlc → IR rewrite → the toolchain's bundled zig cc —
// no network, no build service. Only when the local toolchain can't do it
// (no nurlc/zig on this box) does it fall back to POSTing
// {source, filename} to <NURL_BUILD_API>/build_wasm. A direct nurlapi
// answers with raw wasm bytes; the public playground proxy answers with
// JSON carrying `wasm_base64` (and `nurlc_errors` on failure). Both are
// handled.
//
//   $NURL_BUILD_API   fallback build service base URL
//                     (default https://play.nurl-lang.org)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_cli.nu`
$ `deps/wasmbuilder/src/build.nu`

@ build_api_url → String { ^ ( env_var_or `NURL_BUILD_API` `https://play.nurl-lang.org` ) }

// Wall-clock cap on one fallback build request.
@ __build_api_timeout → i { ^ 90 }

// ── kernel wrapping ──────────────────────────────────────────────
// The caller supplies just a per-element kernel `@ kernel i x → i { … }`
// (plus any imports/helpers). wrap_kernel generates the rest of the program:
// a main that reads lo/hi from argv, folds `kernel(x)` over [lo, hi) with the
// reduce op, and prints the partial — the same map-reduce shape as the
// expression path, so the model never writes argv/loop/print boilerplate.

@ __red_identity_src i op → s {
    ? == op 1 { ^ `1` } {}  // product
    ? == op 2 { ^ `9223372036854775807` } {}  // min → +∞
    ? == op 3 { ^ `- 0 9223372036854775807` } {}  // max → −∞
    ^ `0`  // sum, count
}

// acc-update for one mapped value `kv` (must match work.nu's red_fold).
@ __red_combine_src i op → s {
    ? == op 1 { ^ `* acc kv` } {}  // product
    ? == op 2 { ^ `? < kv acc kv acc` } {}  // min
    ? == op 3 { ^ `? > kv acc kv acc` } {}  // max
    ? == op 4 { ^ `? != kv 0 + acc 1 acc` } {}  // count of truthy
    ^ `+ acc kv`  // sum
}

// Float (f64) duals — must match work.nu's red_id_f / red_fold_f. ±∞ identities
// come from their f64 bit patterns (see work.nu).
@ __red_identity_src_f i op → s {
    ? == op 1 { ^ `1.0` } {}  // product
    ? == op 2 { ^ `( bits_to_f64 9218868437227405312 )` } {}  // min → +∞
    ? == op 3 { ^ `( bits_to_f64 -4503599627370496 )` } {}  // max → −∞
    ^ `0.0`  // sum, count
}

@ __red_combine_src_f i op → s {
    ? == op 1 { ^ `* acc kv` } {}  // product
    ? == op 2 { ^ `? < kv acc kv acc` } {}  // min
    ? == op 3 { ^ `? > kv acc kv acc` } {}  // max
    ? == op 4 { ^ `? != kv 0.0 + acc 1.0 acc` } {}  // count of truthy
    ^ `+ acc kv`  // sum
}

// Wrap a bare kernel into a complete wasm-ready program for reduce op `op`.
// dtype 0 (int): kernel is `@ kernel i x → i`; the module folds in i64 and
// prints the partial as a decimal integer. dtype 1 (float): kernel is
// `@ kernel i x → f` (x is the integer index, returns a double); the module
// folds in f64 and prints the partial's f64 BIT PATTERN as a decimal integer —
// so it rides the same stdout→int wire, and the coordinator reinterprets it
// (work.nu tids_combine float path).
//
// kkind 0 (element): the generated main folds kernel(x) over [lo, hi).
// kkind 1 (chunk):   the kernel is `@ kernel i lo i hi → i` (or `→ f`) and the
// main calls it ONCE with the whole sub-range — the kernel owns the loop. This
// is the right granularity for kernels with per-invocation setup cost (open a
// CUDA context, JIT a device kernel, allocate buffers): one setup per CHUNK
// instead of one per element. The reduce op still combines the chunk partials.
@ wrap_kernel s source i op i dtype i kkind → String {
    ? == kkind 1 { ^ ( __wrap_kernel_chunk source dtype ) } {}
    ? == dtype 1 { ^ ( __wrap_kernel_f source op ) } {}
    : String w ( string_new )
    // `$ `stdlib/core/string.nu`` — backticks emitted by code (can't nest in a
    // backtick literal). nurlc dedups this if the kernel imports it too.
    ( string_push_str w `$ ` ) ( string_push_char w 96 )
    ( string_push_str w `stdlib/core/string.nu` ) ( string_push_char w 96 )
    ( string_push_str w `\n` )
    ( string_push_str w source )
    ( string_push_str w `\n@ __swarmk_main → i {\n` )
    ( string_push_str w `  : i argc ( nurl_argv_count )\n` )
    ( string_push_str w `  ? < argc 3 { ^ 1 } {}\n` )
    ( string_push_str w `  : i lo ( nurl_str_to_int ( nurl_argv_get 1 ) )\n` )
    ( string_push_str w `  : i hi ( nurl_str_to_int ( nurl_argv_get 2 ) )\n` )
    ( string_push_str w `  : ~ i acc ` ) ( string_push_str w ( __red_identity_src op ) ) ( string_push_str w `\n` )
    ( string_push_str w `  : ~ i x lo\n` )
    ( string_push_str w `  ~ < x hi { : i kv ( kernel x ) = acc ` ) ( string_push_str w ( __red_combine_src op ) ) ( string_push_str w ` = x + x 1 }\n` )
    ( string_push_str w `  ( nurl_print_int acc )\n  ^ 0\n}\n` )
    ( string_push_str w `@ main → i { ^ ( __swarmk_main ) }\n` )
    ^ w
}

// The chunk-kind program: main hands the whole sub-range to the kernel in one
// call. dtype 0: `@ kernel i lo i hi → i`, partial printed as a decimal
// integer. dtype 1: `@ kernel i lo i hi → f`, partial printed as its f64 bit
// pattern (same int wire; the coordinator reinterprets).
@ __wrap_kernel_chunk s source i dtype → String {
    : String w ( string_new )
    ( string_push_str w `$ ` ) ( string_push_char w 96 )
    ( string_push_str w `stdlib/core/string.nu` ) ( string_push_char w 96 )
    ? == dtype 1 {
        ( string_push_str w `\n$ ` ) ( string_push_char w 96 )
        ( string_push_str w `stdlib/std/floatbits.nu` ) ( string_push_char w 96 )
    } {}
    ( string_push_str w `\n` )
    ( string_push_str w source )
    ( string_push_str w `\n@ __swarmk_main → i {\n` )
    ( string_push_str w `  : i argc ( nurl_argv_count )\n` )
    ( string_push_str w `  ? < argc 3 { ^ 1 } {}\n` )
    ( string_push_str w `  : i lo ( nurl_str_to_int ( nurl_argv_get 1 ) )\n` )
    ( string_push_str w `  : i hi ( nurl_str_to_int ( nurl_argv_get 2 ) )\n` )
    ? == dtype 1 {
        ( string_push_str w `  ( nurl_print_int ( f64_to_bits ( kernel lo hi ) ) )\n` )
    } {
        ( string_push_str w `  ( nurl_print_int ( kernel lo hi ) )\n` )
    }
    ( string_push_str w `  ^ 0\n}\n` )
    ( string_push_str w `@ main → i { ^ ( __swarmk_main ) }\n` )
    ^ w
}

// The dtype=1 (f64) program. Imports floatbits so the module can print the
// partial as an f64 bit pattern (and synthesize the ±∞ identities).
@ __wrap_kernel_f s source i op → String {
    : String w ( string_new )
    ( string_push_str w `$ ` ) ( string_push_char w 96 )
    ( string_push_str w `stdlib/core/string.nu` ) ( string_push_char w 96 )
    ( string_push_str w `\n$ ` ) ( string_push_char w 96 )
    ( string_push_str w `stdlib/std/floatbits.nu` ) ( string_push_char w 96 )
    ( string_push_str w `\n` )
    ( string_push_str w source )
    ( string_push_str w `\n@ __swarmk_main → i {\n` )
    ( string_push_str w `  : i argc ( nurl_argv_count )\n` )
    ( string_push_str w `  ? < argc 3 { ^ 1 } {}\n` )
    ( string_push_str w `  : i lo ( nurl_str_to_int ( nurl_argv_get 1 ) )\n` )
    ( string_push_str w `  : i hi ( nurl_str_to_int ( nurl_argv_get 2 ) )\n` )
    ( string_push_str w `  : ~ f acc ` ) ( string_push_str w ( __red_identity_src_f op ) ) ( string_push_str w `\n` )
    ( string_push_str w `  : ~ i x lo\n` )
    ( string_push_str w `  ~ < x hi { : f kv ( kernel x ) = acc ` ) ( string_push_str w ( __red_combine_src_f op ) ) ( string_push_str w ` = x + x 1 }\n` )
    ( string_push_str w `  ( nurl_print_int ( f64_to_bits acc ) )\n  ^ 0\n}\n` )
    ( string_push_str w `@ main → i { ^ ( __swarmk_main ) }\n` )
    ^ w
}

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
//
// Local wasmbuilder first. A LOCAL "nurlc failed" is a genuine source
// error and is returned as-is (the build service would only repeat it);
// any other local error means the environment can't build wasm (no
// toolchain, no zig, download forbidden) → fall back to the build API.
@ compile_to_wasm s source → !( Vec u ) String {
    : ~ WbOpts wopts ( wb_opts_default )
    = . wopts opt `-O1`
    = . wopts quiet T
    : !( Vec u ) String lr ( wb_build_source source `kernel.nu` wopts )
    ?? lr {
        T wasm → { ^ @ !( Vec u ) String { T wasm } }
        F le → {
            ? ( string_contains le `nurlc failed` ) { ^ @ !( Vec u ) String { F le } } {}
            // Anything else means this box could not build wasm — say so out
            // loud before falling back. Swallowing it hid a real toolchain bug
            // behind a build-service error for a long time, and the fallback
            // ships the caller's kernel source to a third-party host, which is
            // never something to do silently.
            ( nurl_eprint `swarm-mcp: local wasm build failed: ` )
            ( nurl_eprint ( string_data le ) )
            ( nurl_eprint `\nswarm-mcp: falling back to the build API at ` )
            : String bu ( build_api_url )
            ( nurl_eprintln ( string_data bu ) )
            ( string_free bu )
            : !( Vec u ) String rr ( __compile_via_api source )
            ?? rr {
                T wasm → { ( string_free le ) ^ @ !( Vec u ) String { T wasm } }
                F re → {
                    // Both paths failed: the LOCAL error is the actionable one,
                    // so lead with it and keep the remote note as context.
                    : String both ( string_concat ( string_from `local build failed: ` ) le )
                    ( string_push_str both ` — and the build-service fallback also failed: ` )
                    ( string_push_str both ( string_data re ) )
                    ( string_free re )
                    ^ @ !( Vec u ) String { F both }
                }
            }
        }
    }
    ^ @ !( Vec u ) String { F ( string_from `wasm build failed` ) }
}

// The remote fallback: POST the kernel to <NURL_BUILD_API>/build_wasm.
@ __compile_via_api s source → !( Vec u ) String {
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
    // A build service that hangs must not hang the MCP tool call with it: the
    // library default is a 300 s cap, which an agent experiences as a dead
    // server. 90 s is far past a healthy build (~10 s) and still answerable.
    : !HttpcResp HttpcErr rr ( httpc_request_timeout `POST` ( string_data url ) ( string_data body ) ( string_data hb ) ( __build_api_timeout ) )
    ( string_free body ) ( string_free hb )
    : ~ ! ( Vec u ) String out @ !( Vec u ) String { F ( string_from `internal` ) }
    ?? rr {
        F e → {
            // "could not reach" was wrong for the common case — the service
            // answered the connect and then never finished. Name both.
            : String m ( string_concat ( string_from `the build API at ` ) ( string_concat ( string_from ( string_data url ) ) ( string_from ` did not answer within ` ) ) )
            ( string_push_str m ( nurl_str_int ( __build_api_timeout ) ) )
            ( string_push_str m `s (unreachable, or it accepted the request and never finished)` )
            = out @ !( Vec u ) String { F m }
        }
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
