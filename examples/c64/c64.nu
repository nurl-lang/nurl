// examples/c64/c64.nu — native CLI front-end for the C64 / 6510 core.
//
// Milestone 1 runs the CPU headlessly against Klaus Dormann's 6502
// functional test — the canonical 6502 correctness oracle, exactly as
// the Game Boy core is validated against Blargg's cpu_instrs.
//
// Run:  ./c64 roms/6502_functional_test.bin
//       ./c64 roms/6502_functional_test.bin <instr-budget>
//
// The test image is a full 64 KiB memory dump; entry is $0400. Each pass
// or failure point is a `JMP *` self-loop ("trap"), so the runner steps
// until the PC stops advancing and reports the trap address. The success
// trap for the standard build is $3469.

$ `examples/c64/core.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

// ── Hex printing for addresses ──────────────────────────────────────
@ hex_nib i n → i { ^ ? < n 10 + 48 n + 55 n }
@ print_hex16 i v → v {
    : String s ( string_with_cap 5 )
    ( string_push_char s 36 )                       // '$'
    ( string_push_char s ( hex_nib & >> v 12 0xF ) )
    ( string_push_char s ( hex_nib & >> v 8 0xF ) )
    ( string_push_char s ( hex_nib & >> v 4 0xF ) )
    ( string_push_char s ( hex_nib & v 0xF ) )
    ( nurl_print ( string_data s ) )
    ( string_free s )
}

// ── Run the functional test, watching for the trap self-loop ────────
// Returns 0 on success ($3469 reached), 1 on a failure trap, 2 on error.
@ run_test s path i budget i success → i {
    : !( Vec u ) IoErr rr ( read_file_bytes path )
    : ~ i status 2
    ?? rr {
        F _ → {
            ( nurl_print `cannot read test image: ` ) ( nurl_print path ) ( nurl_print `\n` )
            = status 2
        }
        T img → {
            ( mem_alloc )
            ( mem_load ( vec_data [u] img ) ( vec_len [u] img ) 0 )
            ( vec_free [u] img )
            ( cpu_set_pc 0x400 )

            : ~ i instr 0
            : ~ i trapped 0
            : ~ i trap_pc 0
            ~ & == trapped 0 < instr budget {
                : i prev ( cpu_pc )
                ( step )
                ? == ( cpu_pc ) prev { = trapped 1  = trap_pc prev } {}
                = instr + instr 1
            }

            ? == trapped 0 {
                ( nurl_print `no trap within budget (` )
                ( nurl_print ( nurl_str_int instr ) ) ( nurl_print ` instructions) — pc=` )
                ( print_hex16 ( cpu_pc ) ) ( nurl_print `\n` )
                = status 2
            } {
                ? == trap_pc success {
                    ( nurl_print `PASS — reached success trap at ` )
                    ( print_hex16 trap_pc ) ( nurl_print ` after ` )
                    ( nurl_print ( nurl_str_int instr ) ) ( nurl_print ` instructions\n` )
                    = status 0
                } {
                    ( nurl_print `FAIL — trapped at ` ) ( print_hex16 trap_pc )
                    ( nurl_print ` after ` ) ( nurl_print ( nurl_str_int instr ) )
                    ( nurl_print ` instructions\n` )
                    = status 1
                }
            }
        }
    }
    ^ status
}

// ── Boot mode: load the three C64 ROMs, run, dump the text screen ───
@ run_boot s kpath s bpath s cpath i frames → i {
    ( c64_alloc )
    ?? ( read_file_bytes kpath ) {
        T k → { ( load_kernal ( vec_data [u] k ) ( vec_len [u] k ) )  ( vec_free [u] k ) }
        F _ → { ( nurl_print `cannot read KERNAL: ` ) ( nurl_print kpath ) ( nurl_print `\n` )  ^ 2 }
    }
    ?? ( read_file_bytes bpath ) {
        T b → { ( load_basic ( vec_data [u] b ) ( vec_len [u] b ) )  ( vec_free [u] b ) }
        F _ → { ( nurl_print `cannot read BASIC: ` ) ( nurl_print bpath ) ( nurl_print `\n` )  ^ 2 }
    }
    ?? ( read_file_bytes cpath ) {
        T c → { ( load_chargen ( vec_data [u] c ) ( vec_len [u] c ) )  ( vec_free [u] c ) }
        F _ → { ( nurl_print `cannot read CHARGEN: ` ) ( nurl_print cpath ) ( nurl_print `\n` )  ^ 2 }
    }
    ( c64_boot )
    : ~ i f 0
    ~ < f frames { ( run_one_frame )  = f + f 1 }
    ( nurl_print `--- screen after ` ) ( nurl_print ( nurl_str_int frames ) ) ( nurl_print ` frames ---\n` )
    ( screen_dump )
    ^ 0
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    ? < ( vec_len [String] args ) 2 {
        ( nurl_print `usage: c64 <6502_functional_test.bin> [instr-budget]\n` )
        ( nurl_print `       c64 --boot <kernal> <basic> <chargen> [frames]\n` )
        ^ 2
    } {}
    : ~ s a1 ``
    ?? ( vec_get [String] args 1 ) { T a → = a1 ( string_data a )  F _ → {} }
    ? ( nurl_str_eq a1 `--boot` ) {
        ? < ( vec_len [String] args ) 5 { ( nurl_print `usage: c64 --boot <kernal> <basic> <chargen> [frames]\n` )  ^ 2 } {}
        : ~ s kp ``  : ~ s bp ``  : ~ s cp ``
        : ~ i frames 150         // ~3 s emulated — enough to reach the READY prompt
        ?? ( vec_get [String] args 2 ) { T a → = kp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 3 ) { T a → = bp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 4 ) { T a → = cp ( string_data a )  F _ → {} }
        ? > ( vec_len [String] args ) 5 {
            ?? ( vec_get [String] args 5 ) { T a → = frames ( nurl_str_to_int ( string_data a ) )  F _ → {} }
        } {}
        ^ ( run_boot kp bp cp frames )
    } {}
    : ~ s path ``
    ?? ( vec_get [String] args 1 ) { T a → = path ( string_data a )  F _ → {} }
    : ~ i budget 200000000
    ? > ( vec_len [String] args ) 2 {
        ?? ( vec_get [String] args 2 ) { T b → = budget ( nurl_str_to_int ( string_data b ) )  F _ → {} }
    } {}
    ^ ( run_test path budget 0x3469 )
}
