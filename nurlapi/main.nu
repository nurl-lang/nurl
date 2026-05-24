$ `stdlib/ext/http_full.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/int.nu`
$ `stdlib/ext/regex.nu`

// ── Globals ──────────────────────────────────────────────────────────

@ get_nurlc_path → String { ^ ( env_var_or `NURLC_PATH` `/opt/nurl/build/nurlc` ) }
@ get_stdlib_dir → String { ^ ( env_var_or `NURL_STDLIB_DIR` `/opt/nurl/stdlib` ) }
@ get_output_dir → String { ^ ( env_var_or `NURL_OUTPUT_DIR` `/app/output` ) }
@ get_examples_dir → String { ^ ( env_var_or `NURL_EXAMPLES_DIR` `/opt/nurl/examples` ) }
@ get_wasi_clang → String { ^ ( env_var_or `WASI_CLANG` `/opt/wasi-sdk/bin/clang` ) }
@ get_runtime_wasm_o → String { ^ ( env_var_or `NURL_RUNTIME_WASM_O` `/opt/nurl/stdlib/runtime.wasm.o` ) }
@ get_canvas_wasm_o → String { ^ ( env_var_or `NURL_CANVAS_WASM_O` `/opt/nurl/stdlib/canvas.wasm.o` ) }
@ get_audio_wasm_o → String { ^ ( env_var_or `NURL_AUDIO_WASM_O` `/opt/nurl/stdlib/audio_wasm.o` ) }
@ get_runtime_win_o → String { ^ ( env_var_or `NURL_RUNTIME_WIN_O` `/opt/nurl/stdlib/runtime.win.o` ) }
@ get_runtime_mac_o → String { ^ ( env_var_or `NURL_RUNTIME_MAC_O` `/opt/nurl/stdlib/runtime.mac.o` ) }
@ get_zig → String { ^ ( env_var_or `NURL_ZIG` `/opt/zig/zig` ) }
@ get_work_root → String { ^ ( env_var_or `NURL_WORK_ROOT` `/opt/nurl` ) }
@ get_static_dir → String { ^ ( env_var_or `NURL_STATIC_DIR` `/app/static` ) }

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

// ── IR Shimming for WASM ─────────────────────────────────────────────

@ prepare_ir_for_wasi String ir → String {
  : String res ( string_from ( string_data ir ) )

  // 1. Rename main definition robustly.
  : String r1 ( string_replace res ` @main(` ` @__main_argc_argv(` )
  ( string_free res ) = res r1

  // 2. Prepend WASM triple and datalayout.
  : String head ( string_from `target datalayout = "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20"\ntarget triple = "wasm32-unknown-wasi"\n` )
  : String r3 ( string_concat head res )
  ( string_free res ) ( string_free head ) = res r3

  : String shims ( string_from `\n; ── wasm32 libc ABI shims ──\n` )
  : ( Vec String ) shimmed ( vec_new [String] )
  
  : s list `malloc:p:s,calloc:p:ss,realloc:p:ps,puts:i:p,putchar:i:i,getchar:i:,strlen:s:p,strcmp:i:pp,strncmp:i:pps,strcpy:p:pp,strncpy:p:pps,strcat:p:pp,strdup:p:p,memcpy:p:pps,memmove:p:pps,memset:p:pis,memcmp:i:pps,memmem:p:psps,atoi:i:p,abs:i:i,exit:v:i,rand:i:,srand:v:s,system:i:p,write:i:ips,read:i:ips,open:i:pii,close:i:i`
  : String slist ( string_from list )
  : ( Vec String ) entries ( string_split slist `,` )
  
  : ~ i idx 0
  ~ < idx ( vec_len [String] entries ) {
    : ? String entry_opt ( vec_get [String] entries idx )
    ?? entry_opt { T entry → {
        : ( Vec String ) parts ( string_split entry `:` )
        ? == ( vec_len [String] parts ) 3 {
          : String name ( string_new ) : String ret ( string_new ) : String pms ( string_new )
          : ? String n_o ( vec_get [String] parts 0 ) ?? n_o { T s → { ( string_free name ) = name ( string_from ( string_data s ) ) } F → {} }
          : ? String r_o ( vec_get [String] parts 1 ) ?? r_o { T s → { ( string_free ret ) = ret ( string_from ( string_data s ) ) } F → {} }
          : ? String p_o ( vec_get [String] parts 2 ) ?? p_o { T s → { = pms ( string_from ( string_data s ) ) } F → {} }
          
          : String pat ( string_from `@` ) ( string_push_str pat ( string_data name ) ) ( string_push_char pat 40 )
          
          ? ( string_contains res ( string_data pat ) ) {
             : String sname ( string_from `@__nurl_` ) ( string_push_str sname ( string_data name ) ) ( string_push_str sname `_shim(` )
             
             : b already_shimmed F
             : ~ i si 0 ~ < si ( vec_len [String] shimmed ) {
               : ? String s_o ( vec_get [String] shimmed si ) ?? s_o { T s → { ? ( string_eq s name ) { = already_shimmed T } {} } F → {} }
               = si + si 1
             }

             ? == already_shimmed F {
               // 1. Rename ALL occurrences (including the original
               // `declare X @<libc>(...)` line emitted by nurlc).
               : String tmp ( string_replace res ( string_data pat ) ( string_data sname ) )
               ( string_free res ) = res tmp
               ( vec_push [String] shimmed ( string_from ( string_data name ) ) )

               // 2. Strip the renamed declaration line. After step 1, the IR
               // contains lines like `declare i8*  @__nurl_malloc_shim(i64)\n`
               // (1- or 2-space variants depending on nurlc's column-aligned
               // emit). clang rejects ANY `declare` + `define` of the same
               // function name as a redefinition, so we must remove the
               // declare line before step 3 emits the define. The previous
               // regex approach used a `^`-anchor that only matches start-of-
               // string in NURL's regex; this string_replace fallback covers
               // both 1-space and 2-space variants for the 4 LLVM types that
               // nurlc emits as the libc-style return.
               : ( Vec s ) types ( vec_new [s] )
               ( vec_push [s] types `i8*` ) ( vec_push [s] types `i64` ) ( vec_push [s] types `void` ) ( vec_push [s] types `i32` )
               : ~ i ti 0 ~ < ti ( vec_len [s] types ) {
                  : ? s t_o ( vec_get [s] types ti )
                  ?? t_o { T t → {
                     // Build: "declare " + t + "  @__nurl_<name>_shim(" — 2 space variant
                     : String two_decl ( string_from `declare ` )
                     ( string_push_str two_decl t ) ( string_push_str two_decl `  @__nurl_` )
                     ( string_push_str two_decl ( string_data name ) ) ( string_push_str two_decl `_shim(` )

                     // 1-space variant
                     : String one_decl ( string_from `declare ` )
                     ( string_push_str one_decl t ) ( string_push_str one_decl ` @__nurl_` )
                     ( string_push_str one_decl ( string_data name ) ) ( string_push_str one_decl `_shim(` )

                     // Find each declare line by its prefix, then locate the
                     // line's trailing `\n` and replace the whole line range
                     // with "". Since string_replace works on exact substrings
                     // we must find the line length first.
                     : ? i tp ( string_index_of res ( string_data two_decl ) )
                     ?? tp { T pos → {
                        // Find `\n` after pos
                        : i rn ( string_len res )
                        : ~ i le pos
                        ~ & < le rn != ( string_get res le ) 10 { = le + le 1 }
                        ? < le rn { = le + le 1 } {}
                        : String full_line ( string_substr res pos - le pos )
                        : String tmp2 ( string_replace res ( string_data full_line ) `` )
                        ( string_free res ) = res tmp2 ( string_free full_line )
                     } F _ → {
                        : ? i op ( string_index_of res ( string_data one_decl ) )
                        ?? op { T pos2 → {
                           : i rn2 ( string_len res )
                           : ~ i le2 pos2
                           ~ & < le2 rn2 != ( string_get res le2 ) 10 { = le2 + le2 1 }
                           ? < le2 rn2 { = le2 + le2 1 } {}
                           : String full_line2 ( string_substr res pos2 - le2 pos2 )
                           : String tmp3 ( string_replace res ( string_data full_line2 ) `` )
                           ( string_free res ) = res tmp3 ( string_free full_line2 )
                        } F _ → {} }
                     } }
                     ( string_free two_decl ) ( string_free one_decl )
                  } F → {} }
                  = ti + ti 1
               }
               ( vec_free [s] types )

               // 3. Build shim definition. We've already gated emission on
               // `already_shimmed=F` above, so always emit here — the prior
               // `needed` check was buggy: it inspected `res` for the renamed
               // CALL sites left behind by step 1, mistaking those for an
               // existing DEFINITION and silently dropping the shim body.
               // Without the body, wasm-ld fails with `undefined symbol:
               // __nurl_<fn>_shim`. Tracked separately by `shimmed` Vec.
               : String sname_def ( string_from `@__nurl_` ) ( string_push_str sname_def ( string_data name ) ) ( string_push_str sname_def `_shim(` )
               ? T {
                 ( string_push_str shims `\ndeclare ` )
                 : i r_char ? > ( string_len ret ) 0 ( string_get ret 0 ) 0
                 ( string_push_str shims ? == r_char 112 `i8*` ? == r_char 118 `void` `i32` )
                 ( string_push_str shims ` @` ) ( string_push_str shims ( string_data name ) ) ( string_push_char shims 40 )
                 : ~ i k 0 ~ < k ( string_len pms ) { ? > k 0 { ( string_push_str shims `, ` ) } {} : i p ( string_get pms k ) ( string_push_str shims ? == p 112 `i8*` `i32` ) = k + k 1 }
                 // External linkage (no `internal`) so the shim define
                 // satisfies any pre-existing `declare @__nurl_<name>_shim(...)`
                 // lines that step 1 might have produced by renaming the
                 // original `declare @<libc>(...)`. Step 2's regex-based
                 // declaration-restore uses a `^`-anchored pattern which
                 // only matches start-of-string in NURL regex, so the old
                 // renamed `declare` survives and would conflict with an
                 // `internal`-linkage define.
                 ( string_push_str shims `)\ndefine ` )
                 ( string_push_str shims ? == r_char 112 `i8*` ? == r_char 118 `void` `i64` )
                 ( string_push_str shims ` @__nurl_` ) ( string_push_str shims ( string_data name ) ) ( string_push_str shims `_shim(` )
                 : ~ i k2 0 ~ < k2 ( string_len pms ) { ? > k2 0 { ( string_push_str shims `, ` ) } {} : i p ( string_get pms k2 ) ( string_push_str shims ? == p 112 `i8* %a` `i64 %a` ) ( string_push_int shims k2 ) = k2 + k2 1 }
                 ( string_push_str shims `) {\n` )
                 : ~ i k3 0 ~ < k3 ( string_len pms ) { : i p ( string_get pms k3 ) ? != p 112 { ( string_push_str shims `  %t` ) ( string_push_int shims k3 ) ( string_push_str shims ` = trunc i64 %a` ) ( string_push_int shims k3 ) ( string_push_str shims ` to i32\n` ) } {} = k3 + k3 1 }
                 ( string_push_str shims `  %r = tail call ` )
                 ( string_push_str shims ? == r_char 112 `i8*` ? == r_char 118 `void` `i32` )
                 ( string_push_str shims ` @` ) ( string_push_str shims ( string_data name ) ) ( string_push_char shims 40 )
                 : ~ i k4 0 ~ < k4 ( string_len pms ) {
                   ? > k4 0 { ( string_push_str shims `, ` ) } {}
                   : i p ( string_get pms k4 ) ? == p 112 { ( string_push_str shims `i8* %a` ) ( string_push_int shims k4 ) } { ( string_push_str shims `i32 %t` ) ( string_push_int shims k4 ) }
                   = k4 + k4 1
                 }
                 ( string_push_str shims `)\n` )
                 ? == r_char 118 { ( string_push_str shims `  ret void\n` ) } { ? == r_char 112 { ( string_push_str shims `  ret i8* %r\n` ) } { : s op ? == r_char 115 `zext` `sext` ( string_push_str shims `  %rw = ` ) ( string_push_str shims op ) ( string_push_str shims ` i32 %r to i64\n  ret i64 %rw\n` ) } }
                 ( string_push_str shims `}\n` )
               } {}
               ( string_free sname_def )
             } {}
             ( string_free sname )
          } {}
          ( string_free pat ) ( string_free name ) ( string_free ret ) ( string_free pms )
        } {}
        ( vec_free_with [String] parts \ String s → v { ( string_free s ) } )
    } F → {} }
    = idx + idx 1
  }
  ( vec_free_with [String] entries \ String s → v { ( string_free s ) } )
  ( string_free slist ) ( vec_free_with [String] shimmed \ String s → v { ( string_free s ) } )

  : String final ( string_concat res shims )
  ( string_free res ) ( string_free shims )
  ^ final
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

@ json_str_or_null s str → Json {
  ? == ( nurl_str_len str ) 0 { ^ ( json_null ) } { ^ ( json_str_lit str ) }
}

@ get_body_str HttpRequest req → String {
  : i blen ( vec_len [u] . req body )
  : String body_str ( string_with_cap + blen 1 )
  : ~ i bi 0 ~ < bi blen { : ? u co ( vec_get [u] . req body bi ) ?? co { T c → { ( string_push_char body_str c ) } F → {} } = bi + bi 1 } ( __string_seal body_str )
  ^ body_str
}

// ── Build handler (Native Linux) ─────────────────────────────────────

@ h_build HttpRequest req Params params → HttpResponse {
  ( nurl_print `[srv] POST /build\n` )
  : String body_str ( get_body_str req )
  : ! Json ParseErr root_res ( json_parse ( string_data body_str ) )
  ?? root_res {
    T root → {
      : s source ( get_common_json root `source` `` )
      ? == ( nurl_str_len source ) 0 { ( json_free root ) ( string_free body_str ) ^ ( response_text 400 `{"error":"source is required"}\n` ) } {}
      : s filename ( get_common_json root `filename` `main.nu` )
      : s opt ( get_common_json root `opt` `-O2` )

      : String build_id ( create_build_id )
      : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )

      : ! v IoErr dr ( dir_create ( string_data build_dir ) )
      ?? dr {
        T _ → {
          : String nu_path ( path_join ( string_data build_dir ) filename )
          ( write_file ( string_data nu_path ) source )
          : String bin_name ( string_from filename )
          ? ( string_ends_with bin_name `.nu` ) { : String tmp ( string_substr bin_name 0 - ( string_len bin_name ) 3 ) ( string_free bin_name ) = bin_name tmp } {}
          : String ll_name ( string_from ( string_data bin_name ) ) ( string_push_str ll_name `.ll` )
          : String ll_path ( path_join ( string_data build_dir ) ( string_data ll_name ) )
          : String bin_path ( path_join ( string_data build_dir ) ( string_data bin_name ) )

          : b uses_canvas >= ( nurl_str_find source `stdlib/ext/canvas.nu` ) 0
          : b uses_audio >= ( nurl_str_find source `stdlib/ext/audio.nu` ) 0

          : ( Vec s ) nurlc_args ( vec_new [s] ) ( vec_push [s] nurlc_args ( string_data nu_path ) )
          : ! Output ProcessErr nurlc_res ( process_run ( string_data ( get_nurlc_path ) ) nurlc_args `` ) ( vec_free [s] nurlc_args )

          ?? nurlc_res {
            T n_out → {
              : i n_rc ( output_exit_code n_out )
              ? ( output_success n_out ) {
                ( write_file ( string_data ll_path ) ( output_stdout n_out ) )
                : ( Vec s ) clang_args ( vec_new [s] )
                ( vec_push [s] clang_args opt ) ( vec_push [s] clang_args `-Wno-override-module` ) ( vec_push [s] clang_args ( string_data ll_path ) )
                : String runtime_o ( path_join ( string_data ( get_stdlib_dir ) ) `runtime.native.o` )
                ( vec_push [s] clang_args ( string_data runtime_o ) ) ( vec_push [s] clang_args `-o` ) ( vec_push [s] clang_args ( string_data bin_path ) )
                ( vec_push [s] clang_args `-lm` ) ( vec_push [s] clang_args `-lpthread` ) ( vec_push [s] clang_args `-lcurl` )

                : ! Output ProcessErr clang_res ( process_run `clang` clang_args `` ) ( vec_free [s] clang_args )

                ?? clang_res {
                  T c_out → {
                    : i c_rc ( output_exit_code c_out )
                    : Json res ( json_obj_new )
                    ( json_obj_set res `status` ( json_str_lit ? == c_rc 0 `ok` `error` ) )
                    ( json_obj_set res `message` ( json_str_lit `compiled nurl → native binary` ) )
                    ( json_obj_set res `filename` ( json_str_lit filename ) )
                    ( json_obj_set res `nurlc_returncode` ( json_int n_rc ) )
                    ( json_obj_set res `clang_returncode` ( json_int c_rc ) )
                    ( json_obj_set res `nurlc_stdout` ( json_str_lit `[nurlc] build successful` ) )
                    ( json_obj_set res `nurlc_stderr` ( json_str_lit ( output_stderr n_out ) ) )
                    ( json_obj_set res `clang_stdout` ( json_str_lit ( output_stdout c_out ) ) )
                    ( json_obj_set res `clang_stderr` ( json_str_lit ( output_stderr c_out ) ) )
                    ( json_obj_set res `uses_canvas` ( json_bool uses_canvas ) )
                    ( json_obj_set res `uses_audio` ( json_bool uses_audio ) )
                    
                    : String ll_url ( string_new ) : String bin_url ( string_new )
                    ? == c_rc 0 {
                      : ! i IoErr ll_size_res ( file_size ( string_data ll_path ) )
                      : ! i IoErr bin_size_res ( file_size ( string_data bin_path ) )
                      : Json ll_art ( json_obj_new )
                      ( json_obj_set ll_art `name` ( json_str_lit ( string_data ll_name ) ) )
                      ( json_obj_set ll_art `bytes` ( json_int ?? ll_size_res { T s → s F _ → 0 } ) )
                      = ll_url ( string_with_cap 64 )
                      ( string_push_str ll_url `/download/` ) ( string_push_str ll_url ( string_data build_id ) ) ( string_push_str ll_url `/` ) ( string_push_str ll_url ( string_data ll_name ) )
                      ( json_obj_set ll_art `download_url` ( json_str_lit ( string_data ll_url ) ) )
                      ( json_obj_set res `ll_artifact` ll_art )

                      : Json bin_art ( json_obj_new )
                      ( json_obj_set bin_art `name` ( json_str_lit ( string_data bin_name ) ) )
                      ( json_obj_set bin_art `bytes` ( json_int ?? bin_size_res { T s → s F _ → 0 } ) )
                      = bin_url ( string_with_cap 64 )
                      ( string_push_str bin_url `/download/` ) ( string_push_str bin_url ( string_data build_id ) ) ( string_push_str bin_url `/` ) ( string_push_str bin_url ( string_data bin_name ) )
                      ( json_obj_set bin_art `download_url` ( json_str_lit ( string_data bin_url ) ) )
                      ( json_obj_set res `binary_artifact` bin_art )
                    } {}

                    : String body ( json_stringify res )
                    : HttpResponse hr ( response_text 200 ( string_data body ) )
                    ( response_set_header hr `Content-Type` `application/json` )
                    
                    ( string_free ll_url ) ( string_free bin_url ) ( json_free res ) ( string_free runtime_o )
                    ( output_free n_out ) ( output_free c_out ) ( json_free root )
                    ( string_free nu_path ) ( string_free ll_name ) ( string_free ll_path ) ( string_free bin_name ) ( string_free bin_path )
                    ( string_free build_id ) ( string_free build_dir ) ( string_free body_str ) ( string_free body ) 
                    ^ hr
                  }
                  F ce → { ^ ( response_text 500 `{"error":"clang process failed"}\n` ) }
                }
              } {
                : HttpResponse hr422 ( response_text 422 ( output_stderr n_out ) )
                ( output_free n_out ) ( json_free root ) ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name ) ( string_free bin_path ) ( string_free build_id ) ( string_free build_dir ) ( string_free body_str )
                ^ hr422
              }
            }
            F _ → { ^ ( response_text 500 `{"error":"nurlc failed"}\n` ) }
          }
        }
        F _ → { ^ ( response_text 500 `{"error":"could not create build dir"}\n` ) }
      }
    }
    F err → { ^ ( response_text 400 `{"error":"invalid json"}\n` ) }
  }
}

// ── Build handler (WASM) ─────────────────────────────────────────────

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
          : String bin_name ( string_from filename )
          ? ( string_ends_with bin_name `.nu` ) { : String tmp ( string_substr bin_name 0 - ( string_len bin_name ) 3 ) ( string_free bin_name ) = bin_name tmp } {}
          : String ll_name ( string_from ( string_data bin_name ) ) ( string_push_str ll_name `.ll` )
          : String wasm_name ( string_from ( string_data bin_name ) ) ( string_push_str wasm_name `.wasm` )

          : String ll_path ( path_join ( string_data build_dir ) ( string_data ll_name ) )
          : String wasm_path ( path_join ( string_data build_dir ) ( string_data wasm_name ) )

          : b uses_canvas >= ( nurl_str_find source `stdlib/ext/canvas.nu` ) 0
          : b uses_audio >= ( nurl_str_find source `stdlib/ext/audio.nu` ) 0

          : ( Vec s ) nurlc_args ( vec_new [s] ) ( vec_push [s] nurlc_args ( string_data nu_path ) )
          : ! Output ProcessErr nurlc_res ( process_run ( string_data ( get_nurlc_path ) ) nurlc_args `` ) ( vec_free [s] nurlc_args )

          ?? nurlc_res {
            T n_out → {
              : i n_rc ( output_exit_code n_out )
              ? ( output_success n_out ) {
                : String ir ( string_from ( output_stdout n_out ) )
                : String ir_fixed ( prepare_ir_for_wasi ir )
                ( write_file ( string_data ll_path ) ( string_data ir_fixed ) )
                ( string_free ir )

                : b uses_canvas F
                : ! Regex ParseErr re_canv ( regex_compile `@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\b` )
                ?? re_canv { T rc → { = uses_canvas ( regex_test rc ( string_data ir_fixed ) ) ( regex_free rc ) } F _ → {} }
                
                : b uses_audio F
                : ! Regex ParseErr re_aud ( regex_compile `@audio_(level|bin|bin_count|peak_bin|centroid|freq_of|sample_rate|is_silent|ready)\b` )
                ?? re_aud { T ra → { = uses_audio ( regex_test ra ( string_data ir_fixed ) ) ( regex_free ra ) } F _ → {} }

                : ( Vec s ) clang_args ( vec_new [s] )
                ( vec_push [s] clang_args `--target=wasm32-wasi` ) ( vec_push [s] clang_args `-O2` ) ( vec_push [s] clang_args `-Wno-override-module` ) ( vec_push [s] clang_args ( string_data ll_path ) )
                ( vec_push [s] clang_args ( string_data ( get_runtime_wasm_o ) ) )
                ? uses_canvas { ( vec_push [s] clang_args ( string_data ( get_canvas_wasm_o ) ) ) } {}
                ? uses_audio { ( vec_push [s] clang_args ( string_data ( get_audio_wasm_o ) ) ) } {}
                ? | uses_canvas uses_audio { ( vec_push [s] clang_args `-Wl,--allow-undefined` ) } {}
                ( vec_push [s] clang_args `-o` ) ( vec_push [s] clang_args ( string_data wasm_path ) ) ( vec_push [s] clang_args `-lm` )

                : ! Output ProcessErr clang_res ( process_run ( string_data ( get_wasi_clang ) ) clang_args `` ) ( vec_free [s] clang_args )

                ?? clang_res {
                  T c_out → {
                    : i c_rc ( output_exit_code c_out )
                    : Json res ( json_obj_new )
                    ( json_obj_set res `status` ( json_str_lit ? == c_rc 0 `ok` `error` ) )
                    ( json_obj_set res `message` ( json_str_lit `compiled nurl → wasm32-wasi` ) )
                    ( json_obj_set res `filename` ( json_str_lit filename ) )
                    ( json_obj_set res `wasm_base64` ( json_null ) )
                    ( json_obj_set res `wasm_bytes` ( json_int 0 ) )
                    ( json_obj_set res `nurlc_stderr` ( json_str_or_null ( output_stderr n_out ) ) )
                    ( json_obj_set res `nurlc_errors` ( json_arr_new ) )
                    ( json_obj_set res `clang_stderr` ( json_str_or_null ( output_stderr c_out ) ) )
                    ( json_obj_set res `llvm_ir` ? | emit_ll != c_rc 0 { ( json_str_lit ( string_data ir_fixed ) ) } { ( json_null ) } )
                    ( json_obj_set res `uses_canvas` ( json_bool uses_canvas ) )
                    ( json_obj_set res `uses_audio` ( json_bool uses_audio ) )
                    
                    : String b64 ( string_new ) : String wasm_url ( string_new )
                    ? == c_rc 0 {
                      : ! i IoErr wasm_size_res ( file_size ( string_data wasm_path ) )
                      : i w_bytes ?? wasm_size_res { T s → s F _ → 0 }
                      ( json_obj_set res `wasm_bytes` ( json_int w_bytes ) )
                      : ! ( Vec u ) IoErr wasm_data_res ( read_file_bytes ( string_data wasm_path ) )
                      ?? wasm_data_res { T w_data → { 
                          : String b ( b64_encode_vec w_data ) ( json_obj_set res `wasm_base64` ( json_str_lit ( string_data b ) ) )
                          ( string_free b64 ) = b64 b ( vec_free [u] w_data ) } F _ → {} }
                      = wasm_url ( string_with_cap 64 )
                      ( string_push_str wasm_url `/download/` ) ( string_push_str wasm_url ( string_data build_id ) ) ( string_push_str wasm_url `/` ) ( string_push_str wasm_url ( string_data wasm_name ) )
                      ( json_obj_set res `download_url` ( json_str_lit ( string_data wasm_url ) ) )
                    } {}

                    : String body ( json_stringify res )
                    : HttpResponse hr ( response_text 200 ( string_data body ) )
                    ( response_set_header hr `Content-Type` `application/json` )
                    
                    ( string_free b64 ) ( string_free wasm_url ) ( json_free res ) ( string_free ir_fixed )
                    ( output_free n_out ) ( output_free c_out ) ( json_free root )
                    ( string_free nu_path ) ( string_free ll_name ) ( string_free ll_path ) ( string_free wasm_name ) ( string_free wasm_path )
                    ( string_free build_id ) ( string_free build_dir ) ( string_free body_str ) ( string_free body )
                    ^ hr
                  }
                  F ce → { ( string_free ir_fixed ) ^ ( response_text 500 `{"error":"wasi-clang failed"}\n` ) }
                }
              } {
                : HttpResponse hr422 ( response_text 422 ( output_stderr n_out ) )
                ( output_free n_out ) ( json_free root ) ( string_free nu_path ) ( string_free ll_path ) ( string_free wasm_path ) ( string_free build_id ) ( string_free build_dir ) ( string_free body_str )
                ^ hr422
              }
            }
            F _ → { ^ ( response_text 500 `{"error":"nurlc failed"}\n` ) }
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
  : String body_str ( get_body_str req )
  : ! Json ParseErr root_res ( json_parse ( string_data body_str ) )
  ?? root_res {
    T root → {
      : s source ( get_common_json root `source` `` )
      ? == ( nurl_str_len source ) 0 { ( json_free root ) ( string_free body_str ) ^ ( response_text 400 `{"error":"source is required"}\n` ) } {}
      : s filename ( get_common_json root `filename` `main.nu` )
      : s opt ( get_common_json root `opt` `-O2` )
      : String build_id ( create_build_id )
      : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )
      : ! v IoErr dr ( dir_create ( string_data build_dir ) )
      ?? dr {
        T _ → {
          : String nu_path ( path_join ( string_data build_dir ) filename )
          ( write_file ( string_data nu_path ) source )
          : String ll_path ( path_join ( string_data build_dir ) `main.ll` )
          : String bin_name ( string_from filename )
          ? ( string_ends_with bin_name `.nu` ) { : String tmp ( string_substr bin_name 0 - ( string_len bin_name ) 3 ) ( string_free bin_name ) = bin_name tmp } {}
          ( string_push_str bin_name `.exe` )
          : String bin_path ( path_join ( string_data build_dir ) ( string_data bin_name ) )
          : ( Vec s ) nurlc_args ( vec_new [s] ) ( vec_push [s] nurlc_args ( string_data nu_path ) )
          : ! Output ProcessErr nurlc_res ( process_run ( string_data ( get_nurlc_path ) ) nurlc_args `` ) ( vec_free [s] nurlc_args )
          ?? nurlc_res {
            T n_out → {
              : i n_rc ( output_exit_code n_out )
              ? ( output_success n_out ) {
                ( write_file ( string_data ll_path ) ( output_stdout n_out ) )
                : ( Vec s ) clang_args ( vec_new [s] )
                ( vec_push [s] clang_args `--target=x86_64-w64-mingw32` ) ( vec_push [s] clang_args opt ) ( vec_push [s] clang_args `-Wno-override-module` ) ( vec_push [s] clang_args ( string_data ll_path ) )
                ( vec_push [s] clang_args ( string_data ( get_runtime_win_o ) ) ) ( vec_push [s] clang_args `-o` ) ( vec_push [s] clang_args ( string_data bin_path ) )
                ( vec_push [s] clang_args `-L/opt/curl-mingw/lib` ) ( vec_push [s] clang_args `-lcurl` ) ( vec_push [s] clang_args `-lws2_32` ) ( vec_push [s] clang_args `-lcrypt32` ) ( vec_push [s] clang_args `-lbcrypt` ) ( vec_push [s] clang_args `-lncrypt` ) ( vec_push [s] clang_args `-lsecur32` ) ( vec_push [s] clang_args `-ladvapi32` )
                : ! Output ProcessErr clang_res ( process_run `clang` clang_args `` ) ( vec_free [s] clang_args )
                ?? clang_res {
                  T c_out → {
                    : i c_rc ( output_exit_code c_out )
                    : Json res ( json_obj_new )
                    ( json_obj_set res `status` ( json_str_lit ? == c_rc 0 `ok` `error` ) ) ( json_obj_set res `message` ( json_str_lit `compiled nurl → windows .exe` ) ) ( json_obj_set res `filename` ( json_str_lit filename ) ) ( json_obj_set res `nurlc_returncode` ( json_int n_rc ) ) ( json_obj_set res `clang_returncode` ( json_int c_rc ) )
                    ( json_obj_set res `nurlc_stdout` ( json_str_lit `[nurlc] build successful` ) ) ( json_obj_set res `nurlc_stderr` ( json_str_lit ( output_stderr n_out ) ) ) ( json_obj_set res `clang_stdout` ( json_str_lit ( output_stdout c_out ) ) ) ( json_obj_set res `clang_stderr` ( json_str_lit ( output_stderr c_out ) ) )
                    : String bin_url ( string_new )
                    ? == c_rc 0 { : ! i IoErr bin_size_res ( file_size ( string_data bin_path ) ) : Json bin_art ( json_obj_new ) ( json_obj_set bin_art `name` ( json_str_lit ( string_data bin_name ) ) ) ( json_obj_set bin_art `bytes` ( json_int ?? bin_size_res { T s → s F _ → 0 } ) )
                      = bin_url ( string_with_cap 64 ) ( string_push_str bin_url `/download/` ) ( string_push_str bin_url ( string_data build_id ) ) ( string_push_str bin_url `/` ) ( string_push_str bin_url ( string_data bin_name ) )
                      ( json_obj_set bin_art `download_url` ( json_str_lit ( string_data bin_url ) ) ) ( json_obj_set res `binary_artifact` bin_art ) } {}
                    : String body ( json_stringify res )
                    : HttpResponse hr ( response_text 200 ( string_data body ) ) ( response_set_header hr `Content-Type` `application/json` )
                    ( string_free bin_url ) ( json_free res ) ( output_free n_out ) ( output_free c_out ) ( json_free root )
                    ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name ) ( string_free bin_path )
                    ( string_free build_id ) ( string_free build_dir ) ( string_free body_str ) ( string_free body ) ^ hr
                  } F ce → { ^ ( response_text 500 `{"error":"clang process failed"}\n` ) } }
              } {
                : HttpResponse hr422 ( response_text 422 ( output_stderr n_out ) )
                ( output_free n_out ) ( json_free root ) ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name ) ( string_free bin_path ) ( string_free build_id ) ( string_free build_dir ) ( string_free body_str )
                ^ hr422
              } } F _ → { ^ ( response_text 500 `{"error":"nurlc failed"}\n` ) } }
        } F _ → { ^ ( response_text 500 `{"error":"could not create build dir"}\n` ) } } } F _ → { ^ ( response_text 400 `{"error":"invalid json"}\n` ) } }
}

// ── Build handler (macOS) ────────────────────────────────────────────

@ h_build_macos HttpRequest req Params params → HttpResponse {
  ( nurl_print `[srv] POST /build_macos\n` )
  : String body_str ( get_body_str req )
  : ! Json ParseErr root_res ( json_parse ( string_data body_str ) )
  ?? root_res {
    T root → {
      : s source ( get_common_json root `source` `` )
      ? == ( nurl_str_len source ) 0 { ( json_free root ) ( string_free body_str ) ^ ( response_text 400 `{"error":"source is required"}\n` ) } {}
      : s filename ( get_common_json root `filename` `main.nu` )
      : s opt ( get_common_json root `opt` `-O2` )
      : String build_id ( create_build_id )
      : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )
      : ! v IoErr dr ( dir_create ( string_data build_dir ) )
      ?? dr {
        T _ → {
          : String nu_path ( path_join ( string_data build_dir ) filename )
          ( write_file ( string_data nu_path ) source )
          : String ll_path ( path_join ( string_data build_dir ) `main.ll` )
          : String bin_name ( string_from filename )
          ? ( string_ends_with bin_name `.nu` ) { : String tmp ( string_substr bin_name 0 - ( string_len bin_name ) 3 ) ( string_free bin_name ) = bin_name tmp } {}
          : String bin_path ( path_join ( string_data build_dir ) ( string_data bin_name ) )
          : ( Vec s ) nurlc_args ( vec_new [s] ) ( vec_push [s] nurlc_args ( string_data nu_path ) )
          : ! Output ProcessErr nurlc_res ( process_run ( string_data ( get_nurlc_path ) ) nurlc_args `` ) ( vec_free [s] nurlc_args )
          ?? nurlc_res {
            T n_out → {
              : i n_rc ( output_exit_code n_out )
              ? ( output_success n_out ) {
                ( write_file ( string_data ll_path ) ( output_stdout n_out ) )
                : ( Vec s ) zig_args ( vec_new [s] )
                ( vec_push [s] zig_args `cc` ) ( vec_push [s] zig_args `-target` ) ( vec_push [s] zig_args `x86_64-macos-none` ) ( vec_push [s] zig_args opt )
                ( vec_push [s] zig_args `-Wno-override-module` ) ( vec_push [s] zig_args ( string_data ll_path ) ) ( vec_push [s] zig_args ( string_data ( get_runtime_mac_o ) ) ) ( vec_push [s] zig_args `-o` ) ( vec_push [s] zig_args ( string_data bin_path ) )
                : ! Output ProcessErr zig_res ( process_run ( string_data ( get_zig ) ) zig_args `` ) ( vec_free [s] zig_args )
                ?? zig_res {
                  T z_out → {
                    : i z_rc ( output_exit_code z_out )
                    : Json res ( json_obj_new )
                    ( json_obj_set res `status` ( json_str_lit ? == z_rc 0 `ok` `error` ) ) ( json_obj_set res `message` ( json_str_lit `compiled nurl → macOS Mach-O` ) ) ( json_obj_set res `filename` ( json_str_lit filename ) ) ( json_obj_set res `nurlc_returncode` ( json_int n_rc ) ) ( json_obj_set res `clang_returncode` ( json_int z_rc ) )
                    ( json_obj_set res `nurlc_stdout` ( json_str_lit `[nurlc] build successful` ) ) ( json_obj_set res `nurlc_stderr` ( json_str_lit ( output_stderr n_out ) ) ) ( json_obj_set res `clang_stdout` ( json_str_lit ( output_stdout z_out ) ) ) ( json_obj_set res `clang_stderr` ( json_str_lit ( output_stderr z_out ) ) )
                    : String bin_url ( string_new )
                    ? == z_rc 0 { : ! i IoErr bin_size_res ( file_size ( string_data bin_path ) ) : Json bin_art ( json_obj_new ) ( json_obj_set bin_art `name` ( json_str_lit ( string_data bin_name ) ) ) ( json_obj_set bin_art `bytes` ( json_int ?? bin_size_res { T s → s F _ → 0 } ) )
                      = bin_url ( string_with_cap 64 ) ( string_push_str bin_url `/download/` ) ( string_push_str bin_url ( string_data build_id ) ) ( string_push_str bin_url `/` ) ( string_push_str bin_url ( string_data bin_name ) )
                      ( json_obj_set bin_art `download_url` ( json_str_lit ( string_data bin_url ) ) ) ( json_obj_set res `binary_artifact` bin_art ) } {}
                    : String body ( json_stringify res )
                    : HttpResponse hr ( response_text 200 ( string_data body ) ) ( response_set_header hr `Content-Type` `application/json` )
                    ( string_free bin_url ) ( json_free res ) ( output_free n_out ) ( output_free z_out ) ( json_free root )
                    ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name ) ( string_free bin_path )
                    ( string_free build_id ) ( string_free build_dir ) ( string_free body_str ) ( string_free body ) ^ hr
                  } F ce → { ^ ( response_text 500 `{"error":"zig process failed"}\n` ) } }
              } {
                : HttpResponse hr422 ( response_text 422 ( output_stderr n_out ) )
                ( output_free n_out ) ( json_free root ) ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name ) ( string_free bin_path ) ( string_free build_id ) ( string_free build_dir ) ( string_free body_str )
                ^ hr422
              } } F _ → { ^ ( response_text 500 `{"error":"nurlc failed"}\n` ) } }
        } F _ → { ^ ( response_text 500 `{"error":"could not create build dir"}\n` ) } } } F _ → { ^ ( response_text 400 `{"error":"invalid json"}\n` ) } }
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
  : String nurlc_path ( get_nurlc_path ) : String stdlib_dir ( get_stdlib_dir ) : String wasi_clang ( get_wasi_clang ) : String runtime_wasm ( get_runtime_wasm_o )
  : Json j ( json_obj_new )
  ( json_obj_set j `status` ( json_str_lit `ok` ) )
  ( json_obj_set j `nurlc_available` ( json_bool ( file_exists ( string_data nurlc_path ) ) ) )
  ( json_obj_set j `nurlc_path` ( json_str_lit ( string_data nurlc_path ) ) )
  ( json_obj_set j `wasi_toolchain_available` ( json_bool | ( file_exists ( string_data wasi_clang ) ) ( file_exists ( string_data runtime_wasm ) ) ) )
  ( json_obj_set j `stdlib_available` ( json_bool ( file_exists ( string_data stdlib_dir ) ) ) )
  ( json_obj_set j `stdlib_dir` ( json_str_lit ( string_data stdlib_dir ) ) )
  ( json_obj_set j `stdlib_modules` ( list_stdlib_modules ) )
  
  : String body ( json_stringify j )
  : HttpResponse r ( response_text 200 ( string_data body ) ) ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
  ( json_free j ) ( string_free nurlc_path ) ( string_free stdlib_dir ) ( string_free wasi_clang ) ( string_free runtime_wasm ) ( string_free body )
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
