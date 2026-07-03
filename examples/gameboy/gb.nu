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
                = guard + guard ( cpu_advance )
            }
            ( ppu_dump )
            ^ 0
        }
    }
}

// `gb <rom> --audio <frames> [out.pcm]` runs N frames and writes the APU
// output as raw interleaved 16-bit little-endian stereo PCM (48 kHz) — for
// verifying sound generation (plot/play with `ffplay -f s16le -ar 48000
// -ch_layout stereo out.pcm`).
@ audio_dump s path i frames s outpath → i {
    : !( Vec u ) IoErr rr ( read_file_bytes path )
    ?? rr {
        F _ → { ( nurl_print `cannot read ROM\n` ) ^ 2 }
        T rom → { ( cart_load ( vec_data [u] rom ) ( vec_len [u] rom ) ) ( vec_free [u] rom ) }
    }
    : ( Vec u ) pcm ( vec_new [u] )
    : ~ i nz 0
    : ~ i fi 0
    ~ < fi frames {
        ( run_one_frame )
        : ~ i i 0
        ~ < i g_audio_len {
            : i s ( nurl_peek g_audio i )
            : i l & s 0xFFFF
            : i r & >> s 16 0xFFFF
            ? != 0 l { = nz + nz 1 } {}
            ( vec_push [u] pcm # u & l 255 ) ( vec_push [u] pcm # u & >> l 8 255 )
            ( vec_push [u] pcm # u & r 255 ) ( vec_push [u] pcm # u & >> r 8 255 )
            = i + i 1
        }
        = g_audio_len 0
        = fi + fi 1
    }
    ?? ( write_file_bytes outpath pcm ) { T _ → {} F _ → { ( nurl_print `write failed\n` ) } }
    ( nurl_print `wrote ` ) ( nurl_print ( nurl_str_int ( vec_len [u] pcm ) ) )
    ( nurl_print ` PCM bytes, nonzero-L samples: ` ) ( nurl_print ( nurl_str_int nz ) ) ( nurl_print `\n` )
    ( vec_free [u] pcm )
    ^ 0
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
                // it (clearing g_halt). cpu_advance clocks timer + PPU.
                = g_cycles + g_cycles ( cpu_advance )
                = instr + instr 1
                // Check the captured serial text for a verdict.
                ? != 0 & instr 0x3FFF {} {
                    ? ( contains_word g_serial `Passed` ) { = status 0 = done 1 } {}
                    ? ( contains_word g_serial `Failed` ) { = status 1 = done 1 } {}
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
    ?? ( vec_get [String] args 1 ) { T a → = path ( string_data a ) F _ → {} }
    // PPU dump mode: `gb <rom> --ppu [frames]`.
    : ~ b ppu_mode F
    : ~ i frames 60
    ? > ( vec_len [String] args ) 2 {
        ?? ( vec_get [String] args 2 ) {
            T b → {
                ? ( nurl_str_eq ( string_data b ) `--ppu` ) {
                    = ppu_mode T
                    ? > ( vec_len [String] args ) 3 {
                        ?? ( vec_get [String] args 3 ) { T f → = frames ( nurl_str_to_int ( string_data f ) ) F _ → {} }
                    } {}
                } {}
            }
            F _ → {}
        }
    } {}
    ? ppu_mode { ^ ( run_rom_ppu path frames ) } {}
    // Audio dump mode: `gb <rom> --audio <frames> [out.pcm]`.
    : ~ b audio_mode F
    ?? ( vec_get [String] args 2 ) { T b → ? ( nurl_str_eq ( string_data b ) `--audio` ) { = audio_mode T } {} F _ → {} }
    ? audio_mode {
        : ~ i af 300
        : ~ s ap `gb_audio.pcm`
        ?? ( vec_get [String] args 3 ) { T b → = af ( nurl_str_to_int ( string_data b ) ) F _ → {} }
        ?? ( vec_get [String] args 4 ) { T b → = ap ( string_data b ) F _ → {} }
        ^ ( audio_dump path af ap )
    } {}
    : ~ i budget 300000000
    ? > ( vec_len [String] args ) 2 {
        ?? ( vec_get [String] args 2 ) { T b → = budget ( nurl_str_to_int ( string_data b ) ) F _ → {} }
    } {}
    ^ ( run_rom path budget )
}
