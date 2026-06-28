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
$ `stdlib/ext/env.nu`
$ `module.nu`
$ `interp.nu`

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
                    // push integer args in order
                    : ~ i k first_arg
                    ~ < k argc {
                        : String a ( env_arg k )
                        ( vec_push [i] . it vs ( nurl_str_to_int ( string_data a ) ) )
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
                            ( nurl_print_int ?? ( vec_get [i] . it vs - n 1 ) { T x → x F → 0 } )
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

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 { ( usage ) ^ 1 } {}
    // accept `run --invoke <export> <module>` (wasmtime-style) or just
    // `--invoke <export> <module>`.
    : i ii ( __arg_index argc `--invoke` )
    ? < ii 0 { ( usage ) ^ 1 } {}
    ? < argc + ii 3 { ( nurl_print `usage: wasmtime run --invoke <export> <module.wasm> [args…]\n` ) ^ 1 } {}
    : String export ( env_arg + ii 1 )
    : String path ( env_arg + ii 2 )
    : i rc ( run_invoke ( string_data export ) ( string_data path ) + ii 3 argc )
    ( string_free export ) ( string_free path )
    ^ rc
}
