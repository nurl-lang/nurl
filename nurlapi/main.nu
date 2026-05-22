$ `stdlib/ext/http_full.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/int.nu`

// ── Globals ──────────────────────────────────────────────────────────

@ get_nurlc_path → String { ^ ( env_var_or `NURLC_PATH` `/opt/nurl/build/nurlc` ) }
@ get_stdlib_dir → String { ^ ( env_var_or `NURL_STDLIB_DIR` `/opt/nurl/stdlib` ) }
@ get_output_dir → String { ^ ( env_var_or `NURL_OUTPUT_DIR` `/app/output` ) }
@ get_examples_dir → String { ^ ( env_var_or `NURL_EXAMPLES_DIR` `/opt/nurl/examples` ) }
@ get_link_helper → String { ^ ( env_var_or `NURL_LINK_HELPER` `/opt/nurl/build/nurl-build` ) }
@ get_native_clang → String { ^ ( env_var_or `NURL_NATIVE_CLANG` `clang` ) }
@ get_runtime_wasm_o → String { ^ ( env_var_or `NURL_RUNTIME_WASM_O` `/opt/nurl/stdlib/runtime.wasm.o` ) }
@ get_canvas_wasm_o → String { ^ ( env_var_or `NURL_CANVAS_WASM_O` `/opt/nurl/stdlib/canvas.wasm.o` ) }
@ get_audio_wasm_o → String { ^ ( env_var_or `NURL_AUDIO_WASM_O` `/opt/nurl/stdlib/audio_wasm.o` ) }
@ get_runtime_win_o → String { ^ ( env_var_or `NURL_RUNTIME_WIN_O` `/opt/nurl/stdlib/runtime.win.o` ) }
@ get_runtime_mac_o → String { ^ ( env_var_or `NURL_RUNTIME_MAC_O` `/opt/nurl/stdlib/runtime.mac.o` ) }
@ get_windows_target → String { ^ ( env_var_or `NURL_WINDOWS_TARGET` `x86_64-windows-gnu` ) }
@ get_macos_target → String { ^ ( env_var_or `NURL_MACOS_TARGET` `x86_64-macos-none` ) }
@ get_zig → String { ^ ( env_var_or `NURL_ZIG` `/opt/zig/zig` ) }
@ get_wasm_opt → String { ^ ( env_var_or `WASM_OPT` `wasm-opt` ) }
@ get_work_root → String { ^ ( env_var_or `NURL_WORK_ROOT` `/opt/nurl` ) }
@ get_static_dir → String { ^ ( env_var_or `NURL_STATIC_DIR` `/app/static` ) }

@ get_runtime_native_o → String {
  : String stdlib_dir ( get_stdlib_dir )
  : String path ( path_join ( string_data stdlib_dir ) `runtime.native.o` )
  ( string_free stdlib_dir )
  ^ path
}

@ get_canvas_o → String {
  : String stdlib_dir ( get_stdlib_dir )
  : String path ( path_join ( string_data stdlib_dir ) `canvas.o` )
  ( string_free stdlib_dir )
  ^ path
}

@ get_canvas_sdl2_marker → String {
  : String stdlib_dir ( get_stdlib_dir )
  : String path ( path_join ( string_data stdlib_dir ) `canvas.sdl2` )
  ( string_free stdlib_dir )
  ^ path
}

@ create_build_id → String {
  : i now ( now_ms )
  : i mono ( monotonic_ns )
  : i mono_ms / mono 1000000
  : i suffix - mono * mono_ms 1000000
  : String build_id ( string_with_cap 24 )
  ( string_push_int build_id now )
  ( string_push_char build_id 95 )
  ( string_push_int build_id suffix )
  ^ build_id
}

@ drop_str String s → v { ( string_free s ) }

@ list_stdlib_modules → Json {
  : String sdir ( get_stdlib_dir )
  : ! ( Vec String ) IoErr dr ( dir_list ( string_data sdir ) )
  : Json arr ( json_arr_new )
  ?? dr {
    T files → {
      : ~ i i 0 ~ < i ( vec_len [String] files ) {
        ?? ( vec_get [String] files i ) { T f → {
            ? ( string_ends_with f `.nu` ) { ( json_arr_push arr ( json_str_lit ( string_data f ) ) ) } {}
            : String sub ( path_join ( string_data sdir ) ( string_data f ) )
            ? ( file_exists ( string_data sub ) ) {
               : ! ( Vec String ) IoErr dr2 ( dir_list ( string_data sub ) )
               ?? dr2 { T files2 → {
                   : ~ i j 0 ~ < j ( vec_len [String] files2 ) {
                     ?? ( vec_get [String] files2 j ) { T f2 → {
                         ? ( string_ends_with f2 `.nu` ) {
                           : String rel ( path_join ( string_data f ) ( string_data f2 ) )
                           ( json_arr_push arr ( json_str_lit ( string_data rel ) ) )
                           ( string_free rel )
                         } {}
                     } F → {} } = j + j 1
                   }
                   : ~ i k 0 ~ < k ( vec_len [String] files2 ) { ?? ( vec_get [String] files2 k ) { T fs → ( string_free fs ) F → {} } = k + k 1 } ( vec_free [String] files2 )
               } F _ → {} }
            } {}
            ( string_free sub )
        } F → {} } = i + i 1
      }
      : ~ i k 0 ~ < k ( vec_len [String] files ) { ?? ( vec_get [String] files k ) { T fs → ( string_free fs ) F → {} } = k + k 1 } ( vec_free [String] files )
    } F _ → {}
  }
  ( string_free sdir )
  ^ arr
}

// ── Shared logic ─────────────────────────────────────────────────────

@ get_common_json Json root s key s default → s {
  : ? Json opt ( json_obj_get root key )
  ?? opt { T j → { ^ ( json_str_data j ) } F _ → { ^ default } }
}

@ get_common_bool Json root s key b default → b {
  : ? Json opt ( json_obj_get root key )
  ?? opt { T j → { ^ ( json_bool_val j ) } F _ → { ^ default } }
}

@ get_common_int Json root s key i default → i {
  : ? Json opt ( json_obj_get root key )
  ?? opt {
    T j → {
      : ?i no ( json_num_as_i j )
      ?? no { T n → { ^ n } F → { ^ default } }
    }
    F _ → { ^ default }
  }
}

@ json_str_or_null s str → Json {
  ? == ( nurl_str_len str ) 0 { ^ ( json_null ) } { ^ ( json_str_lit str ) }
}

@ get_body_str HttpRequest req → String {
  : i blen ( vec_len [u] . req body )
  : String body_str ( string_with_cap + blen 1 )
  : ~ i bi 0 ~ < bi blen { : ? u co ( vec_get [u] . req body bi ) ?? co { T c → { ( string_push_char body_str c ) } F → {} } = bi + bi 1 } ( __string_seal body_str )
  ^ body_str
}

@ json_response_owned i status Json j → HttpResponse {
  : String body ( json_stringify j )
  : HttpResponse hr ( response_text status ( string_data body ) )
  ( response_set_header hr `Content-Type` `application/json` )
  ( json_free j )
  ( string_free body )
  ^ hr
}

@ build_download_url String build_id s name → String {
  : String url ( string_with_cap 96 )
  ( string_push_str url `/download/` )
  ( string_push_str url ( string_data build_id ) )
  ( string_push_str url `/` )
  ( string_push_str url name )
  ^ url
}

@ build_artifact_json String build_id s path_raw → Json {
  : String name ( path_basename path_raw )
  : ! i IoErr szr ( file_size path_raw )
  : Json obj ( json_obj_new )
  ( json_obj_set obj `name` ( json_str_lit ( string_data name ) ) )
  ( json_obj_set obj `bytes` ( json_int ?? szr { T s → s F _ → 0 } ) )
  : String url ( build_download_url build_id ( string_data name ) )
  ( json_obj_set obj `download_url` ( json_str_lit ( string_data url ) ) )
  ( string_free name )
  ( string_free url )
  ^ obj
}

@ payload_set_artifact Json payload String build_id s path_key s out_key → v {
  : s path_raw ( get_common_json payload path_key `` )
  ? > ( nurl_str_len path_raw ) 0 {
    : Json art ( build_artifact_json build_id path_raw )
    ( json_obj_set payload out_key art )
  } {}
}

@ helper_detail Json payload → String {
  : String out ( string_from ( get_common_json payload `fatal_detail` `` ) )
  ? == ( string_len out ) 0 {
    ( string_free out )
    = out ( string_from ( get_common_json payload `error_message` `` ) )
  } {}
  ? == ( string_len out ) 0 {
    ( string_free out )
    = out ( string_from ( get_common_json payload `stderr` `` ) )
  } {}
  ? == ( string_len out ) 0 {
    ( string_free out )
    = out ( string_from ( get_common_json payload `message` `` ) )
  } {}
  ^ out
}

// ── Build handler (Native Linux) ─────────────────────────────────────

@ free_build_target_cfg String driver String runtime String target String canvas_obj String canvas_marker → v {
  ( string_free driver )
  ( string_free runtime )
  ( string_free target )
  ( string_free canvas_obj )
  ( string_free canvas_marker )
}

@ h_build_target HttpRequest req s kind String driver String runtime String target String canvas_obj String canvas_marker → HttpResponse {
  : String body_str ( get_body_str req )
  : ! Json ParseErr root_res ( json_parse ( string_data body_str ) )
  ?? root_res {
    T root → {
      : s source ( get_common_json root `source` `` )
      ? == ( nurl_str_len source ) 0 {
        ( free_build_target_cfg driver runtime target canvas_obj canvas_marker )
        ( json_free root ) ( string_free body_str )
        ^ ( response_text 400 `{"error":"source is required"}\n` )
      } {}
      : s filename ( get_common_json root `filename` `main.nu` )
      : s opt ( get_common_json root `opt` `-O2` )

      : String build_id ( create_build_id )
      : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )

      : ! v IoErr dr ( dir_create ( string_data build_dir ) )
      ?? dr {
        T _ → {
          : String nu_path ( path_join ( string_data build_dir ) filename )
          ( write_file ( string_data nu_path ) source )
          : String helper_path ( get_link_helper )
          : String work_root ( get_work_root )
          : ( Vec s ) helper_args ( vec_new [s] )
          ( vec_push [s] helper_args `api-build` )
          ( vec_push [s] helper_args `--kind` ) ( vec_push [s] helper_args kind )
          ( vec_push [s] helper_args `--root` ) ( vec_push [s] helper_args ( string_data work_root ) )
          ( vec_push [s] helper_args `--src` ) ( vec_push [s] helper_args ( string_data nu_path ) )
          ( vec_push [s] helper_args `--build-dir` ) ( vec_push [s] helper_args ( string_data build_dir ) )
          ( vec_push [s] helper_args `--driver` ) ( vec_push [s] helper_args ( string_data driver ) )
          ( vec_push [s] helper_args `--runtime` ) ( vec_push [s] helper_args ( string_data runtime ) )
          ( vec_push [s] helper_args `--opt` ) ( vec_push [s] helper_args opt )
          ( vec_push [s] helper_args `--filename` ) ( vec_push [s] helper_args filename )
          ? > ( string_len target ) 0 {
            ( vec_push [s] helper_args `--target` ) ( vec_push [s] helper_args ( string_data target ) )
          } {}
          ? > ( string_len canvas_obj ) 0 {
            ( vec_push [s] helper_args `--canvas-obj` ) ( vec_push [s] helper_args ( string_data canvas_obj ) )
          } {}
          ? > ( string_len canvas_marker ) 0 {
            ( vec_push [s] helper_args `--canvas-sdl2-marker` ) ( vec_push [s] helper_args ( string_data canvas_marker ) )
          } {}

          : ! Output ProcessErr helper_res ( process_run ( string_data helper_path ) helper_args `` )
          ( vec_free [s] helper_args )
          ?? helper_res {
            T h_out → {
              : i helper_rc ( output_exit_code h_out )
              ? != helper_rc 0 {
                : String detail ( string_from ( output_stderr h_out ) )
                ? == ( string_len detail ) 0 { ( string_free detail ) = detail ( string_from ( output_stdout h_out ) ) } {}
                : HttpResponse hr ( response_text 500 ( string_data detail ) )
                ( string_free detail )
                ( output_free h_out )
                ( string_free helper_path ) ( string_free work_root )
                ( string_free nu_path ) ( string_free build_id ) ( string_free build_dir )
                ( json_free root ) ( string_free body_str )
                ( free_build_target_cfg driver runtime target canvas_obj canvas_marker )
                ^ hr
              } {}

              : ! Json ParseErr payload_res ( json_parse ( output_stdout h_out ) )
              ?? payload_res {
                T payload → {
                  : i http_status ( get_common_int payload `http_status` 200 )
                  ( payload_set_artifact payload build_id `ll_path` `ll_artifact` )
                  ( payload_set_artifact payload build_id `binary_path` `binary_artifact` )
                  ? == http_status 200 {
                    ( json_obj_set payload `nurlc_stdout` ( json_str_lit `[nurlc] build successful` ) )
                  } {}
                  : HttpResponse hr ( json_response_owned http_status payload )
                  ( output_free h_out )
                  ( string_free helper_path ) ( string_free work_root )
                  ( string_free nu_path ) ( string_free build_id ) ( string_free build_dir )
                  ( json_free root ) ( string_free body_str )
                  ( free_build_target_cfg driver runtime target canvas_obj canvas_marker )
                  ^ hr
                }
                F _ → {
                  : HttpResponse hr ( response_text 500 `{"error":"helper returned invalid json"}\n` )
                  ( output_free h_out )
                  ( string_free helper_path ) ( string_free work_root )
                  ( string_free nu_path ) ( string_free build_id ) ( string_free build_dir )
                  ( json_free root ) ( string_free body_str )
                  ( free_build_target_cfg driver runtime target canvas_obj canvas_marker )
                  ^ hr
                }
              }
            }
            F _ → {
              : HttpResponse hr ( response_text 500 `{"error":"build helper process failed"}\n` )
              ( string_free helper_path ) ( string_free work_root )
              ( string_free nu_path ) ( string_free build_id ) ( string_free build_dir )
              ( json_free root ) ( string_free body_str )
              ( free_build_target_cfg driver runtime target canvas_obj canvas_marker )
              ^ hr
            }
          }
        }
        F _ → {
          ( free_build_target_cfg driver runtime target canvas_obj canvas_marker )
          ( json_free root ) ( string_free build_id ) ( string_free build_dir ) ( string_free body_str )
          ^ ( response_text 500 `{"error":"could not create build dir"}\n` )
        }
      }
    }
    F err → {
      ( free_build_target_cfg driver runtime target canvas_obj canvas_marker )
      ( string_free body_str )
      ^ ( response_text 400 `{"error":"invalid json"}\n` )
    }
  }
}

@ h_build HttpRequest req Params params → HttpResponse {
  ( nurl_print `[srv] POST /build\n` )
  : String driver ( get_native_clang )
  : String runtime ( get_runtime_native_o )
  : String target ( string_new )
  : String canvas_obj ( get_canvas_o )
  : String canvas_marker ( get_canvas_sdl2_marker )
  ^ ( h_build_target req `native` driver runtime target canvas_obj canvas_marker )
}

// ── Build handler (WASM) ─────────────────────────────────────────────

@ free_build_wasm_cfg String helper_path String work_root String runtime_wasm String canvas_wasm String audio_wasm String zig_driver String wasm_opt → v {
  ( string_free helper_path )
  ( string_free work_root )
  ( string_free runtime_wasm )
  ( string_free canvas_wasm )
  ( string_free audio_wasm )
  ( string_free zig_driver )
  ( string_free wasm_opt )
}

@ h_build_wasm HttpRequest req Params params → HttpResponse {
  ( nurl_print `[srv] POST /build_wasm\n` )
  : String body_str ( get_body_str req )
  : ! Json ParseErr root_res ( json_parse ( string_data body_str ) )
  ?? root_res {
    T root → {
      : s source ( get_common_json root `source` `` )
      ? == ( nurl_str_len source ) 0 { ( json_free root ) ( string_free body_str ) ^ ( response_text 400 `{"error":"source is required"}\n` ) } {}
      : s filename ( get_common_json root `filename` `main.nu` )
      : b emit_ll ( get_common_bool root `emit_ll` F )

      : String build_id ( create_build_id )
      : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )

      : ! v IoErr dr ( dir_create ( string_data build_dir ) )
      ?? dr {
        T _ → {
          : String nu_path ( path_join ( string_data build_dir ) filename )
          ( write_file ( string_data nu_path ) source )
          : String helper_path ( get_link_helper )
          : String work_root ( get_work_root )
          : String runtime_wasm ( get_runtime_wasm_o )
          : String canvas_wasm ( get_canvas_wasm_o )
          : String audio_wasm ( get_audio_wasm_o )
          : String zig ( get_zig )
          : String zig_driver ( string_from ( string_data zig ) )
          ( string_push_str zig_driver ` cc` )
          ( string_free zig )
          : String wasm_opt ( get_wasm_opt )

          : ( Vec s ) helper_args ( vec_new [s] )
          ( vec_push [s] helper_args `api-build-wasm` )
          ( vec_push [s] helper_args `--root` ) ( vec_push [s] helper_args ( string_data work_root ) )
          ( vec_push [s] helper_args `--src` ) ( vec_push [s] helper_args ( string_data nu_path ) )
          ( vec_push [s] helper_args `--build-dir` ) ( vec_push [s] helper_args ( string_data build_dir ) )
          ( vec_push [s] helper_args `--target` ) ( vec_push [s] helper_args `wasm32-wasi` )
          ( vec_push [s] helper_args `--runtime` ) ( vec_push [s] helper_args ( string_data runtime_wasm ) )
          ( vec_push [s] helper_args `--canvas-obj` ) ( vec_push [s] helper_args ( string_data canvas_wasm ) )
          ( vec_push [s] helper_args `--audio-obj` ) ( vec_push [s] helper_args ( string_data audio_wasm ) )
          ( vec_push [s] helper_args `--zig-driver` ) ( vec_push [s] helper_args ( string_data zig_driver ) )
          ( vec_push [s] helper_args `--wasm-opt` ) ( vec_push [s] helper_args ( string_data wasm_opt ) )
          ( vec_push [s] helper_args `--filename` ) ( vec_push [s] helper_args filename )

          : ! Output ProcessErr helper_res ( process_run ( string_data helper_path ) helper_args `` )
          ( vec_free [s] helper_args )
          ?? helper_res {
            T h_out → {
              : i helper_rc ( output_exit_code h_out )
              ? != helper_rc 0 {
                : String detail ( string_from ( output_stderr h_out ) )
                ? == ( string_len detail ) 0 { ( string_free detail ) = detail ( string_from ( output_stdout h_out ) ) } {}
                : HttpResponse hr ( response_text 500 ( string_data detail ) )
                ( string_free detail )
                ( output_free h_out )
                ( free_build_wasm_cfg helper_path work_root runtime_wasm canvas_wasm audio_wasm zig_driver wasm_opt )
                ( string_free nu_path ) ( string_free build_id ) ( string_free build_dir )
                ( json_free root ) ( string_free body_str )
                ^ hr
              } {}

              : ! Json ParseErr payload_res ( json_parse ( output_stdout h_out ) )
              ?? payload_res {
                T payload → {
                  : i http_status ( get_common_int payload `http_status` 200 )
                  ? == http_status 200 {
                    : s wasm_path_raw ( get_common_json payload `wasm_path` `` )
                    ? > ( nurl_str_len wasm_path_raw ) 0 {
                      : ! i IoErr wasm_size_res ( file_size wasm_path_raw )
                      : i w_bytes ?? wasm_size_res { T s → s F _ → 0 }
                      ( json_obj_set payload `wasm_bytes` ( json_int w_bytes ) )
                      : ! ( Vec u ) IoErr wasm_data_res ( read_file_bytes wasm_path_raw )
                      ?? wasm_data_res {
                        T w_data → {
                          : String b64 ( b64_encode_vec w_data )
                          ( json_obj_set payload `wasm_base64` ( json_str_lit ( string_data b64 ) ) )
                          ( vec_free [u] w_data ) ( string_free b64 )
                        }
                        F _ → { ( json_obj_set payload `wasm_base64` ( json_null ) ) }
                      }
                      : String wasm_name ( path_basename wasm_path_raw )
                      : String wasm_url ( build_download_url build_id ( string_data wasm_name ) )
                      ( json_obj_set payload `download_url` ( json_str_lit ( string_data wasm_url ) ) )
                      ( string_free wasm_name ) ( string_free wasm_url )
                    } {}
                    ? emit_ll {
                      : s ll_path_raw ( get_common_json payload `prepared_ll_path` `` )
                      ? > ( nurl_str_len ll_path_raw ) 0 {
                        : ! String IoErr ll_res ( read_file ll_path_raw )
                        ?? ll_res { T ll_text → {
                            ( json_obj_set payload `llvm_ir` ( json_str_lit ( string_data ll_text ) ) )
                            ( string_free ll_text )
                        } F _ → { ( json_obj_set payload `llvm_ir` ( json_null ) ) } }
                      } { ( json_obj_set payload `llvm_ir` ( json_null ) ) } 
                    } { ( json_obj_set payload `llvm_ir` ( json_null ) ) } 
                    ( json_obj_set payload `nurlc_errors` ( json_arr_new ) )
                  } {}
                  : HttpResponse hr ( json_response_owned http_status payload )
                  ( output_free h_out )
                  ( free_build_wasm_cfg helper_path work_root runtime_wasm canvas_wasm audio_wasm zig_driver wasm_opt )
                  ( string_free nu_path ) ( string_free build_id ) ( string_free build_dir )
                  ( json_free root ) ( string_free body_str )
                  ^ hr
                }
                F _ → {
                  : HttpResponse hr ( response_text 500 `{"error":"helper returned invalid json"}\n` )
                  ( output_free h_out )
                  ( free_build_wasm_cfg helper_path work_root runtime_wasm canvas_wasm audio_wasm zig_driver wasm_opt )
                  ( string_free nu_path ) ( string_free build_id ) ( string_free build_dir )
                  ( json_free root ) ( string_free body_str )
                  ^ hr
                }
              }
            }
            F _ → {
              : HttpResponse hr ( response_text 500 `{"error":"build helper process failed"}\n` )
              ( free_build_wasm_cfg helper_path work_root runtime_wasm canvas_wasm audio_wasm zig_driver wasm_opt )
              ( string_free nu_path ) ( string_free build_id ) ( string_free build_dir )
              ( json_free root ) ( string_free body_str )
              ^ hr
            }
          }
        }
        F _ → { ^ ( response_text 500 `{"error":"could not create build dir"}\n` ) }
      }
    }
    F err → { ^ ( response_text 400 `{"error":"invalid json"}\n` ) }
  }
}

// ── Build handler (Windows) ──────────────────────────────────────────

@ h_build_windows HttpRequest req Params params → HttpResponse {
  ( nurl_print `[srv] POST /build_windows\n` )
  : String zig ( get_zig )
  : String driver ( string_from ( string_data zig ) )
  ( string_push_str driver ` cc` )
  ( string_free zig )
  : String runtime ( get_runtime_win_o )
  : String target ( get_windows_target )
  : String canvas_obj ( string_new )
  : String canvas_marker ( string_new )
  ^ ( h_build_target req `windows` driver runtime target canvas_obj canvas_marker )
}

// ── Build handler (macOS) ────────────────────────────────────────────

@ h_build_macos HttpRequest req Params params → HttpResponse {
  ( nurl_print `[srv] POST /build_macos\n` )
  : String zig ( get_zig )
  : String driver ( string_from ( string_data zig ) )
  ( string_push_str driver ` cc` )
  ( string_free zig )
  : String runtime ( get_runtime_mac_o )
  : String target ( get_macos_target )
  : String canvas_obj ( string_new )
  : String canvas_marker ( string_new )
  ^ ( h_build_target req `macos` driver runtime target canvas_obj canvas_marker )
}

// ── Examples handler ────────────────────────────────────────────────

@ h_examples HttpRequest req Params params → HttpResponse {
  ( nurl_print `[srv] GET /examples\n` )
  : String edir ( get_examples_dir )
  : ! ( Vec String ) IoErr dr ( dir_list ( string_data edir ) )
  ?? dr {
    T files → {
      : Json arr ( json_arr_new )
      : ~ i i 0 ~ < i ( vec_len [String] files ) {
        : ? String fs_opt ( vec_get [String] files i )
        ?? fs_opt { T f → { ? ( string_ends_with f `.nu` ) { : String fpath ( path_join ( string_data edir ) ( string_data f ) ) : ! i IoErr szr ( file_size ( string_data fpath ) ) : Json obj ( json_obj_new ) ( json_obj_set obj `name` ( json_str_lit ( string_data f ) ) ) ( json_obj_set obj `path` ( json_str_lit ( string_data f ) ) ) ( json_obj_set obj `bytes` ( json_int ?? szr { T s → s F _ → 0 } ) ) ( json_arr_push arr obj ) ( string_free fpath ) } {} } F → {} }
        = i + i 1
      }
      : String body ( json_stringify arr )
      : HttpResponse res ( response_text 200 ( string_data body ) ) ( response_set_header res `Content-Type` `application/json` )
      ( json_free arr )
      : ~ i k 0 ~ < k ( vec_len [String] files ) { ?? ( vec_get [String] files k ) { T fs → ( string_free fs ) F → {} } = k + k 1 } ( vec_free [String] files ) ( string_free edir ) ( string_free body )
      ^ res
    }
    F _ → { ( string_free edir ) ^ ( response_text 500 `{"error":"could not list examples"}\n` ) }
  }
}

@ h_get_example HttpRequest req Params params → HttpResponse {
  ( nurl_print `[srv] GET /examples/` )
  ?? ( params_get params `name` ) { T n → { ( nurl_print ( string_data n ) ) ( string_free n ) } F → {} }
  ( nurl_print `\n` )
  : ? String name_opt ( params_get params `name` )
  ?? name_opt { T name → {
      : String edir ( get_examples_dir )
      : String fpath ( path_join ( string_data edir ) ( string_data name ) )
      : ! String IoErr cr ( read_file ( string_data fpath ) )
      ?? cr {
        T source → {
          : Json obj ( json_obj_new ) ( json_obj_set obj `name` ( json_str_lit ( string_data name ) ) ) ( json_obj_set obj `source` ( json_str_lit ( string_data source ) ) ) ( json_obj_set obj `bytes` ( json_int ( string_len source ) ) )
          : String body ( json_stringify obj )
          : HttpResponse hr ( response_text 200 ( string_data body ) ) ( response_set_header hr `Content-Type` `application/json` )
          ( json_free obj ) ( string_free source ) ( string_free edir ) ( string_free fpath ) ( string_free name ) ( string_free body )
          ^ hr }
        F _ → { ( string_free edir ) ( string_free fpath ) ( string_free name ) ^ ( response_text 404 `{"error":"example not found"}\n` ) } } }
    F _ → { ^ ( response_text 400 `{"error":"missing example name"}\n` ) } }
}

// ── Health, MCP, Download ────────────────────────────────────────────

@ h_health HttpRequest req Params params → HttpResponse {
  ( nurl_print `[srv] GET /health\n` )
  : String nurlc_path ( get_nurlc_path )
  : String stdlib_dir ( get_stdlib_dir )
  : String link_helper ( get_link_helper )
  : String runtime_wasm ( get_runtime_wasm_o )
  : String zig ( get_zig )
  : Json j ( json_obj_new )
  ( json_obj_set j `status` ( json_str_lit `ok` ) )
  ( json_obj_set j `nurlc_available` ( json_bool ( file_exists ( string_data nurlc_path ) ) ) )
  ( json_obj_set j `nurlc_path` ( json_str_lit ( string_data nurlc_path ) ) )
  ( json_obj_set j `link_helper_available` ( json_bool ( file_exists ( string_data link_helper ) ) ) )
  ( json_obj_set j `link_helper_path` ( json_str_lit ( string_data link_helper ) ) )
  ( json_obj_set j `wasi_toolchain_available` ( json_bool & ( file_exists ( string_data link_helper ) ) | ( file_exists ( string_data runtime_wasm ) ) ( file_exists ( string_data zig ) ) ) )
  ( json_obj_set j `stdlib_available` ( json_bool ( file_exists ( string_data stdlib_dir ) ) ) )
  ( json_obj_set j `stdlib_dir` ( json_str_lit ( string_data stdlib_dir ) ) )
  ( json_obj_set j `stdlib_modules` ( list_stdlib_modules ) )
  
  : String body ( json_stringify j )
  : HttpResponse r ( response_text 200 ( string_data body ) ) ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
  ( json_free j ) ( string_free nurlc_path ) ( string_free stdlib_dir ) ( string_free link_helper ) ( string_free runtime_wasm ) ( string_free zig ) ( string_free body )
  ^ r
}

@ h_mcp_info HttpRequest req Params params → HttpResponse {
  : Json j ( json_obj_new ) ( json_obj_set j `mcp_version` ( json_str_lit `1.0.0` ) ) ( json_obj_set j `server_name` ( json_str_lit `nurl-native-api` ) ) ( json_obj_set j `server_version` ( json_str_lit `0.1.0` ) )
  : String body ( json_stringify j )
  : HttpResponse r ( response_text 200 ( string_data body ) ) ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
  ( json_free j ) ( string_free body )
  ^ r
}

@ h_download HttpRequest req Params params → HttpResponse {
  : ? String bid_opt ( params_get params `build_id` ) : ? String fname_opt ( params_get params `filename` )
  ?? bid_opt { T bid → { ?? fname_opt { T fname → { : String out_dir_base ( get_output_dir ) : String build_dir ( path_join ( string_data out_dir_base ) ( string_data bid ) ) : HttpResponse res ( serve_static ( string_data build_dir ) req ) ( string_free bid ) ( string_free fname ) ( string_free out_dir_base ) ( string_free build_dir ) ^ res } F _ → { ( string_free bid ) ^ ( response_text 400 `{"error":"filename missing"}\n` ) } } } F _ → { ^ ( response_text 400 `{"error":"build_id missing"}\n` ) } }
}

@ h_static HttpRequest req Params params → HttpResponse {
  : String sdir ( get_static_dir )
  : HttpResponse res ( serve_static ( string_data sdir ) req )
  ( string_free sdir )
  ^ res
}

// ─── String-direct variants (no Params) ────────────────────────────────
// The Vec[Route]/Vec[QueryPair] multi-field-struct stride bug manifests
// under Linux + pthread + clang -O2 (even-indexed slots read into thread
// stack regions). To stay threadsafe we bypass Params and route
// dispatch manually, passing captured path segments as plain Strings.

@ h_get_example_for HttpRequest req String name → HttpResponse {
  ( nurl_print `[srv] GET /examples/` )
  ( nurl_print ( string_data name ) )
  ( nurl_print `\n` )
  : String edir ( get_examples_dir )
  : String fpath ( path_join ( string_data edir ) ( string_data name ) )
  : ! String IoErr cr ( read_file ( string_data fpath ) )
  ?? cr {
    T source → {
      : Json obj ( json_obj_new )
      ( json_obj_set obj `name` ( json_str_lit ( string_data name ) ) )
      ( json_obj_set obj `source` ( json_str_lit ( string_data source ) ) )
      ( json_obj_set obj `bytes` ( json_int ( string_len source ) ) )
      : String body ( json_stringify obj )
      : HttpResponse hr ( response_text 200 ( string_data body ) )
      ( response_set_header hr `Content-Type` `application/json` )
      ( json_free obj ) ( string_free source ) ( string_free edir ) ( string_free fpath ) ( string_free body )
      ^ hr
    }
    F _ → {
      ( string_free edir ) ( string_free fpath )
      ^ ( response_text 404 `{"error":"example not found"}\n` )
    }
  }
}

@ h_download_for HttpRequest req String build_id String filename → HttpResponse {
  ( nurl_print `[srv] GET /download/` )
  ( nurl_print ( string_data build_id ) )
  ( nurl_print `/` )
  ( nurl_print ( string_data filename ) )
  ( nurl_print `\n` )
  : String out_dir_base ( get_output_dir )
  : String build_dir ( path_join ( string_data out_dir_base ) ( string_data build_id ) )
  : HttpResponse res ( serve_static ( string_data build_dir ) req )
  ( string_free out_dir_base ) ( string_free build_dir )
  ^ res
}

@ h_static_for HttpRequest req String tail → HttpResponse {
  ? ( __has_dotdot_segment ( string_data tail ) ) {
    ^ ( response_text 403 `forbidden\n` )
  } {}
  : String full ( path_join `static` ( string_data tail ) )
  : ! ( Vec u ) IoErr rd ( read_file_bytes ( string_data full ) )
  ?? rd {
    T body → {
      : String ext ( path_extension ( string_data full ) )
      : s mime ( mime_for_ext ( string_data ext ) )
      ( string_free ext ) ( string_free full )
      : HttpResponse r ( response_new 200 )
      ( response_set_header r `Content-Type` mime )
      ( response_set_body_bytes r body )
      ( vec_free [u] body )
      ^ r
    }
    F _ → { ( string_free full ) ^ ( response_text 404 `not found\n` ) }
  }
}

// Manual dispatcher — uses ONLY string compares + substring extraction.
// No Vec[Route], no Params, no closures stored in heap-Vec — so it
// avoids the multi-field-Vec stride bug that hits Linux/pthread builds.
@ manual_dispatch HttpRequest req → HttpResponse {
  : String mtmp ( string_from ( string_data . req method ) )
  : String ptmp ( string_from ( string_data . req path ) )
  : b is_get  ( string_eq mtmp ( string_from `GET`  ) )
  : b is_post ( string_eq mtmp ( string_from `POST` ) )

  // ── POST routes (build endpoints) ──
  ? & is_post ( string_eq ptmp ( string_from `/build` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_build req ( params_new ) )
  } {}
  ? & is_post ( string_eq ptmp ( string_from `/build_wasm` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_build_wasm req ( params_new ) )
  } {}
  ? & is_post ( string_eq ptmp ( string_from `/build_windows` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_build_windows req ( params_new ) )
  } {}
  ? & is_post ( string_eq ptmp ( string_from `/build_macos` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_build_macos req ( params_new ) )
  } {}

  // ── GET literal routes ──
  ? & is_get ( string_eq ptmp ( string_from `/health` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_health req ( params_new ) )
  } {}
  ? & is_get ( string_eq ptmp ( string_from `/mcp-info` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_mcp_info req ( params_new ) )
  } {}
  ? & is_get ( string_eq ptmp ( string_from `/examples` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_examples req ( params_new ) )
  } {}
  ? & is_get ( string_eq ptmp ( string_from `/favicon.ico` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_favicon req ( params_new ) )
  } {}
  ? & is_get ( string_eq ptmp ( string_from `/favicon.svg` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_favicon req ( params_new ) )
  } {}
  ? & is_get ( string_eq ptmp ( string_from `/` ) ) {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_static req ( params_new ) )
  } {}

  // ── GET wildcard routes (substring tail extraction) ──
  // /examples/<name>
  ? & is_get ( string_starts_with ptmp `/examples/` ) {
    : i plen ( string_len ptmp )
    : String name ( string_substr ptmp 10 - plen 10 )
    ( string_free mtmp ) ( string_free ptmp )
    : HttpResponse res ( h_get_example_for req name )
    ( string_free name )
    ^ res
  } {}

  // /download/<build_id>/<filename>
  ? & is_get ( string_starts_with ptmp `/download/` ) {
    : i plen ( string_len ptmp )
    : String tail ( string_substr ptmp 10 - plen 10 )
    : ? i slash ( string_index_of tail `/` )
    ( string_free mtmp )
    ?? slash {
      T sx → {
        : i tlen ( string_len tail )
        : String build_id ( string_substr tail 0 sx )
        : String fname    ( string_substr tail + sx 1 - - tlen sx 1 )
        ( string_free tail ) ( string_free ptmp )
        : HttpResponse res ( h_download_for req build_id fname )
        ( string_free build_id ) ( string_free fname )
        ^ res
      }
      F _ → {
        ( string_free tail ) ( string_free ptmp )
        ^ ( response_text 400 `{"error":"download path malformed"}\n` )
      }
    }
  } {}

  // /static/<path>
  ? & is_get ( string_starts_with ptmp `/static/` ) {
    : i plen ( string_len ptmp )
    : String tail ( string_substr ptmp 8 - plen 8 )
    ( string_free mtmp ) ( string_free ptmp )
    : HttpResponse res ( h_static_for req tail )
    ( string_free tail )
    ^ res
  } {}

  // ── Catch-all GET → serve from `static/` ──
  ? is_get {
    ( string_free mtmp ) ( string_free ptmp )
    ^ ( h_static req ( params_new ) )
  } {}

  // ── Fallback ──
  ( string_free mtmp ) ( string_free ptmp )
  ^ ( response_text 404 `not found\n` )
}

@ h_favicon HttpRequest req Params params → HttpResponse {
  : String sdir ( get_static_dir )
  : String fp ( path_join ( string_data sdir ) `favicon.svg` )
  : ! ( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
  ( string_free sdir ) ( string_free fp )
  ?? rd {
    T body → {
      : HttpResponse r ( response_new 200 )
      ( response_set_header r `Content-Type` `image/svg+xml` )
      ( response_set_body_bytes r body )
      ( vec_free [u] body )
      ^ r
    }
    F _ → { ^ ( response_text 404 `not found\n` ) }
  }
}

// Serves /static/*path by stripping the `/static/` prefix and joining the
// remainder against the local `static/` directory. Without this, hitting
// `/static/favicon.svg` would resolve to `static/static/favicon.svg`.
@ h_static_prefixed HttpRequest req Params params → HttpResponse {
  : ? String tail_opt ( params_get params `path` )
  ?? tail_opt {
    T tail → {
      ? ( __has_dotdot_segment ( string_data tail ) ) {
        ( string_free tail )
        ^ ( response_text 403 `forbidden\n` )
      } {}
      : String sdir ( get_static_dir )
      : String full ( path_join ( string_data sdir ) ( string_data tail ) )
      ( string_free sdir ) ( string_free tail )
      : ! ( Vec u ) IoErr rd ( read_file_bytes ( string_data full ) )
      ?? rd {
        T body → {
          : String ext ( path_extension ( string_data full ) )
          : s mime ( mime_for_ext ( string_data ext ) )
          ( string_free ext )
          ( string_free full )
          : HttpResponse r ( response_new 200 )
          ( response_set_header r `Content-Type` mime )
          ( response_set_body_bytes r body )
          ( vec_free [u] body )
          ^ r
        }
        F _ → { ( string_free full ) ^ ( response_text 404 `not found\n` ) }
      }
    }
    F _ → { ^ ( response_text 400 `{"error":"path missing"}\n` ) }
  }
}

@ main → i {
  // Anchor the process at NURL_WORK_ROOT so that nurlc subprocesses inherit
  // a cwd from which `$ "stdlib/std/time.nu"`-style imports resolve. NURL's
  // `process_run` doesn't yet support per-child cwd override (MVP scope),
  // so we set it once for the whole server. Static-file handlers explicitly
  // use the absolute NURL_STATIC_DIR path to compensate.
  : String wr ( get_work_root )
  : ! v IoErr cdr ( env_chdir ( string_data wr ) )
  ?? cdr {
    T _ → {
      ( nurl_print `[boot] cwd → ` ) ( nurl_print ( string_data wr ) ) ( nurl_print `\n` )
    }
    F _ → {
      ( nurl_eprint `[boot] WARN: failed to chdir to ` ) ( nurl_eprint ( string_data wr ) )
      ( nurl_eprint ` — stdlib imports in nurlc may fail\n` )
    }
  }
  ( string_free wr )

  : ! TcpListener NetErr lr ( tcp_listen `0.0.0.0` 8000 )
  ?? lr {
    T listener → {
      : Router r ( router_new )
      ( router_post r `/build`         \ HttpRequest req Params params → HttpResponse { ^ ( h_build         req params ) } )
      ( router_post r `/build_wasm`    \ HttpRequest req Params params → HttpResponse { ^ ( h_build_wasm    req params ) } )
      ( router_post r `/build_windows` \ HttpRequest req Params params → HttpResponse { ^ ( h_build_windows req params ) } )
      ( router_post r `/build_macos`   \ HttpRequest req Params params → HttpResponse { ^ ( h_build_macos   req params ) } )
      ( router_get  r `/download/:build_id/:filename` \ HttpRequest req Params params → HttpResponse { ^ ( h_download req params ) } )
      ( router_get  r `/examples`        \ HttpRequest req Params params → HttpResponse { ^ ( h_examples    req params ) } )
      ( router_get  r `/examples/*name`  \ HttpRequest req Params params → HttpResponse { ^ ( h_get_example req params ) } )
      ( router_get  r `/health`          \ HttpRequest req Params params → HttpResponse { ^ ( h_health      req params ) } )
      ( router_get  r `/mcp-info`        \ HttpRequest req Params params → HttpResponse { ^ ( h_mcp_info    req params ) } )
      ( router_get  r `/favicon.ico`     \ HttpRequest req Params params → HttpResponse { ^ ( h_favicon     req params ) } )
      ( router_get  r `/favicon.svg`     \ HttpRequest req Params params → HttpResponse { ^ ( h_favicon     req params ) } )
      ( router_get  r `/static/*path`    \ HttpRequest req Params params → HttpResponse { ^ ( h_static_prefixed req params ) } )
      ( router_get  r `/`                \ HttpRequest req Params params → HttpResponse { ^ ( h_static      req params ) } )
      ( router_get  r `/*path`           \ HttpRequest req Params params → HttpResponse { ^ ( h_static      req params ) } )

      : ( @ HttpResponse HttpRequest ) base \ HttpRequest req → HttpResponse { ^ ( router_handle r req ) }
      : ( @ HttpResponse HttpRequest ) logged ( with_access_log base )
      ( signal_install_shutdown listener )

      // Worker count is overridable so we can A/B test threading vs sequential.
      : String wkstr ( env_var_or `NURL_WORKERS` `16` )
      : i workers ?? ( int_parse ( string_data wkstr ) ) { T n → n F _ → 16 }
      ( string_free wkstr )

      ( nurl_print `[boot] registered routes: ` ) ( nurl_print ( nurl_str_int ( router_count r ) ) ) ( nurl_print `\n` )
      ( nurl_print `NURL API listening on http://0.0.0.0:8000/ (workers=` )
      ( nurl_print ( nurl_str_int workers ) )
      ( nurl_print `, idle=5000ms)\n` )
      : HttpServer srv ( server_new_with_timeout listener logged 5000 )
      : ! v NetErr rr ( server_run_pool srv workers )
      ( signal_clear_shutdown ) ( server_stop srv ) ( router_free r )
      ?? rr { T _ → { ^ 0 } F e → { ( nurl_eprint `[srv] runtime error: ` ) ( nurl_eprint ( net_err_name e ) ) ( nurl_eprint `\n` ) ^ 1 } }
    }
    F e → { ( nurl_eprint `[boot] could not bind 0.0.0.0:8000: ` ) ( nurl_eprint ( net_err_name e ) ) ( nurl_eprint `\n` ) ^ 1 }
  }
}
