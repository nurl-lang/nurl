// examples/gameboy/gb.nu — native CLI front-end for the GB emulator.
//
// Run:  ./gb roms/01-special.gb            (serial-watching test runner)
//       ./gb roms/dmg-acid2.gb --ppu 40    (render N frames, dump framebuffer)

$ `examples/gameboy/core.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

@ ppu_dump → v {
    : *u fb # *u g_fb
    : String row ( string_with_cap 168 )
    : ~ i y 0
    ~ < y 144 {
        ( string_clear row )
        : ~ i x 0
        ~ < x 160 {
            ( string_push_char row + 48 & # i . fb + * y 160 x 255 )
            = x + x 1
        }
        ( nurl_print ( string_data row ) ) ( nurl_print `\n` )
        = y + y 1
    }
    ( string_free row )
}

@ run_rom_ppu s path i frames → i {
    : !( Vec u ) IoErr rr ( read_file_bytes path )
    ?? rr {
        F _ → { ( nurl_print `cannot read ROM\n` ) ^ 2 }
        T rom → {
            ( cart_load ( vec_data [u] rom ) ( vec_len [u] rom ) )
            ( vec_free [u] rom )
            : ~ i guard 0
            ~ & < g_frames frames < guard 2000000000 {
                : ~ i used 4
                ? == g_halt 0 { = used ( step ) } {}
                ( tick_timer used )
                ( tick_ppu used )
                ( service_interrupts )
                = guard + guard used
            }
            ( ppu_dump )
            ^ 0
        }
    }
}

// ── Run a test ROM headlessly, watching the serial output ────────
@ contains_word String hay s needle → b {
    : i hn ( string_len hay )
    : i nn ( nurl_str_len needle )
    ? > nn hn { ^ F } {}
    : s hd ( string_data hay )
    : ~ i i 0
    ~ <= i - hn nn {
        : ~ i j 0
        : ~ b match T
        ~ & < j nn match {
            ? != ( nurl_str_get hd + i j ) ( nurl_str_get needle j ) { = match F } {}
            = j + j 1
        }
        ? match { ^ T } {}
        = i + i 1
    }
    ^ F
}

@ run_rom s path i budget → i {
    : !( Vec u ) IoErr rr ( read_file_bytes path )
    : ~ i status 2
    ?? rr {
        F _ → {
            ( nurl_print `cannot read ROM: ` ) ( nurl_print path ) ( nurl_print `\n` )
            = status 2
        }
        T rom → {
            ( cart_load ( vec_data [u] rom ) ( vec_len [u] rom ) )
            ( vec_free [u] rom )

            : ~ i instr 0
            : ~ i done 0
            ~ & == done 0 < instr budget {
                // While halted the CPU executes nothing — it idles 4
                // T-cycles per loop, keeping the timer running, until
                // `service_interrupts` sees a pending interrupt and wakes
                // it (clearing g_halt).
                : ~ i used 4
                ? == g_halt 0 { = used ( step ) } {}
                ( tick_timer used )
                ( service_interrupts )
                = g_cycles + g_cycles used
                = instr + instr 1
                // Check the captured serial text for a verdict.
                ? != 0 & instr 0x3FFF {} {
                    ? ( contains_word g_serial `Passed` ) { = status 0  = done 1 } {}
                    ? ( contains_word g_serial `Failed` ) { = status 1  = done 1 } {}
                }
            }
            ( nurl_print `--- serial output ---\n` )
            ( nurl_print ( string_data g_serial ) )
            ( nurl_print `\n--- instructions: ` ) ( nurl_print ( nurl_str_int instr ) )
            ( nurl_print ` ---\n` )
        }
    }
    ^ status
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    ? < ( vec_len [String] args ) 2 {
        ( nurl_print `usage: gb <rom.gb> [instr-budget]\n` )
        ( nurl_print `       gb <rom.gb> --ppu [frames]   (render N frames, dump framebuffer)\n` )
        ^ 2
    } {}
    : ~ s path ``
    ?? ( vec_get [String] args 1 ) { T a → = path ( string_data a )  F _ → {} }
    // PPU dump mode: `gb <rom> --ppu [frames]`.
    : ~ b ppu_mode F
    : ~ i frames 60
    ? > ( vec_len [String] args ) 2 {
        ?? ( vec_get [String] args 2 ) {
            T b → {
                ? ( nurl_str_eq ( string_data b ) `--ppu` ) {
                    = ppu_mode T
                    ? > ( vec_len [String] args ) 3 {
                        ?? ( vec_get [String] args 3 ) { T f → = frames ( nurl_str_to_int ( string_data f ) )  F _ → {} }
                    } {}
                } {}
            }
            F _ → {}
        }
    } {}
    ? ppu_mode { ^ ( run_rom_ppu path frames ) } {}
    : ~ i budget 300000000
    ? > ( vec_len [String] args ) 2 {
        ?? ( vec_get [String] args 2 ) { T b → = budget ( nurl_str_to_int ( string_data b ) )  F _ → {} }
    } {}
    ^ ( run_rom path budget )
}
