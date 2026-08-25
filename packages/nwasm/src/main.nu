// packages/nwasm/src/main.nu — nwasm: a WebAssembly runtime in pure NURL.
//
//   nwasm run --invoke <export> <module.wasm> [int args…]
//
// Loads a wasm module and either runs its `_start` as a wasm32-wasi command
// or invokes one exported function directly, printing the result. The engine
// itself is module.nu (decoder) + interp.nu (interpreter and template JIT).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/env.nu`
$ `module.nu`
$ `interp.nu`

// FuncType of an exported function (or #s 0 if unavailable). Imported funcs
// occupy the low indices, so a defined func is m.funcs[fidx - num_import_funcs].
@ __functype * Module m i fidx → s {
    ? < fidx . m num_import_funcs { ^ # s 0 } {}
    : s fp ?? ( vec_get [s] . m funcs - fidx . m num_import_funcs ) { T x → x F → # s 0 }
    ? == # i fp 0 { ^ # s 0 } {}
    : *WFunc f # *WFunc fp
    ^ ?? ( vec_get [s] . m types . f typeidx ) { T x → x F → # s 0 }
}

// valtype of parameter k / the single result (127 = i32 default if unknown).
@ __param_ty s ftp i k → i {
    ? == # i ftp 0 { ^ 127 } {}
    : *FuncType ft # *FuncType ftp
    ^ ?? ( vec_get [i] . ft params k ) { T x → x F → 127 }
}

@ __result_ty_at s ftp i k → i {
    ? == # i ftp 0 { ^ 127 } {}
    : *FuncType ft # *FuncType ftp
    ^ ?? ( vec_get [i] . ft results k ) { T x → x F → 127 }
}

@ __result_count s ftp → i {
    ? == # i ftp 0 { ^ 0 } {}
    : *FuncType ft # *FuncType ftp
    ^ ( vec_len [i] . ft results )
}

// Keep in step with nurl.toml's [package] version — `--version` is what a
// bug report quotes, so a stale literal here misattributes the bug.
@ __nwasm_version → s { ^ `nwasm 1.0.6 (pure NURL)` }

@ usage → v {
    ( nurl_print `nwasm — a WebAssembly runtime in pure NURL\n\n` )
    ( nurl_print `  nwasm run [--dir <path>]… [--env NAME=VALUE]… [--fuel N] [--allow-gpu] [--allow-net] <module.wasm> [args…]\n` )
    ( nurl_print `  nwasm run --invoke <export> <module.wasm> [args…]\n` )
    ( nurl_print `  nwasm --version | --help\n\n` )
    ( nurl_print `Command mode runs a wasm32-wasi module's _start with the given preopened\n` )
    ( nurl_print `directories and environment. Invoke mode calls an exported function with\n` )
    ( nurl_print `integer / floating-point arguments and prints the result.\n\n` )
    ( nurl_print `Options are read up to the module path; everything after it is the guest's\n` )
    ( nurl_print `own argv (so its --help is its own). Use -- before a module path that\n` )
    ( nurl_print `starts with a dash.\n` )
}

@ run_invoke s export s path i first_arg i argc i allow_gpu i allow_net → i {
    : !( Vec u ) IoErr fr ( read_file_bytes path )
    : ~ i rc 0
    ?? fr {
        F e → { ( nurl_print `nwasm: cannot read module file\n` ) = rc 1 }
        T bytes → {
            : *Module m ( module_decode bytes )
            ? ! . m ok {
                ( nurl_print `nwasm: ` ) ( nurl_print ( string_data ( bytes_to_str . m err ) ) ) ( nurl_print `\n` )
                ( module_free m ) = rc 1
            } {
                : i fidx ( module_export_func m export )
                ? < fidx 0 {
                    ( nurl_print `nwasm: no exported function '` ) ( nurl_print export ) ( nurl_print `'\n` )
                    ( module_free m ) = rc 1
                } {
                    // Guard-page memory is on wherever the runtime supports it;
                    // NURL_NWASM_GUARD=0 keeps the bounds-checked Vec path (A/B, debug).
                    ?? ( env_get `NURL_NWASM_GUARD` ) { T gv → { ? != 0 ( nurl_str_eq ( string_data gv ) `0` ) { ( interp_disable_guard ) } {} ( string_free gv ) } F → {} }
                    : *Interp it ( interp_new m )
                    ? != allow_gpu 0 { ( interp_allow_gpu it ) } {}
                    ? != allow_net 0 { ( interp_allow_net it ) } {}
                    : s ftp ( __functype m fidx )
                    // push args, parsed per parameter type (i32/i64 decimal,
                    // f32/f64 floating-point → stored as their bit pattern)
                    : ~ i k first_arg
                    ~ < k argc {
                        : String a ( env_arg k )
                        : i pty ( __param_ty ftp - k first_arg )
                        : i val ? == pty 124 ( f64_to_bits ( nurl_str_to_float ( string_data a ) ) ) ? == pty 125 ( f32_to_bits # f32 ( nurl_str_to_float ( string_data a ) ) ) ( nurl_str_to_int ( string_data a ) )
                        ( vec_push [i] . it vs val )
                        ( string_free a )
                        = k + k 1
                    }
                    ( interp_run_start it )
                    // JIT on by default on capable hosts (code_alloc probes the
                    // capability); NURL_NWASM_JIT=0 keeps the pure interpreter,
                    // NURL_NWASM_PIN=0 keeps every slot in memory (A/B, debug).
                    ?? ( env_get `NURL_NWASM_JIT` ) { T jv → { ? == 0 ( nurl_str_eq ( string_data jv ) `0` ) { ( interp_enable_jit ) } {} ( string_free jv ) } F → { ( interp_enable_jit ) } }
                    ?? ( env_get `NURL_NWASM_PIN` ) { T pv → { ? != 0 ( nurl_str_eq ( string_data pv ) `0` ) { ( interp_disable_pin ) } {} ( string_free pv ) } F → {} }
                    ?? ( env_get `NURL_NWASM_JIT_DUMP` ) { T dv → { ? != 0 ( nurl_str_eq ( string_data dv ) `1` ) { ( interp_enable_jitdump ) } {} ( string_free dv ) } F → {} }
                    ( exec_func it fidx )
                    ? ( interp_trapped it ) {
                        ( nurl_print `nwasm: trap: ` ) ( nurl_print ( string_data ( bytes_to_str . it trapmsg ) ) ) ( nurl_print `\n` )
                        = rc 1
                    } {
                        // every result, in order, one per line, printed by its
                        // declared type (mirrors the reference CLI)
                        : i n ( vec_len [i] . it vs )
                        : ~ i nres ( __result_count ftp )
                        ? > nres n { = nres n } {}
                        ? > nres 0 {
                            : ~ i rj 0
                            ~ < rj nres {
                                : i rv ?? ( vec_get [i] . it vs + - n nres rj ) { T x → x F → 0 }
                                : i rty ( __result_ty_at ftp rj )
                                ? == rty 124 { ( nurl_print ( nurl_str_float ( bits_to_f64 rv ) ) ) } {
                                    ? == rty 125 { ( nurl_print ( nurl_str_float # f ( bits_to_f32 rv ) ) ) } {
                                        ? | == rty 111 == rty 112 { ( nurl_print ? < rv 0 `<null reference>` `<reference>` ) } {
                                            ( nurl_print ( nurl_str_int rv ) ) } } }
                                ( nurl_print `\n` )
                                = rj + rj 1
                            }
                        } { ( nurl_print `(no result)\n` ) }
                    }
                    ( interp_free it )
                    ( module_free m )
                }
            }
        }
    }
    ^ rc
}

// WASI command: run the module's `_start` with argv = [module, prog args…],
// the given preopened directories and environment entries.
@ run_command s path i prog_start i argc ( Vec String ) dirs ( Vec String ) envs i fuel i allow_gpu i allow_net → i {
    : !( Vec u ) IoErr fr ( read_file_bytes path )
    : ~ i rc 0
    ?? fr {
        F e → { ( nurl_eprintln `nwasm: cannot read module file` ) = rc 1 }
        T bytes → {
            : *Module m ( module_decode bytes )
            ? ! . m ok {
                ( nurl_eprint `nwasm: ` ) ( nurl_eprintln ( string_data ( bytes_to_str . m err ) ) )
                ( module_free m ) = rc 1
            } {
                : i fidx ( module_export_func m `_start` )
                ? < fidx 0 {
                    ( nurl_eprintln `nwasm: module has no _start export (not a WASI command)` )
                    ( module_free m ) = rc 1
                } {
                    // Guard-page memory is on wherever the runtime supports it;
                    // NURL_NWASM_GUARD=0 keeps the bounds-checked Vec path (A/B, debug).
                    ?? ( env_get `NURL_NWASM_GUARD` ) { T gv → { ? != 0 ( nurl_str_eq ( string_data gv ) `0` ) { ( interp_disable_guard ) } {} ( string_free gv ) } F → {} }
                    : *Interp it ( interp_new m )
                    ? > fuel 0 { = . it fuel fuel } {}
                    ? != allow_gpu 0 { ( interp_allow_gpu it ) } {}
                    ? != allow_net 0 { ( interp_allow_net it ) } {}
                    : i nd ( vec_len [String] dirs )
                    : ~ i d 0
                    ~ < d nd { ?? ( vec_get [String] dirs d ) { T ds → ( interp_set_preopen it ( string_data ds ) ( string_data ds ) ) F → {} } = d + d 1 }
                    : i ne ( vec_len [String] envs )
                    : ~ i e 0
                    ~ < e ne { ?? ( vec_get [String] envs e ) { T es → ( interp_push_env it ( string_data es ) ) F → {} } = e + e 1 }
                    ( interp_push_arg it path )
                    : ~ i k prog_start
                    ~ < k argc { : String a ( env_arg k ) ( interp_push_arg it ( string_data a ) ) ( string_free a ) = k + k 1 }
                    ( interp_run_start it )
                    // JIT on by default on capable hosts (code_alloc probes the
                    // capability); NURL_NWASM_JIT=0 keeps the pure interpreter,
                    // NURL_NWASM_PIN=0 keeps every slot in memory (A/B, debug).
                    ?? ( env_get `NURL_NWASM_JIT` ) { T jv → { ? == 0 ( nurl_str_eq ( string_data jv ) `0` ) { ( interp_enable_jit ) } {} ( string_free jv ) } F → { ( interp_enable_jit ) } }
                    ?? ( env_get `NURL_NWASM_PIN` ) { T pv → { ? != 0 ( nurl_str_eq ( string_data pv ) `0` ) { ( interp_disable_pin ) } {} ( string_free pv ) } F → {} }
                    ?? ( env_get `NURL_NWASM_JIT_DUMP` ) { T dv → { ? != 0 ( nurl_str_eq ( string_data dv ) `1` ) { ( interp_enable_jitdump ) } {} ( string_free dv ) } F → {} }
                    ( exec_func it fidx )
                    ( interp_flush it )  // _start may return without proc_exit
                    ? ( interp_trapped it ) {
                        ( nurl_eprint `nwasm: trap: ` ) ( nurl_eprintln ( string_data ( bytes_to_str . it trapmsg ) ) )
                        = rc 1
                    } { = rc . it exit_code }
                    ( interp_free it )
                    ( module_free m )
                }
            }
        }
    }
    ^ rc
}

// Every host option is read from the argv PREFIX that ends at the module
// path — a guest's own `--help`, `--version` or `--allow-gpu` belongs to
// the guest. (Scanning all of argv for those three meant `nwasm run app.wasm
// --help` printed the RUNTIME's usage and never started the module; the
// bug surfaced on the first guest with a CLI of its own.) `--` ends the
// host options explicitly, for a module path that starts with a dash.
@ main → i {
    : i argc ( env_args_count )
    : ( Vec String ) dirs ( vec_new [String] )
    : ( Vec String ) envs ( vec_new [String] )
    : ~ String invoke ( string_new )
    : ~ i have_invoke 0
    : ~ i allow_gpu 0
    : ~ i allow_net 0
    : ~ i want_help 0
    : ~ i want_version 0
    : ~ i bad_opt 0
    : ~ i fuel -1
    : ~ i mi -1
    : ~ i k 1
    ~ & == mi -1 < k argc {
        : String a ( env_arg k )
        : s str ( string_data a )
        : ~ b done F
        ? != 0 ( nurl_str_eq str `--` ) {
            = done T
            ? < + k 1 argc { = mi + k 1 } { = k argc }
        } {}
        ? & ! done != 0 ( nurl_str_eq str `--dir` ) {
            = done T
            ? < + k 1 argc { ( vec_push [String] dirs ( env_arg + k 1 ) ) = k + k 2 } { = k + k 1 }
        } {}
        ? & ! done != 0 ( nurl_str_eq str `--env` ) {
            = done T
            ? < + k 1 argc { ( vec_push [String] envs ( env_arg + k 1 ) ) = k + k 2 } { = k + k 1 }
        } {}
        ? & ! done != 0 ( nurl_str_eq str `--fuel` ) {
            = done T
            ? < + k 1 argc { : String fa ( env_arg + k 1 ) = fuel ( nurl_str_to_int ( string_data fa ) ) ( string_free fa ) = k + k 2 } { = k + k 1 }
        } {}
        ? & ! done != 0 ( nurl_str_eq str `--invoke` ) {
            = done T
            ? < + k 1 argc { ( string_free invoke ) = invoke ( env_arg + k 1 ) = have_invoke 1 = k + k 2 } { = k + k 1 }
        } {}
        ? & ! done != 0 ( nurl_str_eq str `--allow-gpu` ) { = done T = allow_gpu 1 = k + k 1 } {}
        ? & ! done != 0 ( nurl_str_eq str `--allow-net` ) { = done T = allow_net 1 = k + k 1 } {}
        ? & ! done | != 0 ( nurl_str_eq str `--help` ) != 0 ( nurl_str_eq str `-h` ) { = done T = want_help 1 = k + k 1 } {}
        ? & ! done != 0 ( nurl_str_eq str `--version` ) { = done T = want_version 1 = k + k 1 } {}
        ? & ! done != 0 ( nurl_str_eq str `run` ) { = done T = k + k 1 } {}
        ? ! done {
            ? != 45 ( nurl_str_get str 0 ) { = mi k } {
                ( nurl_eprint `nwasm: unknown option ` ) ( nurl_eprintln str )
                = bad_opt 1
                = k argc
            }
        } {}
        ( string_free a )
    }
    : ~ i rc 1
    ? != 0 bad_opt { ( usage ) } {
        ? != 0 want_version { ( nurl_print ( __nwasm_version ) ) ( nurl_print `\n` ) = rc 0 } {
            ? != 0 want_help { ( usage ) = rc 0 } {
                ? < argc 2 { ( usage ) } {
                    ? < mi 0 { ( usage ) } {
                        : String path ( env_arg mi )
                        ? != 0 have_invoke {
                            = rc ( run_invoke ( string_data invoke ) ( string_data path ) + mi 1 argc allow_gpu allow_net )
                        } {
                            = rc ( run_command ( string_data path ) + mi 1 argc dirs envs fuel allow_gpu allow_net )
                        }
                        ( string_free path )
                    } } } } }
    ( string_free invoke )
    : i nd ( vec_len [String] dirs )
    : ~ i fd 0
    ~ < fd nd { ?? ( vec_get [String] dirs fd ) { T ds → ( string_free ds ) F → {} } = fd + fd 1 }
    ( vec_free [String] dirs )
    : i ne ( vec_len [String] envs )
    : ~ i fe 0
    ~ < fe ne { ?? ( vec_get [String] envs fe ) { T es → ( string_free es ) F → {} } = fe + fe 1 }
    ( vec_free [String] envs )
    ^ rc
}
