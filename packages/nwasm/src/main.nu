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
// occupy the low indices and have none here; a defined func's is its type.
@ __functype Module m i fidx → s {
    ? < fidx ( module_num_import_funcs m ) { ^ # s 0 } {}
    ^ ( module_func_type m fidx )
}

// valtype of parameter k / the single result (127 = i32 default if unknown).
unsafe @ __param_ty s ftp i k → i {
    ? == # i ftp 0 { ^ 127 } {}
    : *FuncType ft # *FuncType ftp
    ^ ?? ( vec_get [i] . ft params k ) { T x → x F → 127 }
}

unsafe @ __result_ty_at s ftp i k → i {
    ? == # i ftp 0 { ^ 127 } {}
    : *FuncType ft # *FuncType ftp
    ^ ?? ( vec_get [i] . ft results k ) { T x → x F → 127 }
}

unsafe @ __result_count s ftp → i {
    ? == # i ftp 0 { ^ 0 } {}
    : *FuncType ft # *FuncType ftp
    ^ ( vec_len [i] . ft results )
}

// Keep in step with nurl.toml's [package] version — `--version` is what a
// bug report quotes, so a stale literal here misattributes the bug.
@ __nwasm_version → s { ^ `nwasm 2.0.0 (pure NURL)` }

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
            : Module m ( module_decode bytes )
            ? ! ( module_ok m ) {
                ( nurl_print `nwasm: ` ) ( nurl_print ( string_data ( bytes_to_str ( module_err m ) ) ) ) ( nurl_print `\n` )
                = rc 1
            } {
                : i fidx ( module_export_func m export )
                ? < fidx 0 {
                    ( nurl_print `nwasm: no exported function '` ) ( nurl_print export ) ( nurl_print `'\n` )
                    = rc 1
                } {
                    // Guard-page memory is on wherever the runtime supports it;
                    // NURL_NWASM_GUARD=0 keeps the bounds-checked Vec path (A/B, debug).
                    ?? ( env_get `NURL_NWASM_GUARD` ) { T gv → { ? != 0 ( nurl_str_eq ( string_data gv ) `0` ) { ( interp_disable_guard ) } {} } F → {} }
                    : Interp it ( interp_new m )
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
                        ( vec_push [i] ( interp_stack it ) val )
                        = k + k 1
                    }
                    ( interp_run_start it )
                    // JIT on by default on capable hosts (code_alloc probes the
                    // capability); NURL_NWASM_JIT=0 keeps the pure interpreter,
                    // NURL_NWASM_PIN=0 keeps every slot in memory (A/B, debug).
                    ?? ( env_get `NURL_NWASM_JIT` ) { T jv → { ? == 0 ( nurl_str_eq ( string_data jv ) `0` ) { ( interp_enable_jit ) } {} } F → { ( interp_enable_jit ) } }
                    ?? ( env_get `NURL_NWASM_PIN` ) { T pv → { ? != 0 ( nurl_str_eq ( string_data pv ) `0` ) { ( interp_disable_pin ) } {} } F → {} }
                    ?? ( env_get `NURL_NWASM_JIT_DUMP` ) { T dv → { ? != 0 ( nurl_str_eq ( string_data dv ) `1` ) { ( interp_enable_jitdump ) } {} } F → {} }
                    ( exec_func it fidx )
                    ? ( interp_trapped it ) {
                        ( nurl_print `nwasm: trap: ` ) ( nurl_print ( string_data ( bytes_to_str ( interp_trapmsg it ) ) ) ) ( nurl_print `\n` )
                        = rc 1
                    } {
                        // every result, in order, one per line, printed by its
                        // declared type (mirrors the reference CLI)
                        : i n ( vec_len [i] ( interp_stack it ) )
                        : ~ i nres ( __result_count ftp )
                        ? > nres n { = nres n } {}
                        ? > nres 0 {
                            : ~ i rj 0
                            ~ < rj nres {
                                : i rv ?? ( vec_get [i] ( interp_stack it ) + - n nres rj ) { T x → x F → 0 }
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
            : Module m ( module_decode bytes )
            ? ! ( module_ok m ) {
                ( nurl_eprint `nwasm: ` ) ( nurl_eprintln ( string_data ( bytes_to_str ( module_err m ) ) ) )
                = rc 1
            } {
                : i fidx ( module_export_func m `_start` )
                ? < fidx 0 {
                    ( nurl_eprintln `nwasm: module has no _start export (not a WASI command)` )
                    = rc 1
                } {
                    // Guard-page memory is on wherever the runtime supports it;
                    // NURL_NWASM_GUARD=0 keeps the bounds-checked Vec path (A/B, debug).
                    ?? ( env_get `NURL_NWASM_GUARD` ) { T gv → { ? != 0 ( nurl_str_eq ( string_data gv ) `0` ) { ( interp_disable_guard ) } {} } F → {} }
                    : Interp it ( interp_new m )
                    ? > fuel 0 { ( interp_set_fuel it fuel ) } {}
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
                    ~ < k argc { : String a ( env_arg k ) ( interp_push_arg it ( string_data a ) ) = k + k 1 }
                    ( interp_run_start it )
                    // JIT on by default on capable hosts (code_alloc probes the
                    // capability); NURL_NWASM_JIT=0 keeps the pure interpreter,
                    // NURL_NWASM_PIN=0 keeps every slot in memory (A/B, debug).
                    ?? ( env_get `NURL_NWASM_JIT` ) { T jv → { ? == 0 ( nurl_str_eq ( string_data jv ) `0` ) { ( interp_enable_jit ) } {} } F → { ( interp_enable_jit ) } }
                    ?? ( env_get `NURL_NWASM_PIN` ) { T pv → { ? != 0 ( nurl_str_eq ( string_data pv ) `0` ) { ( interp_disable_pin ) } {} } F → {} }
                    ?? ( env_get `NURL_NWASM_JIT_DUMP` ) { T dv → { ? != 0 ( nurl_str_eq ( string_data dv ) `1` ) { ( interp_enable_jitdump ) } {} } F → {} }
                    ( exec_func it fidx )
                    ( interp_flush it )  // _start may return without proc_exit
                    ? ( interp_trapped it ) {
                        ( nurl_eprint `nwasm: trap: ` ) ( nurl_eprintln ( string_data ( bytes_to_str ( interp_trapmsg it ) ) ) )
                        = rc 1
                    } { = rc ( interp_exit_code it ) }
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
            ? < + k 1 argc { : String fa ( env_arg + k 1 ) = fuel ( nurl_str_to_int ( string_data fa ) ) = k + k 2 } { = k + k 1 }
        } {}
        ? & ! done != 0 ( nurl_str_eq str `--invoke` ) {
            = done T
            ? < + k 1 argc { = invoke ( env_arg + k 1 ) = have_invoke 1 = k + k 2 } { = k + k 1 }
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
                    } } } } }
    ^ rc
}
