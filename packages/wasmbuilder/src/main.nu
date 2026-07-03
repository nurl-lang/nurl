// wasmbuilder — compile NURL to wasm32-wasi locally, with zero setup
// beyond the installed toolchain.
//
//   wasmbuilder program.nu                    # → program.wasm
//   wasmbuilder program.nu -o out/app.wasm    # explicit output
//   wasmbuilder program.nu -O z               # size-optimised link
//   wasmbuilder program.nu --emit-ll          # keep the rewritten .ll too
//   wasmbuilder --doctor                      # explain what is resolved
//
// Run the result with any wasm runtime — the reference wasmtime, or the
// pure-NURL one: `nurlpkg install wasmtime && wt run program.wasm`.
//
// The first build on a machine without a bundled zig downloads a pinned,
// sha256-verified zig 0.13.0 into $NURL_HOME/zig (set
// NURL_WASM_NO_DOWNLOAD=1 to forbid that and fail instead).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/args.nu`
$ `stdlib/ext/env.nu`
$ `build.nu`

@ __wbc_version → s { ^ `wasmbuilder 0.1.0` }

// --doctor: print every resolution step so a broken setup explains itself.
@ __wbc_doctor → i {
    ( nurl_print `wasmbuilder --doctor\n\n` )

    : String home ( wb_nurl_home )
    ( nurl_print `  NURL_HOME:    ` ) ( nurl_print ( string_data home ) ) ( nurl_print `\n` )
    ( string_free home )

    : !String String nr ( wb_find_nurlc )
    ?? nr {
        T p → { ( nurl_print `  nurlc:        ` ) ( nurl_print ( string_data p ) ) ( nurl_print `\n` ) ( string_free p ) }
        F e → { ( nurl_print `  nurlc:        MISSING — ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e ) }
    }

    : String sdir ( wb_stdlib_dir )
    : String rc ( path_join ( string_data sdir ) `runtime.c` )
    ( nurl_print `  stdlib C src: ` ) ( nurl_print ( string_data rc ) )
    ( nurl_print ? ( file_exists ( string_data rc ) ) ` (found)\n` ` (MISSING — set $NURL_STDLIB)\n` )
    ( string_free sdir ) ( string_free rc )

    // Resolve the compiler WITHOUT downloading, so --doctor stays read-only.
    : !WbCompiler String cr ( wb_find_compiler F )
    ?? cr {
        T c → {
            ( nurl_print `  wasm cc:      ` ) ( nurl_print ( string_data . c cmd ) )
            ( nurl_print ? . c is_zig ` (zig cc)\n` ` (wasi clang)\n` )
            ( wb_compiler_free c )
        }
        F e → {
            ( nurl_print `  wasm cc:      not found — the first build will download zig 0.13.0 into $NURL_HOME/zig\n                (` )
            ( nurl_print ( string_data e ) ) ( nurl_print `)\n` )
            ( string_free e )
        }
    }

    : String cdir ( wb_cache_dir )
    ( nurl_print `  object cache: ` ) ( nurl_print ( string_data cdir ) ) ( nurl_print `\n` )
    ( string_free cdir )

    ( nurl_print `\nRun a wasm module with the pure-NURL runtime: nurlpkg install wasmtime && wt run app.wasm\n` )
    ^ 0
}

@ main → i {
    : ArgParser p ( args_new `wasmbuilder` `Compile NURL to wasm32-wasi locally (nurlc → IR rewrite → bundled zig cc). No wasi-sdk, no build service.` )
    ( args_opt p `output` 111 `FILE` `output .wasm path (default: <input>.wasm)` )
    ( args_opt p `opt` 79 `LEVEL` `optimisation level 0..3 or z (default 2)` )
    ( args_flag p `emit-ll` 0 `keep the rewritten wasm32 .ll next to the output` )
    ( args_flag p `asyncify` 0 `wasm-opt asyncify wrap for canvas programs (needs binaryen)` )
    ( args_flag p `no-host-imports` 0 `do not pass --ffi-host-imports to nurlc` )
    ( args_flag p `quiet` 113 `suppress progress output` )
    ( args_flag p `doctor` 0 `print how nurlc/zig/runtime resolve on this machine` )
    ( args_flag p `version` 0 `print the version` )
    ( args_flag p `help` 104 `show this help` )

    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( string_free u ) ( args_free p )
        ^ 0
    } {}
    ? ( args_present p `version` ) {
        ( nurl_print ( __wbc_version ) ) ( nurl_print `\n` )
        ( args_free p )
        ^ 0
    } {}
    ? ( args_present p `doctor` ) {
        ( args_free p )
        ^ ( __wbc_doctor )
    } {}

    ? == ( args_positional_count p ) 1 {} {
        ( nurl_eprintln `usage: wasmbuilder <file.nu> [-o out.wasm] [--opt LEVEL] [--emit-ll] [--asyncify] [--doctor]` )
        ( args_free p )
        ^ 2
    }
    : ( Vec String ) pos ( args_positionals p )
    : ~ String input ( string_new )
    : ?String i0 ( vec_get [String] pos 0 )
    ?? i0 { T ip → { ( string_free input ) = input ( string_from ( string_data ip ) ) } F → {} }

    // default output: <input minus .nu>.wasm
    : ~ String out ( args_value_or p `output` `` )
    ? == ( string_len out ) 0 {
        ( string_free out )
        = out ( string_from ( string_data input ) )
        ? ( string_ends_with out `.nu` ) {
            : String t ( string_substr out 0 - ( string_len out ) 3 )
            ( string_free out ) = out t
        } {}
        ( string_push_str out `.wasm` )
    } {}

    : String olevel_v ( args_value_or p `opt` `2` )
    : ~ String olevel ( string_from `-O` )
    ( string_push_str olevel ( string_data olevel_v ) )
    ( string_free olevel_v )

    : ~ WbOpts opts ( wb_opts_default )
    = . opts opt ( string_data olevel )
    ? ( args_present p `no-host-imports` ) { = . opts host_imports F } {}
    ? ( args_present p `emit-ll` ) { = . opts keep_ll T } {}
    ? ( args_present p `asyncify` ) { = . opts asyncify T } {}
    ? ( args_present p `quiet` ) { = . opts quiet T } {}

    : !v String r ( wb_build_file ( string_data input ) ( string_data out ) opts )
    : ~ i rc 0
    ?? r {
        T _ → {
            : !i IoErr szr ( file_size ( string_data out ) )
            : i sz ?? szr { T sv → sv F _ → 0 }
            ? . opts quiet {} {
                : String done ( string_from `wasmbuilder: wrote ` )
                ( string_push_str done ( string_data out ) )
                ( string_push_str done ` (` )
                ( string_push_int done sz )
                ( string_push_str done ` bytes)` )
                ( nurl_eprintln ( string_data done ) )
                ( string_free done )
            }
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            = rc 1
        }
    }
    ( string_free olevel ) ( string_free input ) ( string_free out ) ( args_free p )
    ^ rc
}
