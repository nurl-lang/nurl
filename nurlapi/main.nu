$ `stdlib/ext/http_full.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/int.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/random.nu`
$ `stdlib/ext/regex.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_http.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/nurldoc.nu`

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

@ get_runtime_win_curl_o → String { ^ ( env_var_or `NURL_RUNTIME_WIN_CURL_O` `/opt/nurl/stdlib/runtime.win.curl.o` ) }

@ get_runtime_mac_o → String { ^ ( env_var_or `NURL_RUNTIME_MAC_O` `/opt/nurl/stdlib/runtime.mac.o` ) }

@ get_zig → String { ^ ( env_var_or `NURL_ZIG` `/opt/zig/zig` ) }

@ get_wasm_opt → String { ^ ( env_var_or `NURL_WASM_OPT` `wasm-opt` ) }

@ get_work_root → String { ^ ( env_var_or `NURL_WORK_ROOT` `/opt/nurl` ) }

@ get_static_dir → String { ^ ( env_var_or `NURL_STATIC_DIR` `/app/static` ) }

@ get_readme_path → String { ^ ( env_var_or `NURL_README_PATH` `/opt/nurl/README.md` ) }

@ get_grammar_path → String { ^ ( env_var_or `NURL_GRAMMAR_PATH` `/opt/nurl/spec/grammar.ebnf` ) }

@ get_tests_dir → String { ^ ( env_var_or `NURL_TESTS_DIR` `/opt/nurl/compiler/tests` ) }

@ get_mingw_gcc → String { ^ ( env_var_or `NURL_MINGW_GCC` `/usr/bin/x86_64-w64-mingw32-gcc` ) }

@ get_mingw_curl_prefix → String { ^ ( env_var_or `NURL_MINGW_CURL_PREFIX` `/opt/curl-mingw` ) }

@ get_roadmap_path → String { ^ ( env_var_or `NURL_ROADMAP_PATH` `/opt/nurl/ROADMAP.md` ) }

@ get_gotchas_path → String { ^ ( env_var_or `NURL_GOTCHAS_PATH` `/opt/nurl/docs/GOTCHAS.md` ) }

@ get_license_mit_path → String { ^ ( env_var_or `NURL_LICENSE_MIT_PATH` `/opt/nurl/LICENSE-MIT` ) }

@ get_license_apache_path → String { ^ ( env_var_or `NURL_LICENSE_APACHE_PATH` `/opt/nurl/LICENSE-APACHE` ) }

@ get_notice_path → String { ^ ( env_var_or `NURL_NOTICE_PATH` `/opt/nurl/NOTICE` ) }

@ get_mcp_loopback_url → String { ^ ( env_var_or `NURL_MCP_LOOPBACK_URL` `http://127.0.0.1:8000` ) }

@ get_mcp_server_name → String { ^ ( env_var_or `NURL_MCP_SERVER_NAME` `nurl` ) }

@ get_mcp_server_version → String { ^ ( env_var_or `NURL_MCP_SERVER_VERSION` `1.9.4` ) }

@ get_changelog_path → String { ^ ( env_var_or `NURL_CHANGELOG_PATH` `/opt/nurl/CHANGELOG.md` ) }

// Per-zig-target runtime object path. Used by /build_target so we don't
// have to keep a switch in NURL code — the Dockerfile builds one
// runtime.<id>.o per registered target and the path lookup follows
// suit: `runtime.<target_id>.o` under NURL_STDLIB_DIR.
@ get_runtime_target_o s target_id → String {
    : String sdir ( get_stdlib_dir )
    : String fname ( string_with_cap 32 )
    ( string_push_str fname `runtime.` )
    ( string_push_str fname target_id )
    ( string_push_str fname `.o` )
    : String full ( path_join ( string_data sdir ) ( string_data fname ) )
    ( string_free sdir ) ( string_free fname )
    ^ full
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
    : !( Vec String ) IoErr dr ( dir_list ( string_data sdir ) )
    : Json arr ( json_arr_new )
    ?? dr {
        T files → {
            : ~ i i 0 ~ < i ( vec_len [String] files ) {
                ?? ( vec_get [String] files i ) { T f → {
                        ? ( string_ends_with f `.nu` ) { ( json_arr_push arr ( json_str_lit ( string_data f ) ) ) } {}
                        : String sub ( path_join ( string_data sdir ) ( string_data f ) )
                        ? ( file_exists ( string_data sub ) ) {
                            : !( Vec String ) IoErr dr2 ( dir_list ( string_data sub ) )
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

// The WASM shimming below rewrites IR symbols with whole-string
// string_replace (rename `@main` → `@__main_argc_argv`, libc fns →
// width-shims, POSIX fns → stubs). That is safe for ordinary programs,
// but a program that *emits* LLVM IR — notably the nurlc compiler
// itself — carries those exact tokens inside `c"..."` string constants
// (e.g. `c"define i32 @main(...){\00"`, `c"declare i8* @malloc(i64)"`).
// A naive replace rewrites the constant's *contents* without touching
// its `[N x i8]` length, so clang rejects it with a constant-type
// mismatch and the whole build fails.
//
// To keep the replaces oblivious to string-constant data we mask every
// `@` that lives on a constant line (any line carrying `c"`) to a
// sentinel before rewriting, then restore it at the very end. The
// sentinel has no `@`, so none of the `@name(` patterns can match it,
// and the gate checks (`string_contains res ...`) stop seeing
// string-constant occurrences too — so we only shim symbols that are
// genuinely referenced as code.
@ __ir_at_sentinel → s { ^ `__NURL_IR_AT_SENTINEL__` }

@ mask_ir_str_consts String ir → String {
    : ( Vec String ) lines ( string_split ir `\n` )
    : String out ( string_with_cap ( string_len ir ) )
    : i n ( vec_len [String] lines )
    : ~ i i 0
    ~ < i n {
        : ?String le ( vec_get [String] lines i )
        ?? le {
            T line → {
                ? > i 0 { ( string_push_char out 10 ) } {}
                ? ( string_contains line `c"` ) {
                    : String m ( string_replace line `@` ( __ir_at_sentinel ) )
                    ( string_push_str out ( string_data m ) ) ( string_free m )
                } { ( string_push_str out ( string_data line ) ) }
            }
            F → {}
        }
        = i + i 1
    }
    ( vec_free_with [String] lines \ String s → v { ( string_free s ) } )
    ^ out
}

@ prepare_ir_for_wasi String ir → String {
    : ~ String res ( string_from ( string_data ir ) )

    // 0. Mask `@` inside string constants so the symbol rewrites below
    //    can't corrupt emitted-IR data (see note above). Restored at the
    //    end of the function.
    : String masked ( mask_ir_str_consts res )
    ( string_free res ) = res masked

    // 1. Rename main definition robustly.
    : String r1 ( string_replace res ` @main(` ` @__main_argc_argv(` )
    ( string_free res ) = res r1

    // 2. Prepend WASM triple and datalayout.
    : String head ( string_from `target datalayout = "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20"\ntarget triple = "wasm32-unknown-wasi"\n` )
    : String r3 ( string_concat head res )
    ( string_free res ) ( string_free head ) = res r3

    : String shims ( string_from `\n; ── wasm32 libc ABI shims ──\n` )
    : ( Vec String ) shimmed ( vec_new [String] )

    // libc functions whose NURL FFI declares them with i64 args but wasm32
    // libc expects i32. We rename @<name>(...) → @__nurl_<name>_shim(...)
    // throughout the IR and emit a wrapper that trunc's i64→i32 (and
    // sext/zext on the return). Without this, wasm-ld emits "function
    // signature mismatch" warnings — and since the .wasm still loads with
    // the wrong ABI, the program crashes at runtime ("runtime error:
    // unreachable" or memory corruption). Add new libc functions here as
    // examples surface them.
    //
    // memchr/getcwd/strchr/strrchr added 2026-05-27 — json_basic, mcp_*,
    // serde_demo, claude_chat all hit the memchr mismatch; claude_chat
    // also imports getcwd via std/process.nu.
    //
    // fread/fwrite/fseek/ftell/lseek added 2026-05-27 — find_clone /
    // csv_demo / claude_agent stdio path. wasi-libc has all of these
    // with i32-flavored size_t/long; NURL emits the i64 variants.
    : s list `malloc:p:s,calloc:p:ss,realloc:p:ps,puts:i:p,putchar:i:i,getchar:i:,strlen:s:p,strcmp:i:pp,strncmp:i:pps,strcpy:p:pp,strncpy:p:pps,strcat:p:pp,strdup:p:p,memcpy:p:pps,memmove:p:pps,memset:p:pis,memcmp:i:pps,memchr:p:pis,memmem:p:psps,strchr:p:pi,strrchr:p:pi,atoi:i:p,abs:i:i,exit:v:i,rand:i:,srand:v:s,system:i:p,write:i:ips,read:i:ips,open:i:pii,close:i:i,getcwd:p:ps,fread:s:psps,fwrite:s:psps,fseek:i:pii,ftell:i:p,lseek:i:iii`
    : String slist ( string_from list )
    : ( Vec String ) entries ( string_split slist `,` )

    : ~ i idx 0
    ~ < idx ( vec_len [String] entries ) {
        : ?String entry_opt ( vec_get [String] entries idx )
        ?? entry_opt { T entry → {
                : ( Vec String ) parts ( string_split entry `:` )
                ? == ( vec_len [String] parts ) 3 {
                    : ~ String name ( string_new ) : ~ String ret ( string_new ) : ~ String pms ( string_new )
                    : ?String n_o ( vec_get [String] parts 0 ) ?? n_o { T s → { ( string_free name ) = name ( string_from ( string_data s ) ) } F → {} }
                    : ?String r_o ( vec_get [String] parts 1 ) ?? r_o { T s → { ( string_free ret ) = ret ( string_from ( string_data s ) ) } F → {} }
                    : ?String p_o ( vec_get [String] parts 2 ) ?? p_o { T s → { = pms ( string_from ( string_data s ) ) } F → {} }

                    : String pat ( string_from `@` ) ( string_push_str pat ( string_data name ) ) ( string_push_char pat 40 )

                    ? ( string_contains res ( string_data pat ) ) {
                        : String sname ( string_from `@__nurl_` ) ( string_push_str sname ( string_data name ) ) ( string_push_str sname `_shim(` )

                        : ~ b already_shimmed F
                        : ~ i si 0 ~ < si ( vec_len [String] shimmed ) {
                            : ?String s_o ( vec_get [String] shimmed si ) ?? s_o { T s → { ? ( string_eq s name ) { = already_shimmed T } {} } F → {} }
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
                                : ?s t_o ( vec_get [s] types ti )
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
                                        : ?i tp ( string_index_of res ( string_data two_decl ) )
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
                                                : ?i op ( string_index_of res ( string_data one_decl ) )
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

    // POSIX-only fns that wasi-sysroot doesn't ship at all. The stdlib
    // (std/fs.nu mmap path, std/process.nu fork+exec, std/signal.nu)
    // unconditionally `declare`s and references them; on wasm we satisfy
    // the linker by renaming the IR call sites to internal stub functions
    // that return error sentinels (-1 / MAP_FAILED / NULL). The matching
    // code paths are runtime-gated via `posix_const` (which already
    // returns -1 on wasi), so these stubs never get called in
    // well-formed programs. They unblock builds for csv_demo, find_clone,
    // claude_agent, async_http_server etc.
    //
    // We rename `@<fn>(` → `@__nurl_<fn>_stub(` (and strip the original
    // `declare` line) rather than defining `@<fn>` directly — wasi-sdk's
    // clang refuses `define @mmap` / `@munmap` etc as "invalid
    // redefinition" because libc builtins are recognised by name.
    //
    // Signatures must match the `declare`s nurlc emits exactly. Check
    // with `grep '@<fn>(' < nurlc-output.ll` if a new one is added.
    // POSIX-only fn → stub renaming. Strategy:
    //   1. Replace ` @<name>(` with ` @__nurl_<name>_stub(` everywhere
    //      in the IR. This rewrites both the declare line and every call
    //      site in one pass.
    //   2. Append a `define internal …` for `@__nurl_<name>_stub` that
    //      returns the error sentinel. clang accepts declare+define for
    //      the same renamed name — the rename is needed only because
    //      clang/wasi-sdk treats libc builtin names (mmap/munmap/fork…)
    //      as already-defined and rejects user `define @mmap`.
    //
    // Parallel arrays: posix_names[i] gets the matching stub body
    // posix_bodies[i] when ` @<posix_names[i]>(` is found in the IR.
    : ( Vec s ) posix_names ( vec_new [s] )
    : ( Vec s ) posix_bodies ( vec_new [s] )
    ( vec_push [s] posix_names `mmap` ) ( vec_push [s] posix_bodies `i8* @__nurl_mmap_stub(i8*, i64, i32, i32, i32, i64) {\n  %p = inttoptr i64 -1 to i8*\n  ret i8* %p\n}` )
    ( vec_push [s] posix_names `munmap` ) ( vec_push [s] posix_bodies `i32 @__nurl_munmap_stub(i8*, i64) { ret i32 0 }` )
    ( vec_push [s] posix_names `madvise` ) ( vec_push [s] posix_bodies `i32 @__nurl_madvise_stub(i8*, i64, i32) { ret i32 0 }` )
    ( vec_push [s] posix_names `fork` ) ( vec_push [s] posix_bodies `i64 @__nurl_fork_stub() { ret i64 -1 }` )
    ( vec_push [s] posix_names `execvp` ) ( vec_push [s] posix_bodies `i64 @__nurl_execvp_stub(i8*, i8*) { ret i64 -1 }` )
    ( vec_push [s] posix_names `waitpid` ) ( vec_push [s] posix_bodies `i64 @__nurl_waitpid_stub(i64, i8*, i64) { ret i64 -1 }` )
    ( vec_push [s] posix_names `pipe` ) ( vec_push [s] posix_bodies `i64 @__nurl_pipe_stub(i8*) { ret i64 -1 }` )
    ( vec_push [s] posix_names `dup2` ) ( vec_push [s] posix_bodies `i64 @__nurl_dup2_stub(i64, i64) { ret i64 -1 }` )
    ( vec_push [s] posix_names `signal` ) ( vec_push [s] posix_bodies `i8* @__nurl_signal_stub(i64, i8*) { ret i8* null }` )
    // pthread family — wasi-libc doesn't ship pthread at all. std/thread.nu
    // + std/arc.nu + the M:N async runtime declare these unconditionally.
    // Single-threaded wasm stubs: lock/unlock/signal/broadcast/wait become
    // no-ops returning 0 (success); create returns -1 so any code that
    // actually tries to spawn fails gracefully.
    ( vec_push [s] posix_names `pthread_mutex_init` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_mutex_init_stub(i8*, i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_mutex_lock` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_mutex_lock_stub(i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_mutex_unlock` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_mutex_unlock_stub(i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_mutex_destroy` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_mutex_destroy_stub(i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_cond_init` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_cond_init_stub(i8*, i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_cond_wait` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_cond_wait_stub(i8*, i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_cond_signal` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_cond_signal_stub(i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_cond_broadcast` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_cond_broadcast_stub(i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_cond_destroy` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_cond_destroy_stub(i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_create` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_create_stub(i8*, i8*, i8*, i8*) { ret i64 -1 }` )
    ( vec_push [s] posix_names `pthread_join` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_join_stub(i8*, i8*) { ret i64 0 }` )
    ( vec_push [s] posix_names `pthread_self` ) ( vec_push [s] posix_bodies `i8* @__nurl_pthread_self_stub() { ret i8* null }` )
    ( vec_push [s] posix_names `pthread_detach` ) ( vec_push [s] posix_bodies `i64 @__nurl_pthread_detach_stub(i8*) { ret i64 0 }` )
    // Misc POSIX a thread / IPC example may pull in. kill/getpid live in
    // wasi-libc but only sometimes (depends on sysroot); stub them too so
    // we get a consistent build regardless of which wasi-sdk version
    // happens to be in the image.
    ( vec_push [s] posix_names `kill` ) ( vec_push [s] posix_bodies `i64 @__nurl_kill_stub(i64, i64) { ret i64 -1 }` )
    ( vec_push [s] posix_names `getpid` ) ( vec_push [s] posix_bodies `i64 @__nurl_getpid_stub() { ret i64 1 }` )

    ( string_push_str shims `\n; ── wasi POSIX-only stubs ──\n` )
    : ~ i pi 0
    ~ < pi ( vec_len [s] posix_names ) {
        : ?s name_o ( vec_get [s] posix_names pi )
        : ?s body_o ( vec_get [s] posix_bodies pi )
        ?? name_o { T name → {
                : String needle ( string_from ` @` ) ( string_push_str needle name ) ( string_push_char needle 40 )
                ? ( string_contains res ( string_data needle ) ) {
                    // 1. Rename ` @<name>(` → ` @__nurl_<name>_stub(` everywhere.
                    : String repl ( string_from ` @__nurl_` ) ( string_push_str repl name ) ( string_push_str repl `_stub(` )
                    : String tmp ( string_replace res ( string_data needle ) ( string_data repl ) )
                    ( string_free res ) = res tmp ( string_free repl )

                    // 2. Drop the renamed `declare <ret> @__nurl_<name>_stub(...)`
                    //    line. Without this, clang errors "invalid redefinition" —
                    //    a `declare` (external linkage) followed by `define
                    //    internal` for the same name is treated as a conflict
                    //    even though logically the define satisfies the declare.
                    //    The declare comes from nurlc emitting the FFI prototype;
                    //    we don't want it once we provide our own definition.
                    ?? body_o { T body → {
                            // body is `s` (string literal). Locate ` {` via nurl_str_find
                            // — string_index_of needs a String, not a raw `s`. The IR
                            // template strings we declared above always end in ` { … }`
                            // so the find returns ≥ 0.
                            : i sp_idx ( nurl_str_find body ` {` )
                            ? >= sp_idx 0 {
                                // Build `declare ` + body[0..sp_idx] + `\n` and delete it
                                // from `res`. The renamed declare lives there from step 1.
                                : String body_str ( string_from body )
                                : String prefix ( string_substr body_str 0 sp_idx )
                                : String declare_line ( string_from `declare ` )
                                ( string_push_str declare_line ( string_data prefix ) )
                                ( string_push_char declare_line 10 )
                                : String tmp2 ( string_replace res ( string_data declare_line ) `` )
                                ( string_free res ) = res tmp2
                                ( string_free declare_line ) ( string_free prefix ) ( string_free body_str )
                            } {}

                            // 3. Append the stub definition.
                            ( string_push_str shims `define internal ` )
                            ( string_push_str shims body )
                            ( string_push_str shims `\n` )
                        } F _ → {} }
                } {}
                ( string_free needle )
            } F _ → {} }
        = pi + pi 1
    }
    ( vec_free [s] posix_names ) ( vec_free [s] posix_bodies )

    : String joined ( string_concat res shims )
    ( string_free res ) ( string_free shims )

    // Restore the `@` masked in step 0. The sentinel only exists inside
    // string constants we masked; the appended shims never contain it.
    : String final ( string_replace joined ( __ir_at_sentinel ) `@` )
    ( string_free joined )
    ^ final
}

// ── Shared logic ─────────────────────────────────────────────────────

@ get_common_json Json root s key s default → s {
    : ?Json opt ( json_obj_get root key )
    ?? opt { T j → { ^ ( json_str_data j ) } F _ → { ^ default } }
}

@ get_common_bool Json root s key b default → b {
    : ?Json opt ( json_obj_get root key )
    ?? opt { T j → { ^ ( json_bool_val j ) } F _ → { ^ default } }
}

@ json_str_or_null s str → Json {
    ? == ( nurl_str_len str ) 0 { ^ ( json_null ) } { ^ ( json_str_lit str ) }
}

// ── Build-response helpers (shared by /build*, mirrors api/'s shape) ──

// Build the standard { name, bytes, download_url, token } artifact object.
// `token` is `<build_id>/<name>` — the same opaque identifier used by the
// /download/<build_id>/<name> route, exposed separately so clients can
// reconstruct the URL without re-parsing it (matches api/'s BuildArtifact).
@ make_artifact_json s name i bytes s build_id → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `name` ( json_str_lit name ) )
    ( json_obj_set o `bytes` ( json_int bytes ) )
    : String token ( string_with_cap 64 )
    ( string_push_str token build_id )
    ( string_push_str token `/` )
    ( string_push_str token name )
    : String url ( string_with_cap 64 )
    ( string_push_str url `/download/` )
    ( string_push_str url ( string_data token ) )
    ( json_obj_set o `download_url` ( json_str_lit ( string_data url ) ) )
    ( json_obj_set o `token` ( json_str_lit ( string_data token ) ) )
    ( string_free url )
    ( string_free token )
    ^ o
}

// Concatenate nurlc + clang stderr blobs into one combined log, mirror
// of Python's `"\n".join(s for s in stderr_log if s).strip()`. Returns
// an owned String — caller frees.
@ combine_stderr s a s b → String {
    : i la ( nurl_str_len a )
    : i lb ( nurl_str_len b )
    : String out ( string_with_cap + + la lb 2 )
    ? > la 0 { ( string_push_str out a ) } {}
    ? & > la 0 > lb 0 { ( string_push_char out 10 ) } {}
    ? > lb 0 { ( string_push_str out b ) } {}
    // No post-trim: nurlc/clang stderr blobs are already line-terminated
    // and the playground's <pre> rendering tolerates the trailing newline.
    // Trimming inline triggered a double-free against the explicit `out`
    // free + compiler auto-drop on the trimmed-branch return path.
    ^ out
}

// Parse nurlc stderr blob into a Json array of
// `{ "file": str, "line": int, "col": int, "message": str }` entries.
// Each line that matches `file:line:col: message` becomes one entry;
// non-matching lines are ignored (so debug prints + warnings don't
// pollute the structured diagnostics).
@ parse_nurlc_diagnostics s blob → Json {
    : Json arr ( json_arr_new )
    : i n ( nurl_str_len blob )
    ? <= n 0 { ^ arr } {}

    : ~ i lo 0  // line start
    : ~ i k 0  // cursor
    ~ <= k n {
        : b at_end | == k n == ( nurl_str_get blob k ) 10
        ? at_end {
            // Process [lo, k) as one line.
            ? > k lo {
                // Find first three ':' positions.
                : ~ i c1 - 0 1
                : ~ i c2 - 0 1
                : ~ i c3 - 0 1
                : ~ i j lo
                ~ < j k {
                    ? == ( nurl_str_get blob j ) 58 {
                        ? < c1 0 { = c1 j } {
                            ? < c2 0 { = c2 j } {
                                ? < c3 0 { = c3 j } {}
                            }
                        }
                    } {}
                    = j + j 1
                }
                ? & & & >= c1 0 >= c2 0 >= c3 0 < c3 k {
                    // file = blob[lo..c1], line = parse(blob[c1+1..c2]),
                    // col = parse(blob[c2+1..c3]), msg = blob[c3+2..k] (skip ": ")
                    : s file_s ( nurl_str_slice blob lo - c1 lo )
                    : s line_s ( nurl_str_slice blob + c1 1 - c2 + c1 1 )
                    : s col_s ( nurl_str_slice blob + c2 1 - c3 + c2 1 )
                    // Skip leading whitespace after the third colon.
                    : ~ i ms + c3 1
                    ~ & < ms k == ( nurl_str_get blob ms ) 32 { = ms + ms 1 }
                    : s msg_s ( nurl_str_slice blob ms - k ms )
                    // Validate line+col are digit-only.
                    : ~ b digits_only T
                    : ~ i lp 0
                    ~ < lp ( nurl_str_len line_s ) {
                        : i ch ( nurl_str_get line_s lp )
                        ? | < ch 48 > ch 57 { = digits_only F } {}
                        = lp + lp 1
                    }
                    : ~ i cp 0
                    ~ < cp ( nurl_str_len col_s ) {
                        : i ch ( nurl_str_get col_s cp )
                        ? | < ch 48 > ch 57 { = digits_only F } {}
                        = cp + cp 1
                    }
                    ? & digits_only > ( nurl_str_len file_s ) 0 {
                        : i line_n ( nurl_str_to_int line_s )
                        : i col_n ( nurl_str_to_int col_s )
                        : Json o ( json_obj_new )
                        ( json_obj_set o `file` ( json_str_lit file_s ) )
                        ( json_obj_set o `line` ( json_int line_n ) )
                        ( json_obj_set o `col` ( json_int col_n ) )
                        ( json_obj_set o `message` ( json_str_lit msg_s ) )
                        ( json_arr_push arr o )
                    } {}
                    // file_s/line_s/col_s/msg_s are nurl_str_slice results —
                    // already on the compiler's auto-drop list. Explicit
                    // nurl_free here would be a double-free.
                } {}
            } {}
            = lo + k 1
        } {}
        = k + k 1
    }
    ^ arr
}

// Stamp the shared BuildResponse fields onto `res`. Mirrors api/'s
// BuildResponse exactly so the playground's renderer works unchanged.
// Caller owns `res` and `combined_*` (which are NOT freed here).
//
// `ll_artifact` / `binary_artifact` are emitted as `null` here so every
// response has the same key set; success paths overwrite them via
// `json_obj_set` (which replaces in-place) after this call returns.
@ stamp_build_response Json res s status s message s filename
b uses_canvas
i nurlc_rc s nurlc_stderr i nurlc_stdout_bytes
i clang_rc s clang_stdout s clang_stderr
s combined_stdout s combined_stderr → v {
    ( json_obj_set res `status` ( json_str_lit status ) )
    ( json_obj_set res `message` ( json_str_lit message ) )
    ( json_obj_set res `filename` ( json_str_lit filename ) )
    ( json_obj_set res `uses_canvas` ( json_bool uses_canvas ) )
    ( json_obj_set res `nurlc_returncode` ( json_int nurlc_rc ) )
    ( json_obj_set res `nurlc_stdout_bytes` ( json_int nurlc_stdout_bytes ) )
    ( json_obj_set res `nurlc_stderr` ( json_str_or_null nurlc_stderr ) )
    // clang_rc == -1 is the "clang never ran" sentinel — emit null to match
    // api/'s `clang_returncode: int | None` shape.
    ? == clang_rc - 0 1
    { ( json_obj_set res `clang_returncode` ( json_null ) ) }
    { ( json_obj_set res `clang_returncode` ( json_int clang_rc ) ) }
    ( json_obj_set res `clang_stdout` ( json_str_or_null clang_stdout ) )
    ( json_obj_set res `clang_stderr` ( json_str_or_null clang_stderr ) )
    ( json_obj_set res `stdout` ( json_str_lit combined_stdout ) )
    ( json_obj_set res `stderr` ( json_str_lit combined_stderr ) )
    ( json_obj_set res `nurlc_errors` ( parse_nurlc_diagnostics nurlc_stderr ) )
    ( json_obj_set res `ll_artifact` ( json_null ) )
    ( json_obj_set res `binary_artifact` ( json_null ) )
}

// Append the native-build runtime libs to the clang command. Matches
// what nurl.sh produces locally so a /build link succeeds against the
// committed stdlib/runtime.native.o (FFI-rich: libcurl + openssl +
// sqlite3 + libpq + zlib + zstd).
@ push_native_runtime_libs ( Vec s ) args → v {
    ( vec_push [s] args `-lm` )
    ( vec_push [s] args `-lpthread` )
    ( vec_push [s] args `-lcurl` )
    ( vec_push [s] args `-lssl` )
    ( vec_push [s] args `-lcrypto` )
    ( vec_push [s] args `-lsqlite3` )
    ( vec_push [s] args `-lpq` )
    ( vec_push [s] args `-lz` )
    ( vec_push [s] args `-lzstd` )
}

// Build a 200 OK JSON response for the nurlc-failed-before-link path.
// Mirrors api/'s behaviour (status=error, returncode != 0, structured
// nurlc_errors[]) so the playground's BUILD FAILED renderer works
// uniformly across success + failure + partial-failure cases.
//
// String/Json bindings are auto-dropped at scope exit — do NOT add
// explicit string_free / json_free for `combined`, `res`, `body`
// here (the compiler emits both, double-freeing).
@ nurlc_failure_response s filename i nurlc_rc s nurlc_stderr i nurlc_stdout_bytes → HttpResponse {
    : String combined ( combine_stderr nurlc_stderr `` )
    : Json res ( json_obj_new )
    ( stamp_build_response res
    `error` `nurlc failed` filename F
    nurlc_rc nurlc_stderr nurlc_stdout_bytes
    - 0 1 `` ``
    `` ( string_data combined ) )
    : String body ( json_stringify res )
    : HttpResponse hr ( response_text 200 ( string_data body ) )
    ( response_set_header hr `Content-Type` `application/json` )
    ^ hr
}

// Detect a native-only library dependency that the WebAssembly / Windows
// cross-builds can't satisfy (those targets don't ship the library), so we
// can report a clear message instead of the raw linker wall of undefined
// symbols (e.g. `undefined symbol: PQexec`). Returns a human description of
// the library, or empty if the source needs none. Keyed off the stdlib
// import path — the reliable signal.
@ native_only_dep s source → s {
    ? >= ( nurl_str_find source `stdlib/ext/postgres.nu` ) 0
    { ^ `the PostgreSQL client (libpq, via stdlib/ext/postgres.nu)` } {}
    ^ ``
}

// A clean "BUILD FAILED" JSON response for a program whose native-only
// dependency has no build on `target` ("WebAssembly" / "Windows"). Renders
// through the playground's normal failure path (status=error, message +
// stderr), not a scary linker dump.
@ unsupported_target_response s filename s libdesc s target → HttpResponse {
    : String msg ( string_from `This program uses ` )
    ( string_push_str msg libdesc )
    ( string_push_str msg `, which has no ` )
    ( string_push_str msg target )
    ( string_push_str msg ` build — only the Native (Linux) target can link it. Switch to the Native target to build and run this example.` )
    : Json res ( json_obj_new )
    ( stamp_build_response res `error` ( string_data msg ) filename F
    0 `` 0 - 0 1 `` `` `` ( string_data msg ) )
    : String body ( json_stringify res )
    : HttpResponse hr ( response_text 200 ( string_data body ) )
    ( response_set_header hr `Content-Type` `application/json` )
    ^ hr
}

@ get_body_str HttpRequest req → String {
    : i blen ( vec_len [u] . req body )
    : String body_str ( string_with_cap + blen 1 )
    : ~ i bi 0 ~ < bi blen { : ?u co ( vec_get [u] . req body bi ) ?? co { T c → { ( string_push_char body_str c ) } F → {} } = bi + bi 1 } ( __string_seal body_str )
    ^ body_str
}

// ── Build handler (Native Linux) ─────────────────────────────────────

@ h_build HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] POST /build\n` )
    : String body_str ( get_body_str req )
    : !Json JsonError root_res ( json_parse ( string_data body_str ) )
    ?? root_res {
        T root → {
            : s source ( get_common_json root `source` `` )
            ? == ( nurl_str_len source ) 0 { ( json_free root ) ( string_free body_str ) ^ ( response_text 400 `{"error":"source is required"}\n` ) } {}
            : s filename ( get_common_json root `filename` `main.nu` )
            : s opt ( get_common_json root `opt` `-O2` )

            : String build_id ( create_build_id )
            : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )

            : !v IoErr dr ( dir_create ( string_data build_dir ) )
            ?? dr {
                T _ → {
                    : String nu_path ( path_join ( string_data build_dir ) filename )
                    ( write_file ( string_data nu_path ) source )
                    : ~ String bin_name ( string_from filename )
                    ? ( string_ends_with bin_name `.nu` ) { : String tmp ( string_substr bin_name 0 - ( string_len bin_name ) 3 ) ( string_free bin_name ) = bin_name tmp } {}
                    : String ll_name ( string_from ( string_data bin_name ) ) ( string_push_str ll_name `.ll` )
                    : String ll_path ( path_join ( string_data build_dir ) ( string_data ll_name ) )
                    : String bin_path ( path_join ( string_data build_dir ) ( string_data bin_name ) )

                    : b uses_canvas >= ( nurl_str_find source `stdlib/ext/canvas.nu` ) 0

                    : ( Vec s ) nurlc_args ( vec_new [s] ) ( vec_push [s] nurlc_args ( string_data nu_path ) )
                    : !Output ProcessErr nurlc_res ( process_run ( string_data ( get_nurlc_path ) ) nurlc_args `` ) ( vec_free [s] nurlc_args )

                    ?? nurlc_res {
                        T n_out → {
                            : i n_rc ( output_exit_code n_out )
                            ? ( output_success n_out ) {
                                ( write_file ( string_data ll_path ) ( output_stdout n_out ) )
                                : ( Vec s ) clang_args ( vec_new [s] )
                                ( vec_push [s] clang_args opt )
                                ( vec_push [s] clang_args `-Wno-override-module` )
                                ( vec_push [s] clang_args ( string_data ll_path ) )
                                : String runtime_o ( path_join ( string_data ( get_stdlib_dir ) ) `runtime.native.o` )
                                ( vec_push [s] clang_args ( string_data runtime_o ) )
                                ( vec_push [s] clang_args `-o` )
                                ( vec_push [s] clang_args ( string_data bin_path ) )
                                ( push_native_runtime_libs clang_args )

                                : !Output ProcessErr clang_res ( process_run `clang` clang_args `` ) ( vec_free [s] clang_args )

                                ?? clang_res {
                                    T c_out → {
                                        : i c_rc ( output_exit_code c_out )
                                        : i n_so_bytes ( nurl_str_len ( output_stdout n_out ) )
                                        : s c_so ( output_stdout c_out )
                                        : s c_se ( output_stderr c_out )
                                        : s n_se ( output_stderr n_out )
                                        : String combined_stderr ( combine_stderr n_se c_se )

                                        : Json res ( json_obj_new )
                                        ( stamp_build_response res
                                        ? == c_rc 0 `ok` `error`
                                        ? == c_rc 0 `compiled nurl → native binary` `build failed (see stderr)`
                                        filename uses_canvas
                                        n_rc n_se n_so_bytes
                                        c_rc c_so c_se
                                        c_so ( string_data combined_stderr ) )

                                        ? == c_rc 0 {
                                            : !i IoErr ll_sz ( file_size ( string_data ll_path ) )
                                            : !i IoErr bn_sz ( file_size ( string_data bin_path ) )
                                            ( json_obj_set res `ll_artifact`
                                            ( make_artifact_json ( string_data ll_name )
                                            ?? ll_sz { T s → s F _ → 0 } ( string_data build_id ) ) )
                                            ( json_obj_set res `binary_artifact`
                                            ( make_artifact_json ( string_data bin_name )
                                            ?? bn_sz { T s → s F _ → 0 } ( string_data build_id ) ) )
                                        } {}

                                        : String body ( json_stringify res )
                                        : HttpResponse hr ( response_text 200 ( string_data body ) )
                                        ( response_set_header hr `Content-Type` `application/json` )

                                        ( string_free combined_stderr ) ( json_free res ) ( string_free runtime_o )
                                        ( output_free n_out ) ( output_free c_out ) ( json_free root )
                                        ( string_free nu_path ) ( string_free ll_name ) ( string_free ll_path )
                                        ( string_free bin_name ) ( string_free bin_path )
                                        ( string_free build_id ) ( string_free build_dir )
                                        ( string_free body_str ) ( string_free body )
                                        ^ hr
                                    }
                                    F ce → { ^ ( response_text 500 `{"error":"clang process failed"}\n` ) }
                                }
                            } {
                                : HttpResponse hr_err ( nurlc_failure_response filename ( output_exit_code n_out ) ( output_stderr n_out ) ( nurl_str_len ( output_stdout n_out ) ) )
                                ( output_free n_out ) ( json_free root ) ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name ) ( string_free bin_path ) ( string_free build_id ) ( string_free build_dir ) ( string_free body_str )
                                ^ hr_err
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
    : !Json JsonError root_res ( json_parse ( string_data body_str ) )
    ?? root_res {
        T root → {
            : s source ( get_common_json root `source` `` )
            ? == ( nurl_str_len source ) 0 { ( json_free root ) ( string_free body_str ) ^ ( response_text 400 `{"error":"source is required"}\n` ) } {}
            : s filename ( get_common_json root `filename` `main.nu` )
            // Native-only dependency (e.g. libpq) → no wasm build; report
            // cleanly instead of dumping the wasm-ld undefined-symbol wall.
            : s __wasm_nodep ( native_only_dep source )
            ? != 0 ( nurl_str_len __wasm_nodep )
            { ( json_free root ) ( string_free body_str )
                ^ ( unsupported_target_response filename __wasm_nodep `WebAssembly` ) } {}
            : b emit_ll ( get_common_bool root `emit_ll` F )
            // /build_wasm opt level — defaults to -O1 (was -O2). On serde_demo /
            // claude_chat / json_basic the -O2 link step accounted for 14-24 s of
            // the perceived "playground feels slow"; -O1 produces ~5-15% larger
            // .wasm but cuts compile time roughly in half. Caller can still
            // explicitly request `-O2` or `-Oz` via the JSON `opt` field.
            : s opt ( get_common_json root `opt` `-O1` )

            : String build_id ( create_build_id )
            : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )

            : !v IoErr dr ( dir_create ( string_data build_dir ) )
            ?? dr {
                T _ → {
                    : String nu_path ( path_join ( string_data build_dir ) filename )
                    ( write_file ( string_data nu_path ) source )
                    : ~ String bin_name ( string_from filename )
                    ? ( string_ends_with bin_name `.nu` ) { : String tmp ( string_substr bin_name 0 - ( string_len bin_name ) 3 ) ( string_free bin_name ) = bin_name tmp } {}
                    : String ll_name ( string_from ( string_data bin_name ) ) ( string_push_str ll_name `.ll` )
                    : String wasm_name ( string_from ( string_data bin_name ) ) ( string_push_str wasm_name `.wasm` )

                    : String ll_path ( path_join ( string_data build_dir ) ( string_data ll_name ) )
                    : ~ String wasm_path ( path_join ( string_data build_dir ) ( string_data wasm_name ) )

                    : b uses_canvas >= ( nurl_str_find source `stdlib/ext/canvas.nu` ) 0
                    : b uses_audio >= ( nurl_str_find source `stdlib/ext/audio.nu` ) 0

                    : ( Vec s ) nurlc_args ( vec_new [s] ) ( vec_push [s] nurlc_args ( string_data nu_path ) )
                    : !Output ProcessErr nurlc_res ( process_run ( string_data ( get_nurlc_path ) ) nurlc_args `` ) ( vec_free [s] nurlc_args )

                    ?? nurlc_res {
                        T n_out → {
                            : i n_rc ( output_exit_code n_out )
                            ? ( output_success n_out ) {
                                : String ir ( string_from ( output_stdout n_out ) )
                                : String ir_fixed ( prepare_ir_for_wasi ir )
                                ( write_file ( string_data ll_path ) ( string_data ir_fixed ) )
                                ( string_free ir )

                                // NURL regex doesn't support \b (unknown-escape falls through
                                // to literal 'b'), so the trailing `(` of the IR call/decl
                                // serves as the word boundary instead. Examples that import
                                // canvas/audio via direct `& \`canvas\`` declarations (not
                                // via stdlib/ext/canvas.nu) only show up in the post-IR scan,
                                // so this matters — sand.nu and doomfire.nu silently failed
                                // to link canvas.wasm.o until this fix.
                                : ~ b uses_canvas F
                                : !Regex ParseErr re_canv ( regex_compile `@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\(` )
                                ?? re_canv { T rc → { = uses_canvas ( regex_test rc ( string_data ir_fixed ) ) ( regex_free rc ) } F _ → {} }

                                : ~ b uses_audio F
                                : !Regex ParseErr re_aud ( regex_compile `@audio_(level|bin|bin_count|peak_bin|centroid|freq_of|sample_rate|is_silent|ready)\(` )
                                ?? re_aud { T ra → { = uses_audio ( regex_test ra ( string_data ir_fixed ) ) ( regex_free ra ) } F _ → {} }

                                : ( Vec s ) clang_args ( vec_new [s] )
                                ( vec_push [s] clang_args `--target=wasm32-wasi` ) ( vec_push [s] clang_args opt ) ( vec_push [s] clang_args `-Wno-override-module` ) ( vec_push [s] clang_args ( string_data ll_path ) )
                                ( vec_push [s] clang_args ( string_data ( get_runtime_wasm_o ) ) )
                                ? uses_canvas { ( vec_push [s] clang_args ( string_data ( get_canvas_wasm_o ) ) ) } {}
                                ? uses_audio { ( vec_push [s] clang_args ( string_data ( get_audio_wasm_o ) ) ) } {}
                                ? | uses_canvas uses_audio { ( vec_push [s] clang_args `-Wl,--allow-undefined` ) } {}
                                ( vec_push [s] clang_args `-o` ) ( vec_push [s] clang_args ( string_data wasm_path ) ) ( vec_push [s] clang_args `-lm` )

                                : !Output ProcessErr clang_res ( process_run ( string_data ( get_wasi_clang ) ) clang_args `` ) ( vec_free [s] clang_args )

                                ?? clang_res {
                                    T c_out → {
                                        : ~ i c_rc ( output_exit_code c_out )
                                        : s c_se ( output_stderr c_out )
                                        : s n_se ( output_stderr n_out )
                                        : String combined_stderr ( combine_stderr n_se c_se )

                                        // ── Asyncify wrap for canvas programs ──────────────────
                                        // canvas.sleep yields back to the browser event loop;
                                        // browser_wasi_shim drives this via `asyncify_get_state`
                                        // / `asyncify_start_unwind`. Without this pass the first
                                        // frame renders but the second `canvas_sleep` call hits
                                        // "asyncify_get_state is not a function". We restrict the
                                        // pass to `canvas.sleep` so the instrumentation overhead
                                        // stays minimal.
                                        ? & == c_rc 0 uses_canvas {
                                            : String async_name ( string_from ( string_data bin_name ) ) ( string_push_str async_name `.async.wasm` )
                                            : String asyncified_path ( path_join ( string_data build_dir ) ( string_data async_name ) )
                                            ( string_free async_name )
                                            : ( Vec s ) opt_args ( vec_new [s] )
                                            ( vec_push [s] opt_args `--asyncify` )
                                            ( vec_push [s] opt_args `--pass-arg=asyncify-imports@canvas.sleep` )
                                            ( vec_push [s] opt_args `-O2` )
                                            ( vec_push [s] opt_args ( string_data wasm_path ) )
                                            ( vec_push [s] opt_args `-o` )
                                            ( vec_push [s] opt_args ( string_data asyncified_path ) )
                                            : !Output ProcessErr opt_res ( process_run ( string_data ( get_wasm_opt ) ) opt_args `` )
                                            ( vec_free [s] opt_args )
                                            ?? opt_res {
                                                T o_out → {
                                                    : i opt_rc ( output_exit_code o_out )
                                                    ? == opt_rc 0 {
                                                        ( string_free wasm_path ) = wasm_path asyncified_path
                                                    } {
                                                        = c_rc opt_rc
                                                        ? > ( string_len combined_stderr ) 0 { ( string_push_char combined_stderr 10 ) } {}
                                                        ( string_push_str combined_stderr `wasm-opt --asyncify failed:\n` )
                                                        ( string_push_str combined_stderr ( output_stderr o_out ) )
                                                        ( string_free asyncified_path )
                                                    }
                                                    ( output_free o_out )
                                                }
                                                F _ → {
                                                    = c_rc 127
                                                    ? > ( string_len combined_stderr ) 0 { ( string_push_char combined_stderr 10 ) } {}
                                                    ( string_push_str combined_stderr `wasm-opt not found at ` )
                                                    ( string_push_str combined_stderr ( string_data ( get_wasm_opt ) ) )
                                                    ( string_push_str combined_stderr ` — canvas requires binaryen (apt install binaryen)` )
                                                    ( string_free asyncified_path )
                                                }
                                            }
                                        } {}

                                        : Json res ( json_obj_new )
                                        ( json_obj_set res `status` ( json_str_lit ? == c_rc 0 `ok` `error` ) )
                                        // Match native handler's message text so the playground's
                                        // build-info chip ("compiled" vs "build failed") agrees.
                                        ( json_obj_set res `message` ( json_str_lit ? == c_rc 0 `compiled nurl → wasm32-wasi` `build failed (see stderr)` ) )
                                        ( json_obj_set res `filename` ( json_str_lit filename ) )
                                        ( json_obj_set res `wasm_base64` ( json_null ) )
                                        ( json_obj_set res `wasm_bytes` ( json_int 0 ) )
                                        ( json_obj_set res `nurlc_returncode` ( json_int n_rc ) )
                                        ( json_obj_set res `nurlc_stderr` ( json_str_or_null n_se ) )
                                        ( json_obj_set res `nurlc_errors` ( parse_nurlc_diagnostics n_se ) )
                                        ( json_obj_set res `clang_returncode` ( json_int c_rc ) )
                                        ( json_obj_set res `clang_stderr` ( json_str_or_null c_se ) )
                                        // Unified `stderr` mirrors stamp_build_response; the
                                        // playground's BUILD FAILED renderer only looks at this
                                        // field + nurlc_stderr, so omitting it (as the original
                                        // code did) silently swallowed wasi-clang errors like
                                        // "undefined symbol: canvas_open".
                                        ( json_obj_set res `stderr` ( json_str_lit ( string_data combined_stderr ) ) )
                                        ( json_obj_set res `llvm_ir` ? | emit_ll != c_rc 0 { ( json_str_lit ( string_data ir_fixed ) ) } { ( json_null ) } )
                                        ( json_obj_set res `uses_canvas` ( json_bool uses_canvas ) )
                                        ( json_obj_set res `uses_audio` ( json_bool uses_audio ) )

                                        : ~ String b64 ( string_new ) : ~ String wasm_url ( string_new )
                                        ? == c_rc 0 {
                                            : !i IoErr wasm_size_res ( file_size ( string_data wasm_path ) )
                                            : i w_bytes ?? wasm_size_res { T s → s F _ → 0 }
                                            ( json_obj_set res `wasm_bytes` ( json_int w_bytes ) )
                                            : !( Vec u ) IoErr wasm_data_res ( read_file_bytes ( string_data wasm_path ) )
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

                                        ( string_free b64 ) ( string_free wasm_url ) ( string_free combined_stderr ) ( json_free res ) ( string_free ir_fixed )
                                        ( output_free n_out ) ( output_free c_out ) ( json_free root )
                                        ( string_free nu_path ) ( string_free ll_name ) ( string_free ll_path ) ( string_free wasm_name ) ( string_free wasm_path )
                                        ( string_free build_id ) ( string_free build_dir ) ( string_free body_str ) ( string_free body )
                                        ^ hr
                                    }
                                    F ce → { ( string_free ir_fixed ) ^ ( response_text 500 `{"error":"wasi-clang failed"}\n` ) }
                                }
                            } {
                                : HttpResponse hr_err ( nurlc_failure_response filename ( output_exit_code n_out ) ( output_stderr n_out ) ( nurl_str_len ( output_stdout n_out ) ) )
                                ( output_free n_out ) ( json_free root ) ( string_free nu_path ) ( string_free ll_path ) ( string_free wasm_path ) ( string_free build_id ) ( string_free build_dir ) ( string_free body_str )
                                ^ hr_err
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
    : !Json JsonError root_res ( json_parse ( string_data body_str ) )
    ?? root_res {
        T root → {
            : s source ( get_common_json root `source` `` )
            ? == ( nurl_str_len source ) 0 { ( json_free root ) ( string_free body_str ) ^ ( response_text 400 `{"error":"source is required"}\n` ) } {}
            : s filename ( get_common_json root `filename` `main.nu` )
            // Native-only dependency (e.g. libpq) → no Windows cross-build;
            // report cleanly instead of the mingw undefined-reference wall.
            : s __win_nodep ( native_only_dep source )
            ? != 0 ( nurl_str_len __win_nodep )
            { ( json_free root ) ( string_free body_str )
                ^ ( unsupported_target_response filename __win_nodep `Windows` ) } {}
            : s opt ( get_common_json root `opt` `-O2` )
            : String build_id ( create_build_id )
            : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )
            : !v IoErr dr ( dir_create ( string_data build_dir ) )
            ?? dr {
                T _ → {
                    : String nu_path ( path_join ( string_data build_dir ) filename )
                    ( write_file ( string_data nu_path ) source )
                    : String ll_path ( path_join ( string_data build_dir ) `main.ll` )
                    : ~ String bin_name ( string_from filename )
                    ? ( string_ends_with bin_name `.nu` ) { : String tmp ( string_substr bin_name 0 - ( string_len bin_name ) 3 ) ( string_free bin_name ) = bin_name tmp } {}
                    ( string_push_str bin_name `.exe` )
                    : String bin_path ( path_join ( string_data build_dir ) ( string_data bin_name ) )
                    : ( Vec s ) nurlc_args ( vec_new [s] ) ( vec_push [s] nurlc_args ( string_data nu_path ) )
                    : !Output ProcessErr nurlc_res ( process_run ( string_data ( get_nurlc_path ) ) nurlc_args `` ) ( vec_free [s] nurlc_args )
                    ?? nurlc_res {
                        T n_out → {
                            : i n_rc ( output_exit_code n_out )
                            ? ( output_success n_out ) {
                                ( write_file ( string_data ll_path ) ( output_stdout n_out ) )

                                // Two-step build: (1) clang --target=mingw -c → .o,
                                // (2) x86_64-w64-mingw32-gcc to link with libgcc /
                                // libwinpthread / static libcurl. Single-step clang link
                                // fails on -lgcc lookup since clang's mingw driver can't
                                // resolve mingw-w64's installed support libs by itself.
                                : String obj_path ( path_join ( string_data build_dir ) `main.o` )

                                : ( Vec s ) clang_args ( vec_new [s] )
                                ( vec_push [s] clang_args opt )
                                ( vec_push [s] clang_args `-Wno-override-module` )
                                ( vec_push [s] clang_args `--target=x86_64-w64-mingw32` )
                                // Emit one section per function/datum so the linker's
                                // --gc-sections (below) can drop the parts of the runtime
                                // this program never calls — e.g. the TCP/TLS code that
                                // otherwise drags in ws2_32 / crypt32 / bcrypt imports.
                                ( vec_push [s] clang_args `-ffunction-sections` )
                                ( vec_push [s] clang_args `-fdata-sections` )
                                ( vec_push [s] clang_args `-c` )
                                ( vec_push [s] clang_args ( string_data ll_path ) )
                                ( vec_push [s] clang_args `-o` )
                                ( vec_push [s] clang_args ( string_data obj_path ) )
                                : !Output ProcessErr clang_res ( process_run `clang` clang_args `` ) ( vec_free [s] clang_args )

                                ?? clang_res {
                                    T c_out → {
                                        : i c_rc ( output_exit_code c_out )

                                        // Build the linker command once. We always run mingw-
                                        // gcc — if the compile failed it still gets called but
                                        // exits with its own (informative) error.
                                        : ( Vec s ) link_args ( vec_new [s] )
                                        ( vec_push [s] link_args opt )
                                        // -s strips the COFF symbol table + DWARF debug
                                        // sections, which are the bulk of an unstripped mingw
                                        // binary (~halves the .exe on its own). --gc-sections
                                        // is kept too, but mingw's PE linker barely acts on it
                                        // — it does NOT drop unused runtime code on COFF the
                                        // way ELF ld does. That dead-code removal is handled
                                        // instead by the curl-variant split below.
                                        ( vec_push [s] link_args `-s` )
                                        ( vec_push [s] link_args `-Wl,--gc-sections` )
                                        ( vec_push [s] link_args ( string_data obj_path ) )

                                        // Pick the runtime variant. The default runtime.win.o
                                        // is built WITHOUT libcurl; a program only needs the
                                        // curl bridge when it pulls in stdlib/ext/http.nu,
                                        // which surfaces as nurl_curl_* references in the IR.
                                        // For those we swap in runtime.win.curl.o and link
                                        // static libcurl + its Schannel deps. This keeps
                                        // libcurl (a few hundred KB of .text, plus the
                                        // bcrypt/crypt32/secur32 imports) out of every
                                        // non-HTTP exe — which PE --gc-sections cannot do.
                                        : String curl_marker ( path_join ( string_data ( get_stdlib_dir ) ) `runtime.win.curl` )
                                        : b uses_curl & ( file_exists ( string_data curl_marker ) ) >= ( nurl_str_find ( output_stdout n_out ) `nurl_curl` ) 0
                                        ? uses_curl { ( vec_push [s] link_args ( string_data ( get_runtime_win_curl_o ) ) ) }
                                        { ( vec_push [s] link_args ( string_data ( get_runtime_win_o ) ) ) }

                                        // Static-link libgcc + winpthread so the .exe doesn't
                                        // depend on libgcc_s_seh-1.dll / libwinpthread-1.dll
                                        // — those aren't present on a stock Windows install,
                                        // and missing them makes the program exit silently
                                        // with STATUS_DLL_NOT_FOUND (0xC0000135), which looks
                                        // exactly like "the exe runs but prints nothing".
                                        // System DLL imports stay dynamic via -Wl,-Bdynamic.
                                        ( vec_push [s] link_args `-static-libgcc` )
                                        ( vec_push [s] link_args `-Wl,-Bstatic` )
                                        ( vec_push [s] link_args `-lpthread` )
                                        ( vec_push [s] link_args `-Wl,-Bdynamic` )
                                        : String curl_L ( string_with_cap 64 )
                                        ? uses_curl {
                                            ( string_push_str curl_L `-L` )
                                            ( string_push_str curl_L ( string_data ( get_mingw_curl_prefix ) ) )
                                            ( string_push_str curl_L `/lib` )
                                            ( vec_push [s] link_args ( string_data curl_L ) )
                                            ( vec_push [s] link_args `-lcurl` )
                                            ( vec_push [s] link_args `-lws2_32` )
                                            ( vec_push [s] link_args `-lcrypt32` )
                                            ( vec_push [s] link_args `-lbcrypt` )
                                            ( vec_push [s] link_args `-lncrypt` )
                                            ( vec_push [s] link_args `-lsecur32` )
                                            ( vec_push [s] link_args `-ladvapi32` )
                                        } {
                                            // The curl-free runtime still carries the TCP
                                            // (winsock), random (advapi32/bcrypt) and WinHTTP
                                            // paths. Without libcurl the HTTP backend falls
                                            // back to WinHTTP (nurl_http_perform_full_to), so
                                            // -lwinhttp is required even for non-HTTP programs
                                            // since the whole object is linked. These are all
                                            // tiny system import libs — no static bloat.
                                            ( vec_push [s] link_args `-lws2_32` )
                                            ( vec_push [s] link_args `-ladvapi32` )
                                            ( vec_push [s] link_args `-lbcrypt` )
                                            ( vec_push [s] link_args `-lwinhttp` )
                                        }
                                        ( vec_push [s] link_args `-o` )
                                        ( vec_push [s] link_args ( string_data bin_path ) )
                                        : !Output ProcessErr link_res ( process_run ( string_data ( get_mingw_gcc ) ) link_args `` )
                                        ( vec_free [s] link_args )

                                        ?? link_res {
                                            T l_out → {
                                                : i lnk_rc ( output_exit_code l_out )
                                                : i n_so_bytes ( nurl_str_len ( output_stdout n_out ) )
                                                : s c_so ( output_stdout c_out )
                                                : s c_se ( output_stderr c_out )
                                                : s n_se ( output_stderr n_out )
                                                : s l_se ( output_stderr l_out )
                                                : String stage1 ( combine_stderr n_se c_se )
                                                : String combined_stderr ( combine_stderr ( string_data stage1 ) l_se )

                                                : i final_rc ? != c_rc 0 c_rc lnk_rc
                                                : b ok & == c_rc 0 == lnk_rc 0

                                                : Json res ( json_obj_new )
                                                ( stamp_build_response res
                                                ? ok `ok` `error`
                                                ? ok `compiled nurl → windows .exe` `build failed (see stderr)`
                                                filename F
                                                n_rc n_se n_so_bytes
                                                final_rc c_so c_se
                                                c_so ( string_data combined_stderr ) )

                                                ? ok {
                                                    : !i IoErr bn_sz ( file_size ( string_data bin_path ) )
                                                    ( json_obj_set res `binary_artifact`
                                                    ( make_artifact_json ( string_data bin_name )
                                                    ?? bn_sz { T s → s F _ → 0 } ( string_data build_id ) ) )
                                                } {}

                                                : String body ( json_stringify res )
                                                : HttpResponse hr ( response_text 200 ( string_data body ) )
                                                ( response_set_header hr `Content-Type` `application/json` )
                                                ( string_free stage1 ) ( string_free combined_stderr ) ( json_free res )
                                                ( output_free n_out ) ( output_free c_out ) ( output_free l_out ) ( json_free root )
                                                ( string_free curl_marker ) ( string_free curl_L )
                                                ( string_free nu_path ) ( string_free ll_path ) ( string_free obj_path )
                                                ( string_free bin_name ) ( string_free bin_path )
                                                ( string_free build_id ) ( string_free build_dir )
                                                ( string_free body_str ) ( string_free body )
                                                ^ hr
                                            }
                                            F _ → { ^ ( response_text 500 `{"error":"mingw-gcc invocation failed"}\n` ) }
                                        }
                                    } F ce → { ^ ( response_text 500 `{"error":"clang process failed"}\n` ) } }
                            } {
                                : HttpResponse hr_err ( nurlc_failure_response filename ( output_exit_code n_out ) ( output_stderr n_out ) ( nurl_str_len ( output_stdout n_out ) ) )
                                ( output_free n_out ) ( json_free root ) ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name ) ( string_free bin_path ) ( string_free build_id ) ( string_free build_dir ) ( string_free body_str )
                                ^ hr_err
                            } } F _ → { ^ ( response_text 500 `{"error":"nurlc failed"}\n` ) } }
                } F _ → { ^ ( response_text 500 `{"error":"could not create build dir"}\n` ) } } } F _ → { ^ ( response_text 400 `{"error":"invalid json"}\n` ) } }
}

// ── Build handler (macOS) ────────────────────────────────────────────

@ h_build_macos HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] POST /build_macos\n` )
    : String body_str ( get_body_str req )
    : !Json JsonError root_res ( json_parse ( string_data body_str ) )
    ?? root_res {
        T root → {
            : s source ( get_common_json root `source` `` )
            ? == ( nurl_str_len source ) 0 { ( json_free root ) ( string_free body_str ) ^ ( response_text 400 `{"error":"source is required"}\n` ) } {}
            : s filename ( get_common_json root `filename` `main.nu` )
            : s opt ( get_common_json root `opt` `-O2` )
            : String build_id ( create_build_id )
            : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )
            : !v IoErr dr ( dir_create ( string_data build_dir ) )
            ?? dr {
                T _ → {
                    : String nu_path ( path_join ( string_data build_dir ) filename )
                    ( write_file ( string_data nu_path ) source )
                    : String ll_path ( path_join ( string_data build_dir ) `main.ll` )
                    : ~ String bin_name ( string_from filename )
                    ? ( string_ends_with bin_name `.nu` ) { : String tmp ( string_substr bin_name 0 - ( string_len bin_name ) 3 ) ( string_free bin_name ) = bin_name tmp } {}
                    : String bin_path ( path_join ( string_data build_dir ) ( string_data bin_name ) )
                    : ( Vec s ) nurlc_args ( vec_new [s] ) ( vec_push [s] nurlc_args ( string_data nu_path ) )
                    : !Output ProcessErr nurlc_res ( process_run ( string_data ( get_nurlc_path ) ) nurlc_args `` ) ( vec_free [s] nurlc_args )
                    ?? nurlc_res {
                        T n_out → {
                            : i n_rc ( output_exit_code n_out )
                            ? ( output_success n_out ) {
                                ( write_file ( string_data ll_path ) ( output_stdout n_out ) )
                                : ( Vec s ) zig_args ( vec_new [s] )
                                ( vec_push [s] zig_args `cc` ) ( vec_push [s] zig_args `-target` ) ( vec_push [s] zig_args `x86_64-macos-none` ) ( vec_push [s] zig_args opt )
                                ( vec_push [s] zig_args `-Wno-override-module` ) ( vec_push [s] zig_args ( string_data ll_path ) ) ( vec_push [s] zig_args ( string_data ( get_runtime_mac_o ) ) ) ( vec_push [s] zig_args `-o` ) ( vec_push [s] zig_args ( string_data bin_path ) )
                                : !Output ProcessErr zig_res ( process_run ( string_data ( get_zig ) ) zig_args `` ) ( vec_free [s] zig_args )
                                ?? zig_res {
                                    T z_out → {
                                        : i z_rc ( output_exit_code z_out )
                                        : i n_so_bytes ( nurl_str_len ( output_stdout n_out ) )
                                        : s z_so ( output_stdout z_out )
                                        : s z_se ( output_stderr z_out )
                                        : s n_se ( output_stderr n_out )
                                        : String combined_stderr ( combine_stderr n_se z_se )

                                        : Json res ( json_obj_new )
                                        ( stamp_build_response res
                                        ? == z_rc 0 `ok` `error`
                                        ? == z_rc 0 `compiled nurl → macOS Mach-O` `build failed (see stderr)`
                                        filename F
                                        n_rc n_se n_so_bytes
                                        z_rc z_so z_se
                                        z_so ( string_data combined_stderr ) )

                                        ? == z_rc 0 {
                                            : !i IoErr bn_sz ( file_size ( string_data bin_path ) )
                                            ( json_obj_set res `binary_artifact`
                                            ( make_artifact_json ( string_data bin_name )
                                            ?? bn_sz { T s → s F _ → 0 } ( string_data build_id ) ) )
                                        } {}

                                        : String body ( json_stringify res )
                                        : HttpResponse hr ( response_text 200 ( string_data body ) )
                                        ( response_set_header hr `Content-Type` `application/json` )
                                        ( string_free combined_stderr ) ( json_free res )
                                        ( output_free n_out ) ( output_free z_out ) ( json_free root )
                                        ( string_free nu_path ) ( string_free ll_path )
                                        ( string_free bin_name ) ( string_free bin_path )
                                        ( string_free build_id ) ( string_free build_dir )
                                        ( string_free body_str ) ( string_free body )
                                        ^ hr
                                    } F ce → { ^ ( response_text 500 `{"error":"zig process failed"}\n` ) } }
                            } {
                                : HttpResponse hr_err ( nurlc_failure_response filename ( output_exit_code n_out ) ( output_stderr n_out ) ( nurl_str_len ( output_stdout n_out ) ) )
                                ( output_free n_out ) ( json_free root ) ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name ) ( string_free bin_path ) ( string_free build_id ) ( string_free build_dir ) ( string_free body_str )
                                ^ hr_err
                            } } F _ → { ^ ( response_text 500 `{"error":"nurlc failed"}\n` ) } }
                } F _ → { ^ ( response_text 500 `{"error":"could not create build dir"}\n` ) } } } F _ → { ^ ( response_text 400 `{"error":"invalid json"}\n` ) } }
}

// ── Examples handler ────────────────────────────────────────────────

@ h_examples HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /examples\n` )
    : String edir ( get_examples_dir )
    : !( Vec String ) IoErr dr ( dir_list ( string_data edir ) )
    ?? dr {
        T files → {
            : Json arr ( json_arr_new )
            : ~ i i 0 ~ < i ( vec_len [String] files ) {
                : ?String fs_opt ( vec_get [String] files i )
                ?? fs_opt { T f → { ? ( string_ends_with f `.nu` ) { : String fpath ( path_join ( string_data edir ) ( string_data f ) ) : !i IoErr szr ( file_size ( string_data fpath ) ) : Json obj ( json_obj_new ) ( json_obj_set obj `name` ( json_str_lit ( string_data f ) ) ) ( json_obj_set obj `path` ( json_str_lit ( string_data f ) ) ) ( json_obj_set obj `bytes` ( json_int ?? szr { T s → s F _ → 0 } ) ) ( json_arr_push arr obj ) ( string_free fpath ) } {} } F → {} }
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
    : ?String name_opt ( params_get params `name` )
    ?? name_opt { T name → {
            // A `.md` (e.g. examples/README.md) renders as HTML; `.nu` source
            // stays JSON for the playground's examples dropdown / wasm runner.
            : i nlen ( string_len name )
            ? & & & >= nlen 4
            == ( nurl_str_get ( string_data name ) - nlen 3 ) 46
            == ( nurl_str_get ( string_data name ) - nlen 2 ) 109
            == ( nurl_str_get ( string_data name ) - nlen 1 ) 100 {
                : String rel ( string_with_cap + nlen 10 )
                ( string_push_str rel `examples/` ) ( string_push_str rel ( string_data name ) )
                : HttpResponse mr ( __serve_repo_doc ( string_data rel ) )
                ( string_free rel ) ( string_free name )
                ^ mr
            } {}
            : String edir ( get_examples_dir )
            : String fpath ( path_join ( string_data edir ) ( string_data name ) )
            : !String IoErr cr ( read_file ( string_data fpath ) )
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

// Push a single string entry into a JSON array.
@ __mcp_info_push_str Json arr s v → v {
    ( json_arr_push arr ( json_str_lit v ) )
}

// Resolve the public base URL for the example mcp.json snippet. Prefer
// the NURL_PUBLIC_URL env var (production deployments behind a proxy
// terminate TLS upstream and need an absolute URL); fall back to the
// request's Host header with http://; degrade to http://localhost:8000
// if even that is missing. Returns an owned String.
@ __mcp_info_base_url HttpRequest req → String {
    : String env ( env_var_or `NURL_PUBLIC_URL` `` )
    : i envl ( string_len env )
    ? != envl 0 {
        ? ( string_ends_with env `/` ) {
            : String trimmed ( string_substr env 0 - envl 1 )
            ( string_free env )
            ^ trimmed
        } { ^ env }
    } { ( string_free env ) }
    : ?String host_opt ( header_get . req headers `Host` )
    ?? host_opt {
        T host → {
            : String out ( string_with_cap 64 )
            ( string_push_str out `http://` )
            ( string_push_str out ( string_data host ) )
            ( string_free host )
            ^ out
        }
        F _ → { ^ ( string_from `http://localhost:8000` ) }
    }
}

@ h_mcp_info HttpRequest req Params params → HttpResponse {
    : Json j ( json_obj_new )
    ( json_obj_set j `url_path` ( json_str_lit `/mcp` ) )
    ( json_obj_set j `transport` ( json_str_lit `streamable-http` ) )

    : Json tools ( json_arr_new )
    ( __mcp_info_push_str tools `nurl_build_native` )
    ( __mcp_info_push_str tools `nurl_build_windows` )
    ( __mcp_info_push_str tools `nurl_build_macos` )
    ( __mcp_info_push_str tools `nurl_build_wasm` )
    ( __mcp_info_push_str tools `nurl_build_target` )
    ( __mcp_info_push_str tools `nurl_list_examples` )
    ( __mcp_info_push_str tools `nurl_read_example` )
    ( __mcp_info_push_str tools `nurl_list_stdlib` )
    ( __mcp_info_push_str tools `nurl_read_stdlib` )
    ( __mcp_info_push_str tools `nurl_list_tests` )
    ( __mcp_info_push_str tools `nurl_read_test` )
    ( __mcp_info_push_str tools `nurl_read_grammar` )
    ( __mcp_info_push_str tools `nurl_read_readme` )
    ( __mcp_info_push_str tools `nurl_read_roadmap` )
    ( __mcp_info_push_str tools `nurl_read_gotchas` )
    ( __mcp_info_push_str tools `nurl_changelog` )
    ( json_obj_set j `tools` tools )

    : Json resources ( json_arr_new )
    ( __mcp_info_push_str resources `nurl://grammar` )
    ( __mcp_info_push_str resources `nurl://readme` )
    ( __mcp_info_push_str resources `nurl://roadmap` )
    ( __mcp_info_push_str resources `nurl://gotchas` )
    ( __mcp_info_push_str resources `nurl://stdlib/{path}` )
    ( __mcp_info_push_str resources `nurl://example/{name}` )
    ( __mcp_info_push_str resources `nurl://test/{name}` )
    ( json_obj_set j `resources` resources )

    : Json prompts ( json_arr_new )
    ( __mcp_info_push_str prompts `nurl_coding_assistant` )
    ( json_obj_set j `prompts` prompts )

    // client_config_example: { mcpServers: { nurl: { url, transport } } }
    : String base ( __mcp_info_base_url req )
    : String mcp_url ( string_with_cap + ( string_len base ) 4 )
    ( string_push_str mcp_url ( string_data base ) )
    ( string_push_str mcp_url `/mcp` )
    : Json nurl_entry ( json_obj_new )
    ( json_obj_set nurl_entry `url` ( json_str_lit ( string_data mcp_url ) ) )
    ( json_obj_set nurl_entry `transport` ( json_str_lit `streamable-http` ) )
    : Json servers ( json_obj_new )
    ( json_obj_set servers `nurl` nurl_entry )
    : Json client_cfg ( json_obj_new )
    ( json_obj_set client_cfg `mcpServers` servers )
    ( json_obj_set j `client_config_example` client_cfg )

    : String body ( json_stringify j )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( json_free j ) ( string_free body ) ( string_free base ) ( string_free mcp_url )
    ^ r
}

// ── OpenAPI 3.1 schema served at /openapi.json ────────────────────
//
// Minimal but valid OpenAPI doc — enumerates every public route and
// gives a one-line summary per endpoint. Schemas are kept loose (no
// `$ref` chains) so the doc is self-contained and doesn't require us
// to mirror api/'s 24-schema component map. Adequate for tooling
// (Swagger UI, openapi-clients) that wants endpoint discovery.

// Helper: append one `{method: { summary, responses: { "200": ... } }}`
// entry under `path` in `paths`.
@ __oa_path Json paths s path s method s summary s desc → v {
    : Json op ( json_obj_new )
    : Json tags ( json_arr_new ) ( json_arr_push tags ( json_str_lit `default` ) )
    ( json_obj_set op `tags` tags )
    ( json_obj_set op `summary` ( json_str_lit summary ) )
    ( json_obj_set op `description` ( json_str_lit desc ) )

    : Json ok ( json_obj_new )
    ( json_obj_set ok `description` ( json_str_lit `Successful response.` ) )
    : Json responses ( json_obj_new )
    ( json_obj_set responses `200` ok )
    ( json_obj_set op `responses` responses )

    // Path entry — append onto existing entry if present, else new.
    : ?Json existing ( json_obj_get paths path )
    ?? existing {
        T pj → { ( json_obj_set pj method op ) }
        F _ → {
            : Json pj ( json_obj_new )
            ( json_obj_set pj method op )
            ( json_obj_set paths path pj )
        }
    }
}

@ h_openapi_json HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /openapi.json\n` )
    : Json doc ( json_obj_new )
    ( json_obj_set doc `openapi` ( json_str_lit `3.1.0` ) )

    : Json info ( json_obj_new )
    ( json_obj_set info `title` ( json_str_lit `NURL Compiler API (NURL-native)` ) )
    ( json_obj_set info `version` ( json_str_lit `0.1.0` ) )
    ( json_obj_set info `description` ( json_str_lit `HTTP interface to the NURL compiler — pure-NURL implementation. Compiles NURL source to native x86_64 binaries (POST /build) or wasm32-wasi WebAssembly (POST /build_wasm), serves the in-browser playground at /, and exposes the same surface as a Model Context Protocol server at POST /mcp (Streamable HTTP). See GET /mcp-info for MCP connection details.` ) )
    ( json_obj_set doc `info` info )

    : Json paths ( json_obj_new )

    ( __oa_path paths `/health` `get` `Liveness probe` `Returns 200 OK with a small JSON payload.` )
    ( __oa_path paths `/build` `post` `Compile NURL source to a native x86_64 Linux binary (mirrors nurl.sh)` `nurlc → LLVM IR → clang link → ELF. Returns BuildResponse with ll_artifact + binary_artifact download URLs on success.` )
    ( __oa_path paths `/build_wasm` `post` `Compile NURL source to a wasm32-wasi WebAssembly module` `nurlc → wasi-clang link → .wasm. Returns base64 wasm + canvas/audio FFI flags.` )
    ( __oa_path paths `/build_windows` `post` `Cross-compile to a Windows .exe via mingw-w64` `nurlc → clang+mingw link → PE/COFF. Static libcurl + Schannel TLS.` )
    ( __oa_path paths `/build_macos` `post` `Cross-compile to a macOS x86_64 Mach-O binary via zig cc` `Unsigned — clear quarantine attribute before running on macOS.` )
    ( __oa_path paths `/build_target` `post` `Cross-compile to a registered zig target (linux-arm64-musl, riscv64, …)` `See GET /targets for available target ids.` )
    ( __oa_path paths `/targets` `get` `List available cross-compile targets` `Returns the TargetInfo[] used by the playground's dropdown.` )

    ( __oa_path paths `/examples` `get` `List bundled example programs` `JSON array of {name, path, bytes}.` )
    ( __oa_path paths `/examples/{name}` `get` `Return the source of a bundled example` `Path-encoded name as returned by /examples.` )

    ( __oa_path paths `/stdlib` `get` `List bundled stdlib modules (recursive)` `JSON array of {name, path, bytes}, sorted.` )
    ( __oa_path paths `/stdlib/{name}` `get` `Return the source of a stdlib module` `Returns {name, source, bytes}.` )

    ( __oa_path paths `/tests` `get` `List bundled compiler tests (recursive)` `JSON array of {name, path, bytes}, sorted.` )
    ( __oa_path paths `/tests/{name}` `get` `Return the source of a bundled test` `Returns {name, source, bytes}.` )

    ( __oa_path paths `/readme` `get` `Render README.md as HTML` `Markdown rendered with same chrome as api/'s viewer.` )
    ( __oa_path paths `/readme.md` `get` `Raw README.md source` `text/markdown response.` )
    ( __oa_path paths `/roadmap` `get` `Render ROADMAP.md as HTML` `Markdown rendered with same chrome as api/'s viewer.` )
    ( __oa_path paths `/roadmap.md` `get` `Raw ROADMAP.md source` `text/markdown response.` )
    ( __oa_path paths `/gotchas` `get` `Render docs/GOTCHAS.md as HTML` `Markdown rendered with same chrome as api/'s viewer.` )
    ( __oa_path paths `/gotchas.md` `get` `Raw docs/GOTCHAS.md source` `text/markdown response.` )
    ( __oa_path paths `/grammar` `get` `Render the current NURL grammar (spec/grammar.ebnf)` `EBNF wrapped in a fenced code block.` )
    ( __oa_path paths `/grammar.ebnf` `get` `Raw spec/grammar.ebnf` `text/plain response.` )

    ( __oa_path paths `/license` `get` `Combined license overview (HTML)` `MIT + Apache-2.0 dual-license summary.` )
    ( __oa_path paths `/license/mit` `get` `MIT license, HTML-rendered` `From LICENSE-MIT.` )
    ( __oa_path paths `/license/apache` `get` `Apache-2.0 license, HTML-rendered` `From LICENSE-APACHE.` )
    ( __oa_path paths `/LICENSE-MIT` `get` `Raw MIT license source` `text/plain.` )
    ( __oa_path paths `/LICENSE-APACHE` `get` `Raw Apache-2.0 license source` `text/plain.` )
    ( __oa_path paths `/NOTICE` `get` `Third-party attributions` `text/plain.` )

    ( __oa_path paths `/stdlib-viewer` `get` `Browsable directory listing for stdlib/` `Lightweight HTML index linking to each .nu file.` )
    ( __oa_path paths `/stdlib-docs` `get` `Rendered stdlib API reference (index)` `Auto-generated from module sources by nurldoc, rendered as HTML with the doc chrome.` )
    ( __oa_path paths `/stdlib-docs/{path}` `get` `Rendered API docs for one stdlib module` `nurldoc → Markdown → HTML. Append .md for the raw Markdown.` )
    ( __oa_path paths `/tests-viewer` `get` `Browsable directory listing for compiler/tests/` `Lightweight HTML index linking to each .nu file.` )

    ( __oa_path paths `/docs` `get` `Swagger UI for this OpenAPI 3.1 schema` `Loads /openapi.json into swagger-ui-dist served from unpkg CDN.` )

    ( __oa_path paths `/mcp-info` `get` `MCP server connection info` `Tools, resources, prompts + drop-in mcp.json snippet.` )
    ( __oa_path paths `/mcp` `post` `Model Context Protocol JSON-RPC endpoint (Streamable HTTP)` `Same surface as /build*, /examples, /stdlib, /tests over MCP.` )
    ( __oa_path paths `/mcp` `get` `MCP SSE channel (some clients open a GET as well)` `Returns a streaming SSE channel for server→client notifications.` )

    ( __oa_path paths `/download/{token}` `get` `Stream a build artifact by token` `Tokens come from BuildResponse.ll_artifact.token / binary_artifact.token.` )

    ( __oa_path paths `/.well-known/oauth-protected-resource` `get` `OAuth 2.0 protected resource metadata (RFC 9728)` `Rubber-stamp stub for MCP client compatibility.` )
    ( __oa_path paths `/.well-known/oauth-authorization-server` `get` `OAuth 2.0 authorization server metadata (RFC 8414)` `Rubber-stamp stub for MCP client compatibility.` )
    ( __oa_path paths `/.well-known/openid-configuration` `get` `OIDC discovery alias` `Same shape as the OAuth metadata above.` )
    ( __oa_path paths `/register` `post` `Dynamic Client Registration (RFC 7591)` `Accepts any body; returns a synthetic client_id.` )
    ( __oa_path paths `/authorize` `get` `OAuth authorization endpoint` `Instantly redirects back with a synthetic code.` )
    ( __oa_path paths `/token` `post` `OAuth token endpoint` `Returns a long-lived opaque bearer; /mcp never validates it.` )

    ( json_obj_set doc `paths` paths )

    : Json components ( json_obj_new )
    ( json_obj_set components `schemas` ( json_obj_new ) )
    ( json_obj_set doc `components` components )

    : String body ( json_stringify doc )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( json_free doc ) ( string_free body )
    ^ r
}

// ── Swagger UI shell served at /docs ──────────────────────────────
//
// Renders the OpenAPI 3.1 schema from /openapi.json. The Swagger UI
// assets are pulled from a CDN (unpkg) — no extra files are bundled
// into the image. index.html links here from the "Swagger" chip.
@ h_docs_html HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /docs\n` )
    : String html ( string_with_cap 1024 )
    ( string_push_str html `<!doctype html>\n<html lang="en"><head>\n<meta charset="utf-8" />\n<title>NURL Compiler API · Swagger UI</title>\n<meta name="viewport" content="width=device-width,initial-scale=1" />\n<link rel="icon" type="image/svg+xml" href="/favicon.svg" />\n<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />\n<style>body{margin:0;background:#0f1115;color:#e6e6e6}.swagger-ui{color:#e6e6e6}.swagger-ui .info .title,.swagger-ui .info p,.swagger-ui .info li,.swagger-ui .info a,.swagger-ui .info h1,.swagger-ui .info h2,.swagger-ui .info h3,.swagger-ui .info h4,.swagger-ui .info h5{color:#e6e6e6}.swagger-ui .scheme-container{background:#171a21;box-shadow:none}.swagger-ui .opblock-tag{color:#dbeeff;border-bottom-color:#2a2f3a}.swagger-ui .opblock-tag small{color:#9aa4b2}.swagger-ui .opblock .opblock-summary-path,.swagger-ui .opblock .opblock-summary-path__deprecated,.swagger-ui .opblock .opblock-summary-description{color:#e6e6e6}.swagger-ui .opblock-description-wrapper p,.swagger-ui .opblock-title_normal p,.swagger-ui .markdown p,.swagger-ui .markdown li,.swagger-ui .renderedMarkdown p,.swagger-ui .renderedMarkdown li{color:#cfd6e0}.swagger-ui .opblock{background:#141821;border-color:#2a2f3a;box-shadow:none}.swagger-ui .opblock .opblock-section-header{background:#171a21;box-shadow:none}.swagger-ui .opblock .opblock-section-header h4,.swagger-ui .opblock .opblock-section-header>label{color:#e6e6e6}.swagger-ui .tab li,.swagger-ui .parameter__name,.swagger-ui .parameter__type,.swagger-ui table thead tr td,.swagger-ui table thead tr th,.swagger-ui .response-col_status,.swagger-ui .response-col_links,.swagger-ui .col_header,.swagger-ui label{color:#e6e6e6}.swagger-ui .parameter__in,.swagger-ui .parameter__extension{color:#9aa4b2}.swagger-ui table{border-color:#2a2f3a}.swagger-ui table tbody tr td{color:#cfd6e0;border-color:#2a2f3a}.swagger-ui .responses-inner h4,.swagger-ui .responses-inner h5{color:#e6e6e6}.swagger-ui input[type=text],.swagger-ui input[type=password],.swagger-ui input[type=email],.swagger-ui textarea,.swagger-ui select{background:#0f1115;color:#e6e6e6;border-color:#2a2f3a}.swagger-ui section.models{border-color:#2a2f3a}.swagger-ui section.models h4,.swagger-ui .model-title,.swagger-ui .model{color:#e6e6e6}.swagger-ui section.models .model-container{background:#141821}.swagger-ui .prop-type{color:#7fd0ff}.swagger-ui .prop-format{color:#9aa4b2}.swagger-ui svg{fill:#cfd6e0}.swagger-ui .model-toggle:after{filter:invert(1)}.swagger-ui .topbar{background:#171a21}.swagger-ui .btn{color:#e6e6e6;border-color:#3a4150;background:#1a1f29}.swagger-ui .opblock-body pre.microlight,.swagger-ui .highlight-code>.microlight{background:#0b0d11;color:#e6e6e6}.swagger-ui .info .base-url,.swagger-ui .info hgroup.main a{color:#9aa4b2}</style>\n</head><body>\n<div id="swagger-ui"></div>\n<script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js" crossorigin></script>\n<script>\nwindow.onload = () => {\n  window.ui = SwaggerUIBundle({\n    url: '/openapi.json',\n    dom_id: '#swagger-ui',\n    deepLinking: true,\n    presets: [SwaggerUIBundle.presets.apis],\n    layout: 'BaseLayout'\n  });\n};\n</script>\n</body></html>\n` )
    : HttpResponse r ( response_text 200 ( string_data html ) )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( string_free html )
    ^ r
}

// ── OAuth 2.0 / OIDC rubber-stamp stubs for MCP client compatibility ──
//
// Mirrors api/'s endpoints (Claude Desktop probes these even on
// unauthenticated servers). Every endpoint says "yes, you may" without
// involving a user or persisting state.

// Append the body of `j` to `out` as the response body (JSON, 200 OK).
@ __json_response_200 Json j → HttpResponse {
    : String body ( json_stringify j )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( string_free body )
    ^ r
}

@ h_oauth_protected_resource HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /.well-known/oauth-protected-resource\n` )
    : String base ( __mcp_info_base_url req )
    : String mcp_url ( string_with_cap + ( string_len base ) 5 )
    ( string_push_str mcp_url ( string_data base ) ) ( string_push_str mcp_url `/mcp` )
    : Json j ( json_obj_new )
    ( json_obj_set j `resource` ( json_str_lit ( string_data mcp_url ) ) )
    : Json servers ( json_arr_new )
    ( json_arr_push servers ( json_str_lit ( string_data base ) ) )
    ( json_obj_set j `authorization_servers` servers )
    : Json methods ( json_arr_new )
    ( json_arr_push methods ( json_str_lit `header` ) )
    ( json_obj_set j `bearer_methods_supported` methods )
    ( json_obj_set j `scopes_supported` ( json_arr_new ) )
    : HttpResponse r ( __json_response_200 j )
    ( json_free j ) ( string_free base ) ( string_free mcp_url )
    ^ r
}

// Build helper: append "<base><suffix>" string-literal to the given
// JSON object under key `k`. Frees nothing — base is owned by caller.
@ __oauth_put_url Json j s k s base s suffix → v {
    : String u ( string_with_cap + ( nurl_str_len base ) ( nurl_str_len suffix ) )
    ( string_push_str u base )
    ( string_push_str u suffix )
    ( json_obj_set j k ( json_str_lit ( string_data u ) ) )
    ( string_free u )
}

@ h_oauth_auth_server HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /.well-known/oauth-authorization-server\n` )
    : String base ( __mcp_info_base_url req )
    : s bp ( string_data base )
    : Json j ( json_obj_new )
    ( json_obj_set j `issuer` ( json_str_lit bp ) )
    ( __oauth_put_url j `authorization_endpoint` bp `/authorize` )
    ( __oauth_put_url j `token_endpoint` bp `/token` )
    ( __oauth_put_url j `registration_endpoint` bp `/register` )
    : Json rt ( json_arr_new ) ( json_arr_push rt ( json_str_lit `code` ) )
    ( json_obj_set j `response_types_supported` rt )
    : Json gt ( json_arr_new )
    ( json_arr_push gt ( json_str_lit `authorization_code` ) )
    ( json_arr_push gt ( json_str_lit `client_credentials` ) )
    ( json_obj_set j `grant_types_supported` gt )
    : Json am ( json_arr_new ) ( json_arr_push am ( json_str_lit `none` ) )
    ( json_obj_set j `token_endpoint_auth_methods_supported` am )
    : Json cm ( json_arr_new )
    ( json_arr_push cm ( json_str_lit `S256` ) )
    ( json_arr_push cm ( json_str_lit `plain` ) )
    ( json_obj_set j `code_challenge_methods_supported` cm )
    ( json_obj_set j `scopes_supported` ( json_arr_new ) )
    : HttpResponse r ( __json_response_200 j )
    ( json_free j ) ( string_free base )
    ^ r
}

// POST /register — rubber-stamp Dynamic Client Registration (RFC 7591).
// Returns a synthetic client_id; echoes back metadata fields the caller
// supplied so strict clients (Claude.ai) recognise it as valid.
@ h_oauth_register HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] POST /register\n` )
    : String body_str ( get_body_str req )
    : !Json JsonError parsed ( json_parse ( string_data body_str ) )
    : Json res ( json_obj_new )

    : String cid ( string_with_cap 32 )
    ( string_push_str cid `nurl-mcp-` )
    : i now_ms ( now_ms )
    ( string_push_str cid `synthetic-` )
    : String now_s ( string_with_cap 24 )
    // We don't have itoa; reuse json_int_to_string semantics via Json.
    : Json tmp ( json_int now_ms )
    : String t_str ( json_stringify tmp )
    ( string_push_str cid ( string_data t_str ) )
    ( json_free tmp ) ( string_free t_str )
    ( json_obj_set res `client_id` ( json_str_lit ( string_data cid ) ) )
    ( json_obj_set res `client_id_issued_at` ( json_int / now_ms 1000 ) )
    : Json def_gt ( json_arr_new ) ( json_arr_push def_gt ( json_str_lit `authorization_code` ) )
    ( json_obj_set res `grant_types` def_gt )
    : Json def_rt ( json_arr_new ) ( json_arr_push def_rt ( json_str_lit `code` ) )
    ( json_obj_set res `response_types` def_rt )
    ( json_obj_set res `redirect_uris` ( json_arr_new ) )
    ( json_obj_set res `token_endpoint_auth_method` ( json_str_lit `none` ) )

    // Echo back known DCR metadata fields when present in the body.
    ?? parsed {
        T body → {
            ( __oauth_echo body res `redirect_uris` )
            ( __oauth_echo body res `grant_types` )
            ( __oauth_echo body res `response_types` )
            ( __oauth_echo body res `token_endpoint_auth_method` )
            ( __oauth_echo body res `client_name` )
            ( __oauth_echo body res `client_uri` )
            ( __oauth_echo body res `logo_uri` )
            ( __oauth_echo body res `scope` )
            ( __oauth_echo body res `contacts` )
            ( __oauth_echo body res `tos_uri` )
            ( __oauth_echo body res `policy_uri` )
            ( __oauth_echo body res `jwks_uri` )
            ( __oauth_echo body res `jwks` )
            ( __oauth_echo body res `software_id` )
            ( __oauth_echo body res `software_version` )
            ( __oauth_echo body res `software_statement` )
            ( __oauth_echo body res `application_type` )
            ( json_free body )
        }
        F _ → {}
    }

    : String body ( json_stringify res )
    : HttpResponse r ( response_text 201 ( string_data body ) )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( json_free res ) ( string_free cid ) ( string_free now_s ) ( string_free body ) ( string_free body_str )
    ^ r
}

// Pass-through one body key to res unchanged. `body` retains ownership
// of the original — we deep-clone before transferring into `res` so the
// later json_free(body) doesn't double-free the value.
@ __oauth_echo Json body Json res s key → v {
    : ?Json val_opt ( json_obj_get body key )
    ?? val_opt {
        T val → { ( json_obj_set res key ( json_clone val ) ) }
        F _ → {}
    }
}

// Pluck a query parameter by name from a parsed pairs vector. Returns
// an OWNED clone of the value (caller frees); F if not present.
@ __oauth_query_get ( Vec QueryPair ) pairs s name → ?String {
    : i n ( vec_len [QueryPair] pairs )
    : ~ i k 0
    : ~ ? String found @ ?String { F }
    ~ < k n {
        ?? ( vec_get [QueryPair] pairs k ) {
            T p → {
                ? != 0 ( nurl_str_eq ( string_data . p key ) name ) {
                    = found @ ?String { T ( string_from ( string_data . p value ) ) }
                    = k n
                } { = k + k 1 }
            }
            F _ → { = k + k 1 }
        }
    }
    ^ found
}

@ __oauth_pairs_free ( Vec QueryPair ) pairs → v {
    : i n ( vec_len [QueryPair] pairs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [QueryPair] pairs k ) { T p → ( query_pair_free p ) F _ → {} }
        = k + k 1
    }
    ( vec_free [QueryPair] pairs )
}

// GET /authorize — instantly redirect with a dummy code. No consent UI.
@ h_oauth_authorize HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /authorize\n` )
    : ( Vec QueryPair ) pairs ( parse_query ( string_data . req query ) )
    : ?String redir_opt ( __oauth_query_get pairs `redirect_uri` )
    : ?String state_opt ( __oauth_query_get pairs `state` )
    ( __oauth_pairs_free pairs )
    ?? redir_opt {
        T redir → {
            : String loc ( string_with_cap + ( string_len redir ) 64 )
            ( string_push_str loc ( string_data redir ) )
            ? >= ( nurl_str_find ( string_data redir ) `?` ) 0 {
                ( string_push_char loc 38 )
            } { ( string_push_char loc 63 ) }
            ( string_push_str loc `code=synthetic-` )
            : Json tmp ( json_int ( now_ms ) )
            : String ts ( json_stringify tmp )
            ( string_push_str loc ( string_data ts ) )
            ( json_free tmp ) ( string_free ts )
            ?? state_opt {
                T st → {
                    ( string_push_str loc `&state=` )
                    ( string_push_str loc ( string_data st ) )
                    ( string_free st )
                }
                F _ → {}
            }
            : HttpResponse r ( response_new 302 )
            ( response_set_header r `Location` ( string_data loc ) )
            ( string_free loc ) ( string_free redir )
            ^ r
        }
        F _ → {
            ?? state_opt { T st → { ( string_free st ) } F _ → {} }
            ^ ( response_text 400 `{"error":"redirect_uri required"}` )
        }
    }
}

// POST /token — accepts any grant; returns an opaque bearer the /mcp
// handler never actually checks. Long expiry so clients don't refresh.
@ h_oauth_token HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] POST /token\n` )
    : Json j ( json_obj_new )
    : String tok ( string_with_cap 64 )
    ( string_push_str tok `synthetic-` )
    : Json tmp ( json_int ( now_ms ) )
    : String t_str ( json_stringify tmp )
    ( string_push_str tok ( string_data t_str ) )
    ( json_free tmp ) ( string_free t_str )
    ( json_obj_set j `access_token` ( json_str_lit ( string_data tok ) ) )
    ( json_obj_set j `token_type` ( json_str_lit `Bearer` ) )
    ( json_obj_set j `expires_in` ( json_int 31536000 ) )
    ( json_obj_set j `scope` ( json_str_lit `` ) )
    : HttpResponse r ( __json_response_200 j )
    ( json_free j ) ( string_free tok )
    ^ r
}

// Reads <output_dir>/<build_id>/<filename> directly and returns it
// with the right Content-Type. Replaces an earlier serve_static call
// whose request-path-based resolution double-prefixed the build dir
// ("/download/<id>/<file>" → "<build_dir>/download/<id>/<file>" → 404).
@ h_download HttpRequest req Params params → HttpResponse {
    : ?String bid_opt ( params_get params `build_id` )
    : ?String fname_opt ( params_get params `filename` )
    ?? bid_opt { T bid → {
            ?? fname_opt { T fname → {
                    // Path-traversal defence — refuse `..` in either segment.
                    ? | ( __has_dotdot_segment ( string_data bid ) ) ( __has_dotdot_segment ( string_data fname ) ) {
                        ( string_free bid ) ( string_free fname )
                        ^ ( response_text 403 `forbidden\n` )
                    } {}
                    : String out_dir_base ( get_output_dir )
                    : String build_dir ( path_join ( string_data out_dir_base ) ( string_data bid ) )
                    : String fpath ( path_join ( string_data build_dir ) ( string_data fname ) )
                    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fpath ) )
                    ?? rd {
                        T body → {
                            : String ext ( path_extension ( string_data fpath ) )
                            : s mime ( mime_for_ext ( string_data ext ) )
                            : HttpResponse r ( response_new 200 )
                            ( response_set_header r `Content-Type` mime )
                            ( response_set_body_bytes r body )
                            ( vec_free [u] body )
                            ( string_free ext ) ( string_free fpath ) ( string_free build_dir )
                            ( string_free out_dir_base ) ( string_free bid ) ( string_free fname )
                            ^ r
                        }
                        F _ → {
                            ( string_free fpath ) ( string_free build_dir )
                            ( string_free out_dir_base ) ( string_free bid ) ( string_free fname )
                            ^ ( response_text 404 `not found\n` )
                        }
                    }
                } F _ → { ( string_free bid ) ^ ( response_text 400 `{"error":"filename missing"}\n` ) } }
        } F _ → { ^ ( response_text 400 `{"error":"build_id missing"}\n` ) } }
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
    : !String IoErr cr ( read_file ( string_data fpath ) )
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
    ? | ( __has_dotdot_segment ( string_data build_id ) ) ( __has_dotdot_segment ( string_data filename ) ) {
        ^ ( response_text 403 `forbidden\n` )
    } {}
    : String out_dir_base ( get_output_dir )
    : String build_dir ( path_join ( string_data out_dir_base ) ( string_data build_id ) )
    : String fpath ( path_join ( string_data build_dir ) ( string_data filename ) )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fpath ) )
    ?? rd {
        T body → {
            : String ext ( path_extension ( string_data fpath ) )
            : s mime ( mime_for_ext ( string_data ext ) )
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` mime )
            ( response_set_body_bytes r body )
            ( vec_free [u] body )
            ( string_free ext ) ( string_free fpath ) ( string_free build_dir ) ( string_free out_dir_base )
            ^ r
        }
        F _ → {
            ( string_free fpath ) ( string_free build_dir ) ( string_free out_dir_base )
            ^ ( response_text 404 `not found\n` )
        }
    }
}

@ h_static_for HttpRequest req String tail → HttpResponse {
    ? ( __has_dotdot_segment ( string_data tail ) ) {
        ^ ( response_text 403 `forbidden\n` )
    } {}
    : String full ( path_join `static` ( string_data tail ) )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data full ) )
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
    : b is_get ( string_eq mtmp ( string_from `GET` ) )
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
        : ?i slash ( string_index_of tail `/` )
        ( string_free mtmp )
        ?? slash {
            T sx → {
                : i tlen ( string_len tail )
                : String build_id ( string_substr tail 0 sx )
                : String fname ( string_substr tail + sx 1 - - tlen sx 1 )
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
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
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
    : ?String tail_opt ( params_get params `path` )
    ?? tail_opt {
        T tail → {
            ? ( __has_dotdot_segment ( string_data tail ) ) {
                ( string_free tail )
                ^ ( response_text 403 `forbidden\n` )
            } {}
            : String sdir ( get_static_dir )
            : String full ( path_join ( string_data sdir ) ( string_data tail ) )
            ( string_free sdir ) ( string_free tail )
            : !( Vec u ) IoErr rd ( read_file_bytes ( string_data full ) )
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

// ── Markdown → HTML renderer (Python markdown lib equivalent) ─────
//
// Minimal but README/ROADMAP/GOTCHAS-grade renderer. Supports:
//   * ATX headings (# .. ######)
//   * Fenced code blocks (```lang … ```) with language class
//   * Tables (GitHub-style `| col | col |` with `|---|---|` separator)
//   * Blockquotes (>)
//   * Unordered + ordered lists (- / *  /  1. 2. …)
//   * Horizontal rule (---, ***, ___)
//   * Inline: backtick code, **bold**, *em*, [text](url), <autolink>
//   * HTML escapes raw text, leaves entity refs alone.
//
// Not supported: nested lists by indent, definition lists, footnotes,
// reference-style links, setext headings, raw HTML passthrough. Python
// markdown handles those, but they don't appear in our doc set.

@ __html_escape_char String out i c → v {
    ? == c 38 { ( string_push_str out `&amp;` ) } {
        ? == c 60 { ( string_push_str out `&lt;` ) } {
            ? == c 62 { ( string_push_str out `&gt;` ) } {
                ? == c 34 { ( string_push_str out `&quot;` ) } {
                    ( string_push_char out c )
                }
            }
        }
    }
}

@ __html_escape_into s src String out → v {
    : i n ( nurl_str_len src )
    : ~ i k 0
    ~ < k n {
        ( __html_escape_char out ( nurl_str_get src k ) )
        = k + k 1
    }
}

// Helper: get byte from a string buffer at idx (0 if past end).
@ __md_byte s buf i n i idx → i {
    ? | < idx 0 >= idx n { ^ 0 } {}
    ^ ( nurl_str_get buf idx )
}

// Skip ASCII spaces from `start`. Returns next non-space index.
@ __md_skip_ws s buf i n i start → i {
    : ~ i i start
    ~ < i n {
        : i c ( nurl_str_get buf i )
        ? | == c 32 == c 9 { = i + i 1 } { ^ i }
    }
    ^ i
}

// Render inline elements from `buf[from..to)` into `out`. Inline grammar
// is recursion-free: walks left→right, handles `` ` `` (code spans),
// `**` (bold), `*` (em), `[txt](url)`, `<url>` autolinks. `to` is the
// exclusive upper bound; `buf` is the underlying NUL-terminated buffer.
@ __md_inline s buf i from i to String out → v {
    : ~ i i from
    ~ < i to {
        : i c ( nurl_str_get buf i )
        : i c1 ( __md_byte buf to + i 1 )

        // Backslash-escape: consume next char verbatim.
        ? == c 92 {
            ? > c1 0 {
                ( __html_escape_char out c1 )
                = i + i 2
            } {
                ( string_push_char out c )
                = i + i 1
            }
        } {

            // Code span: `…`
            ? == c 96 {
                : ~ i end - 0 1
                : ~ i j + i 1
                ~ < j to {
                    ? == ( nurl_str_get buf j ) 96 { = end j = j to } { = j + j 1 }
                }
                ? >= end 0 {
                    ( string_push_str out `<code>` )
                    : ~ i k + i 1
                    ~ < k end {
                        ( __html_escape_char out ( nurl_str_get buf k ) )
                        = k + k 1
                    }
                    ( string_push_str out `</code>` )
                    = i + end 1
                } {
                    ( __html_escape_char out c )
                    = i + i 1
                }
            } {

                // Bold: **…**
                ? & == c 42 == c1 42 {
                    : ~ i end - 0 1
                    : ~ i j + i 2
                    ~ < j - to 1 {
                        ? & == ( nurl_str_get buf j ) 42 == ( nurl_str_get buf + j 1 ) 42 {
                            = end j = j to
                        } { = j + j 1 }
                    }
                    ? >= end 0 {
                        ( string_push_str out `<strong>` )
                        ( __md_inline buf + i 2 end out )
                        ( string_push_str out `</strong>` )
                        = i + end 2
                    } {
                        ( __html_escape_char out c )
                        = i + i 1
                    }
                } {

                    // Em: *…* (single, no nesting)
                    ? == c 42 {
                        : ~ i end - 0 1
                        : ~ i j + i 1
                        ~ < j to {
                            ? == ( nurl_str_get buf j ) 42 { = end j = j to } { = j + j 1 }
                        }
                        ? >= end 0 {
                            ( string_push_str out `<em>` )
                            : ~ i k + i 1
                            ~ < k end {
                                ( __html_escape_char out ( nurl_str_get buf k ) )
                                = k + k 1
                            }
                            ( string_push_str out `</em>` )
                            = i + end 1
                        } {
                            ( __html_escape_char out c )
                            = i + i 1
                        }
                    } {

                        // Image: ![alt](url)
                        ? & == c 33 == c1 91 {
                            : ~ i mid - 0 1
                            : ~ i close - 0 1
                            : ~ i j + i 2
                            ~ < j to {
                                ? == ( nurl_str_get buf j ) 93 {
                                    ? == ( __md_byte buf to + j 1 ) 40 { = mid j = close mid = j to } { = j to }
                                } { = j + j 1 }
                            }
                            ? >= mid 0 {
                                : ~ i k + mid 2
                                ~ < k to {
                                    ? == ( nurl_str_get buf k ) 41 { = close k = k to } { = k + k 1 }
                                }
                            } {}
                            ? & >= mid 0 > close mid {
                                ( string_push_str out `<img alt="` )
                                : ~ i a + i 2
                                ~ < a mid {
                                    ( __html_escape_char out ( nurl_str_get buf a ) )
                                    = a + a 1
                                }
                                ( string_push_str out `" src="` )
                                : ~ i b + mid 2
                                ~ < b close {
                                    ( __html_escape_char out ( nurl_str_get buf b ) )
                                    = b + b 1
                                }
                                ( string_push_str out `">` )
                                = i + close 1
                            } {
                                ( __html_escape_char out c )
                                = i + i 1
                            }
                        } {

                            // Link: [text](url)
                            ? == c 91 {
                                : ~ i mid - 0 1
                                : ~ i close - 0 1
                                : ~ i j + i 1
                                ~ < j to {
                                    ? == ( nurl_str_get buf j ) 93 {
                                        ? == ( __md_byte buf to + j 1 ) 40 { = mid j = close mid = j to } { = j to }
                                    } { = j + j 1 }
                                }
                                ? >= mid 0 {
                                    : ~ i k + mid 2
                                    ~ < k to {
                                        ? == ( nurl_str_get buf k ) 41 { = close k = k to } { = k + k 1 }
                                    }
                                } {}
                                ? & >= mid 0 > close mid {
                                    ( string_push_str out `<a href="` )
                                    : ~ i b + mid 2
                                    ~ < b close {
                                        ( __html_escape_char out ( nurl_str_get buf b ) )
                                        = b + b 1
                                    }
                                    ( string_push_str out `">` )
                                    ( __md_inline buf + i 1 mid out )
                                    ( string_push_str out `</a>` )
                                    = i + close 1
                                } {
                                    ( __html_escape_char out c )
                                    = i + i 1
                                }
                            } {

                                // Autolink: <http://…> / <https://…>
                                ? == c 60 {
                                    : i p2 ( __md_byte buf to + i 1 )
                                    : i p3 ( __md_byte buf to + i 2 )
                                    : i p4 ( __md_byte buf to + i 3 )
                                    : i p5 ( __md_byte buf to + i 4 )
                                    : i p6 ( __md_byte buf to + i 5 )
                                    : b is_url & & == p2 104 & == p3 116 & == p4 116 == p5 112 | == p6 58 == p6 115
                                    ? is_url {
                                        : ~ i end - 0 1
                                        : ~ i j + i 1
                                        ~ < j to {
                                            ? == ( nurl_str_get buf j ) 62 { = end j = j to } { = j + j 1 }
                                        }
                                        ? >= end 0 {
                                            ( string_push_str out `<a href="` )
                                            : ~ i k + i 1
                                            ~ < k end {
                                                ( __html_escape_char out ( nurl_str_get buf k ) )
                                                = k + k 1
                                            }
                                            ( string_push_str out `">` )
                                            : ~ i k2 + i 1
                                            ~ < k2 end {
                                                ( __html_escape_char out ( nurl_str_get buf k2 ) )
                                                = k2 + k2 1
                                            }
                                            ( string_push_str out `</a>` )
                                            = i + end 1
                                        } {
                                            ( __html_escape_char out c )
                                            = i + i 1
                                        }
                                    } {
                                        ( __html_escape_char out c )
                                        = i + i 1
                                    }
                                } {

                                    ( __html_escape_char out c )
                                    = i + i 1
                                } } } } } } }
    }
}

// Open / close block-level wrappers, closing whatever single open
// block was previously active. `state` is a 1-element mutable Vec[i]
// holding the active block kind (0=none, 1=p, 2=ul, 3=ol, 4=blockquote).
@ __md_close_block ( Vec i ) state String out → v {
    : i kind ?? ( vec_get [i] state 0 ) { T kv → kv F _ → 0 }
    ? == kind 1 { ( string_push_str out `</p>\n` ) } {}
    ? == kind 2 { ( string_push_str out `</ul>\n` ) } {}
    ? == kind 3 { ( string_push_str out `</ol>\n` ) } {}
    ? == kind 4 { ( string_push_str out `</blockquote>\n` ) } {}
    ( vec_set [i] state 0 0 )
}

@ __md_open_block ( Vec i ) state i kind String out s tag → v {
    : i cur ?? ( vec_get [i] state 0 ) { T cv → cv F _ → 0 }
    ? != cur kind {
        ( __md_close_block state out )
        ( string_push_char out 60 )  // '<'
        ( string_push_str out tag )
        ( string_push_str out `>\n` )
        ( vec_set [i] state 0 kind )
    } {}
}

// Render fenced code-block lines. `info` is the optional language tag.
@ __md_open_code String out s info → v {
    : i ilen ( nurl_str_len info )
    ? > ilen 0 {
        ( string_push_str out `<pre><code class="language-` )
        ( __html_escape_into info out )
        ( string_push_str out `">` )
    } {
        ( string_push_str out `<pre><code>` )
    }
}

// Convert `src` (markdown) to HTML. Returns an owned String.
// ── GFM table support ────────────────────────────────────────────────

// Index of the next '\n' at/after `pos`, or -1 if none.
@ __md_nl_at s src i pos i n → i {
    : ~ i scan pos
    ~ < scan n { ? == ( nurl_str_get src scan ) 10 { ^ scan } { = scan + scan 1 } }
    ^ - 0 1
}

// Start of the line after the one beginning at `pos`.
@ __md_next_pos s src i pos i n → i {
    : i nl ( __md_nl_at src pos n )
    ^ ? >= nl 0 + nl 1 n
}

// The line beginning at `pos` as an owned String, sans trailing \r / \n.
@ __md_read_line s src i pos i n → String {
    : i nl ( __md_nl_at src pos n )
    : i hard_end ? >= nl 0 nl n
    : i line_end ? & > hard_end pos == ( nurl_str_get src - hard_end 1 ) 13 - hard_end 1 hard_end
    : String line ( string_with_cap + - line_end pos 1 )
    : ~ i k pos ~ < k line_end { ( string_push_char line ( nurl_str_get src k ) ) = k + k 1 }
    ( __string_seal line )
    ^ line
}

@ __md_has_pipe s line i n → b {
    : ~ i i 0
    ~ < i n { ? == ( nurl_str_get line i ) 124 { ^ T } {} = i + i 1 }
    ^ F
}

// A GFM delimiter row: only `| - : space tab`, with at least one `-`.
@ __md_is_table_delim s line i n → b {
    ? == n 0 { ^ F } {}
    : ~ b seen_dash F
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get line i )
        ? | | | | == c 124 == c 45 == c 58 == c 32 == c 9 {
            ? == c 45 { = seen_dash T } {}
        } { ^ F }
        = i + i 1
    }
    ^ seen_dash
}

// Emit one `<tr>` of cells. `celltag` is "th" or "td". Splits on `|`,
// dropping the empty segments a leading/trailing `|` produces, and trims
// each cell before inline-formatting it.
@ __md_table_row s line i n String out s celltag → v {
    // Content range [s0, e0): skip outer whitespace + one outer pipe each end.
    : ~ i s0 0
    ~ & < s0 n | == ( nurl_str_get line s0 ) 32 == ( nurl_str_get line s0 ) 9 { = s0 + s0 1 }
    ? & < s0 n == ( nurl_str_get line s0 ) 124 { = s0 + s0 1 } {}
    : ~ i e0 n
    ~ & > e0 s0 | == ( nurl_str_get line - e0 1 ) 32 == ( nurl_str_get line - e0 1 ) 9 { = e0 - e0 1 }
    ? & > e0 s0 == ( nurl_str_get line - e0 1 ) 124 { = e0 - e0 1 } {}
    // Walk cells between pipes in [s0, e0].
    : ~ i cell_start s0
    : ~ i i s0
    ~ <= i e0 {
        ? | == i e0 & < i e0 == ( nurl_str_get line i ) 124 {
            // Trim [cell_start, i).
            : ~ i cs cell_start
            ~ & < cs i | == ( nurl_str_get line cs ) 32 == ( nurl_str_get line cs ) 9 { = cs + cs 1 }
            : ~ i ce i
            ~ & > ce cs | == ( nurl_str_get line - ce 1 ) 32 == ( nurl_str_get line - ce 1 ) 9 { = ce - ce 1 }
            ( string_push_char out 60 ) ( string_push_str out celltag ) ( string_push_char out 62 )
            ( __md_inline line cs ce out )
            ( string_push_str out `</` ) ( string_push_str out celltag ) ( string_push_char out 62 )
            = cell_start + i 1
        } {}
        = i + i 1
    }
}

@ md_to_html s src → String {
    : i n ( nurl_str_len src )
    : String out ( string_with_cap n )
    : ( Vec i ) state ( vec_new [i] ) ( vec_push [i] state 0 )

    : ~ b in_code F

    : ~ i pos 0
    ~ < pos n {
        // Find next newline.
        : ~ i nl_at - 0 1
        : ~ i scan pos
        ~ < scan n {
            ? == ( nurl_str_get src scan ) 10 { = nl_at scan = scan n } { = scan + scan 1 }
        }
        : i hard_end ? >= nl_at 0 nl_at n
        : ~ i next_pos ? >= nl_at 0 + nl_at 1 n
        : i line_end ? & > hard_end pos == ( nurl_str_get src - hard_end 1 ) 13 - hard_end 1 hard_end
        : i line_len - line_end pos

        : String line ( string_with_cap + line_len 1 )
        : ~ i k pos
        ~ < k line_end {
            ( string_push_char line ( nurl_str_get src k ) )
            = k + k 1
        }
        ( __string_seal line )

        : s lp ( string_data line )

        : b is_fence & & & >= line_len 3
        == ( nurl_str_get lp 0 ) 96
        == ( __md_byte lp line_len 1 ) 96
        == ( __md_byte lp line_len 2 ) 96
        ? in_code {
            ? is_fence {
                ( string_push_str out `</code></pre>\n` )
                = in_code F
            } {
                ( __html_escape_into lp out )
                ( string_push_char out 10 )
            }
        } {
            ? == line_len 0 {
                ( __md_close_block state out )
            } {
                ? is_fence {
                    ( __md_close_block state out )
                    : String info ( string_substr line 3 - line_len 3 )
                    ( __md_open_code out ( string_data info ) )
                    ( string_free info )
                    = in_code T
                } {
                    // Heading?
                    : ~ i hcount 0
                    : ~ i hi 0
                    ~ < hi line_len {
                        ? & == ( nurl_str_get lp hi ) 35 < hi 6 { = hcount + hcount 1 = hi + hi 1 } { = hi line_len }
                    }
                    ? & > hcount 0 == ( __md_byte lp line_len hcount ) 32 {
                        ( __md_close_block state out )
                        ( string_push_str out `<h` )
                        : String hn ( string_with_cap 2 ) ( string_push_char hn + 48 hcount ) ( __string_seal hn )
                        ( string_push_str out ( string_data hn ) )
                        ( string_push_char out 62 )
                        : i htxt_start + hcount 1
                        ( __md_inline lp htxt_start line_len out )
                        ( string_push_str out `</h` )
                        ( string_push_str out ( string_data hn ) )
                        ( string_push_str out `>\n` )
                        ( string_free hn )
                    } {
                        // Horizontal rule?
                        ? ( __md_is_hr lp line_len ) {
                            ( __md_close_block state out )
                            ( string_push_str out `<hr />\n` )
                        } {
                            // Blockquote?
                            ? & == ( nurl_str_get lp 0 ) 62 == ( __md_byte lp line_len 1 ) 32 {
                                ( __md_open_block state 4 out `blockquote` )
                                ( __md_inline lp 2 line_len out )
                                ( string_push_char out 10 )
                            } {
                                // Unordered list item?
                                ? & | == ( nurl_str_get lp 0 ) 45 == ( nurl_str_get lp 0 ) 42 == ( __md_byte lp line_len 1 ) 32 {
                                    ( __md_open_block state 2 out `ul` )
                                    ( string_push_str out `<li>` )
                                    ( __md_inline lp 2 line_len out )
                                    ( string_push_str out `</li>\n` )
                                } {
                                    // Ordered list item?
                                    ? ( __md_starts_ol lp line_len ) {
                                        ( __md_open_block state 3 out `ol` )
                                        : i dot_idx ( __md_find_dot lp line_len )
                                        : i text_idx + dot_idx 2
                                        ( string_push_str out `<li>` )
                                        ( __md_inline lp text_idx line_len out )
                                        ( string_push_str out `</li>\n` )
                                    } {
                                        // GFM table? Current line has a `|` and
                                        // the next line is a delimiter row.
                                        : ~ b is_table F
                                        ? ( __md_has_pipe lp line_len ) {
                                            : String dline ( __md_read_line src next_pos n )
                                            = is_table ( __md_is_table_delim ( string_data dline ) ( string_len dline ) )
                                            ( string_free dline )
                                        } {}
                                        ? is_table {
                                            ( __md_close_block state out )
                                            ( string_push_str out `<table>\n<thead>\n<tr>` )
                                            ( __md_table_row lp line_len out `th` )
                                            ( string_push_str out `</tr>\n</thead>\n<tbody>\n` )
                                            // Skip past the delimiter row, then
                                            // consume contiguous `|`-bearing rows.
                                            : ~ i tp ( __md_next_pos src next_pos n )
                                            : ~ b done F
                                            ~ & ! done < tp n {
                                                : String row ( __md_read_line src tp n )
                                                : i rl ( string_len row )
                                                ? & > rl 0 ( __md_has_pipe ( string_data row ) rl ) {
                                                    ( string_push_str out `<tr>` )
                                                    ( __md_table_row ( string_data row ) rl out `td` )
                                                    ( string_push_str out `</tr>\n` )
                                                    = tp ( __md_next_pos src tp n )
                                                } { = done T }
                                                ( string_free row )
                                            }
                                            ( string_push_str out `</tbody>\n</table>\n` )
                                            = next_pos tp
                                        } {
                                            // Paragraph
                                            ( __md_open_block state 1 out `p` )
                                            ( __md_inline lp 0 line_len out )
                                            ( string_push_char out 32 )
                                        }
                                    } } } } }
                } }
        }

        ( string_free line )
        = pos next_pos
    }
    ( __md_close_block state out )
    ? in_code { ( string_push_str out `</code></pre>\n` ) } {}
    ( vec_free [i] state )
    ^ out
}

// Horizontal rule detector: line is 3+ of one char from {-, *, _},
// optionally with intervening spaces, and nothing else.
@ __md_is_hr s line i n → b {
    ? < n 3 { ^ F } {}
    : i first ( nurl_str_get line 0 )
    ? & != first 45 & != first 42 != first 95 { ^ F } {}
    : ~ i k 0
    : ~ i count 0
    ~ < k n {
        : i c ( nurl_str_get line k )
        ? == c first { = count + count 1 } {
            ? | == c 32 == c 9 {} { ^ F } }
        = k + k 1
    }
    ^ >= count 3
}

// Detect ordered-list item prefix: digits followed by '.' and ' '.
@ __md_starts_ol s line i n → b {
    : ~ i k 0
    : ~ i digits 0
    ~ < k n {
        : i c ( nurl_str_get line k )
        ? & >= c 48 <= c 57 { = digits + digits 1 = k + k 1 } { = k n }
    }
    ? <= digits 0 { ^ F } {}
    ? & < digits n == ( nurl_str_get line digits ) 46 {
        ? & < + digits 1 n == ( nurl_str_get line + digits 1 ) 32 { ^ T } { ^ F }
    } { ^ F }
}

@ __md_find_dot s line i n → i {
    : ~ i k 0
    ~ < k n { : i c ( nurl_str_get line k ) ? == c 46 { ^ k } {} = k + k 1 }
    ^ - 0 1
}

// Doc-page wrapper — same chrome as api/'s _DOC_PAGE_TEMPLATE.
@ __doc_page_html s title String body s raw_path → String {
    : String out ( string_with_cap + ( string_len body ) 4096 )
    ( string_push_str out `<!doctype html>\n<html lang="en"><head>\n<meta charset="utf-8" />\n<title>` )
    ( string_push_str out title )
    ( string_push_str out ` · NURL</title>\n<meta name="viewport" content="width=device-width,initial-scale=1" />\n<link rel="icon" type="image/svg+xml" href="/favicon.svg" />\n<style>\n  :root { --bg:#0f1115; --panel:#161a21; --panel-2:#1b2029; --border:#262c38; --fg:#e6e8ee; --fg-dim:#9aa3b2; --accent:#7cc4ff; }\n  html,body { background:var(--bg); color:var(--fg); margin:0; }\n  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, sans-serif; line-height:1.6; }\n  .wrap { max-width: 860px; margin: 0 auto; padding: 2rem 1.25rem 4rem; }\n  header.doc-hdr { display:flex; align-items:center; gap:.75rem; padding:.75rem 1rem; border-bottom:1px solid var(--border); background:var(--panel); position:sticky; top:0; z-index:10; }\n  header.doc-hdr a { color:var(--accent); text-decoration:none; font-size:.9rem; }\n  header.doc-hdr a:hover { text-decoration:underline; }\n  header.doc-hdr .title { font-weight:600; }\n  header.doc-hdr .spacer { flex:1; }\n  h1,h2,h3,h4 { color:#fff; margin-top:2rem; }\n  h1 { border-bottom:1px solid var(--border); padding-bottom:.35em; }\n  h2 { border-bottom:1px solid var(--border); padding-bottom:.25em; }\n  a { color:var(--accent); }\n  code, pre { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }\n  code { background:var(--panel-2); padding:.1em .35em; border-radius:4px; font-size:.92em; color:#e6e8ee; }\n  pre { background:var(--panel); border:1px solid var(--border); padding:.85rem 1rem; border-radius:8px; overflow:auto; font-size:.85rem; line-height:1.5; }\n  pre code { background:transparent; padding:0; }\n  blockquote { border-left:3px solid var(--border); margin:1em 0; padding:.25rem 1rem; color:var(--fg-dim); background:var(--panel); }\n  table { border-collapse:collapse; }\n  th, td { border:1px solid var(--border); padding:.4rem .75rem; }\n  th { background:var(--panel); }\n  hr { border:0; border-top:1px solid var(--border); margin:2rem 0; }\n  img { max-width:100%; }\n  ul, ol { padding-left: 1.5rem; }\n</style>\n</head><body>\n<header class="doc-hdr">\n  <a href="/">← Playground</a>\n  <span class="title">` )
    ( string_push_str out title )
    ( string_push_str out `</span>\n  <div class="spacer"></div>\n  <a href="` )
    ( string_push_str out raw_path )
    ( string_push_str out `" target="_blank" rel="noopener">raw</a>\n</header>\n<div class="wrap">\n` )
    ( string_push_str out ( string_data body ) )
    ( string_push_str out `\n</div>\n</body></html>\n` )
    ^ out
}

// Helper: serve a markdown file at `fp` rendered as HTML with the
// shared doc chrome. 404 if the source isn't present.
@ __serve_md_as_html s fp s title s raw_path s not_found_msg → HttpResponse {
    : !( Vec u ) IoErr rd ( read_file_bytes fp )
    ?? rd {
        T body → {
            : i blen ( vec_len [u] body )
            : String src ( string_with_cap + blen 1 )
            : ~ i ki 0
            ~ < ki blen { : ?u co ( vec_get [u] body ki ) ?? co { T c → { ( string_push_char src c ) } F → {} } = ki + ki 1 }
            ( __string_seal src )
            ( vec_free [u] body )
            : String rendered ( md_to_html ( string_data src ) )
            ( string_free src )
            : String page ( __doc_page_html title rendered raw_path )
            ( string_free rendered )
            : HttpResponse r ( response_text 200 ( string_data page ) )
            ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
            ( string_free page )
            ^ r
        }
        F _ → { ^ ( response_text 404 not_found_msg ) }
    }
}

// Serve any repo file by its repo-relative path (under the work root):
// `.md` rendered as HTML with the doc chrome, everything else as plain
// text. The route hierarchy mirrors the repo layout (`/docs/…`, `/spec/…`,
// `/bench/…`, `/ROADMAP.md`, …) so that the relative links the browser
// finds inside a rendered README/doc resolve to a live, rendered target
// instead of a 404. Path traversal is rejected.
@ __serve_repo_doc s rel → HttpResponse {
    ? ( __has_dotdot_segment rel ) { ^ ( response_text 403 `forbidden\n` ) } {}
    : String root ( get_work_root )
    : String fp ( path_join ( string_data root ) rel )
    : i rn ( nurl_str_len rel )
    : b is_md & & & >= rn 4
    == ( nurl_str_get rel - rn 3 ) 46
    == ( nurl_str_get rel - rn 2 ) 109
    == ( nurl_str_get rel - rn 1 ) 100
    : String rawp ( string_with_cap + rn 1 )
    ( string_push_char rawp 47 ) ( string_push_str rawp rel )
    : HttpResponse r ? is_md
    ( __serve_md_as_html ( string_data fp ) rel ( string_data rawp ) `not found\n` )
    ( __serve_file_text ( string_data fp ) `text/plain; charset=utf-8` `not found\n` )
    ( string_free root ) ( string_free fp ) ( string_free rawp )
    ^ r
}

// Wildcard doc handlers — prepend the route's repo subdirectory to the
// captured `*path` tail, then hand off to __serve_repo_doc.
@ __serve_repo_subdir Params params s subdir → HttpResponse {
    ?? ( params_get params `path` ) {
        T tail → {
            : String rel ( string_with_cap + ( string_len tail ) 8 )
            ( string_push_str rel subdir )
            ( string_push_str rel ( string_data tail ) )
            : HttpResponse r ( __serve_repo_doc ( string_data rel ) )
            ( string_free rel ) ( string_free tail )
            ^ r
        }
        F _ → { ^ ( response_text 400 `path missing\n` ) }
    }
}

@ h_docs_file HttpRequest req Params params → HttpResponse { ^ ( __serve_repo_subdir params `docs/` ) }

@ h_spec_file HttpRequest req Params params → HttpResponse { ^ ( __serve_repo_subdir params `spec/` ) }

@ h_bench_file HttpRequest req Params params → HttpResponse { ^ ( __serve_repo_subdir params `bench/` ) }

// ── Doc passthrough — README.md / grammar.ebnf ────────────────────

@ h_readme HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /readme\n` )
    : String fp ( get_readme_path )
    : HttpResponse r ( __serve_md_as_html ( string_data fp ) `README` `/readme.md` `README.md not found\n` )
    ( string_free fp )
    ^ r
}

@ h_grammar HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /grammar\n` )
    : String fp ( get_grammar_path )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ?? rd {
        T body → {
            : i blen ( vec_len [u] body )
            : String text ( string_with_cap + blen 1 )
            : ~ i ki 0
            ~ < ki blen { : ?u co ( vec_get [u] body ki ) ?? co { T c → { ( string_push_char text c ) } F → {} } = ki + ki 1 }
            ( __string_seal text )
            ( vec_free [u] body )
            // Wrap the EBNF as a single fenced code block and pump it through
            // the markdown renderer so we reuse the doc-page chrome.
            : String wrapped ( string_with_cap + ( string_len text ) 64 )
            ( string_push_str wrapped `# Grammar (` )
            ( string_push_char wrapped 96 )
            ( string_push_str wrapped `spec/grammar.ebnf` )
            ( string_push_char wrapped 96 )
            ( string_push_str wrapped `)\n\n` )
            ( string_push_char wrapped 96 ) ( string_push_char wrapped 96 ) ( string_push_char wrapped 96 )
            ( string_push_str wrapped `ebnf\n` )
            ( string_push_str wrapped ( string_data text ) )
            ( string_push_char wrapped 10 )
            ( string_push_char wrapped 96 ) ( string_push_char wrapped 96 ) ( string_push_char wrapped 96 )
            ( string_push_char wrapped 10 )
            ( string_free text )
            : String rendered ( md_to_html ( string_data wrapped ) )
            ( string_free wrapped )
            : String page ( __doc_page_html `Grammar` rendered `/grammar.ebnf` )
            ( string_free rendered )
            : HttpResponse hr ( response_text 200 ( string_data page ) )
            ( response_set_header hr `Content-Type` `text/html; charset=utf-8` )
            ( string_free fp ) ( string_free page )
            ^ hr
        }
        F _ → {
            ( string_free fp )
            ^ ( response_text 404 `grammar.ebnf not found\n` )
        }
    }
}

// ── Raw doc passthroughs — text/markdown / text/plain ─────────────

// Internal: read a file and return it with the chosen Content-Type.
// 404 if the file isn't present, identical to api/'s HTTPException 404.
@ __serve_file_text s fpath s mime s not_found_msg → HttpResponse {
    : !( Vec u ) IoErr rd ( read_file_bytes fpath )
    ?? rd {
        T body → {
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` mime )
            ( response_set_body_bytes r body )
            ( vec_free [u] body )
            ^ r
        }
        F _ → { ^ ( response_text 404 not_found_msg ) }
    }
}

@ h_readme_md HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /readme.md\n` )
    : String fp ( get_readme_path )
    : HttpResponse r ( __serve_file_text ( string_data fp ) `text/markdown; charset=utf-8` `README.md not found\n` )
    ( string_free fp )
    ^ r
}

@ h_roadmap HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /roadmap\n` )
    : String fp ( get_roadmap_path )
    : HttpResponse r ( __serve_md_as_html ( string_data fp ) `Roadmap` `/roadmap.md` `ROADMAP.md not found\n` )
    ( string_free fp )
    ^ r
}

@ h_roadmap_md HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /roadmap.md\n` )
    : String fp ( get_roadmap_path )
    : HttpResponse r ( __serve_file_text ( string_data fp ) `text/markdown; charset=utf-8` `ROADMAP.md not found\n` )
    ( string_free fp )
    ^ r
}

@ h_gotchas HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /gotchas\n` )
    : String fp ( get_gotchas_path )
    : HttpResponse r ( __serve_md_as_html ( string_data fp ) `Gotchas` `/gotchas.md` `GOTCHAS.md not found\n` )
    ( string_free fp )
    ^ r
}

@ h_gotchas_md HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /gotchas.md\n` )
    : String fp ( get_gotchas_path )
    : HttpResponse r ( __serve_file_text ( string_data fp ) `text/markdown; charset=utf-8` `GOTCHAS.md not found\n` )
    ( string_free fp )
    ^ r
}

@ h_grammar_ebnf HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /grammar.ebnf\n` )
    : String fp ( get_grammar_path )
    : HttpResponse r ( __serve_file_text ( string_data fp ) `text/plain; charset=utf-8` `grammar.ebnf not found\n` )
    ( string_free fp )
    ^ r
}

@ h_license_mit_raw HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /LICENSE-MIT\n` )
    : String fp ( get_license_mit_path )
    : HttpResponse r ( __serve_file_text ( string_data fp ) `text/plain; charset=utf-8` `LICENSE-MIT not found\n` )
    ( string_free fp )
    ^ r
}

@ h_license_apache_raw HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /LICENSE-APACHE\n` )
    : String fp ( get_license_apache_path )
    : HttpResponse r ( __serve_file_text ( string_data fp ) `text/plain; charset=utf-8` `LICENSE-APACHE not found\n` )
    ( string_free fp )
    ^ r
}

@ h_notice_raw HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /NOTICE\n` )
    : String fp ( get_notice_path )
    : HttpResponse r ( __serve_file_text ( string_data fp ) `text/plain; charset=utf-8` `NOTICE not found\n` )
    ( string_free fp )
    ^ r
}

// /license — minimal HTML index that links to the two raw text files.
@ h_license HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /license\n` )
    : String html ( string_with_cap 1024 )
    ( string_push_str html `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>License · NURL</title>` )
    ( string_push_str html `<style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0f1115;color:#e6e8ee;max-width:780px;margin:2rem auto;padding:0 1.25rem;line-height:1.6}a{color:#7cc4ff}h1{border-bottom:1px solid #262c38;padding-bottom:.35em}</style>` )
    ( string_push_str html `</head><body><h1>NURL — License</h1>` )
    ( string_push_str html `<p>NURL is dual-licensed under either of:</p><ul>` )
    ( string_push_str html `<li><a href="/license/mit">MIT License</a> (<a href="/LICENSE-MIT">raw</a>)</li>` )
    ( string_push_str html `<li><a href="/license/apache">Apache License 2.0</a> (<a href="/LICENSE-APACHE">raw</a>)</li>` )
    ( string_push_str html `</ul><p>at your option. SPDX: <code>MIT OR Apache-2.0</code></p>` )
    ( string_push_str html `<p>See also <a href="/NOTICE">NOTICE</a>.</p></body></html>` )
    : HttpResponse r ( response_text 200 ( string_data html ) )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ^ r
}

// /license/mit, /license/apache — the rendered-page variants. Python
// renders markdown→HTML; until the NURL markdown parser lands these
// serve the raw text wrapped in a dark <pre> so the page looks like
// the rest of the playground rather than a stark white default.
@ __serve_doc_pre s title s fpath s raw_path s not_found_msg → HttpResponse {
    : !( Vec u ) IoErr rd ( read_file_bytes fpath )
    ?? rd {
        T body → {
            : String html ( string_with_cap + ( vec_len [u] body ) 2048 )
            ( string_push_str html `<!doctype html><html lang="en"><head><meta charset="utf-8">` )
            ( string_push_str html `<title>` ) ( string_push_str html title ) ( string_push_str html ` · NURL</title>` )
            ( string_push_str html `<style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0f1115;color:#e6e8ee;margin:0}header{display:flex;align-items:center;gap:.75rem;padding:.75rem 1rem;border-bottom:1px solid #262c38;background:#161a21;position:sticky;top:0}header a{color:#7cc4ff;text-decoration:none;font-size:.9rem}header .title{font-weight:600}header .spacer{flex:1}.wrap{max-width:860px;margin:0 auto;padding:1.5rem 1.25rem 4rem}pre{font-family:ui-monospace,Menlo,Consolas,monospace;background:#161a21;border:1px solid #262c38;padding:1rem;border-radius:8px;white-space:pre-wrap;word-wrap:break-word;font-size:.85rem;line-height:1.5}</style>` )
            ( string_push_str html `</head><body><header><a href="/">← Playground</a><span class="title">` )
            ( string_push_str html title )
            ( string_push_str html `</span><div class="spacer"></div><a href="` )
            ( string_push_str html raw_path )
            ( string_push_str html `" target="_blank" rel="noopener">raw</a></header><div class="wrap"><pre>` )
            // Append body as escaped HTML. Minimal escape: &, <, >. For licenses + .md
            // these characters are rare; we walk the byte buffer once.
            : i blen ( vec_len [u] body )
            : ~ i k 0
            ~ < k blen {
                : ?u co ( vec_get [u] body k )
                ?? co {
                    T c → {
                        ? == c 38 { ( string_push_str html `&amp;` ) } {
                            ? == c 60 { ( string_push_str html `&lt;` ) } {
                                ? == c 62 { ( string_push_str html `&gt;` ) } {
                                    ( string_push_char html c )
                                }
                            }
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free [u] body )
            ( string_push_str html `</pre></div></body></html>` )
            : HttpResponse r ( response_text 200 ( string_data html ) )
            ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
            ^ r
        }
        F _ → { ^ ( response_text 404 not_found_msg ) }
    }
}

@ h_license_mit HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /license/mit\n` )
    : String fp ( get_license_mit_path )
    : HttpResponse r ( __serve_doc_pre `MIT License` ( string_data fp ) `/LICENSE-MIT` `LICENSE-MIT not found\n` )
    ( string_free fp )
    ^ r
}

@ h_license_apache HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /license/apache\n` )
    : String fp ( get_license_apache_path )
    : HttpResponse r ( __serve_doc_pre `Apache License 2.0` ( string_data fp ) `/LICENSE-APACHE` `LICENSE-APACHE not found\n` )
    ( string_free fp )
    ^ r
}

// ── Recursive .nu file listings — /stdlib + /tests JSON ──────────

// Join `root` with `prefix`; when `prefix` is empty, returns a fresh
// copy of `root`. Factored out because inline ternary on a String
// return trips a codegen bug ("call @?" with String args).
@ __join_or_root s root s prefix → String {
    ? > ( nurl_str_len prefix ) 0 { ^ ( path_join root prefix ) } {}
    ^ ( string_from root )
}

// Walk `root_dir` recursively. For every regular .nu file found,
// append { name: <rel>, path: <rel>, bytes: N } to `arr`. `rel` is
// the path relative to root_dir (POSIX-style, "/" separator).
// Subdirectories are entered if dir_list succeeds on them. Entries
// at each level are sorted alphabetically before walking, which gives
// a globally sorted output (top-level "foo.nu" comes before subdir
// "g/bar.nu" iff "foo.nu" < "g" lexicographically).
@ __walk_nu_files Json arr s root_dir s rel_prefix → v {
    : String full ( __join_or_root root_dir rel_prefix )
    : !( Vec String ) IoErr dr ( dir_list ( string_data full ) )
    ?? dr {
        T entries → {
            ( sort_by [String] entries \ String a String b → i {
                ^ ( nurl_str_cmp ( string_data a ) ( string_data b ) )
            } )
            : i n ( vec_len [String] entries )
            : ~ i i 0
            ~ < i n {
                ?? ( vec_get [String] entries i ) {
                    T name → {
                        : String child_rel ( __join_or_root rel_prefix ( string_data name ) )
                        : String child_full ( path_join ( string_data full ) ( string_data name ) )
                        ? ( string_ends_with name `.nu` ) {
                            : !i IoErr sz ( file_size ( string_data child_full ) )
                            ?? sz {
                                T bytes → {
                                    : Json o ( json_obj_new )
                                    ( json_obj_set o `name` ( json_str_lit ( string_data child_rel ) ) )
                                    ( json_obj_set o `path` ( json_str_lit ( string_data child_rel ) ) )
                                    ( json_obj_set o `bytes` ( json_int bytes ) )
                                    ( json_arr_push arr o )
                                }
                                F _ → {}
                            }
                        } {
                            // Try to recurse — if it's a directory, dir_list succeeds.
                            ( __walk_nu_files arr root_dir ( string_data child_rel ) )
                        }
                        ( string_free child_full )
                        ( string_free child_rel )
                    }
                    F _ → {}
                }
                = i + i 1
            }
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] entries k ) { T fs → ( string_free fs ) F _ → {} }
                = k + k 1
            }
            ( vec_free [String] entries )
        }
        F _ → {}
    }
    ( string_free full )
}

@ h_stdlib_list HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /stdlib\n` )
    : String dir ( get_stdlib_dir )
    : Json arr ( json_arr_new )
    ( __walk_nu_files arr ( string_data dir ) `` )
    : String body ( json_stringify arr )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( json_free arr ) ( string_free dir ) ( string_free body )
    ^ r
}

@ h_tests_list HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /tests\n` )
    : String dir ( get_tests_dir )
    : Json arr ( json_arr_new )
    ( __walk_nu_files arr ( string_data dir ) `` )
    : String body ( json_stringify arr )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( json_free arr ) ( string_free dir ) ( string_free body )
    ^ r
}

// ── Directory listing viewers — /stdlib-viewer + /tests-viewer ──

// Single Monaco-highlighted viewer page lives in
// `static/viewer.html` and self-detects stdlib vs. tests via
// `location.pathname`. Both /stdlib-viewer and /tests-viewer serve
// the SAME file — only the URL the browser landed on differs, which
// the page's JS uses to pick the back-end endpoint (`/stdlib` vs
// `/tests`), the title, and the breadcrumb prefix. This keeps the
// NURL handler a thin static-file passthrough; replacing the previous
// inline-built minimal directory listing.
@ __serve_viewer_html → HttpResponse {
    : String sdir ( get_static_dir )
    : String fp ( path_join ( string_data sdir ) `viewer.html` )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ( string_free sdir ) ( string_free fp )
    ?? rd {
        T body → {
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
            ( response_set_body_bytes r body )
            ( vec_free [u] body )
            ^ r
        }
        F _ → { ^ ( response_text 500 `viewer.html not found in static dir\n` ) }
    }
}

// Serve the Game Boy WebAssembly demo page (static/gameboydemo.html).
@ __serve_gameboydemo → HttpResponse {
    : String sdir ( get_static_dir )
    : String fp ( path_join ( string_data sdir ) `gameboydemo.html` )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ( string_free sdir ) ( string_free fp )
    ?? rd {
        T body → {
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
            ( response_set_body_bytes r body )
            ( vec_free [u] body )
            ^ r
        }
        F _ → { ^ ( response_text 500 `gameboydemo.html not found in static dir\n` ) }
    }
}

// Serve the Commodore 64 WebAssembly demo page (static/c64demo.html).
@ __serve_c64demo → HttpResponse {
    : String sdir ( get_static_dir )
    : String fp ( path_join ( string_data sdir ) `c64demo.html` )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ( string_free sdir ) ( string_free fp )
    ?? rd {
        T body → {
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
            ( response_set_body_bytes r body )
            ( vec_free [u] body )
            ^ r
        }
        F _ → { ^ ( response_text 500 `c64demo.html not found in static dir\n` ) }
    }
}

@ h_stdlib_viewer HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /stdlib-viewer\n` )
    ^ ( __serve_viewer_html )
}

@ h_tests_viewer HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /tests-viewer\n` )
    ^ ( __serve_viewer_html )
}

// Single-file passthrough used by /stdlib/<path> and /tests/<path>.
// Returns a `{name, source, bytes}` JSON object so the shape matches
// api/'s StdlibContent / TestContent (the viewer pages fetch JSON).
// Refuses `..` segments.
@ __serve_module_json HttpRequest req String dir s name → HttpResponse {
    ? ( __has_dotdot_segment name ) {
        ^ ( response_text 403 `{"error":"forbidden"}` )
    } {}
    : String fpath ( path_join ( string_data dir ) name )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fpath ) )
    ?? rd {
        T body → {
            : i sz ( vec_len [u] body )
            : String src ( string_with_cap + sz 1 )
            : ~ i ki 0 ~ < ki sz { : ?u co ( vec_get [u] body ki ) ?? co { T c → { ( string_push_char src c ) } F → {} } = ki + ki 1 }
            ( __string_seal src )
            : Json o ( json_obj_new )
            ( json_obj_set o `name` ( json_str_lit name ) )
            ( json_obj_set o `source` ( json_str_lit ( string_data src ) ) )
            ( json_obj_set o `bytes` ( json_int sz ) )
            : String body_s ( json_stringify o )
            : HttpResponse r ( response_text 200 ( string_data body_s ) )
            ( response_set_header r `Content-Type` `application/json` )
            ( string_free src ) ( json_free o ) ( string_free body_s )
            ( vec_free [u] body )
            ( string_free fpath )
            ^ r
        }
        F _ → {
            ( string_free fpath )
            ^ ( response_text 404 `{"error":"not found"}` )
        }
    }
}

@ h_stdlib_file HttpRequest req Params params → HttpResponse {
    : ?String tail_opt ( params_get params `path` )
    ?? tail_opt {
        T tail → {
            : String dir ( get_stdlib_dir )
            : HttpResponse r ( __serve_module_json req dir ( string_data tail ) )
            ( string_free dir ) ( string_free tail )
            ^ r
        }
        F _ → { ^ ( response_text 400 `{"error":"path missing"}\n` ) }
    }
}

@ h_tests_file HttpRequest req Params params → HttpResponse {
    : ?String tail_opt ( params_get params `path` )
    ?? tail_opt {
        T tail → {
            : String dir ( get_tests_dir )
            : HttpResponse r ( __serve_module_json req dir ( string_data tail ) )
            ( string_free dir ) ( string_free tail )
            ^ r
        }
        F _ → { ^ ( response_text 400 `{"error":"path missing"}\n` ) }
    }
}

// ── /stdlib-docs — rendered API reference (nurldoc → md_to_html) ──────
//
// The stdlib source is self-documenting (a `//` module-header block + doc
// comments above each declaration); `nurldoc_render` turns one module
// into Markdown and the existing md_to_html + doc chrome present it with
// the same dark theme as the README/spec pages. `/stdlib-docs` is an
// auto-generated index; `/stdlib-docs/<path>` renders one module
// (`<path>.md` returns the raw Markdown).

// First path segment of `p` ("std/time.nu" → "std"; "json.nu" → "root").
@ __sd_group s p → String {
    : i n ( nurl_str_len p )
    : ~ i slash -1
    : ~ i k 0
    ~ & < k n < slash 0 { ? == ( nurl_str_get p k ) 47 { = slash k } {} = k + k 1 }
    ? < slash 0 { ^ ( string_from `root` ) } {}
    ^ ( string_from ( nurl_str_slice p 0 slash ) )
}

@ __stdlib_doc_index → HttpResponse {
    : Json mods ( list_stdlib_modules )
    : i nm ( json_arr_len mods )
    : ( Vec String ) paths ( vec_new [String] )
    : ~ i i 0
    ~ < i nm {
        : ?Json e ( json_arr_get mods i )
        ?? e { T j → ( vec_push [String] paths ( string_from ( json_str_data j ) ) ) F _ → {} }
        = i + i 1
    }
    ( json_free mods )
    : ( @ i String String ) cmp \ String a String b → i { ^ ( nurl_str_cmp ( string_data a ) ( string_data b ) ) }
    ( sort_by [String] paths cmp )
    : *u cmp_env # *u cmp 1
    ( nurl_free # s cmp_env )

    : String md ( string_with_cap 8192 )
    ( string_push_str md `# NURL Standard Library\n\n` )
    ( string_push_str md `Auto-generated API reference — extracted from each module's source by ` )
    ( string_push_char md 96 ) ( string_push_str md `nurldoc` ) ( string_push_char md 96 )
    ( string_push_str md `. Pick a module for its rendered signatures and doc comments.\n` )
    : ~ String cur ( string_from `` )
    : ~ i k 0
    ~ < k ( vec_len [String] paths ) {
        ?? ( vec_get [String] paths k ) {
            T p → {
                : s ps ( string_data p )
                : String grp ( __sd_group ps )
                ? == 0 ( nurl_str_eq ( string_data grp ) ( string_data cur ) ) {
                    ( string_push_str md `\n## ` ) ( string_push_str md ( string_data grp ) ) ( string_push_str md `\n\n` )
                    ( string_free cur ) = cur ( string_from ( string_data grp ) )
                } {}
                ( string_free grp )
                ( string_push_str md `- [` ) ( string_push_str md ps )
                ( string_push_str md `](/stdlib-docs/` ) ( string_push_str md ps ) ( string_push_str md `)\n` )
                ( string_free p )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( string_free cur )
    ( vec_free [String] paths )

    : String html ( md_to_html ( string_data md ) )
    ( string_free md )
    : String page ( __doc_page_html `NURL Standard Library` html `/stdlib-docs` )
    ( string_free html )
    : HttpResponse r ( response_text 200 ( string_data page ) )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( string_free page )
    ^ r
}

@ h_stdlib_docs HttpRequest req Params params → HttpResponse {
    : ?String tail_opt ( params_get params `path` )
    ?? tail_opt {
        T tail → {
            ( nurl_print `[srv] GET /stdlib-docs/` ) ( nurl_print ( string_data tail ) ) ( nurl_print `\n` )
            ? ( __has_dotdot_segment ( string_data tail ) ) {
                ( string_free tail )
                ^ ( response_text 403 `forbidden\n` )
            } {}
            : i tn ( string_len tail )
            : b is_raw ( string_ends_with tail `.md` )
            : String rel ? is_raw ( string_from ( nurl_str_slice ( string_data tail ) 0 - tn 3 ) ) ( string_from ( string_data tail ) )
            : String dir ( get_stdlib_dir )
            : String fp ( path_join ( string_data dir ) ( string_data rel ) )
            : !String IoErr cr ( read_file ( string_data fp ) )
            : HttpResponse res ?? cr {
                T src → {
                    : String docmd ( nurldoc_render ( string_data src ) ( string_data rel ) )
                    ( string_free src )
                    : HttpResponse r ? is_raw {
                        : HttpResponse rr ( response_text 200 ( string_data docmd ) )
                        ( response_set_header rr `Content-Type` `text/markdown; charset=utf-8` )
                        ^ rr
                    } {
                        : String html ( md_to_html ( string_data docmd ) )
                        : String rawp ( string_with_cap + ( string_len rel ) 20 )
                        ( string_push_str rawp `/stdlib-docs/` ) ( string_push_str rawp ( string_data rel ) ) ( string_push_str rawp `.md` )
                        : String page ( __doc_page_html ( string_data rel ) html ( string_data rawp ) )
                        ( string_free html ) ( string_free rawp )
                        : HttpResponse rr ( response_text 200 ( string_data page ) )
                        ( response_set_header rr `Content-Type` `text/html; charset=utf-8` )
                        ( string_free page )
                        ^ rr
                    }
                    ( string_free docmd )
                    ^ r
                }
                F _ → ( response_text 404 `module not found\n` )
            }
            ( string_free fp ) ( string_free dir ) ( string_free rel ) ( string_free tail )
            ^ res
        }
        F _ → { ^ ( response_text 400 `path missing\n` ) }
    }
}

@ h_stdlib_docs_index HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /stdlib-docs\n` )
    ^ ( __stdlib_doc_index )
}

// ── /targets — JSON list of compile targets (UI dropdown source) ──

// Append one TargetInfo entry to `arr`. Shape mirrors api/'s
// TargetInfo dataclass — id / label / group / endpoint / runnable /
// notes — so the playground's existing dropdown JS works unchanged.
@ __push_target Json arr s id s label s group s endpoint b runnable s notes → v {
    : Json o ( json_obj_new )
    ( json_obj_set o `id` ( json_str_lit id ) )
    ( json_obj_set o `label` ( json_str_lit label ) )
    ( json_obj_set o `group` ( json_str_lit group ) )
    ( json_obj_set o `endpoint` ( json_str_lit endpoint ) )
    ( json_obj_set o `runnable` ( json_bool runnable ) )
    ( json_obj_set o `notes` ( json_str_lit notes ) )
    ( json_arr_push arr o )
}

@ h_targets HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] GET /targets\n` )
    : Json arr ( json_arr_new )
    ( __push_target arr `wasm` `WebAssembly · wasm32-wasi` `WebAssembly` `/build_wasm` T `runs in-browser · full canvas/audio FFI` )
    ( __push_target arr `linux-x64` `Linux x86_64 · native (glibc)` `Linux` `/build` F `full FFI: HTTP / sqlite / canvas` )
    ( __push_target arr `linux-x64-musl` `Linux x86_64 · musl (static)` `Linux` `/build_target` F `static ELF · no HTTP/canvas/audio` )
    ( __push_target arr `linux-arm64-musl` `Linux ARM64 · musl (static)` `Linux` `/build_target` F `static ELF · no HTTP/canvas/audio` )
    ( __push_target arr `linux-arm64-gnu` `Linux ARM64 · glibc` `Linux` `/build_target` F `dynamic ELF (glibc 2.31+) · no HTTP/canvas/audio` )
    ( __push_target arr `linux-riscv64-musl` `Linux RISC-V 64 · musl (static)` `Linux` `/build_target` F `static ELF · no HTTP/canvas/audio` )
    ( __push_target arr `macos-x64` `macOS x86_64 · Intel` `macOS` `/build_target` F `libSystem only · no HTTP/canvas/audio` )
    ( __push_target arr `macos-arm64` `macOS ARM64 · Apple Silicon` `macOS` `/build_target` F `libSystem only · no HTTP/canvas/audio` )
    ( __push_target arr `windows-x64` `Windows x86_64 · .exe (mingw-w64)` `Windows` `/build_windows` F `static libcurl HTTP · no canvas/audio` )
    : String body ( json_stringify arr )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( json_free arr ) ( string_free body )
    ^ r
}

// ── /build_target — generic cross-compile via zig cc ───────────────

// Resolve target_id → (zig triple, static-flag, libs string).
// Returns empty triple when the id is unknown (caller emits 400).
@ __zig_triple_for s id → s {
    ? ( nurl_str_eq id `linux-x64-musl` ) { ^ `x86_64-linux-musl` } {}
    ? ( nurl_str_eq id `linux-arm64-musl` ) { ^ `aarch64-linux-musl` } {}
    ? ( nurl_str_eq id `linux-arm64-gnu` ) { ^ `aarch64-linux-gnu.2.31` } {}
    ? ( nurl_str_eq id `linux-riscv64-musl` ) { ^ `riscv64-linux-musl` } {}
    ? ( nurl_str_eq id `macos-x64` ) { ^ `x86_64-macos-none` } {}
    ? ( nurl_str_eq id `macos-arm64` ) { ^ `aarch64-macos-none` } {}
    ^ ``
}

@ __zig_is_static s id → b {
    ? ( nurl_str_eq id `linux-x64-musl` ) { ^ T } {}
    ? ( nurl_str_eq id `linux-arm64-musl` ) { ^ T } {}
    ? ( nurl_str_eq id `linux-riscv64-musl` ) { ^ T } {}
    ^ F
}

@ __zig_is_linux s id → b {
    ? ( nurl_str_eq id `linux-x64-musl` ) { ^ T } {}
    ? ( nurl_str_eq id `linux-arm64-musl` ) { ^ T } {}
    ? ( nurl_str_eq id `linux-arm64-gnu` ) { ^ T } {}
    ? ( nurl_str_eq id `linux-riscv64-musl` ) { ^ T } {}
    ^ F
}

@ h_build_target HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] POST /build_target\n` )
    : String body_str ( get_body_str req )
    : !Json JsonError root_res ( json_parse ( string_data body_str ) )
    ?? root_res {
        T root → {
            : s source ( get_common_json root `source` `` )
            : s target ( get_common_json root `target` `` )
            : s filename ( get_common_json root `filename` `main.nu` )
            : s opt ( get_common_json root `opt` `-O2` )
            ? == ( nurl_str_len source ) 0 { ( json_free root ) ( string_free body_str ) ^ ( response_text 400 `{"error":"source is required"}\n` ) } {}
            : s triple ( __zig_triple_for target )
            ? == ( nurl_str_len triple ) 0 {
                ( json_free root ) ( string_free body_str )
                ^ ( response_text 400 `{"error":"unknown target id (see GET /targets)"}\n` )
            } {}
            : b is_static ( __zig_is_static target )
            : b is_linux ( __zig_is_linux target )

            : String build_id ( create_build_id )
            : String build_dir ( path_join ( string_data ( get_output_dir ) ) ( string_data build_id ) )
            : !v IoErr dr ( dir_create ( string_data build_dir ) )
            ?? dr {
                T _ → {
                    : String nu_path ( path_join ( string_data build_dir ) filename )
                    ( write_file ( string_data nu_path ) source )
                    : String ll_path ( path_join ( string_data build_dir ) `main.ll` )
                    : ~ String bin_name ( string_from filename )
                    ? ( string_ends_with bin_name `.nu` ) { : String tmp ( string_substr bin_name 0 - ( string_len bin_name ) 3 ) ( string_free bin_name ) = bin_name tmp } {}
                    : String bin_path ( path_join ( string_data build_dir ) ( string_data bin_name ) )
                    : String rt_o ( get_runtime_target_o target )

                    : ( Vec s ) nurlc_args ( vec_new [s] ) ( vec_push [s] nurlc_args ( string_data nu_path ) )
                    : !Output ProcessErr nurlc_res ( process_run ( string_data ( get_nurlc_path ) ) nurlc_args `` ) ( vec_free [s] nurlc_args )
                    ?? nurlc_res {
                        T n_out → {
                            : i n_rc ( output_exit_code n_out )
                            ? ( output_success n_out ) {
                                ( write_file ( string_data ll_path ) ( output_stdout n_out ) )
                                : ( Vec s ) zig_args ( vec_new [s] )
                                ( vec_push [s] zig_args `cc` )
                                ( vec_push [s] zig_args `-target` ) ( vec_push [s] zig_args triple )
                                ( vec_push [s] zig_args opt )
                                ( vec_push [s] zig_args `-Wno-override-module` )
                                ? is_static { ( vec_push [s] zig_args `-static` ) } {}
                                ( vec_push [s] zig_args ( string_data ll_path ) )
                                ( vec_push [s] zig_args ( string_data rt_o ) )
                                ? is_linux { ( vec_push [s] zig_args `-lm` ) ( vec_push [s] zig_args `-lpthread` ) } {}
                                ( vec_push [s] zig_args `-o` ) ( vec_push [s] zig_args ( string_data bin_path ) )
                                : !Output ProcessErr zig_res ( process_run ( string_data ( get_zig ) ) zig_args `` ) ( vec_free [s] zig_args )
                                ?? zig_res {
                                    T z_out → {
                                        : i z_rc ( output_exit_code z_out )
                                        : i n_so_bytes ( nurl_str_len ( output_stdout n_out ) )
                                        : s z_so ( output_stdout z_out )
                                        : s z_se ( output_stderr z_out )
                                        : s n_se ( output_stderr n_out )
                                        : String combined_stderr ( combine_stderr n_se z_se )

                                        : Json res ( json_obj_new )
                                        ( stamp_build_response res
                                        ? == z_rc 0 `ok` `error`
                                        ? == z_rc 0 `compiled nurl → zig target` `build failed (see stderr)`
                                        filename F
                                        n_rc n_se n_so_bytes
                                        z_rc z_so z_se
                                        z_so ( string_data combined_stderr ) )
                                        // Target-specific extras retained on top of the
                                        // shared shape (api/ uses BuildResponse without
                                        // them; harmless additions for inspection).
                                        ( json_obj_set res `target` ( json_str_lit target ) )
                                        ( json_obj_set res `triple` ( json_str_lit triple ) )

                                        ? == z_rc 0 {
                                            : !i IoErr bn_sz ( file_size ( string_data bin_path ) )
                                            ( json_obj_set res `binary_artifact`
                                            ( make_artifact_json ( string_data bin_name )
                                            ?? bn_sz { T s → s F _ → 0 } ( string_data build_id ) ) )
                                        } {}

                                        : String body ( json_stringify res )
                                        : HttpResponse hr ( response_text 200 ( string_data body ) )
                                        ( response_set_header hr `Content-Type` `application/json` )
                                        ( string_free combined_stderr ) ( json_free res )
                                        ( output_free n_out ) ( output_free z_out ) ( json_free root )
                                        ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name )
                                        ( string_free bin_path ) ( string_free rt_o ) ( string_free build_id )
                                        ( string_free build_dir ) ( string_free body_str ) ( string_free body )
                                        ^ hr
                                    }
                                    F _ → { ^ ( response_text 500 `{"error":"zig cc invocation failed"}\n` ) }
                                }
                            } {
                                : HttpResponse hr_err ( nurlc_failure_response filename ( output_exit_code n_out ) ( output_stderr n_out ) ( nurl_str_len ( output_stdout n_out ) ) )
                                ( output_free n_out ) ( json_free root )
                                ( string_free nu_path ) ( string_free ll_path ) ( string_free bin_name )
                                ( string_free bin_path ) ( string_free rt_o ) ( string_free build_id )
                                ( string_free build_dir ) ( string_free body_str )
                                ^ hr_err
                            }
                        }
                        F _ → { ^ ( response_text 500 `{"error":"nurlc failed"}\n` ) }
                    }
                }
                F _ → { ^ ( response_text 500 `{"error":"could not create build dir"}\n` ) }
            }
        }
        F _ → { ^ ( response_text 400 `{"error":"invalid json"}\n` ) }
    }
}

// ═════════════════════════════════════════════════════════════════════
//
//   MCP (Model Context Protocol) — POST /mcp Streamable HTTP transport
//
// ═════════════════════════════════════════════════════════════════════
//
// Design notes — addressing the two reliability gaps the Python
// playground hit in production:
//
// 1. **Session persistence across container restarts.** Claude WebUI
//    connector lost its session every time the Cloudflare deployment
//    rolled, even when nothing playground-related changed. Root cause
//    was the Python MCP server validating Mcp-Session-Id against a
//    per-process in-memory set — a fresh pod = a fresh set = every
//    previously-issued sid rejected.
//
//    NURL approach: the session ID is **opaque to the server**. On the
//    first request (no Mcp-Session-Id header) we generate one and
//    return it in the response header; on every subsequent request we
//    echo whatever sid the client sends back, no validation. Clients
//    that connected before the restart keep working — their sid is
//    accepted verbatim. This is a deliberate trade against fully
//    stateful sessions (which MCP allows but doesn't require); for a
//    request/response RPC server with no per-session state to lose,
//    statelessness IS the correctness property.
//
// 2. **Burst handling.** Python MCP stalled under tightly-clustered
//    requests because the asyncio event loop serialised them through
//    one task. NURL piggybacks on `server_run_pool`'s 16 pthread
//    workers — each POST /mcp dispatches on its own thread, no
//    serialisation. JSON-RPC batches (top-level arrays) are also
//    supported by `stdlib/ext/mcp_http.nu`'s handler, routing each
//    sub-request through the dispatch and collecting non-notification
//    replies into an array response.
//
// Surface:
//   POST   /mcp  — single JSON-RPC request or batch array
//   GET    /mcp  — single-event SSE stub (`event: ready`) so clients
//                  detect the protocol. Continuous server-initiated
//                  notifications need a queue + chunked writer; v2.
//   DELETE /mcp  — 204 No Content (stateless tear-down).
//   OPTIONS /mcp — auto-handled by `http_router.nu` since the HEAD/
//                  OPTIONS support commit.
//
// 15 tools, 7 resources, 1 prompt — full Python parity.

// ── Helpers for tool argument extraction (borrowed `s`) ────────────

@ __mcp_args_get s key Json args s default → s {
    : ?Json v ( json_obj_get args key )
    ?? v {
        T j → {
            ^ ?? j {
                JStr s → ( string_data s )
                _ → default
            }
        }
        F _ → { ^ default }
    }
}

// Integer tool argument: JNum → i; absent / non-numeric → default.
@ __mcp_args_get_int s key Json args i default → i {
    : ?Json v ( json_obj_get args key )
    ?? v {
        T j → { ^ ?? ( json_num_as_i j ) { T n → n F _ → default } }
        F _ → { ^ default }
    }
}

// ── Tool schemas — small helpers keep the descriptor table terse.

@ __mcp_prop s ptype s desc → Json {
    : Json p ( json_obj_new )
    ( json_obj_set p `type` ( json_str_lit ptype ) )
    ( json_obj_set p `description` ( json_str_lit desc ) )
    ^ p
}

@ __mcp_prop_enum s ptype s desc ( Vec s ) enum_vals → Json {
    : Json p ( json_obj_new )
    ( json_obj_set p `type` ( json_str_lit ptype ) )
    ( json_obj_set p `description` ( json_str_lit desc ) )
    : Json e ( json_arr_new )
    : i en ( vec_len [s] enum_vals )
    : ~ i k 0
    ~ < k en {
        ?? ( vec_get [s] enum_vals k ) { T v → ( json_arr_push e ( json_str_lit v ) ) F _ → {} }
        = k + k 1
    }
    ( json_obj_set p `enum` e )
    ^ p
}

// Schema: { source: string (required), filename: string (optional) }
@ __mcp_schema_source_filename → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( json_obj_set props `source`
    ( __mcp_prop `string` `NURL source code (full file contents)` ) )
    ( json_obj_set props `filename`
    ( __mcp_prop `string` `Logical filename for diagnostics (default main.nu)` ) )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `source` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ __mcp_schema_build_target → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( json_obj_set props `source`
    ( __mcp_prop `string` `NURL source code (full file contents)` ) )
    : ( Vec s ) targets ( vec_new [s] )
    ( vec_push [s] targets `linux-x64-musl` )
    ( vec_push [s] targets `linux-arm64-musl` )
    ( vec_push [s] targets `linux-arm64-gnu` )
    ( vec_push [s] targets `linux-riscv64-musl` )
    ( vec_push [s] targets `macos-x64` )
    ( vec_push [s] targets `macos-arm64` )
    ( json_obj_set props `target`
    ( __mcp_prop_enum `string` `Cross-compile target id` targets ) )
    ( vec_free [s] targets )
    ( json_obj_set props `filename`
    ( __mcp_prop `string` `Logical filename for diagnostics (default main.nu)` ) )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `source` ) )
    ( json_arr_push req ( json_str_lit `target` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ __mcp_schema_name → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( json_obj_set props `name`
    ( __mcp_prop `string` `Relative path under the catalogue root (e.g. core/string.nu)` ) )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `name` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ __mcp_schema_empty → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    ( json_obj_set schema `properties` ( json_obj_new ) )
    ^ schema
}

// ── Tool result helpers ─────────────────────────────────────────────

// Wrap raw text (or stringified JSON) as a single text-content tool
// result. The Claude UI renders text content monospace + verbatim,
// which is exactly what we want for source listings and JSON blobs.
@ __mcp_result_text s text → Json { ^ ( mcp_tool_result_text text ) }

@ __mcp_result_error s message → Json { ^ ( mcp_tool_result_error message ) }

// Read a file and return its content as a tool result. Captures
// large reads as one big text block — Claude's per-message size
// cap is the real bound here (~200 KB at time of writing).
@ __mcp_read_file_result s fpath → Json {
    : !( Vec u ) IoErr rd ( read_file_bytes fpath )
    ?? rd {
        T body → {
            : String s_body ( bytes_to_str body )
            : Json result ( __mcp_result_text ( string_data s_body ) )
            ( vec_free [u] body )
            ( string_free s_body )
            ^ result
        }
        F _ → { ^ ( __mcp_result_error `file not found` ) }
    }
}

// Recursively list every .nu file under `dir`, return as a JSON array
// of {name, path, bytes}. Reuses the same walker /stdlib + /tests use.
@ __mcp_list_files_result s dir → Json {
    : Json arr ( json_arr_new )
    ( __walk_nu_files arr dir `` )
    : String body ( json_stringify arr )
    : Json result ( __mcp_result_text ( string_data body ) )
    ( json_free arr )
    ( string_free body )
    ^ result
}

// ── Loopback HTTP for the 5 build tools ────────────────────────────
//
// Each build tool builds a {source, filename, [target]} body, POSTs
// it to its own HTTP endpoint on `NURL_MCP_LOOPBACK_URL` (default
// http://127.0.0.1:8000) and returns the response body verbatim as
// the tool result. Goes through the SAME handler the HTTP API
// uses — one canonical implementation, two interfaces. Each call
// crosses the worker-pool boundary (MCP request thread + /build
// thread), which the 16-worker default of server_run_pool handles
// trivially.

@ __mcp_build_endpoint s endpoint Json body → Json {
    : String body_s ( json_stringify body )
    : String url_base ( get_mcp_loopback_url )
    : String url ( string_with_cap + 64 ( string_len url_base ) )
    ( string_push_str url ( string_data url_base ) )
    ( string_push_str url endpoint )
    : !Response HttpErr r ( http_post ( string_data url ) ( string_data body_s ) `application/json` )
    ( string_free body_s ) ( string_free url ) ( string_free url_base )
    ?? r {
        T resp → {
            : s text ( http_body_str resp )
            : Json result ( __mcp_result_text text )
            ( response_free resp )
            ^ result
        }
        F e → {
            : String msg ( string_with_cap 64 )
            ( string_push_str msg `loopback build call failed: ` )
            ( string_push_str msg ( http_err_name e ) )
            : Json result ( __mcp_result_error ( string_data msg ) )
            ( string_free msg )
            ^ result
        }
    }
}

@ __mcp_tool_build_source_filename s endpoint Json args → Json {
    : s source ( __mcp_args_get `source` args `` )
    : s filename ( __mcp_args_get `filename` args `main.nu` )
    ? == ( nurl_str_len source ) 0 {
        ^ ( __mcp_result_error `argument 'source' is required` )
    } {}
    : Json body ( json_obj_new )
    ( json_obj_set body `source` ( json_str_lit source ) )
    ( json_obj_set body `filename` ( json_str_lit filename ) )
    : Json result ( __mcp_build_endpoint endpoint body )
    ( json_free body )
    ^ result
}

@ __mcp_tool_build_target_impl Json args → Json {
    : s source ( __mcp_args_get `source` args `` )
    : s target ( __mcp_args_get `target` args `` )
    : s filename ( __mcp_args_get `filename` args `main.nu` )
    ? == ( nurl_str_len source ) 0 { ^ ( __mcp_result_error `argument 'source' is required` ) } {}
    ? == ( nurl_str_len target ) 0 { ^ ( __mcp_result_error `argument 'target' is required` ) } {}
    : Json body ( json_obj_new )
    ( json_obj_set body `source` ( json_str_lit source ) )
    ( json_obj_set body `target` ( json_str_lit target ) )
    ( json_obj_set body `filename` ( json_str_lit filename ) )
    : Json result ( __mcp_build_endpoint `/build_target` body )
    ( json_free body )
    ^ result
}

// ── nurl_changelog — targeted CHANGELOG.md retrieval ────────────────
//
// CHANGELOG.md is ~240 KB and growing; dumping it whole into a model
// context to answer "when did X change?" wastes the window. This tool
// returns COMPLETE changelog entries — one top-level `- ` bullet plus a
// `[release] — date › category` provenance line — selected by
// AND-matched case-insensitive terms, optionally narrowed to one
// release. With no arguments it returns a compact index (releases +
// ent counts) so a model can orient itself with one cheap call.
// Output is byte-capped; a trailing note reports how many further
// matches were omitted so the model knows to refine, not re-read.

// Lowercase an owned copy of a borrowed `s`.
@ __lc_owned s raw → String {
    : String tmp ( string_from raw )
    : String lc ( string_to_lower tmp )
    ( string_free tmp )
    ^ lc
}

@ __cl_is_ws i c → b { ^ | | | == c 10 == c 13 == c 32 == c 9 }

// True iff every non-empty term occurs in `hay_lc` (both lowercase).
@ __cl_terms_match String hay_lc ( Vec String ) terms → b {
    : i n ( vec_len [String] terms )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] terms k ) {
            T t → {
                ? & > ( string_len t ) 0 < ( nurl_str_find ( string_data hay_lc ) ( string_data t ) ) 0 { ^ F } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ T
}

// Total output cap (bytes) for one tool call. Entries average ~1-2 KB;
// 32 KB keeps even a generous `limit` from flooding the caller's
// context while still fitting ~15-25 full entries.
@ __cl_out_cap → i { ^ 32768 }

// Flush one accumulated ent: count it, run the release filter and the
// term match, and append it to `out` when within `limit` and the byte
// cap. `ctr` is the shared [total, matched, emitted] counter Vec (Vec is
// a shared boxed handle — mutations are visible to the caller). Clears
// `ent` so the caller can keep accumulating into the same String.
@ __cl_flush String ent String cur_rel String cur_rel_lc String cur_cat
( Vec String ) terms String rel_lc String out i limit ( Vec i ) ctr → v {
    ? > ( string_len ent ) 0 {
        // Trim trailing blank lines / whitespace off the body.
        : ~ i e ( string_len ent )
        ~ & > e 0 ( __cl_is_ws ( string_get ent - e 1 ) ) { = e - e 1 }
        : String body ( string_substr ent 0 e )

        : i total ?? ( vec_get [i] ctr 0 ) { T v → v F _ → 0 }
        ( vec_set [i] ctr 0 + total 1 )

        // Release filter: empty = all; else substring of the heading.
        : b rel_ok | == ( string_len rel_lc ) 0 >= ( nurl_str_find ( string_data cur_rel_lc ) ( string_data rel_lc ) ) 0
        ? rel_ok {
            // Provenance line, e.g. `[0.9.6] — 2026-06-08 › Fixed`.
            : String prov ( string_with_cap 64 )
            ( string_push_str prov ( string_data cur_rel ) )
            ? > ( string_len cur_cat ) 0 {
                ( string_push_str prov ` › ` )
                ( string_push_str prov ( string_data cur_cat ) )
            } {}
            // Match against provenance + body so terms like `fixed` or a
            // release date can hit the heading too.
            : String hay ( string_with_cap + + ( string_len prov ) ( string_len body ) 2 )
            ( string_push_str hay ( string_data prov ) )
            ( string_push_char hay 10 )
            ( string_push_str hay ( string_data body ) )
            : String hay_lc ( string_to_lower hay )
            ? ( __cl_terms_match hay_lc terms ) {
                : i matched ?? ( vec_get [i] ctr 1 ) { T v → v F _ → 0 }
                ( vec_set [i] ctr 1 + matched 1 )
                : i emitted ?? ( vec_get [i] ctr 2 ) { T v → v F _ → 0 }
                ? & < emitted limit < ( string_len out ) ( __cl_out_cap ) {
                    ( string_push_str out ( string_data prov ) )
                    ( string_push_char out 10 )
                    ( string_push_str out ( string_data body ) )
                    ( string_push_str out `\n\n` )
                    ( vec_set [i] ctr 2 + emitted 1 )
                } {}
            } {}
            ( string_free hay_lc ) ( string_free hay ) ( string_free prov )
        } {}
        ( string_free body )
        ( string_clear ent )
    } {}
}

// Walk the changelog line by line, accumulating top-level `- ` bullets.
// Continuation lines are indented or blank; a non-indented line that is
// not a bullet or heading (intro prose, the link-reference definitions
// at the bottom) terminates the open ent without joining it.
@ __changelog_entries String src ( Vec String ) terms String rel_lc String out i limit ( Vec i ) ctr → v {
    : ( Vec String ) lines ( string_split src `\n` )
    : i nl ( vec_len [String] lines )
    : ~ String cur_rel ( string_from `` )
    : ~ String cur_rel_lc ( string_from `` )
    : ~ String cur_cat ( string_from `` )
    : String ent ( string_new )
    : ~ i li 0
    ~ < li nl {
        ?? ( vec_get [String] lines li ) {
            T line → {
                : i ln ( string_len line )
                ? ( string_starts_with line `## ` ) {
                    ( __cl_flush ent cur_rel cur_rel_lc cur_cat terms rel_lc out limit ctr )
                    ( string_free cur_rel ) = cur_rel ( string_substr line 3 - ln 3 )
                    ( string_free cur_rel_lc ) = cur_rel_lc ( string_to_lower cur_rel )
                    ( string_free cur_cat ) = cur_cat ( string_from `` )
                } {
                    ? ( string_starts_with line `### ` ) {
                        ( __cl_flush ent cur_rel cur_rel_lc cur_cat terms rel_lc out limit ctr )
                        ( string_free cur_cat ) = cur_cat ( string_substr line 4 - ln 4 )
                    } {
                        // Both bullet styles appear in the file: `- ` in the
                        // 0.9.1+ sections, `* ` in the older ones.
                        ? | ( string_starts_with line `- ` ) ( string_starts_with line `* ` ) {
                            ( __cl_flush ent cur_rel cur_rel_lc cur_cat terms rel_lc out limit ctr )
                            ( string_push_str ent ( string_data line ) )
                            ( string_push_char ent 10 )
                        } {
                            : ~ b is_cont F
                            ? == ln 0 { = is_cont T } {
                                : i c0 ( string_get line 0 )
                                ? | == c0 32 == c0 9 { = is_cont T } {}
                            }
                            ? is_cont {
                                ? > ( string_len ent ) 0 {
                                    ( string_push_str ent ( string_data line ) )
                                    ( string_push_char ent 10 )
                                } {}
                            } {
                                ( __cl_flush ent cur_rel cur_rel_lc cur_cat terms rel_lc out limit ctr )
                            }
                        }
                    }
                }
            }
            F _ → {}
        }
        = li + li 1
    }
    ( __cl_flush ent cur_rel cur_rel_lc cur_cat terms rel_lc out limit ctr )
    ( string_free cur_rel ) ( string_free cur_rel_lc ) ( string_free cur_cat ) ( string_free ent )
    ( vec_free_with [String] lines \ String l → v { ( string_free l ) } )
}

@ __cl_idx_line String idx String rel i count → v {
    ( string_push_str idx ( string_data rel ) )
    ( string_push_str idx ` — ` )
    ( string_push_int idx count )
    ( string_push_str idx ` entries\n` )
}

// Index mode (no query, no release): release headings + entry counts.
@ __changelog_index_result String src → Json {
    : ( Vec String ) lines ( string_split src `\n` )
    : i nl ( vec_len [String] lines )
    : String idx ( string_with_cap 1024 )
    : ~ String cur_rel ( string_from `` )
    : ~ i cur_count 0
    : ~ i total 0
    : ~ i releases 0
    : ~ i li 0
    ~ < li nl {
        ?? ( vec_get [String] lines li ) {
            T line → {
                : i ln ( string_len line )
                ? ( string_starts_with line `## ` ) {
                    ? > ( string_len cur_rel ) 0 { ( __cl_idx_line idx cur_rel cur_count ) } {}
                    ( string_free cur_rel ) = cur_rel ( string_substr line 3 - ln 3 )
                    = cur_count 0
                    = releases + releases 1
                } {
                    ? | ( string_starts_with line `- ` ) ( string_starts_with line `* ` ) {
                        = cur_count + cur_count 1
                        = total + total 1
                    } {}
                }
            }
            F _ → {}
        }
        = li + li 1
    }
    ? > ( string_len cur_rel ) 0 { ( __cl_idx_line idx cur_rel cur_count ) } {}
    ( string_free cur_rel )
    ( vec_free_with [String] lines \ String l → v { ( string_free l ) } )

    : String hdr ( string_with_cap + ( string_len idx ) 256 )
    ( string_push_str hdr `CHANGELOG.md — ` )
    ( string_push_int hdr releases )
    ( string_push_str hdr ` releases, ` )
    ( string_push_int hdr total )
    ( string_push_str hdr ` entries. Call again with 'query' (space-separated terms, ALL must match, case-insensitive) and/or 'release' (e.g. 0.9.6 or Unreleased) to fetch full entries; 'limit' defaults to 10.\n\n` )
    ( string_push_str hdr ( string_data idx ) )
    : Json result ( __mcp_result_text ( string_data hdr ) )
    ( string_free hdr ) ( string_free idx )
    ^ result
}

@ __mcp_tool_changelog Json args → Json {
    : s query ( __mcp_args_get `query` args `` )
    : s release ( __mcp_args_get `release` args `` )
    : ~ i limit ( __mcp_args_get_int `limit` args 10 )
    ? < limit 1 { = limit 1 } {}
    ? > limit 50 { = limit 50 } {}

    : String fp ( get_changelog_path )
    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
    ( string_free fp )
    ?? rd {
        T bytes → {
            : String src ( bytes_to_str bytes )
            ( vec_free [u] bytes )
            ? & == ( nurl_str_len query ) 0 == ( nurl_str_len release ) 0 {
                : Json r ( __changelog_index_result src )
                ( string_free src )
                ^ r
            } {}

            : String q_lc ( __lc_owned query )
            : ( Vec String ) terms ( string_split q_lc ` ` )
            : String rel_lc ( __lc_owned release )
            : String out ( string_with_cap 4096 )
            : ( Vec i ) ctr ( vec_new [i] )
            ( vec_push [i] ctr 0 ) ( vec_push [i] ctr 0 ) ( vec_push [i] ctr 0 )
            ( __changelog_entries src terms rel_lc out limit ctr )
            : i total ?? ( vec_get [i] ctr 0 ) { T v → v F _ → 0 }
            : i matched ?? ( vec_get [i] ctr 1 ) { T v → v F _ → 0 }
            : i emitted ?? ( vec_get [i] ctr 2 ) { T v → v F _ → 0 }

            : String hdr ( string_with_cap + ( string_len out ) 256 )
            ( string_push_int hdr matched )
            ( string_push_str hdr ` of ` )
            ( string_push_int hdr total )
            ( string_push_str hdr ` changelog entries match` )
            ? > ( nurl_str_len query ) 0 {
                ( string_push_str hdr ` query '` )
                ( string_push_str hdr query )
                ( string_push_str hdr `'` )
            } {}
            ? > ( nurl_str_len release ) 0 {
                ( string_push_str hdr ` in release '` )
                ( string_push_str hdr release )
                ( string_push_str hdr `'` )
            } {}
            ( string_push_str hdr `.\n\n` )
            ( string_push_str hdr ( string_data out ) )
            ? == matched 0 {
                ( string_push_str hdr `No matches — terms are AND-ed substrings; try fewer or shorter terms, or call without arguments for the release index.\n` )
            } {}
            ? > matched emitted {
                ( string_push_str hdr `… ` )
                ( string_push_int hdr - matched emitted )
                ( string_push_str hdr ` more matching entries omitted (limit/byte cap) — narrow the query, filter by release, or raise 'limit'.\n` )
            } {}
            : Json result ( __mcp_result_text ( string_data hdr ) )
            ( string_free hdr ) ( string_free out ) ( string_free rel_lc )
            ( vec_free_with [String] terms \ String t → v { ( string_free t ) } )
            ( string_free q_lc ) ( vec_free [i] ctr ) ( string_free src )
            ^ result
        }
        F _ → { ^ ( __mcp_result_error `CHANGELOG.md not found` ) }
    }
}

@ __mcp_schema_changelog → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( json_obj_set props `query`
    ( __mcp_prop `string` `Space-separated search terms; an entry matches only if EVERY term occurs in it (case-insensitive substring). Omit together with 'release' to get the release index.` ) )
    ( json_obj_set props `release`
    ( __mcp_prop `string` `Restrict to one release, e.g. '0.9.6' or 'Unreleased' (substring match on the release heading).` ) )
    ( json_obj_set props `limit`
    ( __mcp_prop `integer` `Maximum entries to return (default 10, max 50). Output is also byte-capped at 32 KB.` ) )
    ( json_obj_set schema `properties` props )
    ^ schema
}

// ── Tool dispatch by name ──────────────────────────────────────────

@ __mcp_dispatch_tool s name Json args → Json {
    // Build tools — five compilation targets.
    ? != 0 ( nurl_str_eq name `nurl_build_native` ) {
        ^ ( __mcp_tool_build_source_filename `/build` args )
    } {}
    ? != 0 ( nurl_str_eq name `nurl_build_wasm` ) {
        ^ ( __mcp_tool_build_source_filename `/build_wasm` args )
    } {}
    ? != 0 ( nurl_str_eq name `nurl_build_windows` ) {
        ^ ( __mcp_tool_build_source_filename `/build_windows` args )
    } {}
    ? != 0 ( nurl_str_eq name `nurl_build_macos` ) {
        ^ ( __mcp_tool_build_source_filename `/build_macos` args )
    } {}
    ? != 0 ( nurl_str_eq name `nurl_build_target` ) {
        ^ ( __mcp_tool_build_target_impl args )
    } {}

    // Browse — three catalogues.
    ? != 0 ( nurl_str_eq name `nurl_list_examples` ) {
        : String dir ( get_examples_dir )
        : Json result ( __mcp_list_files_result ( string_data dir ) )
        ( string_free dir )
        ^ result
    } {}
    ? != 0 ( nurl_str_eq name `nurl_list_stdlib` ) {
        : String dir ( get_stdlib_dir )
        : Json result ( __mcp_list_files_result ( string_data dir ) )
        ( string_free dir )
        ^ result
    } {}
    ? != 0 ( nurl_str_eq name `nurl_list_tests` ) {
        : String dir ( get_tests_dir )
        : Json result ( __mcp_list_files_result ( string_data dir ) )
        ( string_free dir )
        ^ result
    } {}

    // Read per-catalogue. Refuses `..` segments to stop directory
    // traversal — same defensive shape h_static* uses.
    ? != 0 ( nurl_str_eq name `nurl_read_example` ) {
        : s rel ( __mcp_args_get `name` args `` )
        ? | == ( nurl_str_len rel ) 0 ( __has_dotdot_segment rel ) {
            ^ ( __mcp_result_error `bad or missing 'name'` )
        } {}
        : String dir ( get_examples_dir )
        : String fp ( path_join ( string_data dir ) rel )
        : Json result ( __mcp_read_file_result ( string_data fp ) )
        ( string_free dir ) ( string_free fp )
        ^ result
    } {}
    ? != 0 ( nurl_str_eq name `nurl_read_stdlib` ) {
        : s rel ( __mcp_args_get `name` args `` )
        ? | == ( nurl_str_len rel ) 0 ( __has_dotdot_segment rel ) {
            ^ ( __mcp_result_error `bad or missing 'name'` )
        } {}
        : String dir ( get_stdlib_dir )
        : String fp ( path_join ( string_data dir ) rel )
        : Json result ( __mcp_read_file_result ( string_data fp ) )
        ( string_free dir ) ( string_free fp )
        ^ result
    } {}
    ? != 0 ( nurl_str_eq name `nurl_read_test` ) {
        : s rel ( __mcp_args_get `name` args `` )
        ? | == ( nurl_str_len rel ) 0 ( __has_dotdot_segment rel ) {
            ^ ( __mcp_result_error `bad or missing 'name'` )
        } {}
        : String dir ( get_tests_dir )
        : String fp ( path_join ( string_data dir ) rel )
        : Json result ( __mcp_read_file_result ( string_data fp ) )
        ( string_free dir ) ( string_free fp )
        ^ result
    } {}

    // Single-file reads — 4 doc files.
    ? != 0 ( nurl_str_eq name `nurl_read_grammar` ) {
        : String fp ( get_grammar_path )
        : Json result ( __mcp_read_file_result ( string_data fp ) )
        ( string_free fp ) ^ result
    } {}
    ? != 0 ( nurl_str_eq name `nurl_read_readme` ) {
        : String fp ( get_readme_path )
        : Json result ( __mcp_read_file_result ( string_data fp ) )
        ( string_free fp ) ^ result
    } {}
    ? != 0 ( nurl_str_eq name `nurl_read_roadmap` ) {
        : String fp ( get_roadmap_path )
        : Json result ( __mcp_read_file_result ( string_data fp ) )
        ( string_free fp ) ^ result
    } {}
    ? != 0 ( nurl_str_eq name `nurl_read_gotchas` ) {
        : String fp ( get_gotchas_path )
        : Json result ( __mcp_read_file_result ( string_data fp ) )
        ( string_free fp ) ^ result
    } {}

    // Targeted changelog retrieval.
    ? != 0 ( nurl_str_eq name `nurl_changelog` ) {
        ^ ( __mcp_tool_changelog args )
    } {}

    ^ ( __mcp_result_error `unknown tool` )
}

// ── tools/list response ─────────────────────────────────────────────

@ __mcp_tool_desc s name s desc Json schema → Json {
    ^ ( mcp_tool_descriptor name desc schema )
}

@ __mcp_build_tools_list → Json {
    : Json arr ( json_arr_new )

    // Build tools.
    ( json_arr_push arr ( __mcp_tool_desc `nurl_build_native`
    `Compile NURL source to a native x86_64 Linux ELF binary. Returns build status, nurlc+clang return codes, combined stderr, download URLs for the generated .ll and the binary. Equivalent to POST /build.`
    ( __mcp_schema_source_filename ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_build_wasm`
    `Compile NURL source to a wasm32-wasi WebAssembly module. Returns base64-encoded wasm bytes, compile logs, download URL. Runs in-browser via a WASI shim or with wasmtime. Equivalent to POST /build_wasm.`
    ( __mcp_schema_source_filename ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_build_windows`
    `Cross-compile NURL source to a Windows x86_64 .exe via mingw-w64 (clang -c → x86_64-w64-mingw32-gcc link). Static libcurl + Schannel TLS when the runtime is libcurl-enabled. Returns build status, return codes, combined stderr, download URL. Equivalent to POST /build_windows.`
    ( __mcp_schema_source_filename ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_build_macos`
    `Cross-compile NURL source to a macOS x86_64 Mach-O binary via zig cc. Unsigned — clear quarantine attribute before running. Equivalent to POST /build_macos.`
    ( __mcp_schema_source_filename ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_build_target`
    `Cross-compile NURL source to one of several extra targets via zig cc. target selects which: *-musl static ELFs (x86_64/ARM64/RISC-V 64 Linux), linux-arm64-gnu dynamic glibc ELF, macos-x64/macos-arm64 unsigned Mach-O. Equivalent to POST /build_target.`
    ( __mcp_schema_build_target ) ) )

    // Browse.
    ( json_arr_push arr ( __mcp_tool_desc `nurl_list_examples`
    `List bundled NURL example programs. Returns a JSON array of {name, path, bytes} entries, sorted alphabetically.`
    ( __mcp_schema_empty ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_list_stdlib`
    `List bundled NURL stdlib modules. Returns a JSON array of {name, path, bytes} entries (recursive — core/, std/, ext/), sorted alphabetically.`
    ( __mcp_schema_empty ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_list_tests`
    `List bundled compiler tests. Returns a JSON array of {name, path, bytes} entries, sorted alphabetically.`
    ( __mcp_schema_empty ) ) )

    // Read per-catalogue.
    ( json_arr_push arr ( __mcp_tool_desc `nurl_read_example`
    `Return the source of a bundled example. name is the relative path returned by nurl_list_examples.`
    ( __mcp_schema_name ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_read_stdlib`
    `Return the source of a stdlib module. name is the relative path returned by nurl_list_stdlib (e.g. core/string.nu).`
    ( __mcp_schema_name ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_read_test`
    `Return the source of a bundled compiler test. name is the relative path returned by nurl_list_tests.`
    ( __mcp_schema_name ) ) )

    // Read docs.
    ( json_arr_push arr ( __mcp_tool_desc `nurl_read_grammar`
    `Return the current NURL grammar EBNF (spec/grammar.ebnf).`
    ( __mcp_schema_empty ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_read_readme`
    `Return README.md verbatim — project overview, syntax cheat sheet, build instructions.`
    ( __mcp_schema_empty ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_read_roadmap`
    `Return ROADMAP.md verbatim — current development plan + ship log.`
    ( __mcp_schema_empty ) ) )
    ( json_arr_push arr ( __mcp_tool_desc `nurl_read_gotchas`
    `Return docs/GOTCHAS.md verbatim — known compiler quirks with workarounds.`
    ( __mcp_schema_empty ) ) )

    // Changelog.
    ( json_arr_push arr ( __mcp_tool_desc `nurl_changelog`
    `Targeted CHANGELOG.md retrieval — the changelog is large (240+ KB) and growing, so never fetch it whole. Call with NO arguments first to get a compact index (releases + entry counts). Then pass query (space-separated terms, ALL must occur, case-insensitive) and/or release (e.g. 0.9.6 or Unreleased) to get complete changelog entries, each prefixed with its '[release] — date › category' provenance, newest first. Use this to find out when/whether a feature, fix, or rename happened. Results respect limit (default 10) and a 32 KB byte cap; a trailing note reports omitted match counts.`
    ( __mcp_schema_changelog ) ) )

    : Json out ( json_obj_new )
    ( json_obj_set out `tools` arr )
    ^ out
}

// ── Resources (nurl:// URIs mirroring the read-tools) ──────────────

@ __mcp_resource_desc s uri s name s desc s mime → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `uri` ( json_str_lit uri ) )
    ( json_obj_set o `name` ( json_str_lit name ) )
    ( json_obj_set o `description` ( json_str_lit desc ) )
    ( json_obj_set o `mimeType` ( json_str_lit mime ) )
    ^ o
}

@ __mcp_build_resources_list → Json {
    : Json arr ( json_arr_new )
    ( json_arr_push arr ( __mcp_resource_desc `nurl://readme` `README` `Project overview + syntax cheat sheet.` `text/markdown` ) )
    ( json_arr_push arr ( __mcp_resource_desc `nurl://roadmap` `ROADMAP` `Current development plan + ship log.` `text/markdown` ) )
    ( json_arr_push arr ( __mcp_resource_desc `nurl://gotchas` `GOTCHAS` `Known compiler quirks + workarounds.` `text/markdown` ) )
    ( json_arr_push arr ( __mcp_resource_desc `nurl://grammar` `Grammar` `Current NURL grammar (EBNF).` `text/plain` ) )
    ( json_arr_push arr ( __mcp_resource_desc `nurl://stdlib` `Stdlib` `JSON listing of every stdlib module.` `application/json` ) )
    ( json_arr_push arr ( __mcp_resource_desc `nurl://examples` `Examples` `JSON listing of every bundled example.` `application/json` ) )
    ( json_arr_push arr ( __mcp_resource_desc `nurl://tests` `Tests` `JSON listing of every compiler test.` `application/json` ) )
    : Json out ( json_obj_new )
    ( json_obj_set out `resources` arr )
    ^ out
}

@ __mcp_resource_text_node s uri s mime s text → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `uri` ( json_str_lit uri ) )
    ( json_obj_set o `mimeType` ( json_str_lit mime ) )
    ( json_obj_set o `text` ( json_str_lit text ) )
    ^ o
}

@ __mcp_resource_read_for s uri → Json {
    : Json arr ( json_arr_new )
    ? != 0 ( nurl_str_eq uri `nurl://readme` ) {
        : String fp ( get_readme_path )
        : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
        ?? rd {
            T body → {
                : String s_body ( bytes_to_str body )
                ( json_arr_push arr ( __mcp_resource_text_node uri `text/markdown` ( string_data s_body ) ) )
                ( vec_free [u] body ) ( string_free s_body )
            }
            F _ → {}
        }
        ( string_free fp )
    } {
        ? != 0 ( nurl_str_eq uri `nurl://roadmap` ) {
            : String fp ( get_roadmap_path )
            : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
            ?? rd { T body → {
                    : String s_body ( bytes_to_str body )
                    ( json_arr_push arr ( __mcp_resource_text_node uri `text/markdown` ( string_data s_body ) ) )
                    ( vec_free [u] body ) ( string_free s_body )
                } F _ → {} }
            ( string_free fp )
        } {
            ? != 0 ( nurl_str_eq uri `nurl://gotchas` ) {
                : String fp ( get_gotchas_path )
                : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
                ?? rd { T body → {
                        : String s_body ( bytes_to_str body )
                        ( json_arr_push arr ( __mcp_resource_text_node uri `text/markdown` ( string_data s_body ) ) )
                        ( vec_free [u] body ) ( string_free s_body )
                    } F _ → {} }
                ( string_free fp )
            } {
                ? != 0 ( nurl_str_eq uri `nurl://grammar` ) {
                    : String fp ( get_grammar_path )
                    : !( Vec u ) IoErr rd ( read_file_bytes ( string_data fp ) )
                    ?? rd { T body → {
                            : String s_body ( bytes_to_str body )
                            ( json_arr_push arr ( __mcp_resource_text_node uri `text/plain` ( string_data s_body ) ) )
                            ( vec_free [u] body ) ( string_free s_body )
                        } F _ → {} }
                    ( string_free fp )
                } {
                    ? != 0 ( nurl_str_eq uri `nurl://stdlib` ) {
                        : String dir ( get_stdlib_dir )
                        : Json listing ( json_arr_new )
                        ( __walk_nu_files listing ( string_data dir ) `` )
                        : String body ( json_stringify listing )
                        ( json_arr_push arr ( __mcp_resource_text_node uri `application/json` ( string_data body ) ) )
                        ( json_free listing ) ( string_free body ) ( string_free dir )
                    } {
                        ? != 0 ( nurl_str_eq uri `nurl://examples` ) {
                            : String dir ( get_examples_dir )
                            : Json listing ( json_arr_new )
                            ( __walk_nu_files listing ( string_data dir ) `` )
                            : String body ( json_stringify listing )
                            ( json_arr_push arr ( __mcp_resource_text_node uri `application/json` ( string_data body ) ) )
                            ( json_free listing ) ( string_free body ) ( string_free dir )
                        } {
                            ? != 0 ( nurl_str_eq uri `nurl://tests` ) {
                                : String dir ( get_tests_dir )
                                : Json listing ( json_arr_new )
                                ( __walk_nu_files listing ( string_data dir ) `` )
                                : String body ( json_stringify listing )
                                ( json_arr_push arr ( __mcp_resource_text_node uri `application/json` ( string_data body ) ) )
                                ( json_free listing ) ( string_free body ) ( string_free dir )
                            } {} } } } } } }
    : Json out ( json_obj_new )
    ( json_obj_set out `contents` arr )
    ^ out
}

// ── Prompts ────────────────────────────────────────────────────────

@ __mcp_build_prompts_list → Json {
    : Json arr ( json_arr_new )
    : Json p ( json_obj_new )
    ( json_obj_set p `name` ( json_str_lit `nurl_coding_assistant` ) )
    ( json_obj_set p `description` ( json_str_lit `Compact NURL grammar + canonical-example primer so small models ground themselves before writing or reviewing NURL code.` ) )
    ( json_obj_set p `arguments` ( json_arr_new ) )
    ( json_arr_push arr p )
    : Json out ( json_obj_new )
    ( json_obj_set out `prompts` arr )
    ^ out
}

@ __mcp_prompts_get_for s name → Json {
    ? != 0 ( nurl_str_eq name `nurl_coding_assistant` ) {
        : Json content ( json_obj_new )
        ( json_obj_set content `type` ( json_str_lit `text` ) )
        ( json_obj_set content `text` ( json_str_lit `You are about to read or write NURL source. NURL uses prefix notation: every operator comes before its arguments and arity is fixed. Calls require parentheses: ( fn arg1 arg2 ). Single-letter type keywords (i u f b s v), no semicolons. Functions: @ name params → ret { body }. Bindings: : type name expr (immutable) or : ~ type name expr (mutable). Pattern match: ?? expr { Variant payload → body ... }. Read README and GOTCHAS first via the tools — every common pitfall has a documented diagnostic. When writing code, ALWAYS check examples for the closest shape before guessing syntax.` ) )

        : Json msg ( json_obj_new )
        ( json_obj_set msg `role` ( json_str_lit `user` ) )
        ( json_obj_set msg `content` content )

        : Json msgs ( json_arr_new )
        ( json_arr_push msgs msg )

        : Json out ( json_obj_new )
        ( json_obj_set out `description` ( json_str_lit `NURL coding primer` ) )
        ( json_obj_set out `messages` msgs )
        ^ out
    } {}
    // Unknown name — return an empty result (caller wraps in error envelope).
    : Json out ( json_obj_new )
    ( json_obj_set out `description` ( json_str_lit `unknown prompt` ) )
    ( json_obj_set out `messages` ( json_arr_new ) )
    ^ out
}

// ── Top-level dispatch ─────────────────────────────────────────────

// Pull `id` Json off the request — JNull when absent (notification).
@ __mcp_get_id Json req → Json {
    : ?Json o ( json_obj_get req `id` )
    ?? o {
        T j → { ^ ( json_clone j ) }
        F _ → { ^ ( json_null ) }
    }
}

// NURL backtick strings cannot embed a literal backtick, so the
// instructions blurb is assembled at runtime from segments interleaved
// with explicit backtick bytes.
@ __mcp_instructions_text → String {
    : String s ( string_with_cap 800 )
    : i bt 96
    ( string_push_str s `NURL language toolchain. Use ` )
    ( string_push_char s bt ) ( string_push_str s `nurl_build_native` ) ( string_push_char s bt )
    ( string_push_str s ` (Linux x86_64 ELF), ` )
    ( string_push_char s bt ) ( string_push_str s `nurl_build_windows` ) ( string_push_char s bt )
    ( string_push_str s ` (Windows .exe via mingw-w64), ` )
    ( string_push_char s bt ) ( string_push_str s `nurl_build_macos` ) ( string_push_char s bt )
    ( string_push_str s ` (macOS x86_64 Mach-O), ` )
    ( string_push_char s bt ) ( string_push_str s `nurl_build_target` ) ( string_push_char s bt )
    ( string_push_str s ` (cross-compile to RISC-V / ARM64 Linux or ARM64 macOS), or ` )
    ( string_push_char s bt ) ( string_push_str s `nurl_build_wasm` ) ( string_push_char s bt )
    ( string_push_str s ` to compile source. The language uses a terse prefix notation: functions are declared with ` )
    ( string_push_char s bt ) ( string_push_str s `@ name → ret_ty { body }` ) ( string_push_char s bt )
    ( string_push_str s `, return via ` )
    ( string_push_char s bt ) ( string_push_str s `^ expr` ) ( string_push_char s bt )
    ( string_push_str s `, and call functions with parenthesised prefix form like ` )
    ( string_push_char s bt ) ( string_push_str s `( puts ` )
    ( string_push_char s bt ) ( string_push_str s `hello` ) ( string_push_char s bt )
    ( string_push_str s ` )` ) ( string_push_char s bt )
    ( string_push_str s `. Read ` )
    ( string_push_char s bt ) ( string_push_str s `nurl://grammar` ) ( string_push_char s bt )
    ( string_push_str s ` and ` )
    ( string_push_char s bt ) ( string_push_str s `nurl://readme` ) ( string_push_char s bt )
    ( string_push_str s ` for the full spec; fetch working examples via ` )
    ( string_push_char s bt ) ( string_push_str s `nurl_read_example` ) ( string_push_char s bt )
    ( string_push_str s `.` )
    ^ s
}

// Initialize result with tools + resources + prompts capabilities.
//
// Pinned to MCP revision `2025-03-26` (FastMCP's default) for parity
// with the Python reference server — most MCP clients negotiate that
// version. The capability sub-fields advertise the FastMCP shape so
// clients that key off `listChanged`/`subscribe` see the expected
// surface even though we don't push change notifications today.
@ __mcp_initialize → Json {
    : Json experimental_cap ( json_obj_new )
    : Json tools_cap ( json_obj_new )
    ( json_obj_set tools_cap `listChanged` ( json_bool F ) )
    : Json resources_cap ( json_obj_new )
    ( json_obj_set resources_cap `subscribe` ( json_bool F ) )
    ( json_obj_set resources_cap `listChanged` ( json_bool F ) )
    : Json prompts_cap ( json_obj_new )
    ( json_obj_set prompts_cap `listChanged` ( json_bool F ) )

    : Json caps ( json_obj_new )
    ( json_obj_set caps `experimental` experimental_cap )
    ( json_obj_set caps `prompts` prompts_cap )
    ( json_obj_set caps `resources` resources_cap )
    ( json_obj_set caps `tools` tools_cap )

    : Json info ( json_obj_new )
    : String name ( get_mcp_server_name )
    : String version ( get_mcp_server_version )
    ( json_obj_set info `name` ( json_str_lit ( string_data name ) ) )
    ( json_obj_set info `version` ( json_str_lit ( string_data version ) ) )
    ( string_free name ) ( string_free version )

    : String instructions ( __mcp_instructions_text )

    : Json out ( json_obj_new )
    ( json_obj_set out `protocolVersion` ( json_str_lit `2025-03-26` ) )
    ( json_obj_set out `capabilities` caps )
    ( json_obj_set out `serverInfo` info )
    ( json_obj_set out `instructions` ( json_str_lit ( string_data instructions ) ) )
    ( string_free instructions )
    ^ out
}

// `dispatch` per mcp_http_handler contract: takes a single parsed
// JSON-RPC request (borrowed), returns Some(reply) for a request or
// None for a notification.
@ mcp_dispatch Json req → ?Json {
    : ?Json mo ( json_obj_get req `method` )
    : s method ?? mo {
        T j → ?? j { JStr s → ( string_data s ) _ → `` }
        F _ → ``
    }
    : Json id ( __mcp_get_id req )
    : ?Json id_opt ( json_obj_get req `id` )
    : b is_notification ?? id_opt { T _ → F F _ → T }

    // Notifications: never reply, regardless of method.
    ? is_notification {
        ( json_free id )
        ^ @ ?Json { F }
    } {}

    // Method routing.
    ? != 0 ( nurl_str_eq method `initialize` ) {
        : Json result ( __mcp_initialize )
        : Json env ( mcp_response_result id result )
        ( json_free id )
        ^ @ ?Json { T env }
    } {}
    ? != 0 ( nurl_str_eq method `ping` ) {
        : Json env ( mcp_response_result id ( json_obj_new ) )
        ( json_free id )
        ^ @ ?Json { T env }
    } {}
    ? != 0 ( nurl_str_eq method `tools/list` ) {
        : Json env ( mcp_response_result id ( __mcp_build_tools_list ) )
        ( json_free id )
        ^ @ ?Json { T env }
    } {}
    ? != 0 ( nurl_str_eq method `tools/call` ) {
        : ?Json po ( json_obj_get req `params` )
        ?? po {
            T params → {
                : s tname ( __mcp_args_get `name` params `` )
                : ?Json ao ( json_obj_get params `arguments` )
                : Json args ?? ao { T j → ( json_clone j ) F _ → ( json_obj_new ) }
                : Json result ( __mcp_dispatch_tool tname args )
                : Json env ( mcp_response_result id result )
                ( json_free args ) ( json_free id )
                ^ @ ?Json { T env }
            }
            F _ → {
                : Json env ( mcp_response_error id mcp_err_invalid_params `tools/call requires params` )
                ( json_free id )
                ^ @ ?Json { T env }
            }
        }
    } {}
    ? != 0 ( nurl_str_eq method `resources/list` ) {
        : Json env ( mcp_response_result id ( __mcp_build_resources_list ) )
        ( json_free id )
        ^ @ ?Json { T env }
    } {}
    ? != 0 ( nurl_str_eq method `resources/read` ) {
        : ?Json po ( json_obj_get req `params` )
        ?? po {
            T params → {
                : s uri ( __mcp_args_get `uri` params `` )
                : Json result ( __mcp_resource_read_for uri )
                : Json env ( mcp_response_result id result )
                ( json_free id )
                ^ @ ?Json { T env }
            }
            F _ → {
                : Json env ( mcp_response_error id mcp_err_invalid_params `resources/read requires params.uri` )
                ( json_free id )
                ^ @ ?Json { T env }
            }
        }
    } {}
    ? != 0 ( nurl_str_eq method `prompts/list` ) {
        : Json env ( mcp_response_result id ( __mcp_build_prompts_list ) )
        ( json_free id )
        ^ @ ?Json { T env }
    } {}
    ? != 0 ( nurl_str_eq method `prompts/get` ) {
        : ?Json po ( json_obj_get req `params` )
        ?? po {
            T params → {
                : s pname ( __mcp_args_get `name` params `` )
                : Json env ( mcp_response_result id ( __mcp_prompts_get_for pname ) )
                ( json_free id )
                ^ @ ?Json { T env }
            }
            F _ → {
                : Json env ( mcp_response_error id mcp_err_invalid_params `prompts/get requires params.name` )
                ( json_free id )
                ^ @ ?Json { T env }
            }
        }
    } {}

    // Unknown method.
    : Json env ( mcp_response_error id mcp_err_method_not_found `method not found` )
    ( json_free id )
    ^ @ ?Json { T env }
}

// ── /mcp handler with session generation on first request ──────────
//
// Wraps `mcp_http_handler mcp_dispatch` with a layer that sets
// `Mcp-Session-Id: <random>` on the response whenever the client
// didn't send one. The base handler echoes back any sid the client
// did send — together that gives us:
//
//   - first request (no sid) → server picks one, returns it
//   - subsequent requests (with sid) → echoed verbatim
//   - container restart → client's sid still accepted (no whitelist)
//
// 64-bit hex sid = 16 chars; ample collision-resistance for an
// MCP session pool.

@ mcp_http_with_session ( @ HttpResponse HttpRequest ) base → ( @ HttpResponse HttpRequest ) {
    ^ \ HttpRequest req → HttpResponse {
        : HttpResponse resp ( base req )
        : ?String had_sid ( header_get . req headers `Mcp-Session-Id` )
        ?? had_sid {
            T s → ( string_free s )
            F _ → {
                : String sid ( rand_hex_str 16 )
                ( response_set_header resp `Mcp-Session-Id` ( string_data sid ) )
                ( string_free sid )
            }
        }
        ^ resp
    }
}

// Router-compatible (HttpRequest, Params) entry point.
@ h_mcp HttpRequest req Params params → HttpResponse {
    ( nurl_print `[srv] ` )
    ( nurl_print ( string_data . req method ) )
    ( nurl_print ` /mcp\n` )
    : ( @ ?Json Json ) disp \ Json r → ?Json { ^ ( mcp_dispatch r ) }
    : ( @ HttpResponse HttpRequest ) base ( mcp_http_handler disp )
    : ( @ HttpResponse HttpRequest ) wrapped ( mcp_http_with_session base )
    : HttpResponse out ( wrapped req )
    // These three closures are built per request and die here. A closure
    // is a by-value { fn_ptr, env_ptr } pair whose env is a heap
    // allocation with no auto-drop — release the envs explicitly
    // (std/panic.nu recover's convention; nurl_free is NULL-safe for the
    // capture-less `disp`). Without this every /mcp request leaked the
    // two capturing envs.
    ( nurl_free # s # *u wrapped 1 )
    ( nurl_free # s # *u base 1 )
    ( nurl_free # s # *u disp 1 )
    ^ out
}

// ── Compile-concurrency gate ──────────────────────────────────────────
//
// The worker pool (server_run_pool, NURL_WORKERS=16) lets up to 16
// requests run at once. A compile request spawns `clang -O2 -flto`, which
// can use hundreds of MB; 16 of those simultaneously can blow the
// container's memory cap and get the whole process OOM-killed (the
// "container is not listening" symptom). The accept pool stays wide so
// light requests (docs, examples, MCP tools/list, SSE) keep flowing, but
// the heavy COMPILE step is bounded by a counting semaphore. Default 4
// concurrent compiles; tune with NURL_COMPILE_SLOTS.
@ get_compile_slots → i {
    : String s ( env_var_or `NURL_COMPILE_SLOTS` `4` )
    : i n ?? ( int_parse ( string_data s ) ) { T v → v F _ → 4 }
    ( string_free s )
    ^ ? > n 0 n 1
}

// A request that triggers a compile: POST /build* (native/wasm/win/mac/
// target) or POST /mcp (the build_* MCP tools). GET /mcp is the light SSE
// drain and is deliberately NOT gated.
@ __is_compile_route HttpRequest req → b {
    : s m ( string_data . req method )
    ? == 0 ( nurl_str_eq m `POST` ) { ^ F } {}
    : s p ( string_data . req path )
    ? != 0 ( nurl_str_eq p `/mcp` ) { ^ T } {}
    : String ps ( string_from p )
    : b hit ( string_starts_with ps `/build` )
    ( string_free ps )
    ^ hit
}

// Dispatch a request, holding a compile permit across the handler for
// compile routes. The permit is released even if the handler panics
// (NURL `recover` would otherwise let the server-level recovery skip our
// release, leaking a permit and eventually deadlocking the gate). Kept a
// top-level fn — not a closure body — so the inner `recover` closure is
// not nested inside another closure.
@ __gated_handle Router r Semaphore gate HttpRequest req → HttpResponse {
    ? ( __is_compile_route req ) {
        ( sem_acquire gate )
        : ~ HttpResponse resp ( response_text 500 `internal error: handler panicked\n` )
        : !v PanicInfo pr ( recover \ → v { = resp ( router_handle r req ) } )
        ( sem_release gate )
        ?? pr { T _ → {} F p → { ( panic_info_free p ) } }
        ^ resp
    } {
        ^ ( router_handle r req )
    }
}

@ main → i {
    // Anchor the process at NURL_WORK_ROOT so that nurlc subprocesses inherit
    // a cwd from which `$ "stdlib/std/time.nu"`-style imports resolve. NURL's
    // `process_run` doesn't yet support per-child cwd override (MVP scope),
    // so we set it once for the whole server. Static-file handlers explicitly
    // use the absolute NURL_STATIC_DIR path to compensate.
    : String wr ( get_work_root )
    : !v IoErr cdr ( env_chdir ( string_data wr ) )
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

    : !TcpListener NetErr lr ( tcp_listen `0.0.0.0` 8000 )
    ?? lr {
        T listener → {
            : Router r ( router_new )
            ( router_post r `/build` \ HttpRequest req Params params → HttpResponse { ^ ( h_build req params ) } )
            ( router_post r `/build_wasm` \ HttpRequest req Params params → HttpResponse { ^ ( h_build_wasm req params ) } )
            ( router_post r `/build_windows` \ HttpRequest req Params params → HttpResponse { ^ ( h_build_windows req params ) } )
            ( router_post r `/build_macos` \ HttpRequest req Params params → HttpResponse { ^ ( h_build_macos req params ) } )
            ( router_post r `/build_target` \ HttpRequest req Params params → HttpResponse { ^ ( h_build_target req params ) } )
            ( router_get r `/download/:build_id/:filename` \ HttpRequest req Params params → HttpResponse { ^ ( h_download req params ) } )
            ( router_get r `/examples` \ HttpRequest req Params params → HttpResponse { ^ ( h_examples req params ) } )
            ( router_get r `/examples/*name` \ HttpRequest req Params params → HttpResponse { ^ ( h_get_example req params ) } )
            ( router_get r `/health` \ HttpRequest req Params params → HttpResponse { ^ ( h_health req params ) } )
            ( router_get r `/targets` \ HttpRequest req Params params → HttpResponse { ^ ( h_targets req params ) } )
            ( router_get r `/readme` \ HttpRequest req Params params → HttpResponse { ^ ( h_readme req params ) } )
            ( router_get r `/readme.md` \ HttpRequest req Params params → HttpResponse { ^ ( h_readme_md req params ) } )
            ( router_get r `/roadmap` \ HttpRequest req Params params → HttpResponse { ^ ( h_roadmap req params ) } )
            ( router_get r `/roadmap.md` \ HttpRequest req Params params → HttpResponse { ^ ( h_roadmap_md req params ) } )
            ( router_get r `/gotchas` \ HttpRequest req Params params → HttpResponse { ^ ( h_gotchas req params ) } )
            ( router_get r `/gotchas.md` \ HttpRequest req Params params → HttpResponse { ^ ( h_gotchas_md req params ) } )
            ( router_get r `/grammar` \ HttpRequest req Params params → HttpResponse { ^ ( h_grammar req params ) } )
            ( router_get r `/grammar.ebnf` \ HttpRequest req Params params → HttpResponse { ^ ( h_grammar_ebnf req params ) } )
            // Render repo docs by their natural path so relative links inside
            // README / docs resolve to a live rendered target (not a 404).
            ( router_get r `/docs/*path` \ HttpRequest req Params params → HttpResponse { ^ ( h_docs_file req params ) } )
            ( router_get r `/spec/*path` \ HttpRequest req Params params → HttpResponse { ^ ( h_spec_file req params ) } )
            ( router_get r `/bench/*path` \ HttpRequest req Params params → HttpResponse { ^ ( h_bench_file req params ) } )
            ( router_get r `/README.md` \ HttpRequest req Params params → HttpResponse { ^ ( __serve_repo_doc `README.md` ) } )
            ( router_get r `/ROADMAP.md` \ HttpRequest req Params params → HttpResponse { ^ ( __serve_repo_doc `ROADMAP.md` ) } )
            ( router_get r `/CHANGELOG.md` \ HttpRequest req Params params → HttpResponse { ^ ( __serve_repo_doc `CHANGELOG.md` ) } )
            ( router_get r `/CONTRIBUTING.md` \ HttpRequest req Params params → HttpResponse { ^ ( __serve_repo_doc `CONTRIBUTING.md` ) } )
            ( router_get r `/license` \ HttpRequest req Params params → HttpResponse { ^ ( h_license req params ) } )
            ( router_get r `/license/mit` \ HttpRequest req Params params → HttpResponse { ^ ( h_license_mit req params ) } )
            ( router_get r `/license/apache` \ HttpRequest req Params params → HttpResponse { ^ ( h_license_apache req params ) } )
            ( router_get r `/LICENSE-MIT` \ HttpRequest req Params params → HttpResponse { ^ ( h_license_mit_raw req params ) } )
            ( router_get r `/LICENSE-APACHE` \ HttpRequest req Params params → HttpResponse { ^ ( h_license_apache_raw req params ) } )
            ( router_get r `/NOTICE` \ HttpRequest req Params params → HttpResponse { ^ ( h_notice_raw req params ) } )
            ( router_get r `/stdlib-viewer` \ HttpRequest req Params params → HttpResponse { ^ ( h_stdlib_viewer req params ) } )
            ( router_get r `/stdlib-docs` \ HttpRequest req Params params → HttpResponse { ^ ( h_stdlib_docs_index req params ) } )
            ( router_get r `/stdlib-docs/*path` \ HttpRequest req Params params → HttpResponse { ^ ( h_stdlib_docs req params ) } )
            ( router_get r `/tests-viewer` \ HttpRequest req Params params → HttpResponse { ^ ( h_tests_viewer req params ) } )
            ( router_get r `/gameboydemo` \ HttpRequest req Params params → HttpResponse { ^ ( __serve_gameboydemo ) } )
            ( router_get r `/c64demo` \ HttpRequest req Params params → HttpResponse { ^ ( __serve_c64demo ) } )
            ( router_get r `/stdlib` \ HttpRequest req Params params → HttpResponse { ^ ( h_stdlib_list req params ) } )
            ( router_get r `/tests` \ HttpRequest req Params params → HttpResponse { ^ ( h_tests_list req params ) } )
            ( router_get r `/stdlib/*path` \ HttpRequest req Params params → HttpResponse { ^ ( h_stdlib_file req params ) } )
            ( router_get r `/tests/*path` \ HttpRequest req Params params → HttpResponse { ^ ( h_tests_file req params ) } )
            ( router_get r `/mcp-info` \ HttpRequest req Params params → HttpResponse { ^ ( h_mcp_info req params ) } )
            ( router_post r `/mcp` \ HttpRequest req Params params → HttpResponse { ^ ( h_mcp req params ) } )
            ( router_get r `/mcp` \ HttpRequest req Params params → HttpResponse { ^ ( h_mcp req params ) } )
            ( router_get r `/.well-known/oauth-protected-resource` \ HttpRequest req Params params → HttpResponse { ^ ( h_oauth_protected_resource req params ) } )
            ( router_get r `/.well-known/oauth-protected-resource/mcp` \ HttpRequest req Params params → HttpResponse { ^ ( h_oauth_protected_resource req params ) } )
            ( router_get r `/.well-known/oauth-authorization-server` \ HttpRequest req Params params → HttpResponse { ^ ( h_oauth_auth_server req params ) } )
            ( router_get r `/.well-known/openid-configuration` \ HttpRequest req Params params → HttpResponse { ^ ( h_oauth_auth_server req params ) } )
            ( router_post r `/register` \ HttpRequest req Params params → HttpResponse { ^ ( h_oauth_register req params ) } )
            ( router_get r `/authorize` \ HttpRequest req Params params → HttpResponse { ^ ( h_oauth_authorize req params ) } )
            ( router_post r `/token` \ HttpRequest req Params params → HttpResponse { ^ ( h_oauth_token req params ) } )
            ( router_get r `/openapi.json` \ HttpRequest req Params params → HttpResponse { ^ ( h_openapi_json req params ) } )
            ( router_get r `/docs` \ HttpRequest req Params params → HttpResponse { ^ ( h_docs_html req params ) } )
            ( router_any r `DELETE` `/mcp` \ HttpRequest req Params params → HttpResponse { ^ ( h_mcp req params ) } )
            ( router_get r `/favicon.ico` \ HttpRequest req Params params → HttpResponse { ^ ( h_favicon req params ) } )
            ( router_get r `/favicon.svg` \ HttpRequest req Params params → HttpResponse { ^ ( h_favicon req params ) } )
            ( router_get r `/static/*path` \ HttpRequest req Params params → HttpResponse { ^ ( h_static_prefixed req params ) } )
            ( router_get r `/` \ HttpRequest req Params params → HttpResponse { ^ ( h_static req params ) } )
            ( router_get r `/*path` \ HttpRequest req Params params → HttpResponse { ^ ( h_static req params ) } )

            // Compile-concurrency gate: bound how many `clang` compiles run
            // at once so a wide worker pool can't OOM the container.
            : i compile_slots ( get_compile_slots )
            : Semaphore compile_gate ( sem_new compile_slots )
            : ( @ HttpResponse HttpRequest ) base \ HttpRequest req → HttpResponse { ^ ( __gated_handle r compile_gate req ) }
            : ( @ HttpResponse HttpRequest ) logged ( with_access_log base )
            ( signal_install_shutdown listener )

            // Worker count is overridable so we can A/B test threading vs sequential.
            : String wkstr ( env_var_or `NURL_WORKERS` `16` )
            : i workers ?? ( int_parse ( string_data wkstr ) ) { T n → n F _ → 16 }
            ( string_free wkstr )

            ( nurl_print `[boot] registered routes: ` ) ( nurl_print ( nurl_str_int ( router_count r ) ) ) ( nurl_print `\n` )
            ( nurl_print `NURL API listening on http://0.0.0.0:8000/ (workers=` )
            ( nurl_print ( nurl_str_int workers ) )
            ( nurl_print `, compile_slots=` )
            ( nurl_print ( nurl_str_int compile_slots ) )
            ( nurl_print `, idle=5000ms)\n` )
            : HttpServer srv ( server_new_with_timeout listener logged 5000 )
            : !v NetErr rr ( server_run_pool srv workers )
            ( signal_clear_shutdown ) ( server_stop srv ) ( sem_free compile_gate ) ( router_free r )
            // The handler chain (`logged` wraps `base`) is dead once the
            // worker pool has returned — release the closure envs so a
            // clean shutdown reports zero leaks under LeakSanitizer.
            ( nurl_free # s # *u logged 1 )
            ( nurl_free # s # *u base 1 )
            ?? rr { T _ → { ^ 0 } F e → { ( nurl_eprint `[srv] runtime error: ` ) ( nurl_eprint ( net_err_name e ) ) ( nurl_eprint `\n` ) ^ 1 } }
        }
        F e → { ( nurl_eprint `[boot] could not bind 0.0.0.0:8000: ` ) ( nurl_eprint ( net_err_name e ) ) ( nurl_eprint `\n` ) ^ 1 }
    }
}
