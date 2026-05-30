// examples/gameboy/gb.nu — a cycle-aware Game Boy (DMG) emulator core.
//
// Milestone 1+2: cartridge load + flat MMU (serial capture, timer,
// interrupts) + the full Sharp LR35902 CPU (every opcode + CB-prefix,
// exact Z/N/H/C flags, DAA). Validated headlessly against Blargg's
// `cpu_instrs` test ROMs, which report results over the serial port
// (0xFF01/0xFF02) — we capture that and look for "Passed" / "Failed".
//
// Run:  ./gb roms/01-special.gb
//       ./gb roms/cpu_instrs.gb 250000000
//
// The optional second argument is an instruction budget (default large).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

// ── Machine state (single instance — module globals) ──────────────
: s g_mem 0            // 64 KiB flat address space (*u, held as s)
: i ra 0
: i rf 0
: i rb 0
: i rc 0
: i rd 0
: i re 0
: i rh 0
: i rl 0
: i sp 0
: i pc 0
: i g_ime 0           // interrupt master enable
: i g_ime_next 0      // EI enables IME after the FOLLOWING instruction
: i g_halt 0
: i g_halt_bug 0      // HALT with IME=0 and a pending interrupt
: i g_div 0           // internal 16-bit divider; DIV is its high byte
: i g_tima_sub 0      // accumulated cycles toward the next TIMA tick
: i g_cycles 0
: String g_serial 0   // captured serial output

// ── Flag register helpers (F = Z N H C 0 0 0 0) ──────────────────
@ set_flags i z i n i h i c → v {
    : ~ i f 0
    ? != z 0 { = f | f 0x80 } {}
    ? != n 0 { = f | f 0x40 } {}
    ? != h 0 { = f | f 0x20 } {}
    ? != c 0 { = f | f 0x10 } {}
    = rf f
}
@ flag_z → i { ^ ? != 0 & rf 0x80 1 0 }
@ flag_n → i { ^ ? != 0 & rf 0x40 1 0 }
@ flag_h → i { ^ ? != 0 & rf 0x20 1 0 }
@ flag_c → i { ^ ? != 0 & rf 0x10 1 0 }

// ── Memory ────────────────────────────────────────────────────────
@ mem_raw → *u { ^ # *u g_mem }

@ rd8 i addr → i {
    : i a & addr 0xFFFF
    // Joypad: report "nothing pressed".
    ? == a 0xFF00 { ^ 0xCF } {}
    : *u m ( mem_raw )
    ^ & # i . m a 255
}

@ wr8 i addr i val → v {
    : i a & addr 0xFFFF
    : i b & val 0xFF
    // Cartridge ROM is read-only on a 32 KiB (MBC-less) cart.
    ? < a 0x8000 { ^ v } {}
    : *u m ( mem_raw )
    // Serial: writing 0x81 to SC starts a transfer; emit SB and ack.
    ? == a 0xFF02 {
        ? == & b 0x81 0x81 {
            : i sb & # i . m 0xFF01 255
            ( string_push_char g_serial sb )
            = . m 0xFF01 # u 0xFF
            = . m 0xFF02 # u & b 0x7F
            // Request the serial interrupt.
            = . m 0xFF0F # u | & # i . m 0xFF0F 255 0x08
            ^ v
        } {}
        = . m a # u b
        ^ v
    } {}
    // DIV: any write resets the whole internal divider.
    ? == a 0xFF04 { = g_div 0  = . m 0xFF04 # u 0  ^ v } {}
    = . m a # u b
    ^ v
}

@ rd16 i addr → i { ^ | ( rd8 addr ) << ( rd8 + addr 1 ) 8 }
@ wr16 i addr i v → v {
    ( wr8 addr & v 0xFF )
    ( wr8 + addr 1 & >> v 8 0xFF )
}

@ fetch8 → i { : i v ( rd8 pc )  = pc & + pc 1 0xFFFF  ^ v }
@ fetch16 → i { : i v ( rd16 pc )  = pc & + pc 2 0xFFFF  ^ v }

// ── 16-bit register pairs ────────────────────────────────────────
@ get_bc → i { ^ | << rb 8 rc }
@ get_de → i { ^ | << rd 8 re }
@ get_hl → i { ^ | << rh 8 rl }
@ get_af → i { ^ | << ra 8 rf }
@ set_bc i v → v { = rb & >> v 8 0xFF  = rc & v 0xFF }
@ set_de i v → v { = rd & >> v 8 0xFF  = re & v 0xFF }
@ set_hl i v → v { = rh & >> v 8 0xFF  = rl & v 0xFF }
@ set_af i v → v { = ra & >> v 8 0xFF  = rf & v 0xF0 }

// 8-bit register file indexed 0..7 = B C D E H L (HL) A.
@ get_r i idx → i {
    ?? idx {
        0 → ^ rb
        1 → ^ rc
        2 → ^ rd
        3 → ^ re
        4 → ^ rh
        5 → ^ rl
        6 → ^ ( rd8 ( get_hl ) )
        7 → ^ ra
        _ → ^ 0
    }
}
@ set_r i idx i v → v {
    : i b & v 0xFF
    ?? idx {
        0 → = rb b
        1 → = rc b
        2 → = rd b
        3 → = re b
        4 → = rh b
        5 → = rl b
        6 → ( wr8 ( get_hl ) b )
        7 → = ra b
        _ → {}
    }
}

// ── Stack ────────────────────────────────────────────────────────
@ push16 i v → v {
    = sp & - sp 2 0xFFFF
    ( wr16 sp v )
}
@ pop16 → i {
    : i v ( rd16 sp )
    = sp & + sp 2 0xFFFF
    ^ v
}

// ── ALU on A ─────────────────────────────────────────────────────
@ alu_add i v → v {
    : i a ra
    : i r + a v
    ( set_flags ? == & r 0xFF 0 1 0 0 ? > + & a 0xF & v 0xF 0xF 1 0 ? > r 0xFF 1 0 )
    = ra & r 0xFF
}
@ alu_adc i v → v {
    : i a ra
    : i cy ( flag_c )
    : i r + + a v cy
    ( set_flags ? == & r 0xFF 0 1 0 0 ? > + + & a 0xF & v 0xF cy 0xF 1 0 ? > r 0xFF 1 0 )
    = ra & r 0xFF
}
@ alu_sub i v → v {
    : i a ra
    : i r - a v
    ( set_flags ? == & r 0xFF 0 1 0 1 ? < - & a 0xF & v 0xF 0 1 0 ? < r 0 1 0 )
    = ra & r 0xFF
}
@ alu_sbc i v → v {
    : i a ra
    : i cy ( flag_c )
    : i r - - a v cy
    ( set_flags ? == & r 0xFF 0 1 0 1 ? < - - & a 0xF & v 0xF cy 0 1 0 ? < r 0 1 0 )
    = ra & r 0xFF
}
@ alu_and i v → v {
    = ra & ra v
    ( set_flags ? == ra 0 1 0 0 1 0 )
}
@ alu_xor i v → v {
    = ra & ^^ ra v 0xFF
    ( set_flags ? == ra 0 1 0 0 0 0 )
}
@ alu_or i v → v {
    = ra & | ra v 0xFF
    ( set_flags ? == ra 0 1 0 0 0 0 )
}
@ alu_cp i v → v {
    : i a ra
    : i r - a v
    ( set_flags ? == & r 0xFF 0 1 0 1 ? < - & a 0xF & v 0xF 0 1 0 ? < r 0 1 0 )
}
@ alu i opn i v → v {
    ?? opn {
        0 → ( alu_add v )
        1 → ( alu_adc v )
        2 → ( alu_sub v )
        3 → ( alu_sbc v )
        4 → ( alu_and v )
        5 → ( alu_xor v )
        6 → ( alu_or v )
        7 → ( alu_cp v )
        _ → {}
    }
}

@ inc8 i v → i {
    : i r & + v 1 0xFF
    ( set_flags ? == r 0 1 0 0 ? == & v 0xF 0xF 1 0 ( flag_c ) )
    ^ r
}
@ dec8 i v → i {
    : i r & - v 1 0xFF
    ( set_flags ? == r 0 1 0 1 ? == & v 0xF 0 1 0 ( flag_c ) )
    ^ r
}
@ add_hl i rr → v {
    : i hl ( get_hl )
    : i r + hl rr
    ( set_flags ( flag_z ) 0 ? > + & hl 0xFFF & rr 0xFFF 0xFFF 1 0 ? > r 0xFFFF 1 0 )
    ( set_hl & r 0xFFFF )
}

// ── Rotates / shifts (the A-register fast forms) ─────────────────
@ do_rlca → v {
    : i c & >> ra 7 1
    = ra & | << ra 1 c 0xFF
    ( set_flags 0 0 0 c )
}
@ do_rrca → v {
    : i c & ra 1
    = ra & | >> ra 1 << c 7 0xFF
    ( set_flags 0 0 0 c )
}
@ do_rla → v {
    : i c & >> ra 7 1
    = ra & | << ra 1 ( flag_c ) 0xFF
    ( set_flags 0 0 0 c )
}
@ do_rra → v {
    : i c & ra 1
    = ra & | >> ra 1 << ( flag_c ) 7 0xFF
    ( set_flags 0 0 0 c )
}

@ do_daa → v {
    : ~ i a ra
    : ~ i adj 0
    : ~ i carry 0
    ? == ( flag_n ) 0 {
        ? | == ( flag_h ) 1 > & a 0xF 9 { = adj | adj 0x06 } {}
        ? | == ( flag_c ) 1 > a 0x99 { = adj | adj 0x60  = carry 1 } {}
        = a + a adj
    } {
        ? == ( flag_h ) 1 { = adj | adj 0x06 } {}
        ? == ( flag_c ) 1 { = adj | adj 0x60  = carry 1 } {}
        = a - a adj
    }
    = a & a 0xFF
    = ra a
    ( set_flags ? == a 0 1 0 ( flag_n ) 0 carry )
}

// ── CB-prefixed bit operations ───────────────────────────────────
@ cb_rlc i v → i { : i c & >> v 7 1  : i r & | << v 1 c 0xFF  ( set_flags ? == r 0 1 0 0 0 c )  ^ r }
@ cb_rrc i v → i { : i c & v 1  : i r & | >> v 1 << c 7 0xFF  ( set_flags ? == r 0 1 0 0 0 c )  ^ r }
@ cb_rl  i v → i { : i c & >> v 7 1  : i r & | << v 1 ( flag_c ) 0xFF  ( set_flags ? == r 0 1 0 0 0 c )  ^ r }
@ cb_rr  i v → i { : i c & v 1  : i r & | >> v 1 << ( flag_c ) 7 0xFF  ( set_flags ? == r 0 1 0 0 0 c )  ^ r }
@ cb_sla i v → i { : i c & >> v 7 1  : i r & << v 1 0xFF  ( set_flags ? == r 0 1 0 0 0 c )  ^ r }
@ cb_sra i v → i { : i c & v 1  : i r | & >> v 1 0x7F & v 0x80  ( set_flags ? == r 0 1 0 0 0 c )  ^ r }
@ cb_swap i v → i { : i r & | >> v 4 << v 4 0xFF  ( set_flags ? == r 0 1 0 0 0 0 )  ^ r }
@ cb_srl i v → i { : i c & v 1  : i r & >> v 1 0x7F  ( set_flags ? == r 0 1 0 0 0 c )  ^ r }

@ cb_op i opn i v → i {
    ?? opn {
        0 → ^ ( cb_rlc v )
        1 → ^ ( cb_rrc v )
        2 → ^ ( cb_rl v )
        3 → ^ ( cb_rr v )
        4 → ^ ( cb_sla v )
        5 → ^ ( cb_sra v )
        6 → ^ ( cb_swap v )
        7 → ^ ( cb_srl v )
        _ → ^ v
    }
}

@ exec_cb → i {
    : i op ( fetch8 )
    : i x & >> op 6 3      // 0=rot/shift 1=BIT 2=RES 3=SET
    : i y & >> op 3 7      // op index / bit number
    : i z & op 7           // register
    : i v ( get_r z )
    : ~ i cyc ? == z 6 16 8
    ?? x {
        0 → { ( set_r z ( cb_op y v ) ) }
        1 → {  // BIT y,r — Z = !(v & (1<<y)), N=0, H=1, C preserved
            ( set_flags ? == 0 & v << 1 y 1 0 0 1 ( flag_c ) )
            = cyc ? == z 6 12 8
        }
        2 → { ( set_r z & v ^^ << 1 y 0xFF ) }   // RES
        3 → { ( set_r z | v << 1 y ) }           // SET
        _ → {}
    }
    ^ cyc
}

// ── Interrupts ───────────────────────────────────────────────────
// Service the highest-priority pending+enabled interrupt, if IME.
// Returns cycles consumed (20 on dispatch, else 0).
@ service_interrupts → i {
    : i iflag ( rd8 0xFF0F )
    : i ie ( rd8 0xFFFF )
    : i pend & & iflag ie 0x1F
    ? == pend 0 { ^ 0 } {}
    // Any pending+enabled interrupt wakes HALT regardless of IME.
    = g_halt 0
    ? == g_ime 0 { ^ 0 } {}
    : ~ i bit 0
    : ~ i vec 0
    ? != 0 & pend 0x01 { = bit 0x01  = vec 0x40 }
    { ? != 0 & pend 0x02 { = bit 0x02  = vec 0x48 }
        { ? != 0 & pend 0x04 { = bit 0x04  = vec 0x50 }
            { ? != 0 & pend 0x08 { = bit 0x08  = vec 0x58 }
                { = bit 0x10  = vec 0x60 } } } }
    = g_ime 0
    ( wr8 0xFF0F & iflag ^^ bit 0xFF )
    ( push16 pc )
    = pc vec
    ^ 20
}

// ── Timer ────────────────────────────────────────────────────────
// DIV is the high byte of a 16-bit counter clocked every T-cycle.
// TIMA increments at the rate selected by TAC, overflowing to TMA and
// raising the timer interrupt.
@ tac_period i tac → i {
    ?? & tac 3 {
        0 → ^ 1024
        1 → ^ 16
        2 → ^ 64
        3 → ^ 256
        _ → ^ 1024
    }
}
@ tick_timer i cyc → v {
    : *u m ( mem_raw )
    = g_div & + g_div cyc 0xFFFF
    = . m 0xFF04 # u & >> g_div 8 0xFF
    : i tac & # i . m 0xFF07 255
    ? == & tac 0x04 0 { ^ v } {}
    : i period ( tac_period tac )
    = g_tima_sub + g_tima_sub cyc
    ~ >= g_tima_sub period {
        = g_tima_sub - g_tima_sub period
        : i t + & # i . m 0xFF05 255 1
        ? > t 0xFF {
            = . m 0xFF05 # u & # i . m 0xFF06 255
            = . m 0xFF0F # u | & # i . m 0xFF0F 255 0x04
        } {
            = . m 0xFF05 # u & t 0xFF
        }
    }
}

// ── Main instruction step. Returns T-cycles consumed. ────────────
@ step → i {
    // EI takes effect after the instruction following it.
    : i ime_apply g_ime_next
    = g_ime_next 0

    : i op ( fetch8 )
    // The HALT bug: PC fails to advance once after a HALT with IME=0
    // and a pending interrupt — re-read the same opcode byte.
    ? != g_halt_bug 0 { = g_halt_bug 0  = pc & - pc 1 0xFFFF } {}

    : ~ i cyc 4

    // LD r,r' block (0x40..0x7F, 0x76 = HALT).
    ? & >= op 0x40 <= op 0x7F {
        ? == op 0x76 {
            = g_halt 1
            ? == g_ime 0 {
                ? != 0 & & ( rd8 0xFF0F ) ( rd8 0xFFFF ) 0x1F { = g_halt_bug 1  = g_halt 0 } {}
            } {}
        } {
            ( set_r & >> op 3 7 ( get_r & op 7 ) )
            = cyc ? | == & op 7 6 == & >> op 3 7 6 8 4
        }
        ? != ime_apply 0 { = g_ime 1 } {}
        ^ cyc
    } {}

    // ALU A,r block (0x80..0xBF).
    ? & >= op 0x80 <= op 0xBF {
        ( alu & >> op 3 7 ( get_r & op 7 ) )
        = cyc ? == & op 7 6 8 4
        ? != ime_apply 0 { = g_ime 1 } {}
        ^ cyc
    } {}

    ?? op {
        0x00 → {}
        0x10 → { ( fetch8 ) }                                   // STOP (treat as 2-byte NOP)
        0x76 → {}                                               // (handled above)
        0xCB → { = cyc ( exec_cb ) }

        // 16-bit immediate loads.
        0x01 → { ( set_bc ( fetch16 ) ) = cyc 12 }
        0x11 → { ( set_de ( fetch16 ) ) = cyc 12 }
        0x21 → { ( set_hl ( fetch16 ) ) = cyc 12 }
        0x31 → { = sp ( fetch16 ) = cyc 12 }

        // LD (rr),A / LD A,(rr) and the HL+/HL- forms.
        0x02 → { ( wr8 ( get_bc ) ra ) = cyc 8 }
        0x12 → { ( wr8 ( get_de ) ra ) = cyc 8 }
        0x22 → { ( wr8 ( get_hl ) ra ) ( set_hl & + ( get_hl ) 1 0xFFFF ) = cyc 8 }
        0x32 → { ( wr8 ( get_hl ) ra ) ( set_hl & - ( get_hl ) 1 0xFFFF ) = cyc 8 }
        0x0A → { = ra ( rd8 ( get_bc ) ) = cyc 8 }
        0x1A → { = ra ( rd8 ( get_de ) ) = cyc 8 }
        0x2A → { = ra ( rd8 ( get_hl ) ) ( set_hl & + ( get_hl ) 1 0xFFFF ) = cyc 8 }
        0x3A → { = ra ( rd8 ( get_hl ) ) ( set_hl & - ( get_hl ) 1 0xFFFF ) = cyc 8 }

        // INC/DEC 16-bit.
        0x03 → { ( set_bc & + ( get_bc ) 1 0xFFFF ) = cyc 8 }
        0x13 → { ( set_de & + ( get_de ) 1 0xFFFF ) = cyc 8 }
        0x23 → { ( set_hl & + ( get_hl ) 1 0xFFFF ) = cyc 8 }
        0x33 → { = sp & + sp 1 0xFFFF = cyc 8 }
        0x0B → { ( set_bc & - ( get_bc ) 1 0xFFFF ) = cyc 8 }
        0x1B → { ( set_de & - ( get_de ) 1 0xFFFF ) = cyc 8 }
        0x2B → { ( set_hl & - ( get_hl ) 1 0xFFFF ) = cyc 8 }
        0x3B → { = sp & - sp 1 0xFFFF = cyc 8 }

        // INC/DEC 8-bit (operands B C D E H L (HL) A by opcode>>3).
        0x04 → { = rb ( inc8 rb ) }
        0x0C → { = rc ( inc8 rc ) }
        0x14 → { = rd ( inc8 rd ) }
        0x1C → { = re ( inc8 re ) }
        0x24 → { = rh ( inc8 rh ) }
        0x2C → { = rl ( inc8 rl ) }
        0x34 → { ( wr8 ( get_hl ) ( inc8 ( rd8 ( get_hl ) ) ) ) = cyc 12 }
        0x3C → { = ra ( inc8 ra ) }
        0x05 → { = rb ( dec8 rb ) }
        0x0D → { = rc ( dec8 rc ) }
        0x15 → { = rd ( dec8 rd ) }
        0x1D → { = re ( dec8 re ) }
        0x25 → { = rh ( dec8 rh ) }
        0x2D → { = rl ( dec8 rl ) }
        0x35 → { ( wr8 ( get_hl ) ( dec8 ( rd8 ( get_hl ) ) ) ) = cyc 12 }
        0x3D → { = ra ( dec8 ra ) }

        // LD r,d8.
        0x06 → { = rb ( fetch8 ) = cyc 8 }
        0x0E → { = rc ( fetch8 ) = cyc 8 }
        0x16 → { = rd ( fetch8 ) = cyc 8 }
        0x1E → { = re ( fetch8 ) = cyc 8 }
        0x26 → { = rh ( fetch8 ) = cyc 8 }
        0x2E → { = rl ( fetch8 ) = cyc 8 }
        0x36 → { ( wr8 ( get_hl ) ( fetch8 ) ) = cyc 12 }
        0x3E → { = ra ( fetch8 ) = cyc 8 }

        // Rotates on A.
        0x07 → { ( do_rlca ) }
        0x0F → { ( do_rrca ) }
        0x17 → { ( do_rla ) }
        0x1F → { ( do_rra ) }

        // Misc accumulator/flag ops.
        0x27 → { ( do_daa ) }
        0x2F → { = ra & ^^ ra 0xFF 0xFF  ( set_flags ( flag_z ) 1 1 ( flag_c ) ) }   // CPL
        0x37 → { ( set_flags ( flag_z ) 0 0 1 ) }                                      // SCF
        0x3F → { ( set_flags ( flag_z ) 0 0 ? == ( flag_c ) 0 1 0 ) }                  // CCF

        // ADD HL,rr.
        0x09 → { ( add_hl ( get_bc ) ) = cyc 8 }
        0x19 → { ( add_hl ( get_de ) ) = cyc 8 }
        0x29 → { ( add_hl ( get_hl ) ) = cyc 8 }
        0x39 → { ( add_hl sp ) = cyc 8 }

        // LD (a16),SP.
        0x08 → { : i a ( fetch16 )  ( wr16 a sp ) = cyc 20 }

        // Relative jumps.
        0x18 → { ( do_jr T ) = cyc 12 }
        0x20 → { = cyc ? ( do_jr == ( flag_z ) 0 ) 12 8 }
        0x28 → { = cyc ? ( do_jr == ( flag_z ) 1 ) 12 8 }
        0x30 → { = cyc ? ( do_jr == ( flag_c ) 0 ) 12 8 }
        0x38 → { = cyc ? ( do_jr == ( flag_c ) 1 ) 12 8 }

        // ALU A,d8.
        0xC6 → { ( alu_add ( fetch8 ) ) = cyc 8 }
        0xCE → { ( alu_adc ( fetch8 ) ) = cyc 8 }
        0xD6 → { ( alu_sub ( fetch8 ) ) = cyc 8 }
        0xDE → { ( alu_sbc ( fetch8 ) ) = cyc 8 }
        0xE6 → { ( alu_and ( fetch8 ) ) = cyc 8 }
        0xEE → { ( alu_xor ( fetch8 ) ) = cyc 8 }
        0xF6 → { ( alu_or ( fetch8 ) ) = cyc 8 }
        0xFE → { ( alu_cp ( fetch8 ) ) = cyc 8 }

        // PUSH / POP.
        0xC1 → { ( set_bc ( pop16 ) ) = cyc 12 }
        0xD1 → { ( set_de ( pop16 ) ) = cyc 12 }
        0xE1 → { ( set_hl ( pop16 ) ) = cyc 12 }
        0xF1 → { ( set_af ( pop16 ) ) = cyc 12 }
        0xC5 → { ( push16 ( get_bc ) ) = cyc 16 }
        0xD5 → { ( push16 ( get_de ) ) = cyc 16 }
        0xE5 → { ( push16 ( get_hl ) ) = cyc 16 }
        0xF5 → { ( push16 ( get_af ) ) = cyc 16 }

        // Absolute jumps.
        0xC3 → { = pc ( fetch16 ) = cyc 16 }
        0xE9 → { = pc ( get_hl ) }
        0xC2 → { = cyc ? ( do_jp == ( flag_z ) 0 ) 16 12 }
        0xCA → { = cyc ? ( do_jp == ( flag_z ) 1 ) 16 12 }
        0xD2 → { = cyc ? ( do_jp == ( flag_c ) 0 ) 16 12 }
        0xDA → { = cyc ? ( do_jp == ( flag_c ) 1 ) 16 12 }

        // CALL.
        0xCD → { : i a ( fetch16 )  ( push16 pc ) = pc a  = cyc 24 }
        0xC4 → { = cyc ? ( do_call == ( flag_z ) 0 ) 24 12 }
        0xCC → { = cyc ? ( do_call == ( flag_z ) 1 ) 24 12 }
        0xD4 → { = cyc ? ( do_call == ( flag_c ) 0 ) 24 12 }
        0xDC → { = cyc ? ( do_call == ( flag_c ) 1 ) 24 12 }

        // RET / RETI.
        0xC9 → { = pc ( pop16 ) = cyc 16 }
        0xD9 → { = pc ( pop16 ) = g_ime 1  = cyc 16 }
        0xC0 → { = cyc ? ( do_ret == ( flag_z ) 0 ) 20 8 }
        0xC8 → { = cyc ? ( do_ret == ( flag_z ) 1 ) 20 8 }
        0xD0 → { = cyc ? ( do_ret == ( flag_c ) 0 ) 20 8 }
        0xD8 → { = cyc ? ( do_ret == ( flag_c ) 1 ) 20 8 }

        // RST.
        0xC7 → { ( push16 pc ) = pc 0x00  = cyc 16 }
        0xCF → { ( push16 pc ) = pc 0x08  = cyc 16 }
        0xD7 → { ( push16 pc ) = pc 0x10  = cyc 16 }
        0xDF → { ( push16 pc ) = pc 0x18  = cyc 16 }
        0xE7 → { ( push16 pc ) = pc 0x20  = cyc 16 }
        0xEF → { ( push16 pc ) = pc 0x28  = cyc 16 }
        0xF7 → { ( push16 pc ) = pc 0x30  = cyc 16 }
        0xFF → { ( push16 pc ) = pc 0x38  = cyc 16 }

        // High RAM / IO direct loads.
        0xE0 → { ( wr8 + 0xFF00 ( fetch8 ) ra ) = cyc 12 }       // LDH (a8),A
        0xF0 → { = ra ( rd8 + 0xFF00 ( fetch8 ) ) = cyc 12 }     // LDH A,(a8)
        0xE2 → { ( wr8 + 0xFF00 rc ra ) = cyc 8 }                // LD (C),A
        0xF2 → { = ra ( rd8 + 0xFF00 rc ) = cyc 8 }              // LD A,(C)
        0xEA → { ( wr8 ( fetch16 ) ra ) = cyc 16 }               // LD (a16),A
        0xFA → { = ra ( rd8 ( fetch16 ) ) = cyc 16 }             // LD A,(a16)

        // SP arithmetic.
        0xE8 → { ( add_sp_e ) = cyc 16 }                         // ADD SP,r8
        0xF8 → { ( ld_hl_sp_e ) = cyc 12 }                       // LD HL,SP+r8
        0xF9 → { = sp ( get_hl ) = cyc 8 }                       // LD SP,HL

        // Interrupt enable/disable.
        0xF3 → { = g_ime 0  = g_ime_next 0 }                     // DI
        0xFB → { = g_ime_next 1 }                                // EI (delayed)

        _ → { ( bad_op op ) }
    }

    ? != ime_apply 0 { = g_ime 1 } {}
    ^ cyc
}

// Signed relative jump; `cond` gates the branch. Returns cond (so the
// caller can pick taken/not-taken cycles).
@ do_jr b cond → b {
    : i off ( fetch8 )
    ? cond {
        : i so ? > off 127 - off 256 off
        = pc & + pc so 0xFFFF
    } {}
    ^ cond
}
@ do_jp b cond → b {
    : i a ( fetch16 )
    ? cond { = pc a } {}
    ^ cond
}
@ do_call b cond → b {
    : i a ( fetch16 )
    ? cond { ( push16 pc ) = pc a } {}
    ^ cond
}
@ do_ret b cond → b {
    ? cond { = pc ( pop16 ) } {}
    ^ cond
}

// ADD SP,r8 — 16-bit SP plus a signed byte; flags from the low byte add.
@ add_sp_e → v {
    : i off ( fetch8 )
    : i so ? > off 127 - off 256 off
    : i r & + sp so 0xFFFF
    ( set_flags 0 0 ? > + & sp 0xF & off 0xF 0xF 1 0 ? > + & sp 0xFF & off 0xFF 0xFF 1 0 )
    = sp r
}
@ ld_hl_sp_e → v {
    : i off ( fetch8 )
    : i so ? > off 127 - off 256 off
    ( set_flags 0 0 ? > + & sp 0xF & off 0xF 0xF 1 0 ? > + & sp 0xFF & off 0xFF 0xFF 1 0 )
    ( set_hl & + sp so 0xFFFF )
}

@ bad_op i op → v {
    ( nurl_print `\nUNIMPLEMENTED opcode 0x` )
    ( nurl_print ( nurl_str_int op ) )
    ( nurl_print ` at pc=` ) ( nurl_print ( nurl_str_int pc ) ) ( nurl_print `\n` )
}

// ── Boot: post-DMG-bootrom register + IO state ───────────────────
@ boot_state → v {
    = ra 0x01  = rf 0xB0
    = rb 0x00  = rc 0x13
    = rd 0x00  = re 0xD8
    = rh 0x01  = rl 0x4D
    = sp 0xFFFE
    = pc 0x0100
    = g_ime 0
    : *u m ( mem_raw )
    = . m 0xFF05 # u 0x00     // TIMA
    = . m 0xFF06 # u 0x00     // TMA
    = . m 0xFF07 # u 0x00     // TAC
    = . m 0xFF0F # u 0xE1     // IF
    = . m 0xFF40 # u 0x91     // LCDC
    = . m 0xFF41 # u 0x85     // STAT
    = . m 0xFF44 # u 0x00     // LY
    = . m 0xFF47 # u 0xFC     // BGP
    = . m 0xFFFF # u 0x00     // IE
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
            = g_mem ( nurl_alloc 65536 )
            : *u m ( mem_raw )
            : i n ( vec_len [u] rom )
            : *u rp ( vec_data [u] rom )
            : i lim ? > n 0x8000 0x8000 n
            : ~ i i 0
            ~ < i lim { = . m i . rp i  = i + i 1 }
            ( vec_free [u] rom )
            = g_serial ( string_with_cap 256 )
            ( boot_state )

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
        ^ 2
    } {}
    : ~ s path ``
    ?? ( vec_get [String] args 1 ) { T a → = path ( string_data a )  F _ → {} }
    : ~ i budget 300000000
    ? > ( vec_len [String] args ) 2 {
        ?? ( vec_get [String] args 2 ) { T b → = budget ( nurl_str_to_int ( string_data b ) )  F _ → {} }
    } {}
    ^ ( run_rom path budget )
}
