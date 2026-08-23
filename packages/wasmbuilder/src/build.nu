// packages/wasmbuilder/src/build.nu — the wasm build driver (library API).
//
// The pipeline, end to end and fully local:
//
//   .nu ──nurlc──▶ LLVM IR ──wb_prepare_ir_for_wasi──▶ wasm32 IR
//        ──[zig] cc --target=wasm32-wasi + runtime.wasm.o──▶ .wasm
//
// Link flags:
//   -Wl,--gc-sections      The DEFAULT since 2026-07: drops the unreachable
//                          part of the NURL runtime from every module —
//                          ~25 % of the bytes and ~80 % of a JIT's
//                          load-the-module floor. An old note here said NURL
//                          closures (function-table indices) could not
//                          survive the table renumbering, "proven on
//                          nurlc.wasm >150 fns"; re-tested 2026-07-27 at
//                          exactly that scale — a --gc-sections nurlc.wasm
//                          SELF-COMPILES byte-identically to the native
//                          compiler under both the reference wasmtime and
//                          the pure-NURL wt, and the closure corpus
//                          (test_05/test_06) passes. Wherever that trap came
//                          from, today's wasm-ld relocates address-taken
//                          functions correctly through GC. `--no-gc-sections`
//                          / `. opts no_gc_sections` remains as the escape
//                          hatch; a trap that appears only without it would
//                          be a table-renumbering bug — please report it.
//   (nurlapi's -Wl,--allow-undefined is replaced by per-declare
//   "wasm-import-module"="env" IR attributes — zig cc's driver rejects
//   the linker flag; see wasi_ir.nu. Same semantics: undefined symbols
//   become wasm imports the host runtime resolves.)
//
// Library entry points (embed these — no subprocess, no HTTP):
//   ( wb_build_file  nu_path out_wasm opts ) → !v String
//   ( wb_build_source source filename opts ) → !( Vec u ) String
//
// Other packages import `src/build.nu` (which pulls wasi_ir.nu +
// toolchain.nu); the CLI in main.nu is a thin wrapper over the same calls.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/regex.nu`
$ `wasi_ir.nu`
$ `toolchain.nu`

// Build options. `opt` is a BORROWED view (literal or string_data of a
// caller-owned String) — WbOpts is passed by value, so it must not own
// heap fields.
: WbOpts {
    s opt  // clang opt level: `-O0`..`-O3`, `-Oz` (nurlapi uses -O1)
    b host_imports  // pass --ffi-host-imports (auto-dropped on old nurlc)
    b asyncify  // wasm-opt asyncify wrap for canvas programs (needs binaryen)
    b keep_ll  // leave the rewritten .ll next to the .wasm
    b quiet  // suppress progress lines on stderr
    s extra_obj  // extra object(s), space-separated, linked in (`` = none) — e.g.
    // a generated kernels_static.o so `& c` symbols resolve
    // statically instead of becoming env imports
    s extra_cflags  // extra compile/link flags, space-separated (`` = none)
    // — e.g. `-msimd128` for wasm SIMD
    s asyncify_imports  // comma-separated async import names (`` = none);
    // e.g. `env.wgpu_download` for the WebGPU backend's async readback
    b threads  // build for wasi-threads: shared memory, atomics, and the
    // guest-side pthread implementation in runtime.c. The module
    // then imports `wasi.thread-spawn` and exports
    // `wasi_thread_start` + `__stack_pointer`, so it needs a
    // runtime that implements the proposal (packages/wasmtime
    // does). Off by default: a shared memory is a different
    // memory model, not a free upgrade.
    b no_gc_sections  // link with --no-gc-sections instead of the default
    // --gc-sections — the escape hatch if a call_indirect trap
    // ever points at table renumbering again (see the link-flags
    // note at the top of this file). Costs ~25 % module size and
    // most of a JIT runtime's module-load floor.
}

// Split a space-separated flag string into owned Strings (caller frees).
// NOTE: the Vec Strings LEAK by design at the single link call site (a
// handful of tiny strings once per build) to keep the argv `s` views
// alive through process_run.
@ string_split_borrow s flags → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len flags )
    : ~ i a 0
    : ~ i k 0
    ~ <= k n {
        : ~ i c 32
        ? < k n { = c ( nurl_str_get flags k ) } {}
        ? == c 32 {
            ? > k a {
                : String w ( string_with_cap + - k a 1 )
                : ~ i j a
                ~ < j k { ( string_push_char w ( nurl_str_get flags j ) ) = j + j 1 }
                ( vec_push [String] out w )
            } {}
            = a + k 1
        } {}
        = k + k 1
    }
    ^ out
}

@ wb_opts_default → WbOpts {
    ^ @ WbOpts { `-O2` T F F F `` `` `` F F }
}

@ __wb_say b quiet s msg → v {
    ? quiet {} { ( nurl_eprintln msg ) }
}

// Run nurlc on `nu_path`, IR to String. Tries --ffi-host-imports first
// (external FFI symbols become wasm imports — needed for GPU kernels and
// for skipping native FFI sentinel gates); a pre-0.10.8 nurlc rejects the
// flag with "cannot open '--ffi-host-imports'", in which case we rerun
// without it rather than fail.
@ __wb_run_nurlc s nurlc s nu_path b host_imports → !String String {
    : ~ b with_flag host_imports
    : ~ i attempt 0
    ~ < attempt 2 {
        : ( Vec s ) args ( vec_new [s] )
        ( vec_push [s] args nu_path )
        ? with_flag { ( vec_push [s] args `--ffi-host-imports` ) } {}
        : !Output ProcessErr r ( process_run nurlc args `` )
        ( vec_free [s] args )
        ?? r {
            T o → {
                ? ( output_success o ) {
                    : String ir ( string_from ( output_stdout o ) )
                    ( output_free o )
                    ^ @ !String String { T ir }
                } {}
                : String se ( string_from ( output_stderr o ) )
                ( output_free o )
                // old-toolchain flag rejection → retry once without it.
                // Pre-0.10.8 compilers answer either "cannot open
                // '--ffi-host-imports'" (flag taken as a file) or a bare
                // usage line, depending on vintage.
                ? & with_flag | ( string_contains se `--ffi-host-imports` ) ( string_contains se `usage: nurlc` ) {
                    ( string_free se )
                    = with_flag F
                } {
                    : String msg ( string_from `nurlc failed:\n` )
                    ( string_push_str msg ( string_data se ) )
                    ( string_free se )
                    ^ @ !String String { F msg }
                }
            }
            F _ → { ^ @ !String String { F ( string_from `could not run nurlc` ) } }
        }
        = attempt + attempt 1
    }
    ^ @ !String String { F ( string_from `nurlc failed` ) }
}

// Post-rewrite IR scan for canvas/audio host imports (same patterns as
// nurlapi — a program can declare `& canvas` FFI directly without the
// stdlib import, so scanning the source string would miss it).
@ __wb_ir_uses s pattern String ir → b {
    : ~ b uses F
    : !Regex ParseErr re ( regex_compile pattern )
    ?? re { T rc → { = uses ( regex_test rc ( string_data ir ) ) ( regex_free rc ) } F _ → {} }
    ^ uses
}

// Compile one .nu file to `out_wasm`. The heavy lifting shared by the CLI
// and wb_build_source.
@ wb_build_file s nu_path s out_wasm WbOpts opts → !v String {
    ? ( file_exists nu_path ) {} {
        : String msg ( string_from `source not found: ` )
        ( string_push_str msg nu_path )
        ^ @ !v String { F msg }
    }

    // 1. nurlc → IR
    : !String String nr ( wb_find_nurlc )
    : ~ String nurlc ( string_new )
    ?? nr { T p → { ( string_free nurlc ) = nurlc p } F e → { ^ @ !v String { F e } } }
    ( __wb_say . opts quiet `wasmbuilder: nurlc → LLVM IR` )
    : !String String irr ( __wb_run_nurlc ( string_data nurlc ) nu_path . opts host_imports )
    ( string_free nurlc )
    : ~ String ir ( string_new )
    ?? irr { T i → { ( string_free ir ) = ir i } F e → { ^ @ !v String { F e } } }

    // 2. retarget for wasm32-wasi
    ( __wb_say . opts quiet `wasmbuilder: rewriting IR for wasm32-wasi` )
    : String ir_fixed ( wb_prepare_ir_for_wasi_opts ir . opts threads )
    ( string_free ir )

    : b uses_canvas ( __wb_ir_uses `@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\(` ir_fixed )
    : b uses_audio ( __wb_ir_uses `@audio_(level|bin|bin_count|peak_bin|centroid|freq_of|sample_rate|is_silent|ready)\(` ir_fixed )

    // 3. wasm compiler + runtime objects
    : !WbCompiler String cr ( wb_find_compiler T )
    : ~ WbCompiler cc @ WbCompiler { ( string_new ) T }
    ?? cr { T c → { ( wb_compiler_free cc ) = cc c } F e → { ( string_free ir_fixed ) ^ @ !v String { F e } } }

    // Does this program reach the socket layer at all? The runtime object
    // gets the `nurl_net` import bridge only then — otherwise the module
    // would declare imports it never calls, and a runtime that cannot
    // resolve them (the reference wasmtime, a browser) refuses to
    // instantiate it. --gc-sections used to hide that by dropping the
    // unused wrappers; --no-gc-sections did not, which is how a socket-free
    // benchmark ended up unrunnable.
    // A CALL, not a declare: nurlc's preamble declares the whole raw socket
    // ABI in every program, so matching the declaration would turn the
    // bridge on for a program that never opens anything.
    : b uses_net ( __wb_ir_uses `call [^@\n]*@nurl_(tcp|udp|dns)_[a-z_0-9]+\(` ir_fixed )
    : ~ String feat ( string_new )
    ? uses_net { ( string_push_str feat `net` ) } {}
    ? . opts threads {
        ? > ( string_len feat ) 0 { ( string_push_char feat 45 ) } {}
        ( string_push_str feat `threads` )
    } {}
    : !String String ror ( wb_ensure_wasm_obj_feat cc `runtime.c` ( string_data feat ) )
    : ~ String runtime_o ( string_new )
    ?? ror { T p → { ( string_free runtime_o ) = runtime_o p } F e → {
            ( string_free ir_fixed ) ( wb_compiler_free cc )
            ^ @ !v String { F e }
        } }

    : ~ String canvas_o ( string_new )
    ? uses_canvas {
        : !String String cor ( wb_ensure_wasm_obj cc `canvas_wasm.c` )
        ?? cor { T p → { ( string_free canvas_o ) = canvas_o p } F e → {
                ( string_free ir_fixed ) ( wb_compiler_free cc ) ( string_free runtime_o )
                ^ @ !v String { F e }
            } }
    } {}
    : ~ String audio_o ( string_new )
    ? uses_audio {
        : !String String aor ( wb_ensure_wasm_obj cc `audio_wasm.c` )
        ?? aor { T p → { ( string_free audio_o ) = audio_o p } F e → {
                ( string_free ir_fixed ) ( wb_compiler_free cc ) ( string_free runtime_o ) ( string_free canvas_o )
                ^ @ !v String { F e }
            } }
    } {}

    // 4. write the .ll next to the output, link, clean up
    : String ll_path ( string_from out_wasm )
    ( string_push_str ll_path `.ll` )
    : !v IoErr wr ( write_file ( string_data ll_path ) ( string_data ir_fixed ) )
    ( string_free ir_fixed )
    ?? wr { T _ → {} F _ → {
            ( wb_compiler_free cc ) ( string_free runtime_o ) ( string_free canvas_o ) ( string_free audio_o ) ( string_free ll_path )
            ^ @ !v String { F ( string_from `could not write the intermediate .ll (is the output directory writable?)` ) }
        } }

    ( __wb_say . opts quiet `wasmbuilder: linking .wasm (zig cc --target=wasm32-wasi)` )
    : ( Vec s ) args ( vec_new [s] )
    ? . cc is_zig { ( vec_push [s] args `cc` ) } {}
    ( vec_push [s] args `--target=wasm32-wasi` )
    ( vec_push [s] args . opts opt )
    // `zig cc` drops -O for LLVM IR inputs. Not for C — `zig cc -O2 -c x.c`
    // forwards -O2 to cc1 as expected — but for a `.ll` it passes NOTHING
    // and cc1 defaults to -O0. This pipeline hands zig a `.ll`, so every
    // wasm module wasmbuilder produced shipped UNOPTIMISED user code: no
    // mem2reg, so a loop counter stayed a linear-memory load/store pair.
    // A JIT hides it (Cranelift re-optimises what it is given, so the
    // reference wasmtime timings barely moved) and an interpreter cannot:
    // bench/lcg.nu at 1M iterations ran 1.09 s on packages/wasmtime before
    // this line and 0.20 s after it — 5.5x, from two argv tokens.
    // `nurl.sh` carries the same workaround for native builds; this is the
    // wasm side of it. `-Xclang <level>` goes straight to cc1 and survives.
    ? . cc is_zig { ( vec_push [s] args `-Xclang` ) ( vec_push [s] args . opts opt ) } {}
    ( vec_push [s] args `-Wno-override-module` )
    // wasi-threads: atomics + a shared memory the runtime reserves at its
    // maximum, and the stack pointer exported so the host can give each
    // thread its own. (The heap is handled inside runtime.c, which
    // defines the whole C allocation surface for this build — wasm32's
    // libc allocator is single-threaded and cannot be locked from
    // outside.)
    ? . opts threads {
        ( vec_push [s] args `-matomics` )
        ( vec_push [s] args `-mbulk-memory` )
        ( vec_push [s] args `-Wl,--shared-memory` )
        ( vec_push [s] args `-Wl,--max-memory=1073741824` )
        ( vec_push [s] args `-Wl,--export=__stack_pointer` )
        ( vec_push [s] args `-Wl,--export=wasi_thread_start` )
    } {}
    // Section GC is a single explicit choice, not a flag-string fight: a
    // caller layering `-Wl,--(no-)gc-sections` through extra_cflags would
    // be relying on wasm-ld's last-one-wins ordering to defeat the one we
    // push here. `. opts no_gc_sections` picks one flag or the other, so
    // the argv says what was meant. GC is the default; the field is the
    // escape hatch.
    ? . opts no_gc_sections
    { ( vec_push [s] args `-Wl,--no-gc-sections` ) }
    { ( vec_push [s] args `-Wl,--gc-sections` ) }
    ? > ( nurl_str_len . opts extra_cflags ) 0 {
        // split the space-separated flag string into separate argv slots
        : ( Vec String ) fl ( string_split_borrow . opts extra_cflags )
        : ~ i fk 0
        ~ < fk ( vec_len [String] fl ) {
            ?? ( vec_get [String] fl fk ) { T x → { ( vec_push [s] args ( string_data x ) ) } F _ → {} }
            = fk + fk 1
        }
    } {}
    ( vec_push [s] args ( string_data ll_path ) )
    ( vec_push [s] args ( string_data runtime_o ) )
    ? uses_canvas { ( vec_push [s] args ( string_data canvas_o ) ) } {}
    ? uses_audio { ( vec_push [s] args ( string_data audio_o ) ) } {}
    // extra_obj is space-separated: split so several objects can link
    // (e.g. kernels_static.wasm.o + wgpu_asyncify.wasm.o for a module
    // that supports both the static-CPU and WebGPU backends).
    ? > ( nurl_str_len . opts extra_obj ) 0 {
        : ( Vec String ) obs ( string_split_borrow . opts extra_obj )
        : ~ i ok 0
        ~ < ok ( vec_len [String] obs ) {
            ?? ( vec_get [String] obs ok ) { T x → { ( vec_push [s] args ( string_data x ) ) } F _ → {} }
            = ok + ok 1
        }
    } {}
    ( vec_push [s] args `-o` )
    ( vec_push [s] args out_wasm )
    ( vec_push [s] args `-lm` )
    : !Output ProcessErr lr ( process_run ( string_data . cc cmd ) args `` )
    ( vec_free [s] args )
    ( wb_compiler_free cc ) ( string_free runtime_o ) ( string_free canvas_o ) ( string_free audio_o )

    : ~ b link_ok F
    : ~ String link_err ( string_new )
    ?? lr {
        T o → {
            = link_ok ( output_success o )
            ? link_ok {} {
                ( string_free link_err )
                = link_err ( string_from `wasm link failed:\n` )
                ( string_push_str link_err ( output_stderr o ) )
            }
            ( output_free o )
        }
        F _ → {
            ( string_free link_err )
            = link_err ( string_from `could not run the wasm compiler` )
        }
    }
    ? . opts keep_ll {} { ( file_delete ( string_data ll_path ) ) }
    ( string_free ll_path )
    ? link_ok {} { ^ @ !v String { F link_err } }
    ( string_free link_err )

    // 5. optional asyncify wrap (canvas-in-browser programs). Restricted
    //    to canvas.sleep, matching the playground pipeline; any module
    //    can name its own async imports via opts.asyncify_imports (e.g.
    //    env.wgpu_download for the WebGPU backend).
    : b __asy_custom > ( nurl_str_len . opts asyncify_imports ) 0
    ? & . opts asyncify | uses_canvas __asy_custom {
        ( __wb_say . opts quiet `wasmbuilder: wasm-opt --asyncify` )
        : String tmp_out ( string_from out_wasm )
        ( string_push_str tmp_out `.async` )
        : s imps ? __asy_custom . opts asyncify_imports `canvas.sleep`
        : s parg ( nurl_str_cat `--pass-arg=asyncify-imports@` imps )
        : ( Vec s ) oargs ( vec_new [s] )
        // strip DWARF first: wasm-opt's asyncify pass aborts on the debug
        // line-table extensions wasi-sdk/zig objects carry
        // (`Fatal: TODO: DW_LNE_define_file`).
        ( vec_push [s] oargs `--strip-dwarf` )
        ( vec_push [s] oargs `--asyncify` )
        ( vec_push [s] oargs parg )
        ( vec_push [s] oargs `-O2` )
        ( vec_push [s] oargs out_wasm )
        ( vec_push [s] oargs `-o` )
        ( vec_push [s] oargs ( string_data tmp_out ) )
        : String wopt ( env_var_or `NURL_WASM_OPT` `wasm-opt` )
        : !Output ProcessErr orr ( process_run ( string_data wopt ) oargs `` )
        ( vec_free [s] oargs ) ( string_free wopt )
        ?? orr {
            T o → {
                ? ( output_success o ) {
                    ( output_free o )
                    : !v IoErr mv ( fs_rename ( string_data tmp_out ) out_wasm )
                    ( string_free tmp_out )
                    ?? mv { T _ → {} F _ → { ^ @ !v String { F ( string_from `asyncify output rename failed` ) } } }
                } {
                    : String msg ( string_from `wasm-opt --asyncify failed:\n` )
                    ( string_push_str msg ( output_stderr o ) )
                    ( output_free o ) ( string_free tmp_out )
                    ^ @ !v String { F msg }
                }
            }
            F _ → {
                ( string_free tmp_out )
                ^ @ !v String { F ( string_from `wasm-opt not found — --asyncify needs binaryen (apt install binaryen)` ) }
            }
        }
    } {}

    ^ @ !v String { T }
}

// Compile NURL source (a string) to wasm bytes — the embedding API
// swarm-mcp's kernel path uses. Single-file sources only (imports resolve
// against the installed stdlib; a multi-file package should go through
// wb_build_file on its entry point instead).
@ wb_build_source s source s filename WbOpts opts → !( Vec u ) String {
    // temp workspace: $TMPDIR (or %TEMP%, or /tmp)/<mkstemp>.d/
    : ~ String tdir ( env_var_or `TMPDIR` `` )
    ? == ( string_len tdir ) 0 { ( string_free tdir ) = tdir ( env_var_or `TEMP` `/tmp` ) } {}
    : !String IoErr tfr ( fs_tempfile ( string_data tdir ) `wasmbuild-` )
    ( string_free tdir )
    : ~ String work ( string_new )
    ?? tfr { T t → {
            ( file_delete ( string_data t ) )
            ( string_free work ) = work t
            ( string_push_str work `.d` )
        } F _ → { ^ @ !( Vec u ) String { F ( string_from `could not create a temp workspace` ) } } }
    : !v IoErr mk ( dir_create_all ( string_data work ) )
    ?? mk { T _ → {} F _ → {
            ( string_free work )
            ^ @ !( Vec u ) String { F ( string_from `could not create a temp workspace` ) }
        } }

    : ~ String fname ( string_from ? == 0 ( nurl_str_len filename ) `main.nu` filename )
    : String nu_path ( path_join ( string_data work ) ( string_data fname ) )
    : ~ String out_name ( string_from ( string_data fname ) )
    ( string_free fname )
    ? ( string_ends_with out_name `.nu` ) {
        : String t ( string_substr out_name 0 - ( string_len out_name ) 3 )
        ( string_free out_name ) = out_name t
    } {}
    ( string_push_str out_name `.wasm` )
    : String out_path ( path_join ( string_data work ) ( string_data out_name ) )
    ( string_free out_name )

    : !v IoErr wr ( write_file ( string_data nu_path ) source )
    ?? wr { T _ → {} F _ → {
            ( string_free work ) ( string_free nu_path ) ( string_free out_path )
            ^ @ !( Vec u ) String { F ( string_from `could not write the temp source` ) }
        } }

    : !v String br ( wb_build_file ( string_data nu_path ) ( string_data out_path ) opts )
    ?? br { T _ → {} F e → {
            ( file_delete ( string_data nu_path ) )
            ( dir_remove ( string_data work ) )
            ( string_free work ) ( string_free nu_path ) ( string_free out_path )
            ^ @ !( Vec u ) String { F e }
        } }

    : !( Vec u ) IoErr rr ( read_file_bytes ( string_data out_path ) )
    ( file_delete ( string_data nu_path ) )
    ( file_delete ( string_data out_path ) )
    ( dir_remove ( string_data work ) )
    ( string_free work ) ( string_free nu_path ) ( string_free out_path )
    ?? rr {
        T bytes → { ^ @ !( Vec u ) String { T bytes } }
        F _ → { ^ @ !( Vec u ) String { F ( string_from `built .wasm could not be read back` ) } }
    }
}
