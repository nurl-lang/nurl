// packages/nwasm/tests/wasi_test.nu — offline test for the WASI import
// surface. Embeds a hand-assembled wasm32-wasi module that imports
// `wasi_snapshot_preview1.fd_write` and `.proc_exit`, writes "hi from wasi\n"
// to stdout (fd 1) via an iovec in linear memory, then exits with code 42.
// The expected output + exit code are cross-checked against the reference
// wasmtime. Verifies imports dispatch, the data section, fd_write's iovec
// walk, and proc_exit setting the exit code.
//   NURL_STDLIB=<repo> ../../nurl.sh tests/wasi_test.nu /tmp/nwasm && /tmp/nwasm

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `src/module.nu`
$ `src/interp.nu`

@ wasm_wasi → s { ^ `0061736d0100000001100360017f0060000060047f7f7f7f017f02460216776173695f736e617073686f745f70726576696577310970726f635f65786974000016776173695f736e617073686f745f70726576696577310866645f77726974650002030201010503010001071302065f73746172740002066d656d6f727902000a1401120041014100410141c00010011a412a10000b0b20020041000b08100000000d0000000041100b0d68692066726f6d20776173690a` }

// A module that path_open's "t.txt" under preopen fd 3, fd_read's it, echoes
// the bytes to stdout via fd_write, and proc_exit(0)s. Exercises the --dir
// preopen + file fd table (path_open / fd_read / fd_write). Cross-checked
// against reference wasmtime.
@ wasm_freader → s { ^ `0061736d01000000011d0460017f0060097f7f7f7f7f7e7e7f7f017f60047f7f7f7f017f600000028a010416776173695f736e617073686f745f70726576696577310970726f635f65786974000016776173695f736e617073686f745f707265766965773109706174685f6f70656e000116776173695f736e617073686f745f70726576696577310766645f72656164000216776173695f736e617073686f745f70726576696577310866645f77726974650002030201030503010001071302065f73746172740004066d656d6f727902000a430141004103410041e4004105410042004200410041ac0210011a41ac0228020041004101410c10021a4104410c280200360200410141004101411010031a410010000b0b19020041000b08c8000000400000000041e4000b05742e747874` }

// Run a module's `_start`; return 1 on trap, else 0. `dir` is the preopen host
// path (empty = none). Reports a labelled failure line.
@ run_mod s hex s label s dir → i {
    : ~ i fail 0
    : !( Vec u ) ParseErr dr ( bytes_from_hex hex )
    ?? dr {
        T bytes → {
            : *Module m ( module_decode bytes )
            ? . m ok {
                : *Interp it ( interp_new m )
                ? != 0 ( nurl_str_len dir ) { ( interp_set_preopen it dir dir ) } {}
                ( interp_push_arg it label )
                ( exec_func it ( module_export_func m `_start` ) )
                ? ( interp_trapped it ) { ( nurl_print `FAIL: ` ) ( nurl_print label ) ( nurl_print ` trapped\n` ) = fail 1 } {}
                ? ! ( interp_exited it ) { ( nurl_print `FAIL: ` ) ( nurl_print label ) ( nurl_print ` no proc_exit\n` ) = fail 1 } {}
                ? != 0 . it exit_code { ( nurl_print `FAIL: ` ) ( nurl_print label ) ( nurl_print ` nonzero exit\n` ) = fail 1 } {}
                ( interp_free it )
            } { ( nurl_print `FAIL: decode\n` ) = fail 1 }
            ( module_free m )
        }
        F → { ( nurl_print `FAIL: hex\n` ) = fail 1 }
    }
    ^ fail
}

@ main → i {
    : ~ i fails 0
    // ── case 1: fd_write + proc_exit(42) ──
    : !( Vec u ) ParseErr dr ( bytes_from_hex ( wasm_wasi ) )
    ?? dr {
        T bytes → {
            : *Module m ( module_decode bytes )
            ? . m ok {
                : i fidx ( module_export_func m `_start` )
                : *Interp it ( interp_new m )
                ( interp_push_arg it `wasitest` )
                ( exec_func it fidx )
                // the module writes "hi from wasi" to stdout above this line
                ? ( interp_trapped it ) { ( nurl_print `FAIL: trapped\n` ) = fails + fails 1 } {}
                ? ! ( interp_exited it ) { ( nurl_print `FAIL: did not call proc_exit\n` ) = fails + fails 1 } {}
                ( nurl_print `exit_code 42:    ` ) ( nurl_print_int . it exit_code )
                ( nurl_print ? == . it exit_code 42 ` == ` ` != ` ) ( nurl_print `42\n` )
                ? != . it exit_code 42 { = fails + fails 1 } {}
                ( interp_free it )
            } { ( nurl_print `FAIL: module did not decode\n` ) = fails + fails 1 }
            ( module_free m )
        }
        F → { ( nurl_print `FAIL: hex parse\n` ) = fails + fails 1 }
    }
    // ── case 2: --dir preopen + path_open/fd_read/fd_write ──
    : !v IoErr wr ( write_file `/tmp/t.txt` `file-ops work!` )
    ?? wr {
        T x → {
            ( nurl_print `freader (reads /tmp/t.txt): ` )
            = fails + fails ( run_mod ( wasm_freader ) `freader` `/tmp` )
            ( nurl_print `\n` )
        }
        F e → { ( nurl_print `SKIP: cannot stage /tmp/t.txt\n` ) }
    }
    // ── case 3: interp_capture — the embedder reads stdout as a value ──
    // Same module as case 1, but with capture enabled its "hi from wasi\n"
    // must land in interp_stdout_bytes and NOT on our console (the golden
    // pins that: no second "hi from wasi" line appears in this output).
    : !( Vec u ) ParseErr dr3 ( bytes_from_hex ( wasm_wasi ) )
    ?? dr3 {
        T bytes → {
            : *Module m ( module_decode bytes )
            ? . m ok {
                : *Interp it ( interp_new m )
                ( interp_capture it )
                ( interp_push_arg it `wasitest` )
                ( exec_func it ( module_export_func m `_start` ) )
                : ( Vec u ) got ( interp_stdout_bytes it )
                : String gs ( bytes_to_str got )
                ( nurl_print `captured stdout: ` )
                : i okc ( nurl_str_eq ( string_data gs ) `hi from wasi\n` )
                ( nurl_print ? != okc 0 `== ` `!= ` )
                ( nurl_print `"hi from wasi\\n"\n` )
                ? == okc 0 { = fails + fails 1 } {}
                ( string_free gs )
                ( interp_free it )
            } { ( nurl_print `FAIL: module did not decode (capture case)\n` ) = fails + fails 1 }
            ( module_free m )
        }
        F → { ( nurl_print `FAIL: hex parse (capture case)\n` ) = fails + fails 1 }
    }
    ? == fails 0 { ( nurl_print `ALL WASI TESTS PASSED\n` ) } { ( nurl_print `WASI TESTS FAILED\n` ) }
    ^ fails
}
