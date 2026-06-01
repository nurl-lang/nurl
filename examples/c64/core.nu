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
: s g_mem 0         // 64 KiB flat address space (*u, held as s)

@ mem_raw → *u { ^ # *u g_mem }

@ rd8 i addr → i {
    : *u m ( mem_raw )
    ^ & # i . m & addr 0xFFFF 255
}
@ wr8 i addr i val → v {
    : *u m ( mem_raw )
    = . m & addr 0xFFFF # u & val 0xFF
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
