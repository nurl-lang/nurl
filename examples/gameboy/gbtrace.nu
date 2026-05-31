// examples/gameboy/gbtrace.nu — diagnostic front-end for the GB emulator.
// Lock-step / fingerprint / state-injection harness used to debug game
// divergence against a reference emulator (pyboy). Not part of the demo.
//
//   gb <rom> --fp <nf>                 per-frame WRAM/VRAM/OAM + IO fingerprint
//   gb <rom> --inject <state.bin>      load reference state, run 1 frame, dump
//   gb <rom> --injfree <state> <nf>    load state, free-run nf frames, dump each
//   gb <rom> --trace <fromframe> <ns>  per-instruction trace from a frame

$ `examples/gameboy/core.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

@ ls_hexd i n → i { ^ + ? < n 10 48 87 n }
@ ls_pushhex2 String s i b → v {
    ( string_push_char s ( ls_hexd & >> b 4 15 ) )
    ( string_push_char s ( ls_hexd & b 15 ) )
}
@ ls_pushhex4 String s i w → v {
    ( ls_pushhex2 s & >> w 8 255 )
    ( ls_pushhex2 s & w 255 )
}
@ ls_pushhex8 String s i w → v {
    ( ls_pushhex4 s & >> w 16 0xFFFF )
    ( ls_pushhex4 s & w 0xFFFF )
}
@ mem_sum * u m i lo i hi → i {
    : ~ i s 0
    : ~ i a lo
    ~ < a hi { = s + s & # i . m a 255  = a + a 1 }
    ^ s
}

// One full LCD frame of T-cycles, advancing CPU + timer + PPU + IRQs.
@ run_full_frame → v {
    : ~ i cyc 0
    ~ < cyc 70224 { = cyc + cyc ( cpu_advance ) }
}

@ fp_run s rompath i nf → i {
    : !( Vec u ) IoErr rr ( read_file_bytes rompath )
    ?? rr {
        F _ → { ( nurl_print `cannot read ROM\n` ) ^ 2 }
        T rom → { ( cart_load ( vec_data [u] rom ) ( vec_len [u] rom ) )  ( vec_free [u] rom ) }
    }
    : *u m2 ( mem_raw )
    : ~ i fi 0
    ~ < fi nf {
        ( run_one_frame )
        : String ln ( string_with_cap 128 )
        ( string_push_str ln `F` ) ( string_push_int ln fi )
        ( string_push_str ln ` LCDC=` ) ( ls_pushhex2 ln & # i . m2 0xFF40 255 )
        ( string_push_str ln ` LY=` ) ( ls_pushhex2 ln & # i . m2 0xFF44 255 )
        ( string_push_str ln ` IF=` ) ( ls_pushhex2 ln & # i . m2 0xFF0F 255 )
        ( string_push_str ln ` IE=` ) ( ls_pushhex2 ln & # i . m2 0xFFFF 255 )
        ( string_push_str ln ` WRAM=` ) ( ls_pushhex8 ln ( mem_sum m2 0xC000 0xE000 ) )
        ( string_push_str ln ` VRAM=` ) ( ls_pushhex8 ln ( mem_sum m2 0x8000 0xA000 ) )
        ( string_push_str ln ` OAM=` ) ( ls_pushhex8 ln ( mem_sum m2 0xFE00 0xFEA0 ) )
        ( string_push_char ln 10 ) ( nurl_print ( string_data ln ) )
        ( string_free ln )
        = fi + fi 1
    }
    ^ 0
}

@ inject_apply * u s2 i nframes → i {
    : i h0 | & # i . s2 0 255 << & # i . s2 1 255 8
    : i h1 | & # i . s2 2 255 << & # i . s2 3 255 8
    : i h2 | & # i . s2 4 255 << & # i . s2 5 255 8
    : i h3 | & # i . s2 6 255 << & # i . s2 7 255 8
    : i h4 | & # i . s2 8 255 << & # i . s2 9 255 8
    : i h5 | & # i . s2 10 255 << & # i . s2 11 255 8
    : i h6 | & # i . s2 12 255 << & # i . s2 13 255 8
    : i h7 | & # i . s2 14 255 << & # i . s2 15 255 8
    : i h8 | & # i . s2 16 255 << & # i . s2 17 255 8
    : i h9 | & # i . s2 18 255 << & # i . s2 19 255 8
    : i h10 | & # i . s2 20 255 << & # i . s2 21 255 8
    : i h11 | & # i . s2 22 255 << & # i . s2 23 255 8
    : i h12 | & # i . s2 24 255 << & # i . s2 25 255 8
    : i h13 | & # i . s2 26 255 << & # i . s2 27 255 8
    : i h14 | & # i . s2 28 255 << & # i . s2 29 255 8
    = ra h0  = rf h1  = rb h2  = rc h3  = rd h4  = re h5  = rh h6  = rl h7
    = sp h8  = pc h9  = g_div h10  = g_rombank h11  = g_rambank h12  = g_ram_en h13  = g_mode h14
    = g_ime 1  = g_halt 0  = g_dot 0
    : *u m ( mem_raw )
    : ~ i i 0x8000
    ~ < i 0x10000 { = . m i # u & # i . s2 + 30 - i 0x8000 255  = i + i 1 }
    : ~ i fr 0
    ~ < fr nframes {
        ( run_full_frame )
        ? > nframes 1 {
            : *u mf ( mem_raw )
            : String fl ( string_with_cap 64 )
            ( string_push_str fl `f` ) ( string_push_int fl fr )
            ( string_push_str fl ` W=` ) ( ls_pushhex8 fl ( mem_sum mf 0xC000 0xDF00 ) )
            ( string_push_str fl ` V=` ) ( ls_pushhex8 fl ( mem_sum mf 0x8000 0xA000 ) )
            ( string_push_str fl ` O=` ) ( ls_pushhex8 fl ( mem_sum mf 0xFE00 0xFEA0 ) )
            ( string_push_char fl 10 ) ( nurl_print ( string_data fl ) ) ( string_free fl )
        } {}
        = fr + fr 1
    }
    : *u m2 ( mem_raw )
    : String ln ( string_with_cap 160 )
    ( string_push_str ln `A=` ) ( ls_pushhex2 ln ra ) ( ls_pushhex2 ln rf )
    ( string_push_str ln ` BC=` ) ( ls_pushhex2 ln rb ) ( ls_pushhex2 ln rc )
    ( string_push_str ln ` HL=` ) ( ls_pushhex2 ln rh ) ( ls_pushhex2 ln rl )
    ( string_push_str ln ` SP=` ) ( ls_pushhex4 ln sp )
    ( string_push_str ln ` PC=` ) ( ls_pushhex4 ln pc )
    ( string_push_str ln ` WRAM=` ) ( ls_pushhex8 ln ( mem_sum m2 0xC000 0xE000 ) )
    ( string_push_str ln ` VRAM=` ) ( ls_pushhex8 ln ( mem_sum m2 0x8000 0xA000 ) )
    ( string_push_str ln ` OAM=` ) ( ls_pushhex8 ln ( mem_sum m2 0xFE00 0xFEA0 ) )
    ( string_push_char ln 10 ) ( nurl_print ( string_data ln ) )
    ( string_clear ln )
    : ~ i a 0xC000
    ~ < a 0xE000 {
        ( ls_pushhex2 ln & # i . m2 a 255 )
        = a + a 1
        ? == 0 & a 63 { ( nurl_print ( string_data ln ) ) ( string_clear ln ) } {}
    }
    ( string_push_char ln 10 ) ( nurl_print ( string_data ln ) )
    ( string_free ln )
    ^ 0
}

@ inject_run s rompath s statepath i nframes → i {
    : !( Vec u ) IoErr rr ( read_file_bytes rompath )
    ?? rr {
        F _ → { ( nurl_print `cannot read ROM\n` ) ^ 2 }
        T rom → { ( cart_load ( vec_data [u] rom ) ( vec_len [u] rom ) )  ( vec_free [u] rom ) }
    }
    : !( Vec u ) IoErr sr ( read_file_bytes statepath )
    ?? sr {
        F _ → { ( nurl_print `cannot read state\n` ) ^ 2 }
        T st → { ^ ( inject_apply ( vec_data [u] st ) nframes ) }
    }
    ^ 0
}

@ trace_run s rompath i fromf i nsteps → i {
    : !( Vec u ) IoErr rr ( read_file_bytes rompath )
    ?? rr {
        F _ → { ( nurl_print `cannot read ROM\n` ) ^ 2 }
        T rom → { ( cart_load ( vec_data [u] rom ) ( vec_len [u] rom ) )  ( vec_free [u] rom ) }
    }
    ~ < g_frames fromf { ( run_one_frame ) }
    : ~ i k 0
    ~ < k nsteps {
        : String ln ( string_with_cap 96 )
        ( string_push_str ln `B` ) ( ls_pushhex2 ln g_rombank )
        ( string_push_str ln ` PC=` ) ( ls_pushhex4 ln pc )
        ( string_push_str ln ` OP=` ) ( ls_pushhex2 ln ( rd8 pc ) )
        ( string_push_str ln ` AF=` ) ( ls_pushhex2 ln ra ) ( ls_pushhex2 ln rf )
        ( string_push_str ln ` BC=` ) ( ls_pushhex2 ln rb ) ( ls_pushhex2 ln rc )
        ( string_push_str ln ` DE=` ) ( ls_pushhex2 ln rd ) ( ls_pushhex2 ln re )
        ( string_push_str ln ` HL=` ) ( ls_pushhex2 ln rh ) ( ls_pushhex2 ln rl )
        ( string_push_str ln ` SP=` ) ( ls_pushhex4 ln sp )
        ( string_push_char ln 10 ) ( nurl_print ( string_data ln ) )
        ( string_free ln )
        : ~ i used 4
        ? == g_halt 0 { = used ( step ) } {}
        ( tick_timer used )
        ( tick_ppu used )
        : i ic ( service_interrupts )
        ? != ic 0 { ( tick_timer ic ) ( tick_ppu ic ) } {}
        = k + k 1
    }
    ^ 0
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    ? < ( vec_len [String] args ) 4 {
        ( nurl_print `usage: gbtrace <rom> --fp|--inject|--injfree|--trace <arg> [arg2]\n` )
        ^ 2
    } {}
    : ~ s path ``
    : ~ s mode ``
    ?? ( vec_get [String] args 1 ) { T a → = path ( string_data a )  F _ → {} }
    ?? ( vec_get [String] args 2 ) { T a → = mode ( string_data a )  F _ → {} }
    ? ( nurl_str_eq mode `--fp` ) {
        : ~ i nf 200
        ?? ( vec_get [String] args 3 ) { T b → = nf ( nurl_str_to_int ( string_data b ) )  F _ → {} }
        ^ ( fp_run path nf )
    } {}
    ? ( nurl_str_eq mode `--inject` ) {
        : ~ s sp ``
        ?? ( vec_get [String] args 3 ) { T b → = sp ( string_data b )  F _ → {} }
        ^ ( inject_run path sp 1 )
    } {}
    ? ( nurl_str_eq mode `--injfree` ) {
        : ~ s sp ``
        : ~ i nf 1
        ?? ( vec_get [String] args 3 ) { T b → = sp ( string_data b )  F _ → {} }
        ?? ( vec_get [String] args 4 ) { T b → = nf ( nurl_str_to_int ( string_data b ) )  F _ → {} }
        ^ ( inject_run path sp nf )
    } {}
    ? ( nurl_str_eq mode `--trace` ) {
        : ~ i ff 0
        : ~ i ns 100
        ?? ( vec_get [String] args 3 ) { T b → = ff ( nurl_str_to_int ( string_data b ) )  F _ → {} }
        ?? ( vec_get [String] args 4 ) { T b → = ns ( nurl_str_to_int ( string_data b ) )  F _ → {} }
        ^ ( trace_run path ff ns )
    } {}
    ( nurl_print `unknown mode\n` )
    ^ 2
}
