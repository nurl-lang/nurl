// unikernel/demos/wasmc.nu — the NURL compiler, as wasm, inside a
// machine with no operating system.
//
// The image carries three things in its baked-in filesystem: the
// compiler compiled to wasm32-wasi (`nurlc.wasm`), one or more NURL
// programs to compile, and the LLVM IR the NATIVE compiler produced
// for each. The guest decodes the module with `packages/wasmtime`,
// runs it IN-PROCESS over each program — no subprocess exists here to
// run it any other way — captures the IR it writes to stdout, and
// compares it BYTE FOR BYTE with the native compiler's.
//
// That comparison is the whole point. "The wasm build works" is a
// claim about a pipeline; "the wasm compiler emits the same bytes as
// the native one, on a machine with no libc and no kernel" is a claim
// about the language, and it is the one this demo makes. A mismatch
// prints the first differing offset rather than a verdict, because
// with byte-identical output the interesting number is WHERE it
// stopped being identical.
//
// Reading the program from the initfs and writing nothing back is
// deliberate: the filesystem inside the image is read-only, and the
// IR never needs to land anywhere — it is compared in memory and
// dropped.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `packages/wasmtime/src/module.nu`
$ `packages/wasmtime/src/interp.nu`

// The programs to compile, and the native IR to match. Named on the
// kernel command line (argv), so one image serves any corpus baked
// into it: `args="hello.nu vec_basic.nu"`.
@ __first_diff ( Vec u ) a ( Vec u ) b → i {
    : i na ( vec_len [u] a )
    : i nb ( vec_len [u] b )
    : i n ? < na nb na nb
    : ~ i k 0
    ~ < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { ^ k } {}
        = k + k 1
    }
    ? != na nb { ^ n } {}
    ^ -1
}

// Compile `src` with the wasm compiler; return its stdout bytes.
// `ok` is 0 when the module trapped or exited non-zero — a compiler
// that dies is not a compiler that agrees.
: WcRun { i ok ( Vec u ) out String err }

// BORROWS the module: it is decoded ONCE and run per program. Both
// halves of that matter. Decoding a 1.5 MB module is real work to
// repeat eight times under an interpreter on an emulated CPU — and
// `module_decode` CONSUMES its byte vector (module_free frees the
// module's byte image), so decoding per program from the same vector
// hands the second run freed memory. It did, and the guest reported
// it the way a machine with no allocator debugging can: a garbled
// error, then "not a wasm module", then #GP.
@ __run_wasm * Module m s src → WcRun {
    : ~ i ok 0
    : ( Vec u ) out ( vec_new [u] )
    : ~ String err ( string_new )
    {
        : i fidx ( module_export_func m `_start` )
        ? < fidx 0 {
            ( string_free err )
            = err ( string_from `nurlc.wasm has no _start export` )
        } {
            : *Interp it ( interp_new m )
            ( interp_capture it )
            // The compiler reads its input through WASI path_open,
            // which resolves against a PREOPEN. "." is the initfs
            // root, which is where the sources live.
            ( interp_set_preopen it `.` `.` )
            ( interp_push_arg it `nurlc.wasm` )
            ( interp_push_arg it src )
            ( interp_run_start it )
            ( exec_func it fidx )
            ( interp_flush it )
            ? . it trap {
                ( string_free err )
                = err ( bytes_to_str . it trapmsg )
            } {
                ? != . it exit_code 0 {
                    ( string_free err )
                    = err ( bytes_to_str ( interp_stderr_bytes it ) )
                } {
                    = ok 1
                    ( vec_extend [u] out ( interp_stdout_bytes it ) )
                }
            }
            ( interp_free it )
        }
    }
    ^ @ WcRun { ok out err }
}

@ main → i {
    : !( Vec u ) IoErr wr ( read_file_bytes `nurlc.wasm` )
    : ~ i fails 0
    ?? wr {
        F e → {
            ( nurl_print `cannot read nurlc.wasm from the image\n` )
            ^ 1
        }
        T wasm → {
            ( nurl_print `nurlc.wasm bytes: ` )
            ( nurl_print ( nurl_str_int ( vec_len [u] wasm ) ) )
            ( nurl_print `\n` )
            // decode once; `wasm` belongs to the module from here on
            : *Module m ( module_decode wasm )
            ? ! . m ok {
                ( nurl_print `nurlc.wasm did not decode: ` )
                : String dm ( bytes_to_str . m err )
                ( nurl_print ( string_data dm ) )
                ( nurl_print `\n` )
                ( string_free dm )
                ( module_free m )
                ^ 1
            } {}
            : i argc ( env_args_count )
            : ~ i a 1
            ~ < a argc {
                : String src ( env_arg a )
                : String want_path ( string_concat ( string_from ( string_data src ) ) ( string_from `.ll` ) )
                ( nurl_print ( string_data src ) )
                ( nurl_print `: ` )
                : WcRun r ( __run_wasm m ( string_data src ) )
                ? == . r ok 0 {
                    ( nurl_print `wasm compiler failed: ` )
                    ( nurl_print ( string_data . r err ) )
                    ( nurl_print `\n` )
                    = fails + fails 1
                } {
                    ?? ( read_file_bytes ( string_data want_path ) ) {
                        F e2 → {
                            ( nurl_print `no native IR baked in for it\n` )
                            = fails + fails 1
                        }
                        T want → {
                            : i d ( __first_diff . r out want )
                            ? < d 0 {
                                ( nurl_print `byte-identical to native (` )
                                ( nurl_print ( nurl_str_int ( vec_len [u] want ) ) )
                                ( nurl_print ` bytes)\n` )
                            } {
                                ( nurl_print `DIFFERS at byte ` )
                                ( nurl_print ( nurl_str_int d ) )
                                ( nurl_print ` (wasm ` )
                                ( nurl_print ( nurl_str_int ( vec_len [u] . r out ) ) )
                                ( nurl_print ` vs native ` )
                                ( nurl_print ( nurl_str_int ( vec_len [u] want ) ) )
                                ( nurl_print ` bytes)\n` )
                                = fails + fails 1
                            }
                            ( vec_free [u] want )
                        }
                    }
                }
                ( vec_free [u] . r out )
                ( string_free . r err )
                ( string_free want_path )
                ( string_free src )
                = a + a 1
            }
            ( module_free m )
        }
    }
    ( nurl_print ? == fails 0 `all byte-identical\n` `MISMATCHES\n` )
    ^ ? == fails 0 0 1
}
