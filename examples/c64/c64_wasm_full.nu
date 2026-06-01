// examples/c64/core.nu — MOS 6510 (6502) CPU core, in pure NURL.
//
// The engine for the Commodore 64 emulator. This first milestone is the
// CPU: the full documented 6502/6510 instruction set with exact
// N/V/Z/C/D flag semantics, the NMOS decimal-mode ADC/SBC, the JMP
// ($nnnn) page-wrap bug, and cycle-aware stepping. It is validated
// headlessly against Klaus Dormann's 6502 functional test — the
// canonical correctness oracle for 6502 emulation — exactly the way the
// Game Boy core (examples/gameboy/core.nu) is validated against Blargg's
// cpu_instrs.
//
// State lives as module globals (the natural shape for a single machine).
// Memory is a flat 64 KiB space for now; the PLA banking ($0001 →
// KERNAL/BASIC/CHARGEN/IO) and the VIC-II / SID / CIA chips layer on top
// in later milestones without disturbing this CPU.

$ `stdlib/core/string.nu`

// ── CPU registers ───────────────────────────────────────────────────
: i ra 0            // accumulator
: i rx 0            // index X
: i ry 0            // index Y
: i sp 0xFD         // stack pointer (stack lives at 0x0100..0x01FF)
: i pc 0            // program counter
: i rp 0x24         // processor status: N V - B D I Z C (bit5 always 1)

// Status-bit masks.
//   C 0x01  Z 0x02  I 0x04  D 0x08  B 0x10  U 0x20  V 0x40  N 0x80

: i g_cycles 0      // total T-cycles executed

// ── Memory ──────────────────────────────────────────────────────────
: s g_mem 0         // 64 KiB flat RAM (*u, held as s)
: s g_kernal 0      // 8 KiB KERNAL ROM   ($E000-$FFFF)
: s g_basic 0       // 8 KiB BASIC ROM    ($A000-$BFFF)
: s g_chargen 0     // 4 KiB character ROM ($D000-$DFFF when CHAREN=0)
: s g_color 0       // 1 KiB colour RAM   ($D800-$DBFF)
: i g_banked 0      // 0 = flat RAM (CPU test); 1 = full C64 PLA map
: i g_p01_ddr 0     // $0000 CPU-port data-direction register
: i g_p01_data 0    // $0001 CPU-port data latch (banking bits 0-2)

@ mem_raw → *u { ^ # *u g_mem }

// Flat-RAM access (the byte under any ROM is always RAM).
@ ram_rd i a → i { : *u m ( mem_raw )  ^ & # i . m & a 0xFFFF 255 }
@ ram_wr i a i val → v { : *u m ( mem_raw )  = . m & a 0xFFFF # u & val 0xFF }
@ rom_rd s rom i off → i { : *u r # *u rom  ^ & # i . r off 255 }

// The $0001 read: output bits return the latch, input bits float high.
@ port01_read → i { ^ & | & g_p01_data g_p01_ddr & ^^ g_p01_ddr 0xFF 0xFF 0xFF }
@ bank_loram → i { ^ & ( port01_read ) 1 }        // BASIC ROM enable
@ bank_hiram → i { ^ & >> ( port01_read ) 1 1 }   // KERNAL ROM enable
@ bank_charen → i { ^ & >> ( port01_read ) 2 1 }  // I/O (1) vs CHARGEN (0)

// $D000-$DFFF mode: 0 = RAM, 1 = CHARGEN ROM, 2 = I/O.
@ io_mode → i {
    : i any | ( bank_loram ) ( bank_hiram )
    ? == any 0 { ^ 0 } {}
    ? != ( bank_charen ) 0 { ^ 2 } {}
    ^ 1
}

@ rd8 i addr → i {
    : i a & addr 0xFFFF
    ? == g_banked 0 { ^ ( ram_rd a ) } {}
    ? == a 0x0000 { ^ g_p01_ddr } {}
    ? == a 0x0001 { ^ ( port01_read ) } {}
    ? & >= a 0xA000 < a 0xC000 {                       // BASIC ROM / RAM
        ? & != ( bank_loram ) 0 != ( bank_hiram ) 0 { ^ ( rom_rd g_basic - a 0xA000 ) } {}
        ^ ( ram_rd a )
    } {}
    ? & >= a 0xD000 < a 0xE000 {                       // I/O / CHARGEN / RAM
        ?? ( io_mode ) {
            0 → ^ ( ram_rd a )
            1 → ^ ( rom_rd g_chargen - a 0xD000 )
            _ → ^ ( io_read a )
        }
    } {}
    ? >= a 0xE000 {                                    // KERNAL ROM / RAM
        ? != ( bank_hiram ) 0 { ^ ( rom_rd g_kernal - a 0xE000 ) } {}
        ^ ( ram_rd a )
    } {}
    ^ ( ram_rd a )
}
@ wr8 i addr i val → v {
    : i a & addr 0xFFFF
    : i b & val 0xFF
    ? == g_banked 0 { ( ram_wr a b )  ^ v } {}
    ? == a 0x0000 { = g_p01_ddr b  ^ v } {}
    ? == a 0x0001 { = g_p01_data b  ^ v } {}
    ? & >= a 0xD000 < a 0xE000 {                       // I/O writes hit chips
        ? == ( io_mode ) 2 { ( io_write a b )  ^ v } {}
    } {}
    ( ram_wr a b )                                     // RAM under any ROM
}
@ rd16 i addr → i { ^ | ( rd8 addr ) << ( rd8 & + addr 1 0xFFFF ) 8 }

@ fetch8 → i { : i v ( rd8 pc )  = pc & + pc 1 0xFFFF  ^ v }
@ fetch16 → i { : i v ( rd16 pc )  = pc & + pc 2 0xFFFF  ^ v }

// ── Status flags (each accessor returns 0/1; setters take any cond) ──
@ p_c → i { ^ & rp 1 }
@ p_z → i { ^ ? != 0 & rp 0x02 1 0 }
@ p_i → i { ^ ? != 0 & rp 0x04 1 0 }
@ p_d → i { ^ ? != 0 & rp 0x08 1 0 }
@ p_v → i { ^ ? != 0 & rp 0x40 1 0 }
@ p_n → i { ^ ? != 0 & rp 0x80 1 0 }

// Set/clear the bit `mask` according to whether `cond` is nonzero.
@ pset i mask i cond → v { = rp ? != cond 0 | rp mask & rp & ^^ mask 0xFF 0xFF }
@ set_c i b → v { ( pset 0x01 b ) }
@ set_z i b → v { ( pset 0x02 b ) }
@ set_i i b → v { ( pset 0x04 b ) }
@ set_d i b → v { ( pset 0x08 b ) }
@ set_v i b → v { ( pset 0x40 b ) }
@ set_n i b → v { ( pset 0x80 b ) }

// Set Z and N from an 8-bit result.
@ set_zn i v → v {
    : i b & v 0xFF
    ( set_z ? == b 0 1 0 )
    ( set_n & b 0x80 )
}

// ── Stack ───────────────────────────────────────────────────────────
@ push8 i v → v { ( wr8 | 0x100 sp & v 0xFF )  = sp & - sp 1 0xFF }
@ pull8 → i { = sp & + sp 1 0xFF  ^ ( rd8 | 0x100 sp ) }
@ push16 i v → v { ( push8 & >> v 8 0xFF )  ( push8 & v 0xFF ) }
@ pull16 → i { : i lo ( pull8 )  : i hi ( pull8 )  ^ | lo << hi 8 }

// ── Addressing modes (each returns the effective address) ───────────
@ a_zp → i { ^ ( fetch8 ) }
@ a_zpx → i { ^ & + ( fetch8 ) rx 0xFF }
@ a_zpy → i { ^ & + ( fetch8 ) ry 0xFF }
@ a_abs → i { ^ ( fetch16 ) }
@ a_absx → i { ^ & + ( fetch16 ) rx 0xFFFF }
@ a_absy → i { ^ & + ( fetch16 ) ry 0xFFFF }
// ($nn,X): zero-page pointer at (nn+X)&0xFF, read with zero-page wrap.
@ a_indx → i {
    : i z & + ( fetch8 ) rx 0xFF
    ^ | ( rd8 z ) << ( rd8 & + z 1 0xFF ) 8
}
// ($nn),Y: pointer at nn (zero-page wrap), then add Y.
@ a_indy → i {
    : i z ( fetch8 )
    : i base | ( rd8 z ) << ( rd8 & + z 1 0xFF ) 8
    ^ & + base ry 0xFFFF
}
// JMP ($nnnn) indirect — reproduces the NMOS page-wrap bug: the high
// byte is fetched from the same page when the pointer is on a $xxFF.
@ a_ind → i {
    : i p ( fetch16 )
    : i lo ( rd8 p )
    : i hi ( rd8 | & p 0xFF00 & + p 1 0xFF )
    ^ | lo << hi 8
}

// ── Loads / stores ──────────────────────────────────────────────────
@ op_lda i a → v { = ra ( rd8 a )  ( set_zn ra ) }
@ op_ldx i a → v { = rx ( rd8 a )  ( set_zn rx ) }
@ op_ldy i a → v { = ry ( rd8 a )  ( set_zn ry ) }
@ op_sta i a → v { ( wr8 a ra ) }
@ op_stx i a → v { ( wr8 a rx ) }
@ op_sty i a → v { ( wr8 a ry ) }

// ── Logic ───────────────────────────────────────────────────────────
@ op_and i v → v { = ra & ra v  ( set_zn ra ) }
@ op_ora i v → v { = ra & | ra v 0xFF  ( set_zn ra ) }
@ op_eor i v → v { = ra & ^^ ra v 0xFF  ( set_zn ra ) }
@ op_bit i v → v {
    ( set_z ? == & ra v 0 1 0 )
    ( set_n & v 0x80 )
    ( set_v & v 0x40 )
}

// ── Compares ────────────────────────────────────────────────────────
@ op_cmp i reg i v → v {
    ( set_c ? >= reg v 1 0 )
    ( set_zn & - reg v 0xFF )
}

// ── ADC / SBC (binary + NMOS decimal mode) ──────────────────────────
// Decimal ADC follows the canonical NMOS pseudocode (6502.org Appendix
// A): the decimal correction produces the accumulator and carry, while N
// and V come from the signed intermediate and Z from the binary sum.
@ op_adc i v → v {
    : i a ra
    : i c ( p_c )
    ? != ( p_d ) 0 {
        : ~ i al + + & a 0x0F & v 0x0F c
        ? >= al 0x0A { = al + & + al 0x06 0x0F 0x10 } {}
        : i ah + + & a 0xF0 & v 0xF0 al
        ( set_z ? == & + + a v c 0xFF 0 1 0 )
        ( set_n & ah 0x80 )
        ( set_v & & ^^ ^^ a v 0xFF & ^^ a ah 0xFF 0x80 )
        : ~ i r ah
        ? >= r 0xA0 { = r + r 0x60 } {}
        ( set_c ? >= r 0x100 1 0 )
        = ra & r 0xFF
    } {
        : i r + + a v c
        ( set_v & & ^^ ^^ a v 0xFF & ^^ a r 0xFF 0x80 )
        ( set_c ? > r 0xFF 1 0 )
        = ra & r 0xFF
        ( set_zn ra )
    }
}
// SBC: flags come from the binary subtraction regardless of mode; only
// the accumulator differs in decimal mode (NMOS behaviour).
@ op_sbc i v → v {
    : i a ra
    : i c ( p_c )
    : i bin - - a v - 1 c        // a - v - (1-C)
    ( set_v & & ^^ a v ^^ a & bin 0xFF 0x80 )
    ( set_c ? >= bin 0 1 0 )
    ( set_zn & bin 0xFF )
    ? != ( p_d ) 0 {
        : ~ i al - - & a 0x0F & v 0x0F - 1 c
        ? < al 0 { = al - & - al 0x06 0x0F 0x10 } {}
        : ~ i ah + - & a 0xF0 & v 0xF0 al    // (A&F0) - (B&F0) + AL
        ? < ah 0 { = ah - ah 0x60 } {}
        = ra & ah 0xFF
    } {
        = ra & bin 0xFF
    }
}

// ── Increment / decrement ───────────────────────────────────────────
@ op_inc i a → v { : i r & + ( rd8 a ) 1 0xFF  ( wr8 a r )  ( set_zn r ) }
@ op_dec i a → v { : i r & - ( rd8 a ) 1 0xFF  ( wr8 a r )  ( set_zn r ) }

// ── Shifts / rotates (value-in, value-out; flags set here) ──────────
@ sh_asl i v → i { ( set_c & v 0x80 )  : i r & << v 1 0xFF  ( set_zn r )  ^ r }
@ sh_lsr i v → i { ( set_c & v 1 )  : i r & >> v 1 0x7F  ( set_zn r )  ^ r }
@ sh_rol i v → i { : i c ( p_c )  ( set_c & v 0x80 )  : i r & | << v 1 c 0xFF  ( set_zn r )  ^ r }
@ sh_ror i v → i { : i c ( p_c )  ( set_c & v 1 )  : i r & | >> v 1 << c 7 0xFF  ( set_zn r )  ^ r }

// Read-modify-write a memory cell through a shift op selector.
//   0 ASL  1 LSR  2 ROL  3 ROR
@ rmw i sel i a → v {
    : i v ( rd8 a )
    : ~ i r 0
    ?? sel {
        0 → = r ( sh_asl v )
        1 → = r ( sh_lsr v )
        2 → = r ( sh_rol v )
        3 → = r ( sh_ror v )
        _ → {}
    }
    ( wr8 a r )
}

// ── Branches (relative, signed offset) ──────────────────────────────
@ branch b cond → v {
    : i off ( fetch8 )
    : i rel ? >= off 0x80 - off 256 off
    ? cond { = pc & + pc rel 0xFFFF } {}
}

// ── Reset / NMI / IRQ vectors ───────────────────────────────────────
@ cpu_reset → v {
    = ra 0  = rx 0  = ry 0
    = sp 0xFD
    = rp 0x24
    = pc ( rd16 0xFFFC )
    = g_cycles 0
}
@ cpu_set_pc i v → v { = pc & v 0xFFFF }
@ cpu_pc → i { ^ pc }

// Load an up-to-64 KiB image into memory at `base`.
@ mem_load * u src i n i base → v {
    : *u m ( mem_raw )
    : ~ i i 0
    ~ < i n { = . m & + base i 0xFFFF . src i  = i + i 1 }
}

// Allocate the 64 KiB address space (call once before loading an image).
@ mem_alloc → v { = g_mem ( nurl_zalloc 65536 ) }

// ── Single instruction step ─────────────────────────────────────────
// Fetch + decode + execute one instruction; returns the T-cycles used.
// A "trap" (the test ROM's pass/fail self-loop, e.g. `JMP *`) leaves PC
// unchanged — the caller detects pc_before == pc_after.
@ step → i {
    : i op ( fetch8 )
    : ~ i cyc 2
    ?? op {
        // ── LDA ──
        0xA9 → { ( op_lda pc ) = pc & + pc 1 0xFFFF }   // immediate
        0xA5 → { ( op_lda ( a_zp ) ) = cyc 3 }
        0xB5 → { ( op_lda ( a_zpx ) ) = cyc 4 }
        0xAD → { ( op_lda ( a_abs ) ) = cyc 4 }
        0xBD → { ( op_lda ( a_absx ) ) = cyc 4 }
        0xB9 → { ( op_lda ( a_absy ) ) = cyc 4 }
        0xA1 → { ( op_lda ( a_indx ) ) = cyc 6 }
        0xB1 → { ( op_lda ( a_indy ) ) = cyc 5 }
        // ── LDX ──
        0xA2 → { ( op_ldx pc ) = pc & + pc 1 0xFFFF }
        0xA6 → { ( op_ldx ( a_zp ) ) = cyc 3 }
        0xB6 → { ( op_ldx ( a_zpy ) ) = cyc 4 }
        0xAE → { ( op_ldx ( a_abs ) ) = cyc 4 }
        0xBE → { ( op_ldx ( a_absy ) ) = cyc 4 }
        // ── LDY ──
        0xA0 → { ( op_ldy pc ) = pc & + pc 1 0xFFFF }
        0xA4 → { ( op_ldy ( a_zp ) ) = cyc 3 }
        0xB4 → { ( op_ldy ( a_zpx ) ) = cyc 4 }
        0xAC → { ( op_ldy ( a_abs ) ) = cyc 4 }
        0xBC → { ( op_ldy ( a_absx ) ) = cyc 4 }
        // ── STA ──
        0x85 → { ( op_sta ( a_zp ) ) = cyc 3 }
        0x95 → { ( op_sta ( a_zpx ) ) = cyc 4 }
        0x8D → { ( op_sta ( a_abs ) ) = cyc 4 }
        0x9D → { ( op_sta ( a_absx ) ) = cyc 5 }
        0x99 → { ( op_sta ( a_absy ) ) = cyc 5 }
        0x81 → { ( op_sta ( a_indx ) ) = cyc 6 }
        0x91 → { ( op_sta ( a_indy ) ) = cyc 6 }
        // ── STX / STY ──
        0x86 → { ( op_stx ( a_zp ) ) = cyc 3 }
        0x96 → { ( op_stx ( a_zpy ) ) = cyc 4 }
        0x8E → { ( op_stx ( a_abs ) ) = cyc 4 }
        0x84 → { ( op_sty ( a_zp ) ) = cyc 3 }
        0x94 → { ( op_sty ( a_zpx ) ) = cyc 4 }
        0x8C → { ( op_sty ( a_abs ) ) = cyc 4 }

        // ── Transfers ──
        0xAA → { = rx ra ( set_zn rx ) }                // TAX
        0xA8 → { = ry ra ( set_zn ry ) }                // TAY
        0xBA → { = rx sp ( set_zn rx ) }                // TSX
        0x8A → { = ra rx ( set_zn ra ) }                // TXA
        0x9A → { = sp rx }                              // TXS (no flags)
        0x98 → { = ra ry ( set_zn ra ) }                // TYA

        // ── Stack ──
        0x48 → { ( push8 ra ) = cyc 3 }                 // PHA
        0x08 → { ( push8 | rp 0x30 ) = cyc 3 }          // PHP (B+U set)
        0x68 → { = ra ( pull8 ) ( set_zn ra ) = cyc 4 } // PLA
        0x28 → { = rp | & ( pull8 ) 0xEF 0x20 = cyc 4 } // PLP (clear B, set U)

        // ── Logic (immediate then the addressing variants) ──
        0x29 → { ( op_and ( fetch8 ) ) }
        0x25 → { ( op_and ( rd8 ( a_zp ) ) ) = cyc 3 }
        0x35 → { ( op_and ( rd8 ( a_zpx ) ) ) = cyc 4 }
        0x2D → { ( op_and ( rd8 ( a_abs ) ) ) = cyc 4 }
        0x3D → { ( op_and ( rd8 ( a_absx ) ) ) = cyc 4 }
        0x39 → { ( op_and ( rd8 ( a_absy ) ) ) = cyc 4 }
        0x21 → { ( op_and ( rd8 ( a_indx ) ) ) = cyc 6 }
        0x31 → { ( op_and ( rd8 ( a_indy ) ) ) = cyc 5 }
        0x09 → { ( op_ora ( fetch8 ) ) }
        0x05 → { ( op_ora ( rd8 ( a_zp ) ) ) = cyc 3 }
        0x15 → { ( op_ora ( rd8 ( a_zpx ) ) ) = cyc 4 }
        0x0D → { ( op_ora ( rd8 ( a_abs ) ) ) = cyc 4 }
        0x1D → { ( op_ora ( rd8 ( a_absx ) ) ) = cyc 4 }
        0x19 → { ( op_ora ( rd8 ( a_absy ) ) ) = cyc 4 }
        0x01 → { ( op_ora ( rd8 ( a_indx ) ) ) = cyc 6 }
        0x11 → { ( op_ora ( rd8 ( a_indy ) ) ) = cyc 5 }
        0x49 → { ( op_eor ( fetch8 ) ) }
        0x45 → { ( op_eor ( rd8 ( a_zp ) ) ) = cyc 3 }
        0x55 → { ( op_eor ( rd8 ( a_zpx ) ) ) = cyc 4 }
        0x4D → { ( op_eor ( rd8 ( a_abs ) ) ) = cyc 4 }
        0x5D → { ( op_eor ( rd8 ( a_absx ) ) ) = cyc 4 }
        0x59 → { ( op_eor ( rd8 ( a_absy ) ) ) = cyc 4 }
        0x41 → { ( op_eor ( rd8 ( a_indx ) ) ) = cyc 6 }
        0x51 → { ( op_eor ( rd8 ( a_indy ) ) ) = cyc 5 }
        0x24 → { ( op_bit ( rd8 ( a_zp ) ) ) = cyc 3 }
        0x2C → { ( op_bit ( rd8 ( a_abs ) ) ) = cyc 4 }

        // ── ADC ──
        0x69 → { ( op_adc ( fetch8 ) ) }
        0x65 → { ( op_adc ( rd8 ( a_zp ) ) ) = cyc 3 }
        0x75 → { ( op_adc ( rd8 ( a_zpx ) ) ) = cyc 4 }
        0x6D → { ( op_adc ( rd8 ( a_abs ) ) ) = cyc 4 }
        0x7D → { ( op_adc ( rd8 ( a_absx ) ) ) = cyc 4 }
        0x79 → { ( op_adc ( rd8 ( a_absy ) ) ) = cyc 4 }
        0x61 → { ( op_adc ( rd8 ( a_indx ) ) ) = cyc 6 }
        0x71 → { ( op_adc ( rd8 ( a_indy ) ) ) = cyc 5 }
        // ── SBC ──
        0xE9 → { ( op_sbc ( fetch8 ) ) }
        0xE5 → { ( op_sbc ( rd8 ( a_zp ) ) ) = cyc 3 }
        0xF5 → { ( op_sbc ( rd8 ( a_zpx ) ) ) = cyc 4 }
        0xED → { ( op_sbc ( rd8 ( a_abs ) ) ) = cyc 4 }
        0xFD → { ( op_sbc ( rd8 ( a_absx ) ) ) = cyc 4 }
        0xF9 → { ( op_sbc ( rd8 ( a_absy ) ) ) = cyc 4 }
        0xE1 → { ( op_sbc ( rd8 ( a_indx ) ) ) = cyc 6 }
        0xF1 → { ( op_sbc ( rd8 ( a_indy ) ) ) = cyc 5 }

        // ── CMP / CPX / CPY ──
        0xC9 → { ( op_cmp ra ( fetch8 ) ) }
        0xC5 → { ( op_cmp ra ( rd8 ( a_zp ) ) ) = cyc 3 }
        0xD5 → { ( op_cmp ra ( rd8 ( a_zpx ) ) ) = cyc 4 }
        0xCD → { ( op_cmp ra ( rd8 ( a_abs ) ) ) = cyc 4 }
        0xDD → { ( op_cmp ra ( rd8 ( a_absx ) ) ) = cyc 4 }
        0xD9 → { ( op_cmp ra ( rd8 ( a_absy ) ) ) = cyc 4 }
        0xC1 → { ( op_cmp ra ( rd8 ( a_indx ) ) ) = cyc 6 }
        0xD1 → { ( op_cmp ra ( rd8 ( a_indy ) ) ) = cyc 5 }
        0xE0 → { ( op_cmp rx ( fetch8 ) ) }
        0xE4 → { ( op_cmp rx ( rd8 ( a_zp ) ) ) = cyc 3 }
        0xEC → { ( op_cmp rx ( rd8 ( a_abs ) ) ) = cyc 4 }
        0xC0 → { ( op_cmp ry ( fetch8 ) ) }
        0xC4 → { ( op_cmp ry ( rd8 ( a_zp ) ) ) = cyc 3 }
        0xCC → { ( op_cmp ry ( rd8 ( a_abs ) ) ) = cyc 4 }

        // ── INC / DEC memory ──
        0xE6 → { ( op_inc ( a_zp ) ) = cyc 5 }
        0xF6 → { ( op_inc ( a_zpx ) ) = cyc 6 }
        0xEE → { ( op_inc ( a_abs ) ) = cyc 6 }
        0xFE → { ( op_inc ( a_absx ) ) = cyc 7 }
        0xC6 → { ( op_dec ( a_zp ) ) = cyc 5 }
        0xD6 → { ( op_dec ( a_zpx ) ) = cyc 6 }
        0xCE → { ( op_dec ( a_abs ) ) = cyc 6 }
        0xDE → { ( op_dec ( a_absx ) ) = cyc 7 }
        // ── INX/INY/DEX/DEY ──
        0xE8 → { = rx & + rx 1 0xFF ( set_zn rx ) }     // INX
        0xC8 → { = ry & + ry 1 0xFF ( set_zn ry ) }     // INY
        0xCA → { = rx & - rx 1 0xFF ( set_zn rx ) }     // DEX
        0x88 → { = ry & - ry 1 0xFF ( set_zn ry ) }     // DEY

        // ── Shifts / rotates ──
        0x0A → { = ra ( sh_asl ra ) }                   // ASL A
        0x06 → { ( rmw 0 ( a_zp ) ) = cyc 5 }
        0x16 → { ( rmw 0 ( a_zpx ) ) = cyc 6 }
        0x0E → { ( rmw 0 ( a_abs ) ) = cyc 6 }
        0x1E → { ( rmw 0 ( a_absx ) ) = cyc 7 }
        0x4A → { = ra ( sh_lsr ra ) }                   // LSR A
        0x46 → { ( rmw 1 ( a_zp ) ) = cyc 5 }
        0x56 → { ( rmw 1 ( a_zpx ) ) = cyc 6 }
        0x4E → { ( rmw 1 ( a_abs ) ) = cyc 6 }
        0x5E → { ( rmw 1 ( a_absx ) ) = cyc 7 }
        0x2A → { = ra ( sh_rol ra ) }                   // ROL A
        0x26 → { ( rmw 2 ( a_zp ) ) = cyc 5 }
        0x36 → { ( rmw 2 ( a_zpx ) ) = cyc 6 }
        0x2E → { ( rmw 2 ( a_abs ) ) = cyc 6 }
        0x3E → { ( rmw 2 ( a_absx ) ) = cyc 7 }
        0x6A → { = ra ( sh_ror ra ) }                   // ROR A
        0x66 → { ( rmw 3 ( a_zp ) ) = cyc 5 }
        0x76 → { ( rmw 3 ( a_zpx ) ) = cyc 6 }
        0x6E → { ( rmw 3 ( a_abs ) ) = cyc 6 }
        0x7E → { ( rmw 3 ( a_absx ) ) = cyc 7 }

        // ── Jumps / calls / returns ──
        0x4C → { = pc ( a_abs ) = cyc 3 }               // JMP abs
        0x6C → { = pc ( a_ind ) = cyc 5 }               // JMP (ind)
        0x20 → {                                        // JSR abs
            : i target ( fetch16 )
            ( push16 & - pc 1 0xFFFF )
            = pc target  = cyc 6
        }
        0x60 → { = pc & + ( pull16 ) 1 0xFFFF = cyc 6 } // RTS
        0x40 → {                                        // RTI
            = rp | & ( pull8 ) 0xEF 0x20
            = pc ( pull16 )  = cyc 6
        }
        0x00 → {                                        // BRK
            = pc & + pc 1 0xFFFF
            ( push16 pc )
            ( push8 | rp 0x30 )
            ( set_i 1 )
            = pc ( rd16 0xFFFE )  = cyc 7
        }

        // ── Branches ──
        0x90 → { ( branch == ( p_c ) 0 ) }              // BCC
        0xB0 → { ( branch != ( p_c ) 0 ) }              // BCS
        0xD0 → { ( branch == ( p_z ) 0 ) }              // BNE
        0xF0 → { ( branch != ( p_z ) 0 ) }              // BEQ
        0x10 → { ( branch == ( p_n ) 0 ) }              // BPL
        0x30 → { ( branch != ( p_n ) 0 ) }              // BMI
        0x50 → { ( branch == ( p_v ) 0 ) }              // BVC
        0x70 → { ( branch != ( p_v ) 0 ) }              // BVS

        // ── Flag ops ──
        0x18 → { ( set_c 0 ) }                          // CLC
        0x38 → { ( set_c 1 ) }                          // SEC
        0x58 → { ( set_i 0 ) }                          // CLI
        0x78 → { ( set_i 1 ) }                          // SEI
        0xD8 → { ( set_d 0 ) }                          // CLD
        0xF8 → { ( set_d 1 ) }                          // SED
        0xB8 → { ( set_v 0 ) }                          // CLV

        0xEA → {}                                       // NOP
        _ → ( bad_op op )
    }
    = g_cycles + g_cycles cyc
    ^ cyc
}

@ bad_op i op → v {
    ( nurl_print `\nUNIMPLEMENTED opcode 0x` )
    ( nurl_print ( nurl_str_int op ) )
    ( nurl_print ` at pc=` ) ( nurl_print ( nurl_str_int pc ) ) ( nurl_print `\n` )
}

// ════════════════════════════════════════════════════════════════════
//  C64 machine layer — VIC-II, CIA1, colour RAM, interrupts, boot.
//  Built on the same rd8/wr8 the CPU already uses; flips on when the
//  KERNAL/BASIC/CHARGEN ROMs are loaded (g_banked = 1).
// ════════════════════════════════════════════════════════════════════

// ── I/O register files + video timing ───────────────────────────────
: s g_vicreg 0      // 64-byte VIC-II register file
: s g_sidreg 0      // 32-byte SID register file (sound out of scope here)
: s g_cia2reg 0     // 16-byte CIA2 register file (serial/NMI — dumb here)
: s g_fb 0          // 384x272 colour-index framebuffer (*u, with border)
: i g_raster 0      // current raster line 0..311 (PAL)
: i g_rasdot 0      // cycle within the current raster line
: i g_frames 0      // completed video frames

// ── CIA1 (keyboard + the jiffy-IRQ timer) ───────────────────────────
: s g_kb 0          // 8-byte keyboard matrix (row bit set = key down)
: i c1_pra 0xFF     // port A (keyboard column select, joystick #2)
: i c1_prb 0xFF     // port B (keyboard rows, joystick #1)
: i c1_ddra 0  : i c1_ddrb 0
: i c1_ta 0xFFFF    // Timer A counter
: i c1_tb 0xFFFF    // Timer B counter
: i c1_ta_lo 0 : i c1_ta_hi 0 : i c1_tb_lo 0 : i c1_tb_hi 0
: i c1_cra 0   : i c1_crb 0
: i c1_icr 0        // interrupt pending flags (bit0 TA, bit1 TB)
: i c1_imask 0      // enabled-interrupt mask

@ vreg i r → i { : *u v # *u g_vicreg  ^ & # i . v & r 0x3F 255 }
@ cia2_pra → i { : *u c # *u g_cia2reg  ^ & # i . c 0 255 }

// ── Keyboard matrix read (port B) ───────────────────────────────────
@ kb_read → i {
    : *u kb # *u g_kb
    : ~ i res 0xFF
    : ~ i col 0
    ~ < col 8 {
        ? == 0 & c1_pra << 1 col { = res & res ^^ & # i . kb col 255 0xFF } {}
        = col + col 1
    }
    ^ res
}

// ── CIA1 register access ────────────────────────────────────────────
@ cia1_read i reg → i {
    ?? reg {
        0x00 → ^ c1_pra
        0x01 → ^ ( kb_read )
        0x02 → ^ c1_ddra
        0x03 → ^ c1_ddrb
        0x04 → ^ & c1_ta 0xFF
        0x05 → ^ & >> c1_ta 8 0xFF
        0x06 → ^ & c1_tb 0xFF
        0x07 → ^ & >> c1_tb 8 0xFF
        0x0D → {
            : ~ i vv c1_icr
            ? != 0 & & c1_icr c1_imask 0x1F { = vv | vv 0x80 } {}
            = c1_icr 0
            ^ vv
        }
        0x0E → ^ c1_cra
        0x0F → ^ c1_crb
        _ → ^ 0
    }
}
@ cia1_write i reg i b → v {
    ?? reg {
        0x00 → = c1_pra b
        0x01 → = c1_prb b
        0x02 → = c1_ddra b
        0x03 → = c1_ddrb b
        0x04 → = c1_ta_lo b
        0x05 → = c1_ta_hi b
        0x06 → = c1_tb_lo b
        0x07 → = c1_tb_hi b
        0x0D → { ? != 0 & b 0x80 { = c1_imask | c1_imask & b 0x1F } { = c1_imask & c1_imask & ^^ b 0xFF 0x1F } }
        0x0E → { = c1_cra b  ? != 0 & b 0x10 { = c1_ta | c1_ta_lo << c1_ta_hi 8 } {} }
        0x0F → { = c1_crb b  ? != 0 & b 0x10 { = c1_tb | c1_tb_lo << c1_tb_hi 8 } {} }
        _ → {}
    }
}
// Count Timer A (and B) down by `cyc` phi2 cycles; underflow → IRQ flag.
@ cia1_tick i cyc → v {
    ? & != 0 & c1_cra 1 == 0 & c1_cra 0x20 {
        ? >= c1_ta cyc { = c1_ta - c1_ta cyc } {
            = c1_icr | c1_icr 1
            : i over - cyc c1_ta
            : i latch | c1_ta_lo << c1_ta_hi 8
            = c1_ta & - latch over 0xFFFF
            ? != 0 & c1_cra 8 { = c1_cra & c1_cra 0xFE } {}
        }
    } {}
    ? & != 0 & c1_crb 1 == 0 & c1_crb 0x60 {
        ? >= c1_tb cyc { = c1_tb - c1_tb cyc } {
            = c1_icr | c1_icr 2
            : i over - cyc c1_tb
            : i latch | c1_tb_lo << c1_tb_hi 8
            = c1_tb & - latch over 0xFFFF
            ? != 0 & c1_crb 8 { = c1_crb & c1_crb 0xFE } {}
        }
    } {}
}
@ cia1_irq → i { ^ ? != 0 & & c1_icr c1_imask 0x1F 1 0 }

// ── VIC-II / SID register access ────────────────────────────────────
@ vic_read i reg → i {
    : *u v # *u g_vicreg
    ? == reg 0x11 { ^ | & & # i . v 0x11 255 0x7F << & >> g_raster 8 1 7 } {}
    ? == reg 0x12 { ^ & g_raster 0xFF } {}
    ? >= reg 0x2F { ^ 0xFF } {}                        // unused registers read $FF
    ? >= reg 0x20 { ^ | & # i . v reg 255 0xF0 } {}    // colour registers: upper nibble 1
    ^ & # i . v reg 255
}
@ vic_write i reg i b → v {
    : *u v # *u g_vicreg
    ? == reg 0x19 {
        = . v 0x19 # u & & # i . v 0x19 255 ^^ b 0xFF      // writing 1 acks an IRQ latch bit
    } {
        = . v reg # u b
    }
}
@ sid_read i reg → i { : *u s # *u g_sidreg  ^ & # i . s reg 255 }
@ sid_write i reg i b → v { : *u s # *u g_sidreg  = . s reg # u b }

// ── I/O window dispatch ($D000-$DFFF) ───────────────────────────────
@ io_read i a → i {
    ? < a 0xD400 { ^ ( vic_read & a 0x3F ) } {}
    ? < a 0xD800 { ^ ( sid_read & a 0x1F ) } {}
    ? < a 0xDC00 { : *u c # *u g_color  ^ | & & # i . c & a 0x3FF 255 0x0F 0xF0 } {}
    ? < a 0xDD00 { ^ ( cia1_read & a 0x0F ) } {}
    ? < a 0xDE00 { : *u c # *u g_cia2reg  ^ & # i . c & a 0x0F 255 } {}
    ^ 0xFF
}
@ io_write i a i b → v {
    ? < a 0xD400 { ( vic_write & a 0x3F b )  ^ v } {}
    ? < a 0xD800 { ( sid_write & a 0x1F b )  ^ v } {}
    ? < a 0xDC00 { : *u c # *u g_color  = . c & a 0x3FF # u & b 0x0F  ^ v } {}
    ? < a 0xDD00 { ( cia1_write & a 0x0F b )  ^ v } {}
    ? < a 0xDE00 { : *u c # *u g_cia2reg  = . c & a 0x0F # u b  ^ v } {}
}

// ── Video timing: advance the raster line by `cyc` cycles ────────────
@ vic_tick i cyc → v {
    = g_rasdot + g_rasdot cyc
    ~ >= g_rasdot 63 {
        = g_rasdot - g_rasdot 63
        = g_raster + g_raster 1
        ? >= g_raster 312 { = g_raster 0  = g_frames + g_frames 1 } {}
    }
}

// ── Interrupts ──────────────────────────────────────────────────────
@ irq_enter i vec → v {
    ( push16 pc )
    ( push8 & | rp 0x20 0xEF )       // pushed P: U=1, B=0 (hardware IRQ/NMI)
    ( set_i 1 )
    = pc ( rd16 vec )
}

// One CPU instruction + chip clocking + IRQ dispatch; returns cycles.
@ cpu_advance → i {
    : ~ i cyc ( step )
    ( cia1_tick cyc )
    ( vic_tick cyc )
    ? & != 0 ( cia1_irq ) == ( p_i ) 0 {
        ( irq_enter 0xFFFE )
        ( cia1_tick 7 ) ( vic_tick 7 )
        = g_cycles + g_cycles 7  = cyc + cyc 7
    } {}
    ^ cyc
}

// Run until the next frame boundary (one PAL frame ≈ 19656 cycles). The
// guard bounds the loop so it always returns even with the screen off.
@ run_one_frame → v {
    : i target + g_cycles 19656
    : ~ i guard 0
    ~ & < g_cycles target < guard 200000 {
        ( cpu_advance )
        = guard + guard 1
    }
}

// ── Allocation + ROM loading + boot ─────────────────────────────────
@ blit_into s dst i n * u src → v {
    : *u d # *u dst
    : ~ i i 0
    ~ < i n { = . d i . src i  = i + i 1 }
}
@ c64_alloc → v {
    = g_mem ( nurl_zalloc 65536 )
    = g_kernal ( nurl_zalloc 8192 )
    = g_basic ( nurl_zalloc 8192 )
    = g_chargen ( nurl_zalloc 4096 )
    = g_color ( nurl_zalloc 1024 )
    = g_vicreg ( nurl_zalloc 64 )
    = g_sidreg ( nurl_zalloc 32 )
    = g_cia2reg ( nurl_zalloc 16 )
    = g_kb ( nurl_zalloc 8 )
    = g_fb ( nurl_zalloc 104448 )       // 384 * 272
}
@ load_kernal * u src i n → v { ( blit_into g_kernal ? > n 8192 8192 n src ) }
@ load_basic * u src i n → v { ( blit_into g_basic ? > n 8192 8192 n src ) }
@ load_chargen * u src i n → v { ( blit_into g_chargen ? > n 4096 4096 n src ) }

// Cold-boot the machine: ROMs must already be loaded. Sets the CPU port
// to the default $37 (all ROMs + I/O), resets the CIA, and fetches the
// reset vector from KERNAL ($FFFC).
@ c64_boot → v {
    = g_banked 1
    = g_p01_ddr 0x2F
    = g_p01_data 0x37
    = c1_cra 0  = c1_crb 0  = c1_icr 0  = c1_imask 0
    = c1_ta 0xFFFF  = c1_tb 0xFFFF
    = c1_ta_lo 0  = c1_ta_hi 0  = c1_tb_lo 0  = c1_tb_hi 0
    = c1_pra 0xFF  = c1_prb 0xFF  = c1_ddra 0  = c1_ddrb 0
    = g_raster 0  = g_rasdot 0  = g_frames 0  = g_cycles 0
    ( cpu_reset )
}

// ── Rendering: VIC-II standard text mode → colour-index framebuffer ──
@ render_frame → v {
    : *u fb # *u g_fb
    : i border & ( vreg 0x20 ) 0x0F
    : i bg & ( vreg 0x21 ) 0x0F
    : ~ i i 0
    ~ < i 104448 { = . fb i # u border  = i + i 1 }
    // Display enable (DEN, $D011 bit4) off → blanked to border.
    ? == 0 & ( vreg 0x11 ) 0x10 { ^ v } {}
    : *u cram # *u g_color
    : *u cg # *u g_chargen
    : i d18 ( vreg 0x18 )
    : i scrbase + * & ^^ ( cia2_pra ) 0xFF 3 0x4000 * & >> d18 4 0xF 0x400
    : i cbase * & >> d18 1 7 0x800            // char base within VIC bank
    : ~ i r 0
    ~ < r 25 {
        : ~ i col 0
        ~ < col 40 {
            : i ci + * r 40 col
            : i sc & ( ram_rd + scrbase ci ) 0xFF
            : i fg & & # i . cram ci 255 0x0F
            : ~ i ln 0
            ~ < ln 8 {
                // $1000/$1800 in VIC bank 0 see the CHARGEN ROM; any other
                // char base is a RAM (custom) character set.
                : ~ i bits 0
                ? == cbase 0x1000 { = bits & # i . cg + * sc 8 ln 255 } {
                    ? == cbase 0x1800 { = bits & # i . cg + 0x800 + * sc 8 ln 255 } {
                        = bits ( ram_rd + + cbase * sc 8 ln )
                    }
                }
                : ~ i bx 0
                ~ < bx 8 {
                    : i px + + 32 * col 8 bx
                    : i py + + 36 * r 8 ln
                    = . fb + * py 384 px # u ? != 0 & >> bits - 7 bx 1 fg bg
                    = bx + bx 1
                }
                = ln + ln 1
            }
            = col + col 1
        }
        = r + r 1
    }
}

// ── Native helper: dump the 40x25 text screen as ASCII ──────────────
@ scr_to_ascii i sc → i {
    : i c & sc 0x7F
    ? == c 0 { ^ 64 } {}                 // '@'
    ? & >= c 1 <= c 26 { ^ + 64 c } {}   // A-Z
    ? & >= c 27 <= c 31 { ^ + 64 c } {}  // [ \ ] ^ _
    ? & >= c 32 <= c 63 { ^ c } {}       // space, digits, punctuation (ASCII)
    ^ 32
}
@ screen_dump → v {
    : i scrbase + * & ^^ ( cia2_pra ) 0xFF 3 0x4000 * & >> ( vreg 0x18 ) 4 0xF 0x400
    : String row ( string_with_cap 42 )
    : ~ i r 0
    ~ < r 25 {
        ( string_clear row )
        : ~ i col 0
        ~ < col 40 {
            ( string_push_char row ( scr_to_ascii ( ram_rd + scrbase + * r 40 col ) ) )
            = col + col 1
        }
        ( nurl_print ( string_data row ) ) ( nurl_print `\n` )
        = r + r 1
    }
    ( string_free row )
}

// examples/c64/c64_wasm.nu — WebAssembly browser front-end for the C64.
//
// Shares the emulator engine in core.nu and drives it from the
// playground's canvas FFI. The three C64 ROMs (KERNAL / BASIC / CHARGEN)
// and the live keyboard-matrix state are pulled from host-provided import
// functions that c64demo.html wires up. One `run_one_frame` runs per
// displayed frame; `canvas_sleep` is the Asyncify yield back to the
// browser.
//
// Build (in the API container / via nurl_build_wasm): POST the combined
// source (core.nu + this file) to /build_wasm at -O2.


// ── Canvas FFI (module "canvas") — same shape as the Game Boy demo ──
& `canvas` @ canvas_open i w i h → *i
& `canvas` @ canvas_present → v
& `canvas` @ canvas_sleep i ms → v
& `canvas` @ canvas_should_close → i

// ── Host imports wired up by c64demo.html ──
// bank: 0 = KERNAL (8K), 1 = BASIC (8K), 2 = CHARGEN (4K).
& `canvas` @ host_rom_byte i bank i idx → i
// Keyboard matrix: returns the row bitmask for column `col` (bit set = key down).
& `canvas` @ host_kb_col i col → i

// ── C64 16-colour palette (Pepto) → ARGB 0xAARRGGBB (host swaps R/B) ──
@ pal_argb i c → i {
    ?? & c 0x0F {
        0 → ^ 0xFF000000
        1 → ^ 0xFFFFFFFF
        2 → ^ 0xFF68372B
        3 → ^ 0xFF70A4B2
        4 → ^ 0xFF6F3D86
        5 → ^ 0xFF588D43
        6 → ^ 0xFF352879
        7 → ^ 0xFFB8C76F
        8 → ^ 0xFF6F4F25
        9 → ^ 0xFF433900
        10 → ^ 0xFF9A6759
        11 → ^ 0xFF444444
        12 → ^ 0xFF6C6C6C
        13 → ^ 0xFF9AD284
        14 → ^ 0xFF6C5EB5
        15 → ^ 0xFF959595
        _ → ^ 0xFF000000
    }
}

// Copy the 384x272 colour-index framebuffer into the canvas surface (one
// i64 per pixel; the low 32 bits carry the ARGB value).
@ blit * i fb → v {
    : *u src # *u g_fb
    : ~ i i 0
    ~ < i 104448 {
        = . fb i ( pal_argb & # i . src i 255 )
        = i + i 1
    }
}

// Pull a fixed-size ROM bank from the host into a NURL buffer.
@ pull_rom i bank i n → s {
    : s buf ( nurl_alloc n )
    : *u bp # *u buf
    : ~ i i 0
    ~ < i n { = . bp i # u ( host_rom_byte bank i )  = i + i 1 }
    ^ buf
}

@ main → i {
    ( c64_alloc )
    // Load the three ROMs from the host, then cold-boot.
    : s kbuf ( pull_rom 0 8192 )   ( load_kernal  # *u kbuf 8192 )  ( nurl_free kbuf )
    : s bbuf ( pull_rom 1 8192 )   ( load_basic   # *u bbuf 8192 )  ( nurl_free bbuf )
    : s cbuf ( pull_rom 2 4096 )   ( load_chargen # *u cbuf 4096 )  ( nurl_free cbuf )
    ( c64_boot )

    : *i fb ( canvas_open 384 272 )
    : *u kb # *u g_kb
    : ~ i running 1
    ~ != running 0 {
        // Refresh the keyboard matrix from the host.
        : ~ i col 0
        ~ < col 8 { = . kb col # u & ( host_kb_col col ) 255  = col + col 1 }
        ( run_one_frame )
        ( render_frame )
        ( blit fb )
        ( canvas_present )
        ( canvas_sleep 20 )
        ? != 0 ( canvas_should_close ) { = running 0 } {}
    }
    ^ 0
}
