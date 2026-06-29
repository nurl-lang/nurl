// packages/wasmtime/src/main.nu — wasmtime: a WebAssembly runtime in pure NURL.
//
//   wasmtime run --invoke <export> <module.wasm> [int args…]
//
// Loads a wasm module, invokes an exported function with integer arguments, and
// prints the integer result. This is the foundation — the integer interpreter
// core (module.nu + interp.nu). Linear memory, floats, and the WASI surface
// (incl. `--dir`) build on top in later milestones.

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

@ __result_ty s ftp → i {
    ? == # i ftp 0 { ^ 127 } {}
    : *FuncType ft # *FuncType ftp
    ^ ?? ( vec_get [i] . ft results 0 ) { T x → x F → 127 }
}

@ usage → v {
    ( nurl_print `wasmtime — a WebAssembly runtime in pure NURL\n\n` )
    ( nurl_print `  wasmtime run --invoke <export> <module.wasm> [int args…]\n\n` )
    ( nurl_print `Loads the module and calls the exported function with the integer\n` )
    ( nurl_print `arguments, printing the integer result. (Integer core; WASI/--dir WIP.)\n` )
}

// Find the index of `flag` in argv (after position 1); -1 if absent.
@ __arg_index i argc s flag → i {
    : ~ i found -1
    : ~ i k 2
    ~ & == found -1 < k argc {
        : String a ( env_arg k )
        ? != 0 ( nurl_str_eq ( string_data a ) flag ) { = found k } {}
        ( string_free a )
        = k + k 1
    }
    ^ found
}

@ run_invoke s export s path i first_arg i argc → i {
    : !( Vec u ) IoErr fr ( read_file_bytes path )
    : ~ i rc 0
    ?? fr {
        F e → { ( nurl_print `wasmtime: cannot read module file\n` ) = rc 1 }
        T bytes → {
            : *Module m ( module_decode bytes )
            ? ! . m ok {
                ( nurl_print `wasmtime: ` ) ( nurl_print ( string_data ( bytes_to_str . m err ) ) ) ( nurl_print `\n` )
                ( module_free m ) = rc 1
            } {
                : i fidx ( module_export_func m export )
                ? < fidx 0 {
                    ( nurl_print `wasmtime: no exported function '` ) ( nurl_print export ) ( nurl_print `'\n` )
                    ( module_free m ) = rc 1
                } {
                    : *Interp it ( interp_new m )
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
                    ( exec_func it fidx )
                    ? . it trap {
                        ( nurl_print `wasmtime: trap: ` ) ( nurl_print ( string_data ( bytes_to_str . it trapmsg ) ) ) ( nurl_print `\n` )
                        = rc 1
                    } {
                        : i n ( vec_len [i] . it vs )
                        ? > n 0 {
                            : i top ?? ( vec_get [i] . it vs - n 1 ) { T x → x F → 0 }
                            : i rty ( __result_ty ftp )
                            ? == rty 124 { ( nurl_print ( nurl_str_float ( bits_to_f64 top ) ) ) } {
                                ? == rty 125 { ( nurl_print ( nurl_str_float # f ( bits_to_f32 top ) ) ) } {
                                    ( nurl_print_int top ) } }
                            ( nurl_print `\n` )
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

// Index of the `--dir` VALUE argument (`--dir <path>`), or -1 if absent.
@ __dir_arg i argc → i {
    : ~ i found -1
    : ~ i k 1
    ~ & == found -1 < k argc {
        : String a ( env_arg k )
        ? & != 0 ( nurl_str_eq ( string_data a ) `--dir` ) < + k 1 argc { = found + k 1 } {}
        ( string_free a )
        = k + k 1
    }
    ^ found
}

// Index of the first non-flag, non-`run` argument (the module path) other than
// `skip` (the consumed --dir value), or -1.
@ __module_index i argc i skip → i {
    : ~ i found -1
    : ~ i k 1
    ~ & == found -1 < k argc {
        : String a ( env_arg k )
        : s str ( string_data a )
        ? & & != k skip == 0 ( nurl_str_eq str `run` ) != 45 ( nurl_str_get str 0 ) { = found k } {}
        ( string_free a )
        = k + k 1
    }
    ^ found
}

// WASI command: run the module's `_start` with argv = [module, prog args…].
@ run_command s path i prog_start i argc s dir → i {
    : !( Vec u ) IoErr fr ( read_file_bytes path )
    : ~ i rc 0
    ?? fr {
        F e → { ( nurl_eprintln `wasmtime: cannot read module file` ) = rc 1 }
        T bytes → {
            : *Module m ( module_decode bytes )
            ? ! . m ok {
                ( nurl_eprintln `wasmtime: malformed module` ) ( module_free m ) = rc 1
            } {
                : i fidx ( module_export_func m `_start` )
                ? < fidx 0 {
                    ( nurl_eprintln `wasmtime: module has no _start export (not a WASI command)` )
                    ( module_free m ) = rc 1
                } {
                    : *Interp it ( interp_new m )
                    ? != 0 ( nurl_str_len dir ) { ( interp_set_preopen it dir dir ) } {}
                    ( interp_push_arg it path )
                    : ~ i k prog_start
                    ~ < k argc { : String a ( env_arg k ) ( interp_push_arg it ( string_data a ) ) ( string_free a ) = k + k 1 }
                    ( exec_func it fidx )
                    ? . it trap {
                        ( nurl_eprint `wasmtime: trap: ` ) ( nurl_eprintln ( string_data ( bytes_to_str . it trapmsg ) ) )
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

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 { ( usage ) ^ 1 } {}
    // Direct-call mode: `[run] --invoke <export> <module> [args]`.
    : i ii ( __arg_index argc `--invoke` )
    ? >= ii 0 {
        ? < argc + ii 3 { ( nurl_print `usage: wasmtime run --invoke <export> <module.wasm> [args…]\n` ) ^ 1 } {}
        : String export ( env_arg + ii 1 )
        : String path ( env_arg + ii 2 )
        : i rc ( run_invoke ( string_data export ) ( string_data path ) + ii 3 argc )
        ( string_free export ) ( string_free path )
        ^ rc
    } {}
    // WASI command mode: `[run] [--dir <path>] <module.wasm> [args…]`.
    : i di ( __dir_arg argc )
    : i mi ( __module_index argc di )
    ? < mi 0 { ( usage ) ^ 1 } {}
    : String path ( env_arg mi )
    : ~ i rc 0
    ? >= di 0 {
        : String dir ( env_arg di )
        = rc ( run_command ( string_data path ) + mi 1 argc ( string_data dir ) )
        ( string_free dir )
    } {
        = rc ( run_command ( string_data path ) + mi 1 argc `` )
    }
    ( string_free path )
    ^ rc
}
