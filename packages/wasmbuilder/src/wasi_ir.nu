// packages/wasmbuilder/src/wasi_ir.nu — LLVM-IR → wasm32-wasi rewriter.
//
// nurlc emits IR targeting the host (x86_64/arm64, 64-bit pointers, glibc
// FFI declares). This module retargets that IR for wasm32-wasi:
//
//   * renames `@main` → `@__main_argc_argv` (wasi-libc crt entry shape)
//   * prepends the wasm32 datalayout + `wasm32-unknown-wasi` triple
//   * shims libc calls whose NURL FFI declares i64 args/returns where the
//     wasm32 ABI uses i32 (malloc/strlen/memcpy/… — trunc/zext wrappers)
//   * stubs POSIX-only symbols wasi-libc doesn't ship (mmap/fork/pthread…)
//     so the stdlib's unconditional declares link; the stubs return error
//     sentinels and are unreachable behind `posix_const` runtime gates
//   * masks `@` inside `c"…"` string constants first so a program that
//     itself EMITS IR (nurlc.wasm!) doesn't get its data corrupted
//
// Extracted verbatim from nurlapi/main.nu (the /build_wasm handler), which
// is the production-proven pipeline behind play.nurl-lang.org — only the
// function names are prefixed (wb_/__wb_) for library use.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// The shimming below rewrites IR symbols with whole-string
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
@ __wb_ir_at_sentinel → s { ^ `__NURL_IR_AT_SENTINEL__` }

@ __wb_mask_ir_str_consts String ir → String {
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
                    : String m ( string_replace line `@` ( __wb_ir_at_sentinel ) )
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

@ wb_prepare_ir_for_wasi String ir → String {
    : ~ String res ( string_from ( string_data ir ) )

    // 0. Mask `@` inside string constants so the symbol rewrites below
    //    can't corrupt emitted-IR data (see note above). Restored at the
    //    end of the function.
    : String masked ( __wb_mask_ir_str_consts res )
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
    // NOTE: lseek is deliberately NOT shimmed. Its offset and return are
    // off_t, which is 64-bit on wasm32-wasi too — so NURL's i64 declaration
    // (posix.nu: `lseek i32 fd i offset i32 whence → i`) already matches
    // wasi-libc. Narrowing it here produced a signature mismatch and an
    // `unreachable` stub (breaking every fs.nu file-size probe on wasm).
    // Only libc functions whose wasm32 ABI genuinely uses a 32-bit long /
    // size_t where NURL emits i64 belong below (fseek's `long`, ftell, …).
    : s list `malloc:p:s,calloc:p:ss,realloc:p:ps,puts:i:p,putchar:i:i,getchar:i:,strlen:s:p,strcmp:i:pp,strncmp:i:pps,strcpy:p:pp,strncpy:p:pps,strcat:p:pp,strdup:p:p,memcpy:p:pps,memmove:p:pps,memset:p:pis,memcmp:i:pps,memchr:p:pis,memmem:p:psps,strchr:p:pi,strrchr:p:pi,atoi:i:p,abs:i:i,exit:v:i,rand:i:,srand:v:s,system:i:p,write:i:ips,read:i:ips,open:i:pii,close:i:i,getcwd:p:ps,fread:s:pssp,fwrite:s:pssp,fseek:i:piw,ftell:s:p`
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
                                // Return type must match nurlc's call sites: `int`-returning
                                // libc fns (ret char 'i') are declared i32 by nurlc, so the
                                // shim must return i32 — only size_t-like 's' widens to i64.
                                // (A i64 shim vs an i32 call site is a wasm signature mismatch
                                // → `unreachable` trap; nurl_str_eq→strcmp hits this.)
                                ( string_push_str shims ? == r_char 112 `i8*` ? == r_char 118 `void` ? == r_char 105 `i32` `i64` )
                                ( string_push_str shims ` @__nurl_` ) ( string_push_str shims ( string_data name ) ) ( string_push_str shims `_shim(` )
                                // Param char: 'p' = i8* (pointer, pass through), 'w' = i32
                                // (a param nurlc already emits as i32 — e.g. fseek's `whence`
                                // — so the wrapper must accept i32, NOT i64, or the call type
                                // won't match and wasm-ld stubs it), any other = i64 narrowed
                                // to i32 for the wasi call.
                                : ~ i k2 0 ~ < k2 ( string_len pms ) { ? > k2 0 { ( string_push_str shims `, ` ) } {} : i p ( string_get pms k2 ) ( string_push_str shims ? == p 112 `i8* %a` ? == p 119 `i32 %a` `i64 %a` ) ( string_push_int shims k2 ) = k2 + k2 1 }
                                ( string_push_str shims `) {\n` )
                                : ~ i k3 0 ~ < k3 ( string_len pms ) { : i p ( string_get pms k3 ) ? & != p 112 != p 119 { ( string_push_str shims `  %t` ) ( string_push_int shims k3 ) ( string_push_str shims ` = trunc i64 %a` ) ( string_push_int shims k3 ) ( string_push_str shims ` to i32\n` ) } {} = k3 + k3 1 }
                                ( string_push_str shims `  %r = tail call ` )
                                ( string_push_str shims ? == r_char 112 `i8*` ? == r_char 118 `void` `i32` )
                                ( string_push_str shims ` @` ) ( string_push_str shims ( string_data name ) ) ( string_push_char shims 40 )
                                : ~ i k4 0 ~ < k4 ( string_len pms ) {
                                    ? > k4 0 { ( string_push_str shims `, ` ) } {}
                                    : i p ( string_get pms k4 ) ? == p 112 { ( string_push_str shims `i8* %a` ) ( string_push_int shims k4 ) } { ? == p 119 { ( string_push_str shims `i32 %a` ) ( string_push_int shims k4 ) } { ( string_push_str shims `i32 %t` ) ( string_push_int shims k4 ) } }
                                    = k4 + k4 1
                                }
                                ( string_push_str shims `)\n` )
                                ? == r_char 118 { ( string_push_str shims `  ret void\n` ) } { ? == r_char 112 { ( string_push_str shims `  ret i8* %r\n` ) } { ? == r_char 105 { ( string_push_str shims `  ret i32 %r\n` ) } { ( string_push_str shims `  %rw = zext i32 %r to i64\n  ret i64 %rw\n` ) } } }
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

    // Mark every remaining `declare` as a potential host import. This
    // reproduces wasm-ld's `--allow-undefined` semantics WITHOUT the
    // linker flag (zig cc's driver rejects -Wl,--allow-undefined): a
    // symbol that is still undefined at link time becomes a wasm import
    // from module "env" (import name defaults to the symbol name), which
    // the host runtime resolves — WASI, canvas/audio, and the GPU
    // package's cuda/nvrtc bridge in the pure-NURL wasmtime. Symbols that
    // ARE defined (runtime.wasm.o, wasi-libc) resolve normally; wasm-ld
    // only consults the attribute for undefined ones, so blanket-marking
    // is safe (verified: an attributed @puts still binds to wasi-libc).
    // nurlc never emits attribute groups, so `#99` cannot collide.
    // `@llvm.*` intrinsic declares are skipped — they lower in the
    // backend and must not be turned into imports.
    : ( Vec String ) jlines ( string_split joined `\n` )
    ( string_free joined )
    : ~ String marked ( string_with_cap 1024 )
    : i jn ( vec_len [String] jlines )
    : ~ i ji 0
    ~ < ji jn {
        : ?String jlo ( vec_get [String] jlines ji )
        ?? jlo {
            T jline → {
                ? > ji 0 { ( string_push_char marked 10 ) } {}
                ( string_push_str marked ( string_data jline ) )
                ? & ( string_starts_with jline `declare ` ) == ( string_contains jline `@llvm.` ) F {
                    ( string_push_str marked ` #99` )
                } {}
            }
            F → {}
        }
        = ji + ji 1
    }
    ( vec_free_with [String] jlines \ String s → v { ( string_free s ) } )
    ( string_push_str marked `\nattributes #99 = { "wasm-import-module"="env" }\n` )

    // Keep `main` visible as an alias of the renamed entry. zig's debug
    // (-O0) wasi-libc pulls a __main_void.o that references `main`
    // directly — without the alias that link fails with "undefined
    // symbol: main" (release-mode libc variants only reference
    // __main_argc_argv). The alias satisfies both flavors.
    ? ( string_contains marked `define i32 @__main_argc_argv(` ) {
        ( string_push_str marked `@main = alias i32 (i32, i8**), i32 (i32, i8**)* @__main_argc_argv\n` )
    } {}

    // Restore the `@` masked in step 0. The sentinel only exists inside
    // string constants we masked; the appended shims never contain it.
    : String final ( string_replace marked ( __wb_ir_at_sentinel ) `@` )
    ( string_free marked )
    ^ final
}
