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

// ── PRG mode: boot, load a .prg, autostart it, dump the text screen ──
@ load_rom_into s path i bank → b {       // bank: 0 kernal, 1 basic, 2 chargen
    ?? ( read_file_bytes path ) {
        T d → {
            ?? bank {
                0 → ( load_kernal ( vec_data [u] d ) ( vec_len [u] d ) )
                1 → ( load_basic ( vec_data [u] d ) ( vec_len [u] d ) )
                _ → ( load_chargen ( vec_data [u] d ) ( vec_len [u] d ) )
            }
            ( vec_free [u] d )
            ^ T
        }
        F _ → { ( nurl_print `cannot read ROM: ` ) ( nurl_print path ) ( nurl_print `\n` )  ^ F }
    }
}
@ run_prg s kpath s bpath s cpath s prog i frames → i {
    ( c64_alloc )
    ? ( load_rom_into kpath 0 ) {} { ^ 2 }
    ? ( load_rom_into bpath 1 ) {} { ^ 2 }
    ? ( load_rom_into cpath 2 ) {} { ^ 2 }
    ( c64_boot )
    : ~ i f 0
    ~ < f 150 { ( run_one_frame )  = f + f 1 }    // boot to READY first
    ?? ( read_file_bytes prog ) {
        T p → {
            : i addr ( prg_autostart ( vec_data [u] p ) ( vec_len [u] p ) )
            ( vec_free [u] p )
            ( nurl_print `loaded ` ) ( nurl_print prog ) ( nurl_print ` @ ` ) ( print_hex16 addr ) ( nurl_print `\n` )
        }
        F _ → { ( nurl_print `cannot read prg: ` ) ( nurl_print prog ) ( nurl_print `\n` )  ^ 2 }
    }
    : ~ i g 0
    ~ < g frames { ( run_one_frame )  = g + g 1 }
    ( nurl_print `--- screen ---\n` )
    ( screen_dump )
    ( render_frame )
    ( nurl_print `border top=` ) ( nurl_print ( nurl_str_int ( fb_color_at 5 5 ) ) )
    ( nurl_print ` border bottom=` ) ( nurl_print ( nurl_str_int ( fb_color_at 5 260 ) ) )
    ( nurl_print `  framebuffer colour histogram: ` ) ( fb_hist )
    ( nurl_print `collision D01E(spr-spr)=` ) ( nurl_print ( nurl_str_int ( rd8 0xD01E ) ) )
    ( nurl_print ` D01F(spr-bg)=` ) ( nurl_print ( nurl_str_int ( rd8 0xD01F ) ) ) ( nurl_print `\n` )
    // Capture a fresh window of SID output (the ring isn't drained natively).
    = g_audio_len 0
    : ~ i af 0
    ~ < af 5 { ( run_one_frame )  = af + af 1 }
    ( audio_stats )
    ^ 0
}

// ── Disk mode: boot, attach a .d64, autostart its first program ─────
@ run_d64 s kpath s bpath s cpath s dpath i frames → i {
    ( c64_alloc )
    ? ( load_rom_into kpath 0 ) {} { ^ 2 }
    ? ( load_rom_into bpath 1 ) {} { ^ 2 }
    ? ( load_rom_into cpath 2 ) {} { ^ 2 }
    ( c64_boot )
    : ~ i f 0
    ~ < f 150 { ( run_one_frame )  = f + f 1 }
    ?? ( read_file_bytes dpath ) {
        T d → {
            ( disk_attach ( vec_data [u] d ) ( vec_len [u] d ) )
            ( vec_free [u] d )
            : i addr ( disk_autostart )
            ( nurl_print `attached ` ) ( nurl_print dpath ) ( nurl_print `, autostarted @ ` ) ( print_hex16 addr ) ( nurl_print `\n` )
        }
        F _ → { ( nurl_print `cannot read d64: ` ) ( nurl_print dpath ) ( nurl_print `\n` )  ^ 2 }
    }
    : ~ i g 0
    ~ < g frames { ( run_one_frame )  = g + g 1 }
    ( nurl_print `--- screen ---\n` )
    ( screen_dump )
    ( render_frame )
    ( nurl_print `border top=` ) ( nurl_print ( nurl_str_int ( fb_color_at 5 5 ) ) )
    ( nurl_print ` bottom=` ) ( nurl_print ( nurl_str_int ( fb_color_at 5 260 ) ) )
    ( nurl_print `  hist: ` ) ( fb_hist )
    = g_audio_len 0
    : ~ i af 0
    ~ < af 5 { ( run_one_frame )  = af + af 1 }
    ( audio_stats )
    ^ 0
}

// Type a string into the KERNAL keyboard buffer (PETSCII), then run.
@ type_line s txt i frames → v {
    : i n ( nurl_str_len txt )
    : ~ i i 0
    ~ < i n {
        ( kbuf_push ( nurl_str_get txt i ) )
        ( run_one_frame )  ( run_one_frame )       // drip-feed so the buffer never overflows
        = i + i 1
    }
    ( kbuf_push 0x0D )
    : ~ i f 0
    ~ < f frames { ( run_one_frame )  = f + f 1 }
}
// Exercise the KERNAL LOAD trap: LOAD"$",8 then LIST the directory.
@ run_d64dir s kpath s bpath s cpath s dpath → i {
    ( c64_alloc )
    ? ( load_rom_into kpath 0 ) {} { ^ 2 }
    ? ( load_rom_into bpath 1 ) {} { ^ 2 }
    ? ( load_rom_into cpath 2 ) {} { ^ 2 }
    ( c64_boot )
    : ~ i f 0
    ~ < f 150 { ( run_one_frame )  = f + f 1 }
    ?? ( read_file_bytes dpath ) {
        T d → { ( disk_attach ( vec_data [u] d ) ( vec_len [u] d ) )  ( vec_free [u] d ) }
        F _ → { ( nurl_print `cannot read d64\n` )  ^ 2 }
    }
    ( type_line `LOAD"$",8` 40 )
    ( type_line `LIST` 40 )
    ( nurl_print `--- screen (directory) ---\n` )
    ( screen_dump )
    // Named LOAD + RUN of TONE.PRG (exercises disk_find by name).
    ( type_line `NEW` 10 )
    ( type_line `LOAD"TONE",8` 60 )
    ( type_line `RUN` 30 )
    = g_audio_len 0
    : ~ i af 0
    ~ < af 5 { ( run_one_frame )  = af + af 1 }
    ( nurl_print `after LOAD"TONE",8 : RUN — ` ) ( audio_stats )
    ^ 0
}

// Verify RUN/STOP+RESTORE: a .prg blacks the border, then the NMI warm-start
// restores it. (STOP = keyboard matrix col7/row7; RESTORE = the NMI line.)
@ run_nmi s kpath s bpath s cpath s prog → i {
    ( c64_alloc )
    ? ( load_rom_into kpath 0 ) {} { ^ 2 }
    ? ( load_rom_into bpath 1 ) {} { ^ 2 }
    ? ( load_rom_into cpath 2 ) {} { ^ 2 }
    ( c64_boot )
    : ~ i f 0
    ~ < f 150 { ( run_one_frame )  = f + f 1 }
    ?? ( read_file_bytes prog ) {
        T p → { ( prg_autostart ( vec_data [u] p ) ( vec_len [u] p ) )  ( vec_free [u] p ) }
        F _ → { ( nurl_print `cannot read prg\n` )  ^ 2 }
    }
    : ~ i g 0
    ~ < g 30 { ( run_one_frame )  = g + g 1 }
    ( render_frame )
    ( nurl_print `border after program = ` ) ( nurl_print ( nurl_str_int ( fb_color_at 5 5 ) ) ) ( nurl_print ` (program set it black)\n` )
    // Hold RUN/STOP (matrix col7,row7) and pulse RESTORE → NMI warm-start.
    : *u kb # *u g_kb
    = . kb 7 # u 0x80
    = g_restore 1
    ( run_one_frame )
    = g_restore 0
    : ~ i h 0
    ~ < h 30 { ( run_one_frame )  = h + h 1 }
    = . kb 7 # u 0
    : ~ i j 0
    ~ < j 10 { ( run_one_frame )  = j + j 1 }
    ( render_frame )
    ( nurl_print `border after RUN/STOP+RESTORE = ` ) ( nurl_print ( nurl_str_int ( fb_color_at 5 5 ) ) ) ( nurl_print ` (warm-start should restore 14)\n` )
    ^ 0
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    ? < ( vec_len [String] args ) 2 {
        ( nurl_print `usage: c64 <6502_functional_test.bin> [instr-budget]\n` )
        ( nurl_print `       c64 --boot <kernal> <basic> <chargen> [frames]\n` )
        ( nurl_print `       c64 --prg <kernal> <basic> <chargen> <prog.prg> [frames]\n` )
        ( nurl_print `       c64 --d64 <kernal> <basic> <chargen> <disk.d64> [frames]\n` )
        ^ 2
    } {}
    : ~ s a0 ``
    ?? ( vec_get [String] args 1 ) { T a → = a0 ( string_data a )  F _ → {} }
    ? ( nurl_str_eq a0 `--nmi` ) {
        ? < ( vec_len [String] args ) 6 { ( nurl_print `usage: c64 --nmi <k> <b> <c> <prog.prg>\n` )  ^ 2 } {}
        : ~ s kp ``  : ~ s bp ``  : ~ s cp ``  : ~ s pg ``
        ?? ( vec_get [String] args 2 ) { T a → = kp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 3 ) { T a → = bp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 4 ) { T a → = cp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 5 ) { T a → = pg ( string_data a )  F _ → {} }
        ^ ( run_nmi kp bp cp pg )
    } {}
    ? ( nurl_str_eq a0 `--d64dir` ) {
        ? < ( vec_len [String] args ) 6 { ( nurl_print `usage: c64 --d64dir <k> <b> <c> <disk.d64>\n` )  ^ 2 } {}
        : ~ s kp ``  : ~ s bp ``  : ~ s cp ``  : ~ s dp ``
        ?? ( vec_get [String] args 2 ) { T a → = kp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 3 ) { T a → = bp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 4 ) { T a → = cp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 5 ) { T a → = dp ( string_data a )  F _ → {} }
        ^ ( run_d64dir kp bp cp dp )
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
    ? ( nurl_str_eq a1 `--prg` ) {
        ? < ( vec_len [String] args ) 6 { ( nurl_print `usage: c64 --prg <kernal> <basic> <chargen> <prog.prg> [frames]\n` )  ^ 2 } {}
        : ~ s kp ``  : ~ s bp ``  : ~ s cp ``  : ~ s pg ``
        : ~ i frames 120
        ?? ( vec_get [String] args 2 ) { T a → = kp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 3 ) { T a → = bp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 4 ) { T a → = cp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 5 ) { T a → = pg ( string_data a )  F _ → {} }
        ? > ( vec_len [String] args ) 6 {
            ?? ( vec_get [String] args 6 ) { T a → = frames ( nurl_str_to_int ( string_data a ) )  F _ → {} }
        } {}
        ^ ( run_prg kp bp cp pg frames )
    } {}
    ? ( nurl_str_eq a1 `--d64` ) {
        ? < ( vec_len [String] args ) 6 { ( nurl_print `usage: c64 --d64 <kernal> <basic> <chargen> <disk.d64> [frames]\n` )  ^ 2 } {}
        : ~ s kp ``  : ~ s bp ``  : ~ s cp ``  : ~ s dp ``
        : ~ i frames 180
        ?? ( vec_get [String] args 2 ) { T a → = kp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 3 ) { T a → = bp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 4 ) { T a → = cp ( string_data a )  F _ → {} }
        ?? ( vec_get [String] args 5 ) { T a → = dp ( string_data a )  F _ → {} }
        ? > ( vec_len [String] args ) 6 {
            ?? ( vec_get [String] args 6 ) { T a → = frames ( nurl_str_to_int ( string_data a ) )  F _ → {} }
        } {}
        ^ ( run_d64 kp bp cp dp frames )
    } {}
    : ~ s path ``
    ?? ( vec_get [String] args 1 ) { T a → = path ( string_data a )  F _ → {} }
    : ~ i budget 200000000
    ? > ( vec_len [String] args ) 2 {
        ?? ( vec_get [String] args 2 ) { T b → = budget ( nurl_str_to_int ( string_data b ) )  F _ → {} }
    } {}
    ^ ( run_test path budget 0x3469 )
}
