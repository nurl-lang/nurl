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
: ~ i ra 0  // accumulator
: ~ i rx 0  // index X
: ~ i ry 0  // index Y
: ~ i sp 0xFD  // stack pointer (stack lives at 0x0100..0x01FF)
: ~ i pc 0  // program counter
: ~ i rp 0x24  // processor status: N V - B D I Z C (bit5 always 1)

// Status-bit masks.
//   C 0x01  Z 0x02  I 0x04  D 0x08  B 0x10  U 0x20  V 0x40  N 0x80

: ~ i g_cycles 0  // total T-cycles executed

// ── Memory ──────────────────────────────────────────────────────────
: ~ s g_mem 0  // 64 KiB flat RAM (*u, held as s)
: ~ s g_kernal 0  // 8 KiB KERNAL ROM   ($E000-$FFFF)
: ~ s g_basic 0  // 8 KiB BASIC ROM    ($A000-$BFFF)
: ~ s g_chargen 0  // 4 KiB character ROM ($D000-$DFFF when CHAREN=0)
: ~ s g_color 0  // 1 KiB colour RAM   ($D800-$DBFF)
: ~ i g_banked 0  // 0 = flat RAM (CPU test); 1 = full C64 PLA map
: ~ i g_p01_ddr 0  // $0000 CPU-port data-direction register
: ~ i g_p01_data 0  // $0001 CPU-port data latch (banking bits 0-2)

@ mem_raw → *u { ^ # *u g_mem }

// Flat-RAM access (the byte under any ROM is always RAM).
@ ram_rd i a → i { : *u m ( mem_raw ) ^ & # i . m & a 0xFFFF 255 }

@ ram_wr i a i val → v { : *u m ( mem_raw ) = . m & a 0xFFFF # u & val 0xFF }

@ rom_rd s rom i off → i { : *u r # *u rom ^ & # i . r off 255 }

// The $0001 read: output bits return the latch, input bits float high.
@ port01_read → i { ^ & | & g_p01_data g_p01_ddr & ^^ g_p01_ddr 0xFF 0xFF 0xFF }

@ bank_loram → i { ^ & ( port01_read ) 1 }  // BASIC ROM enable
@ bank_hiram → i { ^ & >> ( port01_read ) 1 1 }  // KERNAL ROM enable
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
    ? & >= a 0xA000 < a 0xC000 {  // BASIC ROM / RAM
        ? & != ( bank_loram ) 0 != ( bank_hiram ) 0 { ^ ( rom_rd g_basic - a 0xA000 ) } {}
        ^ ( ram_rd a )
    } {}
    ? & >= a 0xD000 < a 0xE000 {  // I/O / CHARGEN / RAM
        ?? ( io_mode ) {
            0 → ^ ( ram_rd a )
            1 → ^ ( rom_rd g_chargen - a 0xD000 )
            _ → ^ ( io_read a )
        }
    } {}
    ? >= a 0xE000 {  // KERNAL ROM / RAM
        ? != ( bank_hiram ) 0 { ^ ( rom_rd g_kernal - a 0xE000 ) } {}
        ^ ( ram_rd a )
    } {}
    ^ ( ram_rd a )
}

@ wr8 i addr i val → v {
    : i a & addr 0xFFFF
    : i b & val 0xFF
    ? == g_banked 0 { ( ram_wr a b ) ^ v } {}
    ? == a 0x0000 { = g_p01_ddr b ^ v } {}
    ? == a 0x0001 { = g_p01_data b ^ v } {}
    ? & >= a 0xD000 < a 0xE000 {  // I/O writes hit chips
        ? == ( io_mode ) 2 { ( io_write a b ) ^ v } {}
    } {}
    ( ram_wr a b )  // RAM under any ROM
}

@ rd16 i addr → i { ^ | ( rd8 addr ) << ( rd8 & + addr 1 0xFFFF ) 8 }

@ fetch8 → i { : i v ( rd8 pc ) = pc & + pc 1 0xFFFF ^ v }

@ fetch16 → i { : i v ( rd16 pc ) = pc & + pc 2 0xFFFF ^ v }

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
@ push8 i v → v { ( wr8 | 0x100 sp & v 0xFF ) = sp & - sp 1 0xFF }

@ pull8 → i { = sp & + sp 1 0xFF ^ ( rd8 | 0x100 sp ) }

@ push16 i v → v { ( push8 & >> v 8 0xFF ) ( push8 & v 0xFF ) }

@ pull16 → i { : i lo ( pull8 ) : i hi ( pull8 ) ^ | lo << hi 8 }

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
@ op_lda i a → v { = ra ( rd8 a ) ( set_zn ra ) }

@ op_ldx i a → v { = rx ( rd8 a ) ( set_zn rx ) }

@ op_ldy i a → v { = ry ( rd8 a ) ( set_zn ry ) }

@ op_sta i a → v { ( wr8 a ra ) }

@ op_stx i a → v { ( wr8 a rx ) }

@ op_sty i a → v { ( wr8 a ry ) }

// ── Logic ───────────────────────────────────────────────────────────
@ op_and i v → v { = ra & ra v ( set_zn ra ) }

@ op_ora i v → v { = ra & | ra v 0xFF ( set_zn ra ) }

@ op_eor i v → v { = ra & ^^ ra v 0xFF ( set_zn ra ) }

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
    : i bin - - a v - 1 c  // a - v - (1-C)
    ( set_v & & ^^ a v ^^ a & bin 0xFF 0x80 )
    ( set_c ? >= bin 0 1 0 )
    ( set_zn & bin 0xFF )
    ? != ( p_d ) 0 {
        : ~ i al - - & a 0x0F & v 0x0F - 1 c
        ? < al 0 { = al - & - al 0x06 0x0F 0x10 } {}
        : ~ i ah + - & a 0xF0 & v 0xF0 al  // (A&F0) - (B&F0) + AL
        ? < ah 0 { = ah - ah 0x60 } {}
        = ra & ah 0xFF
    } {
        = ra & bin 0xFF
    }
}

// ── Increment / decrement ───────────────────────────────────────────
@ op_inc i a → v { : i r & + ( rd8 a ) 1 0xFF ( wr8 a r ) ( set_zn r ) }

@ op_dec i a → v { : i r & - ( rd8 a ) 1 0xFF ( wr8 a r ) ( set_zn r ) }

// ── Shifts / rotates (value-in, value-out; flags set here) ──────────
@ sh_asl i v → i { ( set_c & v 0x80 ) : i r & << v 1 0xFF ( set_zn r ) ^ r }

@ sh_lsr i v → i { ( set_c & v 1 ) : i r & >> v 1 0x7F ( set_zn r ) ^ r }

@ sh_rol i v → i { : i c ( p_c ) ( set_c & v 0x80 ) : i r & | << v 1 c 0xFF ( set_zn r ) ^ r }

@ sh_ror i v → i { : i c ( p_c ) ( set_c & v 1 ) : i r & | >> v 1 << c 7 0xFF ( set_zn r ) ^ r }

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
    = ra 0 = rx 0 = ry 0
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
    ~ < i n { = . m & + base i 0xFFFF . src i = i + i 1 }
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
        0xA9 → { ( op_lda pc ) = pc & + pc 1 0xFFFF }  // immediate
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
        0xAA → { = rx ra ( set_zn rx ) }  // TAX
        0xA8 → { = ry ra ( set_zn ry ) }  // TAY
        0xBA → { = rx sp ( set_zn rx ) }  // TSX
        0x8A → { = ra rx ( set_zn ra ) }  // TXA
        0x9A → { = sp rx }  // TXS (no flags)
        0x98 → { = ra ry ( set_zn ra ) }  // TYA

        // ── Stack ──
        0x48 → { ( push8 ra ) = cyc 3 }  // PHA
        0x08 → { ( push8 | rp 0x30 ) = cyc 3 }  // PHP (B+U set)
        0x68 → { = ra ( pull8 ) ( set_zn ra ) = cyc 4 }  // PLA
        0x28 → { = rp | & ( pull8 ) 0xEF 0x20 = cyc 4 }  // PLP (clear B, set U)

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
        0xE8 → { = rx & + rx 1 0xFF ( set_zn rx ) }  // INX
        0xC8 → { = ry & + ry 1 0xFF ( set_zn ry ) }  // INY
        0xCA → { = rx & - rx 1 0xFF ( set_zn rx ) }  // DEX
        0x88 → { = ry & - ry 1 0xFF ( set_zn ry ) }  // DEY

        // ── Shifts / rotates ──
        0x0A → { = ra ( sh_asl ra ) }  // ASL A
        0x06 → { ( rmw 0 ( a_zp ) ) = cyc 5 }
        0x16 → { ( rmw 0 ( a_zpx ) ) = cyc 6 }
        0x0E → { ( rmw 0 ( a_abs ) ) = cyc 6 }
        0x1E → { ( rmw 0 ( a_absx ) ) = cyc 7 }
        0x4A → { = ra ( sh_lsr ra ) }  // LSR A
        0x46 → { ( rmw 1 ( a_zp ) ) = cyc 5 }
        0x56 → { ( rmw 1 ( a_zpx ) ) = cyc 6 }
        0x4E → { ( rmw 1 ( a_abs ) ) = cyc 6 }
        0x5E → { ( rmw 1 ( a_absx ) ) = cyc 7 }
        0x2A → { = ra ( sh_rol ra ) }  // ROL A
        0x26 → { ( rmw 2 ( a_zp ) ) = cyc 5 }
        0x36 → { ( rmw 2 ( a_zpx ) ) = cyc 6 }
        0x2E → { ( rmw 2 ( a_abs ) ) = cyc 6 }
        0x3E → { ( rmw 2 ( a_absx ) ) = cyc 7 }
        0x6A → { = ra ( sh_ror ra ) }  // ROR A
        0x66 → { ( rmw 3 ( a_zp ) ) = cyc 5 }
        0x76 → { ( rmw 3 ( a_zpx ) ) = cyc 6 }
        0x6E → { ( rmw 3 ( a_abs ) ) = cyc 6 }
        0x7E → { ( rmw 3 ( a_absx ) ) = cyc 7 }

        // ── Jumps / calls / returns ──
        0x4C → { = pc ( a_abs ) = cyc 3 }  // JMP abs
        0x6C → { = pc ( a_ind ) = cyc 5 }  // JMP (ind)
        0x20 → {  // JSR abs
            : i target ( fetch16 )
            ( push16 & - pc 1 0xFFFF )
            = pc target = cyc 6
        }
        0x60 → { = pc & + ( pull16 ) 1 0xFFFF = cyc 6 }  // RTS
        0x40 → {  // RTI
            = rp | & ( pull8 ) 0xEF 0x20
            = pc ( pull16 ) = cyc 6
        }
        0x00 → {  // BRK
            = pc & + pc 1 0xFFFF
            ( push16 pc )
            ( push8 | rp 0x30 )
            ( set_i 1 )
            = pc ( rd16 0xFFFE ) = cyc 7
        }

        // ── Branches ──
        0x90 → { ( branch == ( p_c ) 0 ) }  // BCC
        0xB0 → { ( branch != ( p_c ) 0 ) }  // BCS
        0xD0 → { ( branch == ( p_z ) 0 ) }  // BNE
        0xF0 → { ( branch != ( p_z ) 0 ) }  // BEQ
        0x10 → { ( branch == ( p_n ) 0 ) }  // BPL
        0x30 → { ( branch != ( p_n ) 0 ) }  // BMI
        0x50 → { ( branch == ( p_v ) 0 ) }  // BVC
        0x70 → { ( branch != ( p_v ) 0 ) }  // BVS

        // ── Flag ops ──
        0x18 → { ( set_c 0 ) }  // CLC
        0x38 → { ( set_c 1 ) }  // SEC
        0x58 → { ( set_i 0 ) }  // CLI
        0x78 → { ( set_i 1 ) }  // SEI
        0xD8 → { ( set_d 0 ) }  // CLD
        0xF8 → { ( set_d 1 ) }  // SED
        0xB8 → { ( set_v 0 ) }  // CLV

        0xEA → {}  // NOP
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
: ~ s g_vicreg 0  // 64-byte VIC-II register file
: ~ s g_sidreg 0  // 32-byte SID register file (sound out of scope here)
: ~ s g_cia2reg 0  // 16-byte CIA2 register file (serial/NMI — dumb here)
: ~ s g_fb 0  // 384x272 colour-index framebuffer (*u, with border)
: ~ s g_fg 0  // 384x272 foreground mask (1 = bg-graphics fg pixel) — sprite priority
: ~ s g_sprcov 0  // 384x272 per-pixel sprite coverage bitmask — collision detection
: ~ i g_coll_ss 0  // sprite-sprite collisions this frame ($D01E)
: ~ i g_coll_sb 0  // sprite-background collisions this frame ($D01F)
: ~ s g_lineborder 0  // per-raster-line border colour (312 bytes) — for raster splits
: ~ s g_linebg 0  // per-raster-line background colour (312 bytes)
: ~ i g_raster 0  // current raster line 0..311 (PAL)
: ~ i g_rasdot 0  // cycle within the current raster line
: ~ i g_frames 0  // completed video frames

// ── CIA1 (keyboard + the jiffy-IRQ timer) ───────────────────────────
: ~ s g_kb 0  // 8-byte keyboard matrix (row bit set = key down)
: ~ i c1_pra 0xFF  // port A (keyboard column select, joystick #2)
: ~ i c1_prb 0xFF  // port B (keyboard rows, joystick #1)
: ~ i c1_ddra 0 : ~ i c1_ddrb 0
: ~ i c1_ta 0xFFFF  // Timer A counter
: ~ i c1_tb 0xFFFF  // Timer B counter
: ~ i c1_ta_lo 0 : ~ i c1_ta_hi 0 : ~ i c1_tb_lo 0 : ~ i c1_tb_hi 0
: ~ i c1_cra 0 : ~ i c1_crb 0
: ~ i c1_icr 0  // interrupt pending flags (bit0 TA, bit1 TB)
: ~ i c1_imask 0  // enabled-interrupt mask

// ── CIA2 (VIC bank select + serial bus; its IRQ output is the NMI) ──
: ~ i c2_pra 0x17  // port A (bits 0-1 = inverted VIC bank, serial bus)
: ~ i c2_prb 0xFF
: ~ i c2_ddra 0x3F : ~ i c2_ddrb 0
: ~ i c2_ta 0xFFFF : ~ i c2_tb 0xFFFF
: ~ i c2_ta_lo 0 : ~ i c2_ta_hi 0 : ~ i c2_tb_lo 0 : ~ i c2_tb_hi 0
: ~ i c2_cra 0 : ~ i c2_crb 0
: ~ i c2_icr 0 : ~ i c2_imask 0
: ~ i g_restore 0  // RESTORE key held (wired straight to the NMI line)
: ~ i g_nmi_prev 0  // previous NMI-line level (NMI is edge-triggered)

@ vreg i r → i { : *u v # *u g_vicreg ^ & # i . v & r 0x3F 255 }

@ cia2_pra → i { ^ c2_pra }

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
        0x0E → { = c1_cra b ? != 0 & b 0x10 { = c1_ta | c1_ta_lo << c1_ta_hi 8 } {} }
        0x0F → { = c1_crb b ? != 0 & b 0x10 { = c1_tb | c1_tb_lo << c1_tb_hi 8 } {} }
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

// ── CIA2 register access (same shape as CIA1; output drives the NMI) ──
@ cia2_read i reg → i {
    ?? reg {
        0x00 → ^ c2_pra
        0x01 → ^ c2_prb
        0x02 → ^ c2_ddra
        0x03 → ^ c2_ddrb
        0x04 → ^ & c2_ta 0xFF
        0x05 → ^ & >> c2_ta 8 0xFF
        0x06 → ^ & c2_tb 0xFF
        0x07 → ^ & >> c2_tb 8 0xFF
        0x0D → { : ~ i vv c2_icr ? != 0 & & c2_icr c2_imask 0x1F { = vv | vv 0x80 } {} = c2_icr 0 ^ vv }
        0x0E → ^ c2_cra
        0x0F → ^ c2_crb
        _ → ^ 0
    }
}

@ cia2_write i reg i b → v {
    ?? reg {
        0x00 → = c2_pra b
        0x01 → = c2_prb b
        0x02 → = c2_ddra b
        0x03 → = c2_ddrb b
        0x04 → = c2_ta_lo b
        0x05 → = c2_ta_hi b
        0x06 → = c2_tb_lo b
        0x07 → = c2_tb_hi b
        0x0D → { ? != 0 & b 0x80 { = c2_imask | c2_imask & b 0x1F } { = c2_imask & c2_imask & ^^ b 0xFF 0x1F } }
        0x0E → { = c2_cra b ? != 0 & b 0x10 { = c2_ta | c2_ta_lo << c2_ta_hi 8 } {} }
        0x0F → { = c2_crb b ? != 0 & b 0x10 { = c2_tb | c2_tb_lo << c2_tb_hi 8 } {} }
        _ → {}
    }
}

@ cia2_tick i cyc → v {
    ? & != 0 & c2_cra 1 == 0 & c2_cra 0x20 {
        ? >= c2_ta cyc { = c2_ta - c2_ta cyc } {
            = c2_icr | c2_icr 1
            : i over - cyc c2_ta
            : i latch | c2_ta_lo << c2_ta_hi 8
            = c2_ta & - latch over 0xFFFF
            ? != 0 & c2_cra 8 { = c2_cra & c2_cra 0xFE } {}
        }
    } {}
    ? & != 0 & c2_crb 1 == 0 & c2_crb 0x60 {
        ? >= c2_tb cyc { = c2_tb - c2_tb cyc } {
            = c2_icr | c2_icr 2
            : i over - cyc c2_tb
            : i latch | c2_tb_lo << c2_tb_hi 8
            = c2_tb & - latch over 0xFFFF
            ? != 0 & c2_crb 8 { = c2_crb & c2_crb 0xFE } {}
        }
    } {}
}
// CIA2's interrupt output is wired to /NMI; RESTORE is wired there too.
@ cia2_nmi → i { ^ ? != 0 & & c2_icr c2_imask 0x1F 1 0 }

@ nmi_line → i { ^ ? != 0 | ( cia2_nmi ) g_restore 1 0 }

// ── VIC-II / SID register access ────────────────────────────────────
@ vic_read i reg → i {
    : *u v # *u g_vicreg
    ? == reg 0x11 { ^ | & & # i . v 0x11 255 0x7F << & >> g_raster 8 1 7 } {}
    ? == reg 0x12 { ^ & g_raster 0xFF } {}
    ? == reg 0x19 { ^ | | & # i . v 0x19 255 0x70 ? != 0 ( vic_irq ) 0x80 0 } {}  // latch + asserted bit
    ? == reg 0x1A { ^ | & # i . v 0x1A 255 0xF0 } {}  // unused enable bits read 1
    ? == reg 0x1E { : i cv & # i . v 0x1E 255 = . v 0x1E # u 0 ^ cv } {}  // clear on read
    ? == reg 0x1F { : i cv & # i . v 0x1F 255 = . v 0x1F # u 0 ^ cv } {}
    ? >= reg 0x2F { ^ 0xFF } {}  // unused registers read $FF
    ? >= reg 0x20 { ^ | & # i . v reg 255 0xF0 } {}  // colour registers: upper nibble 1
    ^ & # i . v reg 255
}
// VIC raster/collision IRQ asserted = any latched source that is enabled.
@ vic_irq → i {
    : *u v # *u g_vicreg
    ^ ? != 0 & & # i . v 0x19 # i . v 0x1A 0x0F 1 0
}

@ vic_write i reg i b → v {
    : *u v # *u g_vicreg
    ? == reg 0x19 {
        = . v 0x19 # u & & # i . v 0x19 255 ^^ b 0xFF  // writing 1 acks an IRQ latch bit
    } {
        = . v reg # u b
    }
}

@ sid_read i reg → i {
    : *u s # *u g_sidreg
    ? == reg 0x1B { ^ & >> ( peek_acc 2 ) 16 0xFF } {}  // OSC3 = voice-3 waveform hi byte
    ? == reg 0x1C { ^ & ( peek_env 2 ) 0xFF } {}  // ENV3 = voice-3 envelope
    ^ & # i . s reg 255
}

@ sid_write i reg i b → v { : *u s # *u g_sidreg = . s reg # u b }

// ════════════════════════════════════════════════════════════════════
//  SID (6581) — 3 voices, ADSR envelopes, tri/saw/pulse/noise. Mixed and
//  resampled to 48 kHz into a stereo ring the host drains via Web Audio
//  (the same path as the Game Boy APU). No filter yet.
// ════════════════════════════════════════════════════════════════════
: ~ s g_audio 0  // i64 ring: low16 = L, bits16-31 = R (both signed 16)
: ~ i g_audio_len 0
: i g_audio_cap 4096
: ~ i g_smp_acc 0  // resample accumulator (adds 48000/cycle; emit at 985248)
: ~ s g_v_acc 0  // per-voice 24-bit phase accumulator (3 i64)
: ~ s g_v_lfsr 0  // per-voice 23-bit noise LFSR
: ~ s g_v_env 0  // per-voice envelope value 0..255
: ~ s g_v_st 0  // 0 release, 1 attack, 2 decay, 3 sustain
: ~ s g_v_rc 0  // rate counter
: ~ s g_v_ec 0  // exponential counter
: ~ s g_v_gate 0  // previous gate bit
: ~ s g_v_wrap 0  // did this voice's accumulator overflow this tick (hard sync)
: ~ i g_f_lp 0  // SID filter state-variable: low-pass integrator
: ~ i g_f_bp 0  // SID filter state-variable: band-pass integrator
: ~ s g_disk 0  // attached 1541 .d64 image (virtual drive 8)
: ~ i g_disk_size 0
: ~ s g_filebuf 0  // scratch holding one extracted file (raw PRG bytes)
: ~ i g_file_track 0
: ~ i g_file_sector 0

@ peek_acc i v → i { ^ ( nurl_peek g_v_acc v ) }

@ peek_env i v → i { ^ ( nurl_peek g_v_env v ) }

@ sreg i off → i { : *u s # *u g_sidreg ^ & # i . s off 255 }

// ADSR rate-counter period (PAL SID clocks) for rate code 0..15.
@ sid_rate i n → i {
    ?? & n 15 {
        0 → ^ 9 1 → ^ 32 2 → ^ 63 3 → ^ 95
        4 → ^ 149 5 → ^ 220 6 → ^ 267 7 → ^ 313
        8 → ^ 392 9 → ^ 977 10 → ^ 1954 11 → ^ 3126
        12 → ^ 3907 13 → ^ 11720 14 → ^ 19532 _ → ^ 31251
    }
}
// Exponential decay/release: env steps down once per this many rate-ticks.
@ sid_exp i env → i {
    ? >= env 0x5D { ^ 1 } {}
    ? >= env 0x36 { ^ 2 } {}
    ? >= env 0x1A { ^ 4 } {}
    ? >= env 0x0E { ^ 8 } {}
    ? >= env 0x06 { ^ 16 } {}
    ^ 30
}
// 12-bit waveform output for a voice (tri/saw/pulse/noise AND-combined).
@ sid_wave i v → i {
    : i base * v 7
    : i ctrl ( sreg + base 4 )
    : i acc ( nurl_peek g_v_acc v )
    : i pw | ( sreg + base 2 ) << & ( sreg + base 3 ) 0x0F 8
    : ~ i out 0xFFF
    : ~ i any 0
    ? != 0 & ctrl 0x10 {  // triangle (ring-mod XORs the source MSB)
        : i src ? == v 0 2 - v 1
        : i msb ? != 0 & ctrl 0x04 & ^^ >> acc 23 >> ( nurl_peek g_v_acc src ) 23 1 & >> acc 23 1
        : i t & >> acc 11 0xFFF
        = out & out ? != 0 msb ^^ t 0xFFF t
        = any 1
    } {}
    ? != 0 & ctrl 0x20 { = out & out & >> acc 12 0xFFF = any 1 } {}  // sawtooth
    ? != 0 & ctrl 0x40 { = out & out ? >= & >> acc 12 0xFFF pw 0xFFF 0 = any 1 } {}  // pulse
    ? != 0 & ctrl 0x80 {  // noise
        : i lf ( nurl_peek g_v_lfsr v )
        : i n | | | | | | | << & >> lf 22 1 11 << & >> lf 20 1 10 << & >> lf 16 1 9 << & >> lf 13 1 8 << & >> lf 11 1 7 << & >> lf 7 1 6 << & >> lf 4 1 5 << & >> lf 2 1 4
        = out & out & n 0xFFF
        = any 1
    } {}
    ^ ? != 0 any out 0
}

// Emit one mixed stereo sample into the ring. Voices routed through the
// filter ($D417) feed a Chamberlin state-variable filter (fixed-point,
// 1/1024); $D418 selects which of LP/BP/HP reaches the output.
@ sid_emit → v {
    ? >= g_audio_len g_audio_cap { ^ v } {}
    : i master & ( sreg 0x18 ) 0x0F
    : i v3off & ( sreg 0x18 ) 0x80
    : i fen ( sreg 0x17 )  // filter-routing bits (per voice)
    : ~ i dry 0  // voices straight to output
    : ~ i wet 0  // voices into the filter
    : ~ i v 0
    ~ < v 3 {
        ? & == v 2 != 0 v3off {} {
            : i wf ( sid_wave v )
            : i env ( nurl_peek g_v_env v )
            : i s / * - wf 2048 env 255
            ? != 0 & fen << 1 v { = wet + wet s } { = dry + dry s }
        }
        = v + v 1
    }
    // State-variable filter on the wet sum.
    : i fc | & ( sreg 0x15 ) 7 << ( sreg 0x16 ) 3  // 11-bit cutoff
    : i f ? > * fc 3 3600 900 / * fc 3 4  // f = min(fc*3/4, 900) /1024
    : i res >> ( sreg 0x17 ) 4
    : i q ? < - 1024 * res 60 120 120 - 1024 * res 60  // q = max(1024-res*60, 120)
    : i hp - - wet g_f_lp / * q g_f_bp 1024
    : i bp + g_f_bp / * f hp 1024
    : i lp + g_f_lp / * f bp 1024
    = g_f_bp bp = g_f_lp lp
    : i mode ( sreg 0x18 )
    : ~ i fout 0
    ? != 0 & mode 0x10 { = fout + fout lp } {}
    ? != 0 & mode 0x20 { = fout + fout bp } {}
    ? != 0 & mode 0x40 { = fout + fout hp } {}
    : i mix + dry fout
    : ~ i o / * * mix master 4 15  // (mix × master × 4) / 15
    ? > o 32767 { = o 32767 } {}
    ? < o -32767 { = o -32767 } {}
    ( nurl_poke g_audio g_audio_len | & o 0xFFFF << & o 0xFFFF 16 )
    = g_audio_len + g_audio_len 1
}

// Advance all three voices + envelopes by `cyc` SID clocks, resampling.
@ sid_tick i cyc → v {
    : ~ i v 0
    ~ < v 3 {
        : i base * v 7
        : i ctrl ( sreg + base 4 )
        : i gate & ctrl 1
        : i pg ( nurl_peek g_v_gate v )
        ? & != 0 gate == pg 0 { ( nurl_poke g_v_st v 1 ) ( nurl_poke g_v_rc v 0 ) } {}  // gate↑ → attack
        ? & == 0 gate != pg 0 { ( nurl_poke g_v_st v 0 ) } {}  // gate↓ → release
        ( nurl_poke g_v_gate v gate )
        // Phase accumulator (TEST bit zeroes it); record any overflow for sync.
        : i freq | ( sreg base ) << ( sreg + base 1 ) 8
        ? != 0 & ctrl 0x08 { ( nurl_poke g_v_acc v 0 ) ( nurl_poke g_v_wrap v 0 ) } {
            : i raw + ( nurl_peek g_v_acc v ) * freq cyc
            ( nurl_poke g_v_wrap v ? >= raw 0x1000000 1 0 )
            ( nurl_poke g_v_acc v & raw 0xFFFFFF )
        }
        // Noise LFSR — clock ~ once per bit-19 advance.
        : ~ i nclk & >> * freq cyc 19 63
        ~ > nclk 0 {
            : i lf ( nurl_peek g_v_lfsr v )
            : i fb & ^^ >> lf 22 >> lf 17 1
            ( nurl_poke g_v_lfsr v & | << lf 1 fb 0x7FFFFF )
            = nclk - nclk 1
        }
        // Envelope.
        : i ad ( sreg + base 5 )
        : i sr ( sreg + base 6 )
        : i st ( nurl_peek g_v_st v )
        : i rate ? == st 1 & >> ad 4 0x0F ? == st 2 & ad 0x0F & sr 0x0F
        : i period ( sid_rate rate )
        : ~ i rc + ( nurl_peek g_v_rc v ) cyc
        ~ >= rc period {
            = rc - rc period
            : ~ i env ( nurl_peek g_v_env v )
            : i sustain * & >> sr 4 0x0F 0x11
            ?? st {
                1 → { = env + env 1 ? >= env 255 { = env 255 ( nurl_poke g_v_st v 2 ) } {} ( nurl_poke g_v_env v env ) }
                _ → {
                    : i target ? == st 0 0 sustain
                    ? > env target {
                        : ~ i ec + ( nurl_peek g_v_ec v ) 1
                        ? >= ec ( sid_exp env ) { = ec 0 ( nurl_poke g_v_env v - env 1 ) } {}
                        ( nurl_poke g_v_ec v ec )
                    } { ? == st 2 { ( nurl_poke g_v_st v 3 ) } {} }
                }
            }
        }
        ( nurl_poke g_v_rc v rc )
        = v + v 1
    }
    // Hard sync: a voice with SYNC set is zeroed when its source (voice
    // v-1, wrapping 0←2) overflowed this tick.
    : ~ i sv 0
    ~ < sv 3 {
        ? != 0 & ( sreg + * sv 7 4 ) 0x02 {
            : i src ? == sv 0 2 - sv 1
            ? != 0 ( nurl_peek g_v_wrap src ) { ( nurl_poke g_v_acc sv 0 ) } {}
        } {}
        = sv + sv 1
    }
    // Resample to the output rate.
    = g_smp_acc + g_smp_acc * 48000 cyc
    ~ >= g_smp_acc 985248 { = g_smp_acc - g_smp_acc 985248 ( sid_emit ) }
}

@ sid_reset → v {
    = g_audio_len 0 = g_smp_acc 0
    = g_f_lp 0 = g_f_bp 0
    : ~ i v 0
    ~ < v 3 {
        ( nurl_poke g_v_acc v 0 ) ( nurl_poke g_v_lfsr v 0x7FFFFF )
        ( nurl_poke g_v_env v 0 ) ( nurl_poke g_v_st v 0 )
        ( nurl_poke g_v_rc v 0 ) ( nurl_poke g_v_ec v 0 ) ( nurl_poke g_v_gate v 0 )
        ( nurl_poke g_v_wrap v 0 )
        = v + v 1
    }
}

// ── I/O window dispatch ($D000-$DFFF) ───────────────────────────────
@ io_read i a → i {
    ? < a 0xD400 { ^ ( vic_read & a 0x3F ) } {}
    ? < a 0xD800 { ^ ( sid_read & a 0x1F ) } {}
    ? < a 0xDC00 { : *u c # *u g_color ^ | & & # i . c & a 0x3FF 255 0x0F 0xF0 } {}
    ? < a 0xDD00 { ^ ( cia1_read & a 0x0F ) } {}
    ? < a 0xDE00 { ^ ( cia2_read & a 0x0F ) } {}
    ^ 0xFF
}

@ io_write i a i b → v {
    ? < a 0xD400 { ( vic_write & a 0x3F b ) ^ v } {}
    ? < a 0xD800 { ( sid_write & a 0x1F b ) ^ v } {}
    ? < a 0xDC00 { : *u c # *u g_color = . c & a 0x3FF # u & b 0x0F ^ v } {}
    ? < a 0xDD00 { ( cia1_write & a 0x0F b ) ^ v } {}
    ? < a 0xDE00 { ( cia2_write & a 0x0F b ) ^ v } {}
}

// ── Video timing: advance the raster line by `cyc` cycles ────────────
@ vic_tick i cyc → v {
    = g_rasdot + g_rasdot cyc
    ~ >= g_rasdot 63 {
        = g_rasdot - g_rasdot 63
        : *u v # *u g_vicreg
        // Snapshot the border/background colour for the line just finished,
        // so mid-frame ($D020/$D021) changes by a raster IRQ show as splits.
        : *u lb # *u g_lineborder
        : *u lg # *u g_linebg
        ? < g_raster 312 {
            = . lb g_raster # u & # i . v 0x20 255
            = . lg g_raster # u & # i . v 0x21 255
        } {}
        = g_raster + g_raster 1
        ? >= g_raster 312 { = g_raster 0 = g_frames + g_frames 1 } {}
        // Raster compare: latch $D019 bit0 when the line is reached.
        : i cmp | & # i . v 0x12 255 ? != 0 & # i . v 0x11 0x80 0x100 0
        ? == g_raster cmp { = . v 0x19 # u | & # i . v 0x19 255 1 } {}
    }
}

// ── Interrupts ──────────────────────────────────────────────────────
@ irq_enter i vec → v {
    ( push16 pc )
    ( push8 & | rp 0x20 0xEF )  // pushed P: U=1, B=0 (hardware IRQ/NMI)
    ( set_i 1 )
    = pc ( rd16 vec )
}

// One CPU instruction + chip clocking + IRQ dispatch; returns cycles.
@ cpu_advance → i {
    // KERNAL LOAD trap: serve device-8 loads from the attached .d64.
    ? & & & == pc 0xF4A5 != 0 g_disk_size != 0 ( bank_hiram ) >= ( rd8 0xBA ) 8 {
        ( disk_kernal_load )
    } {}
    : ~ i cyc ( step )
    ( cia1_tick cyc )
    ( cia2_tick cyc )
    ( vic_tick cyc )
    ( sid_tick cyc )
    // NMI is edge-triggered and non-maskable (CIA2 / RESTORE).
    : i nl ( nmi_line )
    ? & == nl 1 == g_nmi_prev 0 {
        ( irq_enter 0xFFFA )
        ( cia1_tick 7 ) ( cia2_tick 7 ) ( vic_tick 7 ) ( sid_tick 7 )
        = g_cycles + g_cycles 7 = cyc + cyc 7
        = g_nmi_prev nl
        ^ cyc
    } {}
    = g_nmi_prev nl
    ? & != 0 | ( cia1_irq ) ( vic_irq ) == ( p_i ) 0 {
        ( irq_enter 0xFFFE )
        ( cia1_tick 7 ) ( cia2_tick 7 ) ( vic_tick 7 ) ( sid_tick 7 )
        = g_cycles + g_cycles 7 = cyc + cyc 7
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
    // Rasterise the completed frame: updates the framebuffer AND the sprite
    // collision latches ($D01E/$D01F), so polling games see them each frame.
    ( render_frame )
}

// ── Allocation + ROM loading + boot ─────────────────────────────────
@ blit_into s dst i n * u src → v {
    : *u d # *u dst
    : ~ i i 0
    ~ < i n { = . d i . src i = i + i 1 }
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
    = g_fb ( nurl_zalloc 104448 )  // 384 * 272
    = g_fg ( nurl_zalloc 104448 )
    = g_sprcov ( nurl_zalloc 104448 )
    = g_lineborder ( nurl_zalloc 312 )
    = g_linebg ( nurl_zalloc 312 )
    = g_audio ( nurl_zalloc * g_audio_cap 8 )
    = g_v_acc ( nurl_zalloc 24 ) = g_v_lfsr ( nurl_zalloc 24 )
    = g_v_env ( nurl_zalloc 24 ) = g_v_st ( nurl_zalloc 24 )
    = g_v_rc ( nurl_zalloc 24 ) = g_v_ec ( nurl_zalloc 24 ) = g_v_gate ( nurl_zalloc 24 )
    = g_v_wrap ( nurl_zalloc 24 )
    = g_disk ( nurl_zalloc 196608 ) = g_disk_size 0
    = g_filebuf ( nurl_zalloc 65536 )
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
    = c1_cra 0 = c1_crb 0 = c1_icr 0 = c1_imask 0
    = c1_ta 0xFFFF = c1_tb 0xFFFF
    = c1_ta_lo 0 = c1_ta_hi 0 = c1_tb_lo 0 = c1_tb_hi 0
    = c1_pra 0xFF = c1_prb 0xFF = c1_ddra 0 = c1_ddrb 0
    = c2_cra 0 = c2_crb 0 = c2_icr 0 = c2_imask 0
    = c2_ta 0xFFFF = c2_tb 0xFFFF = c2_pra 0x17 = c2_prb 0xFF = c2_ddra 0x3F = c2_ddrb 0
    = g_restore 0 = g_nmi_prev 0
    = g_raster 0 = g_rasdot 0 = g_frames 0 = g_cycles 0
    ( sid_reset )
    ( cpu_reset )
}

// ── .prg loading + autostart ────────────────────────────────────────
// A .prg is [load-addr-lo, load-addr-hi, ...data...]. Copy the data to
// the load address and, for a BASIC-area program ($0801), fix the
// VARTAB/ARYTAB/STREND pointers so RUN sees the right end-of-program.
// Returns the load address (0 on a malformed image).
@ prg_load * u src i n → i {
    ? < n 3 { ^ 0 } {}
    : i addr | & # i . src 0 255 << & # i . src 1 255 8
    : ~ i i 2
    ~ < i n { ( ram_wr & + addr - i 2 0xFFFF & # i . src i 255 ) = i + i 1 }
    : i end & + addr - n 2 0xFFFF
    ? == addr 0x0801 {
        ( ram_wr 0x2D & end 0xFF ) ( ram_wr 0x2E & >> end 8 0xFF )
        ( ram_wr 0x2F & end 0xFF ) ( ram_wr 0x30 & >> end 8 0xFF )
        ( ram_wr 0x31 & end 0xFF ) ( ram_wr 0x32 & >> end 8 0xFF )
    } {}
    ^ addr
}

// Push a PETSCII byte into the KERNAL keyboard buffer ($0277, count $C6).
@ kbuf_push i ch → v {
    : i cnt ( ram_rd 0xC6 )
    ? < cnt 10 {
        ( ram_wr + 0x277 cnt & ch 0xFF )
        ( ram_wr 0xC6 + cnt 1 )
    } {}
}

@ autorun_basic → v {
    ( kbuf_push 0x52 ) ( kbuf_push 0x55 ) ( kbuf_push 0x4E ) ( kbuf_push 0x0D )  // RUN⏎
}
// Type "SYS<addr>⏎" (decimal). NURL has '/' but no '%', so x%10 = x-10*(x/10).
@ autorun_sys i addr → v {
    ( kbuf_push 0x53 ) ( kbuf_push 0x59 ) ( kbuf_push 0x53 )  // SYS
    : ~ i div 10000
    : ~ i started 0
    ~ > div 0 {
        : i q / addr div
        : i d - q * 10 / q 10
        ? != 0 | d started { ( kbuf_push + 0x30 d ) = started 1 } {}
        = div / div 10
    }
    ? == started 0 { ( kbuf_push 0x30 ) } {}
    ( kbuf_push 0x0D )
}
// Load a .prg and queue its autostart (RUN for $0801, else SYS load-addr).
@ prg_autostart * u src i n → i {
    : i addr ( prg_load src n )
    ? == addr 0 { ^ 0 } {}
    ? == addr 0x0801 { ( autorun_basic ) } { ( autorun_sys addr ) }
    ^ addr
}

// ════════════════════════════════════════════════════════════════════
//  1541 .d64 disk image — a virtual drive 8. We parse the CBM DOS
//  filesystem directly (BAM + directory + track/sector chains) and trap
//  the KERNAL LOAD routine, so LOAD"NAME",8 / LOAD"*",8,1 / LOAD"$",8 all
//  work without emulating the 1541's own 6502.
// ════════════════════════════════════════════════════════════════════

// Sectors per track (1-based) and the byte offset of a (track, sector).
@ d64_spt i t → i {
    ? <= t 17 { ^ 21 } {}
    ? <= t 24 { ^ 19 } {}
    ? <= t 30 { ^ 18 } {}
    ^ 17
}

@ d64_off i t i s → i {
    : ~ i sec 0
    : ~ i tt 1
    ~ < tt t { = sec + sec ( d64_spt tt ) = tt + tt 1 }
    ^ * + sec s 256
}

@ disk_byte i off → i {
    ? | < off 0 >= off g_disk_size { ^ 0 } {}
    : *u d # *u g_disk
    ^ & # i . d off 255
}
// Match a directory entry (at entryoff) against a filename in C64 RAM.
@ disk_match i nameptr i namelen i entryoff → i {
    : ~ i i 0
    ~ < i namelen {
        : i nc & ( ram_rd + nameptr i ) 255
        ? == nc 42 { ^ 1 } {}  // '*' → wildcard, rest matches
        ? != nc ( disk_byte + entryoff + 5 i ) { ^ 0 } {}
        = i + i 1
    }
    ? < namelen 16 {
        : i dc ( disk_byte + entryoff + 5 namelen )  // name must end here ($A0/end)
        ? & != dc 0xA0 != dc 0 { ^ 0 } {}
    } {}
    ^ 1
}
// Find a file (name in C64 RAM). Sets g_file_track/sector; returns 1/0.
@ disk_find i nameptr i namelen → i {
    : ~ i t 18 : ~ i s 1 : ~ i guard 0
    ~ & != t 0 < guard 40 {
        : i base ( d64_off t s )
        : i nt ( disk_byte base )
        : i ns ( disk_byte + base 1 )
        : ~ i e 0
        ~ < e 8 {
            : i eo + base * e 32
            ? != 0 & ( disk_byte + eo 2 ) 0x07 {
                ? != 0 ( disk_match nameptr namelen eo ) {
                    = g_file_track ( disk_byte + eo 3 )
                    = g_file_sector ( disk_byte + eo 4 )
                    ^ 1
                } {}
            } {}
            = e + e 1
        }
        = t nt = s ns = guard + guard 1
    }
    ^ 0
}
// Find the first PRG entry (for autostart). Sets g_file_track/sector.
@ disk_find_first → i {
    : ~ i t 18 : ~ i s 1 : ~ i guard 0
    ~ & != t 0 < guard 40 {
        : i base ( d64_off t s )
        : i nt ( disk_byte base )
        : i ns ( disk_byte + base 1 )
        : ~ i e 0
        ~ < e 8 {
            : i eo + base * e 32
            ? == 2 & ( disk_byte + eo 2 ) 0x07 {
                = g_file_track ( disk_byte + eo 3 )
                = g_file_sector ( disk_byte + eo 4 )
                ^ 1
            } {}
            = e + e 1
        }
        = t nt = s ns = guard + guard 1
    }
    ^ 0
}
// Follow the track/sector chain from g_file_track/sector into g_filebuf.
@ disk_read_file → i {
    : ~ i t g_file_track : ~ i s g_file_sector
    : *u d # *u g_filebuf
    : ~ i len 0 : ~ i guard 0
    ~ & != t 0 < guard 800 {
        : i base ( d64_off t s )
        : i nt ( disk_byte base )
        : i ns ( disk_byte + base 1 )
        : i count ? == nt 0 - ns 1 254  // last sector: ns = last used byte index
        : ~ i i 0
        ~ < i count { = . d + len i # u ( disk_byte + base + 2 i ) = i + i 1 }
        = len + len count
        = t nt = s ns = guard + guard 1
    }
    ^ len
}

@ disk_attach * u src i n → v {
    : i cap ? > n 196608 196608 n
    = g_disk_size cap
    : *u d # *u g_disk
    : ~ i i 0
    ~ < i cap { = . d i . src i = i + i 1 }
}
// Auto-load + run the first program on the disk (drop-a-.d64 convenience).
@ disk_autostart → i {
    ? == 0 ( disk_find_first ) { ^ 0 } {}
    : i flen ( disk_read_file )
    ? < flen 3 { ^ 0 } {}
    ^ ( prg_autostart # *u g_filebuf flen )
}

// ── KERNAL LOAD trap ($F4A5) — serve files straight from the image ──
@ fbuf_byte i i → i { : *u fb # *u g_filebuf ^ & # i . fb i 255 }

@ disk_rts → v { = pc & + ( pull16 ) 1 0xFFFF }
// 3-letter file-type mnemonic for the directory listing.
@ disk_type3 i p i ty → v {
    ?? ty {
        1 → { ( ram_wr p 83 ) ( ram_wr + p 1 69 ) ( ram_wr + p 2 81 ) }  // SEQ
        2 → { ( ram_wr p 80 ) ( ram_wr + p 1 82 ) ( ram_wr + p 2 71 ) }  // PRG
        3 → { ( ram_wr p 85 ) ( ram_wr + p 1 83 ) ( ram_wr + p 2 82 ) }  // USR
        4 → { ( ram_wr p 82 ) ( ram_wr + p 1 69 ) ( ram_wr + p 2 76 ) }  // REL
        _ → { ( ram_wr p 68 ) ( ram_wr + p 1 69 ) ( ram_wr + p 2 76 ) }  // DEL
    }
}
// LOAD"$",8 → synthesise a BASIC directory program at $0801.
@ disk_load_dir → v {
    : i bam ( d64_off 18 0 )
    : ~ i p 0x0801
    // Header line (line number 0): reverse-video disk name.
    : i l0 p
    = p + p 2
    ( ram_wr p 0 ) ( ram_wr + p 1 0 ) = p + p 2
    ( ram_wr p 0x12 ) = p + p 1
    ( ram_wr p 34 ) = p + p 1
    : ~ i k 0
    ~ < k 16 { : i c ( disk_byte + bam + 0x90 k ) ( ram_wr p ? == c 0xA0 32 c ) = p + p 1 = k + k 1 }
    ( ram_wr p 34 ) = p + p 1
    ( ram_wr p 0 ) = p + p 1
    ( ram_wr l0 & p 0xFF ) ( ram_wr + l0 1 & >> p 8 0xFF )
    // One BASIC line per directory entry.
    : ~ i t 18 : ~ i s 1 : ~ i guard 0
    ~ & != t 0 < guard 40 {
        : i base ( d64_off t s )
        : i nt ( disk_byte base )
        : i ns ( disk_byte + base 1 )
        : ~ i e 0
        ~ < e 8 {
            : i eo + base * e 32
            : i ty & ( disk_byte + eo 2 ) 0x07
            ? != 0 ty {
                : i blocks | ( disk_byte + eo 30 ) << ( disk_byte + eo 31 ) 8
                : i ll p
                = p + p 2
                ( ram_wr p & blocks 0xFF ) ( ram_wr + p 1 & >> blocks 8 0xFF ) = p + p 2
                ( ram_wr p 32 ) = p + p 1
                ( ram_wr p 34 ) = p + p 1
                : ~ i kk 0
                ~ < kk 16 { : i c ( disk_byte + eo + 5 kk ) ? != c 0xA0 { ( ram_wr p c ) = p + p 1 } {} = kk + kk 1 }
                ( ram_wr p 34 ) = p + p 1
                ( ram_wr p 32 ) = p + p 1
                ( disk_type3 p ty ) = p + p 3
                ( ram_wr p 0 ) = p + p 1
                ( ram_wr ll & p 0xFF ) ( ram_wr + ll 1 & >> p 8 0xFF )
            } {}
            = e + e 1
        }
        = t nt = s ns = guard + guard 1
    }
    ( ram_wr p 0 ) ( ram_wr + p 1 0 )
    : i endp + p 2
    ( ram_wr 0x2D & endp 0xFF ) ( ram_wr 0x2E & >> endp 8 0xFF )
    ( ram_wr 0x2F & endp 0xFF ) ( ram_wr 0x30 & >> endp 8 0xFF )
    ( ram_wr 0x31 & endp 0xFF ) ( ram_wr 0x32 & >> endp 8 0xFF )
    = rx & endp 0xFF = ry & >> endp 8 0xFF
    ( set_c 0 ) ( ram_wr 0x90 0 )
    ( disk_rts )
}

@ disk_kernal_load → v {
    : i sec ( rd8 0xB9 )
    : i namelen ( rd8 0xB7 )
    : i nameptr | ( rd8 0xBB ) << ( rd8 0xBC ) 8
    : i first ? > namelen 0 ( ram_rd nameptr ) 0
    ? & == namelen 1 == first 36 { ( disk_load_dir ) ^ v } {}  // "$" directory
    ? == 0 ( disk_find nameptr namelen ) {
        ( set_c 1 ) ( ram_wr 0x90 0x42 )  // FILE NOT FOUND
        ( disk_rts ) ^ v
    } {}
    : i flen ( disk_read_file )
    : i loadaddr ? == sec 0 | rx << ry 8 | ( fbuf_byte 0 ) << ( fbuf_byte 1 ) 8
    : *u fb # *u g_filebuf
    : ~ i i 2
    ~ < i flen { ( ram_wr & + loadaddr - i 2 0xFFFF & # i . fb i 255 ) = i + i 1 }
    : i end & + loadaddr - flen 2 0xFFFF
    = rx & end 0xFF = ry & >> end 8 0xFF
    ( set_c 0 ) ( ram_wr 0x90 0 )
    ( disk_rts )
}

// ── Rendering: VIC-II → colour-index framebuffer ────────────────────
// Plot a display pixel and record whether it's "foreground" (set bit /
// MC high-bit) so bg-priority sprites can hide behind it.
@ put_px i px i py i c i fg → v {
    ? & & >= px 0 < px 384 & >= py 0 < py 272 {
        : *u fb # *u g_fb
        : *u fm # *u g_fg
        : i idx + * py 384 px
        = . fb idx # u c
        = . fm idx # u fg
    } {}
}
// CHARGEN ROM ($1000/$1800 in VIC bank 0) or a RAM character set.
@ char_bits i cbase i sc i ln → i {
    : *u cg # *u g_chargen
    ? == cbase 0x1000 { ^ & # i . cg + * sc 8 ln 255 } {}
    ? == cbase 0x1800 { ^ & # i . cg + 0x800 + * sc 8 ln 255 } {}
    ^ ( ram_rd + + cbase * sc 8 ln )
}

@ line_bg i r i ln → i {
    : *u lg # *u g_linebg
    ^ & & # i . lg + 50 + * r 8 ln 255 0x0F
}

@ render_frame → v {
    : *u fb # *u g_fb
    : *u lb # *u g_lineborder
    : ~ i py 0
    ~ < py 272 {
        : i ras + py 14
        : i bcol & # i . lb ? < ras 312 ras 311 255
        : ~ i px 0
        ~ < px 384 { = . fb + * py 384 px # u bcol = px + px 1 }
        = py + py 1
    }
    // Display enable (DEN, $D011 bit4) off → blanked to border.
    ? == 0 & ( vreg 0x11 ) 0x10 { ^ v } {}
    : *u fm # *u g_fg
    : ~ i i 0 ~ < i 104448 { = . fm i # u 0 = i + i 1 }
    : i bmm & ( vreg 0x11 ) 0x20  // bitmap mode
    : i mcm & ( vreg 0x16 ) 0x10  // multicolour
    ? != 0 bmm { ( render_bitmap ? != 0 mcm 1 0 ) } { ( render_text ? != 0 mcm 1 0 ) }
    ( render_sprites )
}

// Standard / multicolour character mode.
@ render_text i mcm → v {
    : *u cram # *u g_color
    : i d18 ( vreg 0x18 )
    : i scrbase + * & ^^ ( cia2_pra ) 0xFF 3 0x4000 * & >> d18 4 0xF 0x400
    : i cbase * & >> d18 1 7 0x800
    : i d22 & ( vreg 0x22 ) 0x0F
    : i d23 & ( vreg 0x23 ) 0x0F
    : ~ i r 0
    ~ < r 25 {
        : ~ i col 0
        ~ < col 40 {
            : i ci + * r 40 col
            : i sc & ( ram_rd + scrbase ci ) 0xFF
            : i colb & # i . cram ci 255
            : i mcch ? & != 0 mcm != 0 & colb 0x08 1 0
            : ~ i ln 0
            ~ < ln 8 {
                : i bits ( char_bits cbase sc ln )
                : i bg ( line_bg r ln )
                : i py + + 36 * r 8 ln
                ? != 0 mcch {
                    : i fgc & colb 0x07
                    : ~ i p 0
                    ~ < p 4 {
                        : i vv & >> bits - 6 * 2 p 3
                        : i c ? == vv 0 bg ? == vv 1 d22 ? == vv 2 d23 fgc
                        : i px0 + + 32 * col 8 * p 2
                        ( put_px px0 py c ? >= vv 2 1 0 )
                        ( put_px + px0 1 py c ? >= vv 2 1 0 )
                        = p + p 1
                    }
                } {
                    : i fgc ? != 0 mcm & colb 0x07 & colb 0x0F
                    : ~ i bx 0
                    ~ < bx 8 {
                        : i on & >> bits - 7 bx 1
                        ( put_px + + 32 * col 8 bx py ? != 0 on fgc bg on )
                        = bx + bx 1
                    }
                }
                = ln + ln 1
            }
            = col + col 1
        }
        = r + r 1
    }
}

// Hi-res (320x200) / multicolour (160x200) bitmap mode.
@ render_bitmap i mcm → v {
    : *u cram # *u g_color
    : i d18 ( vreg 0x18 )
    : i vbank * & ^^ ( cia2_pra ) 0xFF 3 0x4000
    : i scrbase + vbank * & >> d18 4 0xF 0x400
    : i bmbase + vbank * & >> d18 3 1 0x2000
    : ~ i r 0
    ~ < r 25 {
        : ~ i col 0
        ~ < col 40 {
            : i ci + * r 40 col
            : i scd & ( ram_rd + scrbase ci ) 0xFF
            : i hi & >> scd 4 0x0F
            : i lo & scd 0x0F
            : i colr & # i . cram ci 0x0F
            : ~ i ln 0
            ~ < ln 8 {
                : i byte & ( ram_rd + + bmbase * ci 8 ln ) 255
                : i bg ( line_bg r ln )
                : i py + + 36 * r 8 ln
                ? != 0 mcm {
                    : ~ i p 0
                    ~ < p 4 {
                        : i vv & >> byte - 6 * 2 p 3
                        : i c ? == vv 0 bg ? == vv 1 hi ? == vv 2 lo colr
                        : i px0 + + 32 * col 8 * p 2
                        ( put_px px0 py c ? >= vv 2 1 0 )
                        ( put_px + px0 1 py c ? >= vv 2 1 0 )
                        = p + p 1
                    }
                } {
                    : ~ i bx 0
                    ~ < bx 8 {
                        : i on & >> byte - 7 bx 1
                        ( put_px + + 32 * col 8 bx py ? != 0 on hi lo on )
                        = bx + bx 1
                    }
                }
                = ln + ln 1
            }
            = col + col 1
        }
        = r + r 1
    }
}

// ── VIC-II hardware sprites (hi-res + multicolour + X/Y expand) ──────
// Colour-index 255 is the transparent sentinel. With `prio` set the
// sprite is behind foreground graphics, so skip pixels the bg marked fg.
@ spr_px i fx i fy i c i s i prio → v {
    ? & & >= fx 0 < fx 384 & >= fy 0 < fy 272 {
        : *u fb # *u g_fb
        : *u fm # *u g_fg
        : *u cov # *u g_sprcov
        : i idx + * fy 384 fx
        : i bit << 1 s
        : i cv & # i . cov idx 255
        ? != 0 cv { = g_coll_ss | g_coll_ss | bit cv } {}  // overlapped another sprite
        ? != 0 & # i . fm idx 255 { = g_coll_sb | g_coll_sb bit } {}  // overlapped foreground
        = . cov idx # u | cv bit
        ? & != 0 prio != 0 & # i . fm idx 255 {} { = . fb idx # u c }
    } {}
}

@ draw_sprite i s i scrbase i vbank i mc i mcm0 i mcm1 i col i xexp i yexp i prio → v {
    : *u v # *u g_vicreg
    : i x | & # i . v * s 2 255 ? != 0 & ( vreg 0x10 ) << 1 s 0x100 0
    : i y & # i . v + * s 2 1 255
    : i ptr & ( ram_rd + + scrbase 0x3F8 s ) 255
    : i data + vbank * ptr 64
    : i ox + x 8  // VIC X=24 → framebuffer x=32
    : i oy - y 14  // VIC Y=50 → framebuffer y=36
    : i xstep ? != 0 xexp 2 1
    : i ystep ? != 0 yexp 2 1
    : ~ i row 0
    ~ < row 21 {
        : ~ i sx 0
        ~ < sx 24 {
            : i bi / sx 8
            : i byte & ( ram_rd + + data * row 3 bi ) 255
            : i inb - sx * 8 bi
            : ~ i c 255
            ? != 0 mc {
                : i bits & >> byte - 6 * 2 / inb 2 3
                = c ? == bits 0 255 ? == bits 1 mcm0 ? == bits 2 col mcm1
            } {
                = c ? != 0 & >> byte - 7 inb 1 col 255
            }
            ? < c 16 {
                : i fx0 + ox * sx xstep
                : i fy0 + oy * row ystep
                : ~ i dy 0
                ~ < dy ystep {
                    : ~ i dx 0
                    ~ < dx xstep { ( spr_px + fx0 dx + fy0 dy c s prio ) = dx + dx 1 }
                    = dy + dy 1
                }
            } {}
            = sx + sx 1
        }
        = row + row 1
    }
}
// Draw sprites 7→0 so sprite 0 lands on top (lower number = higher priority).
@ render_sprites → v {
    : i en & ( vreg 0x15 ) 0xFF
    ? == en 0 { ^ v } {}
    // Reset per-pixel sprite coverage + this frame's collision accumulators.
    : *u cov # *u g_sprcov
    : ~ i z 0
    ~ < z 104448 { = . cov z # u 0 = z + z 1 }
    = g_coll_ss 0 = g_coll_sb 0
    : i vbank * & ^^ ( cia2_pra ) 0xFF 3 0x4000
    : i scrbase + vbank * & >> ( vreg 0x18 ) 4 0xF 0x400
    : i mcm0 & ( vreg 0x25 ) 0x0F
    : i mcm1 & ( vreg 0x26 ) 0x0F
    : ~ i s 7
    ~ >= s 0 {
        ? != 0 & en << 1 s {
            : i col & ( vreg + 0x27 s ) 0x0F
            : i mc ? != 0 & ( vreg 0x1C ) << 1 s 1 0
            : i xexp ? != 0 & ( vreg 0x1D ) << 1 s 1 0
            : i yexp ? != 0 & ( vreg 0x17 ) << 1 s 1 0
            : i prio ? != 0 & ( vreg 0x1B ) << 1 s 1 0
            ( draw_sprite s scrbase vbank mc mcm0 mcm1 col xexp yexp prio )
        } {}
        = s - s 1
    }
    // Accumulate collisions into the latch registers + raise their IRQ source.
    : *u v # *u g_vicreg
    = . v 0x1E # u | & # i . v 0x1E 255 g_coll_ss
    = . v 0x1F # u | & # i . v 0x1F 255 g_coll_sb
    ? != 0 g_coll_ss { = . v 0x19 # u | & # i . v 0x19 255 4 } {}
    ? != 0 g_coll_sb { = . v 0x19 # u | & # i . v 0x19 255 2 } {}
}

// ── Native helper: dump the 40x25 text screen as ASCII ──────────────
@ scr_to_ascii i sc → i {
    : i c & sc 0x7F
    ? == c 0 { ^ 64 } {}  // '@'
    ? & >= c 1 <= c 26 { ^ + 64 c } {}  // A-Z
    ? & >= c 27 <= c 31 { ^ + 64 c } {}  // [ \ ] ^ _
    ? & >= c 32 <= c 63 { ^ c } {}  // space, digits, punctuation (ASCII)
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

// Native helper: summarise the SID audio ring (non-zero + peak sample).
@ audio_stats → v {
    : ~ i nz 0
    : ~ i mx 0
    : ~ i sum 0
    : ~ i i 0
    ~ < i g_audio_len {
        : i s ( nurl_peek g_audio i )
        : i l & s 0xFFFF
        : i sv ? >= l 0x8000 - l 0x10000 l
        ? != 0 sv { = nz + nz 1 } {}
        : i a ? < sv 0 - 0 sv sv
        ? > a mx { = mx a } {}
        = sum + sum a
        = i + i 1
    }
    ( nurl_print `audio: ` ) ( nurl_print ( nurl_str_int g_audio_len ) ) ( nurl_print ` samples, ` )
    ( nurl_print ( nurl_str_int nz ) ) ( nurl_print ` nonzero, peak ` ) ( nurl_print ( nurl_str_int mx ) )
    ( nurl_print `, sum|amp| ` ) ( nurl_print ( nurl_str_int sum ) ) ( nurl_print `\n` )
}

// Native helpers for verifying the VIC framebuffer headlessly.
@ fb_color_at i x i y → i { : *u fb # *u g_fb ^ & # i . fb + * ? < y 272 y 271 384 ? < x 384 x 383 255 }

@ fb_hist → v {
    : *u fb # *u g_fb
    : ~ i ci 0
    ~ < ci 16 {
        : ~ i cnt 0
        : ~ i i 0
        ~ < i 104448 { ? == & # i . fb i 255 ci { = cnt + cnt 1 } {} = i + i 1 }
        ? > cnt 0 { ( nurl_print `c` ) ( nurl_print ( nurl_str_int ci ) ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int cnt ) ) ( nurl_print ` ` ) } {}
        = ci + ci 1
    }
    ( nurl_print `\n` )
}
