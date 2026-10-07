// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// rjit.nu — tier 8: a register-allocating JIT over the predecoded records.
//
// The template tier (interp.nu, `__jit_try`) lowers every record through
// rax against a frame in memory, with the hottest few slots pinned to a
// handful of registers for the whole function. That is a baseline
// compiler: whatever does not fit the pins pays a store and a reload on
// every access, and a value that crosses a loop edge pays a store-forward
// on every iteration of its dependency chain. This tier is an optimizing
// one over the same records and the same calling convention:
//
//   1. every record's slot uses and defs are decoded once;
//   2. records split into basic blocks, and every branch that moves values
//      (a block's results, a loop's params) gets a synthetic EDGE block
//      that holds those moves as one parallel copy;
//   3. slot liveness is solved over the blocks;
//   4. each slot's definitions and uses are grouped into WEBS — the
//      independent values that happen to share a storage slot (the
//      operand-stack slots are reused for every expression in the body);
//   5. webs get a register by linear scan over their live hulls — a web
//      live across a call takes a callee-saved register or memory;
//   6. records are emitted with operands wherever their webs live.
//
// A spilled web lives in its slot's frame home, `[rbx + 8*slot]`: two
// webs of one slot are never live on the same path at once, so they can
// share it. The frame, the argument and result windows, every call-out
// and every trap stub are the template tier's own, so the two tiers call
// each other through the same direct-entry table and fall back to the
// same interpreter bridges.
//
// This file is pure: it turns records into machine code plus the patch
// lists that need the page address. interp.nu owns the page.

$ `stdlib/core/vec.nu`

// ── the per-function compile context ────────────────────────────
// Every field is a growable vector, so helpers mutate through the handle;
// the few scalars live in `st` under the rjs_* indices below.
: Rj {
    ( Vec u ) buf  // the emitted code
    ( Vec i ) st  // scalars — rjs_*
    ( Vec i ) code  // the records, 6 words each (copy)
    ( Vec i ) aux  // br_table rows, 4 words each (copy)
    ( Vec i ) kv  // the constant pool (copy)
    ( Vec i ) ltype  // per local slot: 0 i32, 1 i64, 2 f32, 3 f64
    ( Vec i ) rsig  // per record: a call's callee nparams*65536 + nresults (-1 none/unknown)
    ( Vec i ) uoff  // per record (n+1): its uses are [uoff[r], uoff[r+1])
    ( Vec i ) uslot
    ( Vec i ) uweb
    ( Vec i ) doff  // per record (n+1): its defs are [doff[r], doff[r+1])
    ( Vec i ) dslot
    ( Vec i ) dweb
    ( Vec i ) bfirst  // per block: first record (real) / branch record (edge)
    ( Vec i ) blast  // per block: one past its last record (real) / -1 (edge)
    ( Vec i ) btgt  // per block: edge → its target record, real → -1
    ( Vec i ) bmd  // edge block moves: dst base
    ( Vec i ) bms  // … src base
    ( Vec i ) bmn  // … count
    ( Vec i ) soff  // successor lists: [soff[k], soff[k+1]) in ssucc
    ( Vec i ) ssucc
    ( Vec i ) rblk  // record → the real block holding it
    ( Vec i ) eblk  // per record: first edge block it owns (-1 none)
    ( Vec i ) lin  // live-in bitsets, nb x W words
    ( Vec i ) lout  // live-out bitsets
    ( Vec i ) emoff  // per block: edge-move occurrences [emoff[k], emoff[k+1])
    ( Vec i ) emu  // … source web per moved value
    ( Vec i ) emd  // … destination web per moved value
    ( Vec i ) uf  // union-find parent over web ids
    ( Vec i ) nslot  // per raw web id: its slot
    ( Vec i ) xpos  // interval extension list: (raw id, position) pairs
    ( Vec i ) entw  // entry-defined raw web ids (params / zeroed locals)
    ( Vec i ) wslot  // per web: slot
    ( Vec i ) wcls  // per web: votes (int*65536 + float); then 0 gpr / 1 xmm
    ( Vec i ) wwt  // per web: spill weight
    ( Vec i ) wst  // per web: first position
    ( Vec i ) wen  // per web: last position
    ( Vec i ) wuse  // per web: number of uses
    ( Vec i ) wloc  // per web: location (rjl_*)
    ( Vec i ) whint  // per web: a web whose register it would like
    ( Vec i ) wcc  // per web: 1 when live across a call
    ( Vec i ) wsens  // per web: 1 when some consumer reads bits 32..63 (an i32 def must sign-extend)
    ( Vec i ) wdx  // per web: 1 when live across a record that clobbers rdx (div/rem, bit counts)
    ( Vec i ) dxr  // those records, ascending
    ( Vec i ) cs_off  // direct call sites: the rel32's buffer offset …
    ( Vec i ) cs_fx  // … the callee …
    ( Vec i ) cs_ab  // … its argument base …
    ( Vec i ) cs_nr  // … its result count (the site's slow stub needs all four) …
    ( Vec i ) cs_kind  // … 1 for a register-argument site …
    ( Vec i ) cs_np  // … and its argument count
    ( Vec i ) depth  // per record: loop weight (8^depth, capped)
    ( Vec i ) callr  // records that clobber caller-saved registers, ascending
    ( Vec i ) tgt  // per record: 1 when some branch targets it
    ( Vec i ) lab  // record / stub label → code offset
    ( Vec i ) pat_at  // rel32 sites …
    ( Vec i ) pat_rec  // … and the label each one names
    ( Vec i ) pta_off  // absolute jump-table entries (code offset) …
    ( Vec i ) pta_stub  // … and the code offset they hold
    ( Vec i ) ptr_off  // absolute entries naming a record label …
    ( Vec i ) ptr_rec  // … resolved into pta_* once labels are known
    ( Vec i ) litv  // the literal pool: wide constants read RIP-relative …
    ( Vec i ) lsite  // … the disp32 sites that read them …
    ( Vec i ) lidx  // … and which literal each one names
}

// scalar state indices
@ rjs_n → i { ^ 0 }  // record count
@ rjs_nl → i { ^ 1 }  // nlocals
@ rjs_ns → i { ^ 2 }  // nslots
@ rjs_np → i { ^ 3 }  // nparams
@ rjs_nr → i { ^ 4 }  // nresults
@ rjs_sb → i { ^ 5 }  // sbase (first operand-stack slot)
@ rjs_nb → i { ^ 6 }  // block count
@ rjs_nreal → i { ^ 7 }  // real block count (edge blocks follow)
@ rjs_w → i { ^ 8 }  // bitset words per block
@ rjs_nw → i { ^ 9 }  // web count
@ rjs_nimp → i { ^ 10 }  // imported function count
@ rjs_spcell → i { ^ 11 }  // anchor block address
@ rjs_trapfn → i { ^ 12 }  // runtime trap entry
@ rjs_cofn → i { ^ 13 }  // call-out closure fn
@ rjs_coenv → i { ^ 14 }  // call-out closure env
@ rjs_fidx → i { ^ 15 }  // this function's index
@ rjs_used → i { ^ 16 }  // bitmask of allocatable registers handed out
@ rjs_fweb → i { ^ 17 }  // web whose compare flags are live (-1 none)
@ rjs_fcc → i { ^ 18 }  // … and the condition nibble that means "true"
@ rjs_fail → i { ^ 19 }  // non-zero: give up (the reason, for debugging)
@ rjs_nraw → i { ^ 20 }  // raw web ids handed out
@ rjs_fsel → i { ^ 21 }  // fused SELs still to come on the live flags
@ rjs_forbid → i { ^ 22 }  // registers this function may not allocate

@ rjs_sigoff → i { ^ 23 }  // anchor offset of the canonical signature ids

@ rjs_tbloff → i { ^ 24 }  // anchor offset of the table's Vec control pointer

@ rjs_fl → i { ^ 25 }  // 1: frameless (no calls, nothing in memory: no rbx, no slab frame)

@ rjs_fast → i { ^ 26 }  // 1: the function gets a register-argument entry (≤ 5 params, ≤ 1 result)

@ rjs_fastoff → i { ^ 27 }  // that entry's offset (0 = none)

@ rjs_glob → i { ^ 28 }  // 1: the function reads or writes globals (r9 = their base, reserved)

@ rjs_nst → i { ^ 29 }

@ rj_get Rj c i k → i { ^ ( vec_at [i] . c st k ) }

@ rj_set Rj c i k i v → v { ( vec_put [i] . c st k v ) }

@ rj_fail Rj c i why → v { ? == 0 ( rj_get c ( rjs_fail ) ) { ( rj_set c ( rjs_fail ) why ) } {} }

@ rj_failed Rj c → b { ^ != 0 ( rj_get c ( rjs_fail ) ) }

// a record word: 0 op, 1 A, 2 B, 3 C, 4 D, 5 W5
@ rj_rw Rj c i r i k → i { ^ ( vec_at [i] . c code + * r 6 k ) }

// ── locations ───────────────────────────────────────────────────
// 0..15 a GPR (rax=0 … r15=15), 16..31 an XMM register (16 + n),
// rjl_mem the slot's frame home, rjl_imm a constant-pool value.
@ rjl_mem → i { ^ 32 }

@ rjl_imm → i { ^ 33 }

@ rj_isg i l → b { ^ & >= l 0 < l 16 }

@ rj_isx i l → b { ^ & >= l 16 < l 32 }

// ── the byte stream ─────────────────────────────────────────────
@ rj_b Rj c i x → v { ( vec_push [u] . c buf # u & x 255 ) }

@ rj_d Rj c i x → v {
    ( rj_b c x ) ( rj_b c >> x 8 ) ( rj_b c >> x 16 ) ( rj_b c >> x 24 )
}

@ rj_q Rj c i x → v {
    ( rj_d c x ) ( rj_d c >> x 32 )
}

@ rj_here Rj c → i { ^ ( vec_len [u] . c buf ) }

// patch a rel32 at `at` to land on code offset `dst`
@ rj_patch32 Rj c i at i dst → v {
    : i rel - dst + at 4
    ( vec_put [u] . c buf at # u & rel 255 )
    ( vec_put [u] . c buf + at 1 # u & >> rel 8 255 )
    ( vec_put [u] . c buf + at 2 # u & >> rel 16 255 )
    ( vec_put [u] . c buf + at 3 # u & >> rel 24 255 )
}

@ rj_fits8 i v → b { ^ & >= v -128 <= v 127 }

@ rj_fits32 i v → b { ^ & >= v -2147483648 <= v 2147483647 }

// ── x86-64 encoding ─────────────────────────────────────────────
// REX = 0100WRXB; `force` emits it even when every bit is clear (the
// spl/bpl/sil/dil byte registers exist only under a REX prefix).
@ rj_rex Rj c i w i r i x i bb i force → v {
    : i v | | | << w 3 << & >> r 3 1 2 << & >> x 3 1 1 & >> bb 3 1
    ? | != v 0 != force 0 { ( rj_b c | 64 v ) } {}
}

@ rj_modrr Rj c i reg i rm → v { ( rj_b c | | 192 << & reg 7 3 & rm 7 ) }

// [base + idx<<sc + disp]; idx < 0 = no index
@ rj_modmem Rj c i reg i base i idx i sc i disp → v {
    : i r3 << & reg 7 3
    ? < base 0 {  // no base: [idx<<sc + disp32]
        ( rj_b c | r3 4 ) ( rj_b c | | << sc 6 << & idx 7 3 5 ) ( rj_d c disp ) ^ v
    } {}
    : i b3 & base 7
    : i md ? & == disp 0 != b3 5 0 ? ( rj_fits8 disp ) 1 2
    ? & < idx 0 != b3 4 {
        ( rj_b c | | << md 6 r3 b3 )
    } {
        ( rj_b c | | << md 6 r3 4 )
        : i x3 ? < idx 0 4 & idx 7
        ( rj_b c | | << sc 6 << x3 3 b3 )
    }
    ? == md 1 { ( rj_b c disp ) } {}
    ? == md 2 { ( rj_d c disp ) } {}
}

// [pfx] [REX] [0F] opc ModRM(reg, rm) — register form. `b8` forces REX for
// the 8-bit view of registers 4..7 in whichever operand is a byte register
// (1 = rm, 2 = reg, 3 = both).
@ rj_rr Rj c i pfx i w i esc i opc i reg i rm i b8 → v {
    : i f ? | & != 0 & b8 1 & >= rm 4 <= rm 7 & != 0 & b8 2 & >= reg 4 <= reg 7 1 0
    ? != pfx 0 { ( rj_b c pfx ) } {}
    ( rj_rex c w reg 0 rm f )
    ? != esc 0 { ( rj_b c 15 ) } {}
    ( rj_b c opc )
    ( rj_modrr c reg rm )
}

// the same with a memory operand
@ rj_rm Rj c i pfx i w i esc i opc i reg i base i idx i sc i disp i b8 → v {
    : i f ? & != 0 & b8 2 & >= reg 4 <= reg 7 1 0
    ? != pfx 0 { ( rj_b c pfx ) } {}
    ( rj_rex c w reg ? < idx 0 0 idx ? < base 0 0 base f )
    ? != esc 0 { ( rj_b c 15 ) } {}
    ( rj_b c opc )
    ( rj_modmem c reg base idx sc disp )
}

// frame home of slot s
@ rj_home i s → i { ^ * s 8 }

@ rj_mov_rr Rj c i w i dst i src → v {
    ? != dst src { ( rj_rr c 0 w 0 137 src dst 0 ) } {}  // 89 /r
}

// mov dst, [rbx + 8*s]
@ rj_ldf Rj c i w i dst i s → v { ( rj_rm c 0 w 0 139 dst 3 -1 0 ( rj_home s ) 0 ) }

// mov [rbx + 8*s], src
@ rj_stf Rj c i w i s i src → v { ( rj_rm c 0 w 0 137 src 3 -1 0 ( rj_home s ) 0 ) }

// dst ← imm, shortest form. `keep` = 1 when the flags must survive (no xor).
@ rj_mov_ri Rj c i dst i imm i keep → v {
    ? & == imm 0 == keep 0 {
        ( rj_rr c 0 0 0 49 dst dst 0 ) ^ v  // xor r32,r32
    } {}
    ? & >= imm 0 <= imm 4294967295 {
        ( rj_rex c 0 0 0 dst 0 ) ( rj_b c + 184 & dst 7 ) ( rj_d c imm ) ^ v  // mov r32, imm32 (zero-extends)
    } {}
    ? ( rj_fits32 imm ) {
        ( rj_rex c 1 0 0 dst 0 ) ( rj_b c 199 ) ( rj_modrr c 0 dst ) ( rj_d c imm ) ^ v  // mov r64, simm32
    } {}
    ( rj_rex c 1 0 0 dst 0 ) ( rj_b c + 184 & dst 7 ) ( rj_q c imm )  // movabs
}

// ALU groups: add 0, or 1, and 4, sub 5, xor 6, cmp 7
@ rj_alu_rr Rj c i w i ext i dst i src → v { ( rj_rr c 0 w 0 + * ext 8 1 src dst 0 ) }

@ rj_alu_rf Rj c i w i ext i dst i s → v { ( rj_rm c 0 w 0 + * ext 8 3 dst 3 -1 0 ( rj_home s ) 0 ) }

// imm must fit 32 bits (sign-extended for w=1)
@ rj_alu_ri Rj c i w i ext i dst i imm → v {
    ? ( rj_fits8 imm ) {
        ( rj_rex c w 0 0 dst 0 ) ( rj_b c 131 ) ( rj_modrr c ext dst ) ( rj_b c imm )
    } {
        ( rj_rex c w 0 0 dst 0 ) ( rj_b c 129 ) ( rj_modrr c ext dst ) ( rj_d c imm )
    }
}

// op qword/dword [rbx+8s], imm32
@ rj_alu_fi Rj c i w i ext i s i imm → v {
    ? ( rj_fits8 imm ) {
        ( rj_rm c 0 w 0 131 ext 3 -1 0 ( rj_home s ) 0 ) ( rj_b c imm )
    } {
        ( rj_rm c 0 w 0 129 ext 3 -1 0 ( rj_home s ) 0 ) ( rj_d c imm )
    }
}

@ rj_test_rr Rj c i w i a i bb → v { ( rj_rr c 0 w 0 133 bb a 0 ) }

@ rj_imul_rr Rj c i w i dst i src → v { ( rj_rr c 0 w 1 175 dst src 0 ) }

@ rj_imul_rf Rj c i w i dst i s → v { ( rj_rm c 0 w 1 175 dst 3 -1 0 ( rj_home s ) 0 ) }

@ rj_imul_rri Rj c i w i dst i src i imm → v {
    ? ( rj_fits8 imm ) { ( rj_rr c 0 w 0 107 dst src 0 ) ( rj_b c imm ) } {
        ( rj_rr c 0 w 0 105 dst src 0 ) ( rj_d c imm ) }
}

// shifts: rol 0, ror 1, shl 4, shr 5, sar 7
@ rj_shift_ri Rj c i w i ext i dst i imm → v {
    ( rj_rex c w 0 0 dst 0 ) ( rj_b c 193 ) ( rj_modrr c ext dst ) ( rj_b c imm )
}

@ rj_shift_cl Rj c i w i ext i dst → v {
    ( rj_rex c w 0 0 dst 0 ) ( rj_b c 211 ) ( rj_modrr c ext dst )
}

// movsxd dst, src32
@ rj_movsxd Rj c i dst i src → v { ( rj_rr c 0 1 0 99 dst src 0 ) }

// mov dst32, src32 (zero-extends)
@ rj_mov32 Rj c i dst i src → v { ( rj_rr c 0 0 0 137 src dst 0 ) }

@ rj_setcc Rj c i cc i rm → v { ( rj_rr c 0 0 1 + 144 cc 0 rm 1 ) }

@ rj_movzx8 Rj c i dst i src → v { ( rj_rr c 0 0 1 182 dst src 1 ) }

@ rj_cmov_rr Rj c i w i cc i dst i src → v { ( rj_rr c 0 w 1 + 64 cc dst src 0 ) }

@ rj_cmov_rf Rj c i w i cc i dst i s → v { ( rj_rm c 0 w 1 + 64 cc dst 3 -1 0 ( rj_home s ) 0 ) }

@ rj_push Rj c i r → v { ( rj_rex c 0 0 0 r 0 ) ( rj_b c + 80 & r 7 ) }

@ rj_pop Rj c i r → v { ( rj_rex c 0 0 0 r 0 ) ( rj_b c + 88 & r 7 ) }

// lea dst, [base + idx<<sc + disp] (w=0: the 32-bit form, which wraps)
@ rj_lea Rj c i w i dst i base i idx i sc i disp → v { ( rj_rm c 0 w 0 141 dst base idx sc disp 0 ) }

// [pfx] [REX] [0F] opc ModRM(reg, [rip + literal v]) — a wide constant as a
// memory operand. The disp32 is the instruction's last field (no immediate
// may follow), patched once the pool's place is known.
@ rj_ripop Rj c i pfx i w i esc i opc i reg i v → v {
    ? != pfx 0 { ( rj_b c pfx ) } {}
    ( rj_rex c w reg 0 0 0 )
    ? != esc 0 { ( rj_b c 15 ) } {}
    ( rj_b c opc )
    ( rj_b c | << & reg 7 3 5 )  // mod 00, rm 101: rip-relative
    : ~ i k 0
    : i nl ( vec_len [i] . c litv )
    : ~ i hit -1
    ~ < k nl { ? == ( vec_at [i] . c litv k ) v { = hit k = k nl } { = k + k 1 } }
    ? < hit 0 { = hit nl ( vec_push [i] . c litv v ) } {}
    ( vec_push [i] . c lsite ( rj_here c ) ) ( vec_push [i] . c lidx hit )
    ( rj_d c 0 )
}

// ── jumps and labels ────────────────────────────────────────────
// Labels 0..n-1 are records; n.. are the trap stubs (see rj_stub_*).
@ rj_jcc Rj c i cc i label → v {
    ( rj_b c 15 ) ( rj_b c + 128 cc ) ( rj_d c 0 )
    ( vec_push [i] . c pat_at - ( rj_here c ) 4 ) ( vec_push [i] . c pat_rec label )
}

@ rj_jmp Rj c i label → v {
    ( rj_b c 233 ) ( rj_d c 0 )
    ( vec_push [i] . c pat_at - ( rj_here c ) 4 ) ( vec_push [i] . c pat_rec label )
}

// a forward jump to a not-yet-known local offset: returns the rel32 site
@ rj_jcc_fwd Rj c i cc → i { ( rj_b c 15 ) ( rj_b c + 128 cc ) ( rj_d c 0 ) ^ - ( rj_here c ) 4 }

@ rj_jmp_fwd Rj c → i { ( rj_b c 233 ) ( rj_d c 0 ) ^ - ( rj_here c ) 4 }

@ rj_land Rj c i site → v { ( rj_patch32 c site ( rj_here c ) ) }

// stub labels, after the n record labels
@ rj_stub_oob Rj c → i { ^ ( rj_get c ( rjs_n ) ) }

@ rj_stub_div0 Rj c → i { ^ + ( rj_get c ( rjs_n ) ) 1 }

@ rj_stub_gate Rj c → i { ^ + ( rj_get c ( rjs_n ) ) 2 }

@ rj_stub_ovf Rj c → i { ^ + ( rj_get c ( rjs_n ) ) 3 }

@ rj_stub_iovf Rj c → i { ^ + ( rj_get c ( rjs_n ) ) 4 }

@ rj_stub_inval Rj c → i { ^ + ( rj_get c ( rjs_n ) ) 5 }

@ rj_lab_entry Rj c → i { ^ + ( rj_get c ( rjs_n ) ) 6 }  // the memory entry (+28)

@ rj_lab_fast Rj c → i { ^ + ( rj_get c ( rjs_n ) ) 7 }  // the register-argument entry

// condition nibbles: o 0 no 1 b 2 ae 3 e 4 ne 5 be 6 a 7 s 8 ns 9 p 10 np 11 l 12 ge 13 le 14 g 15
// compare micro-op (56..75) → the nibble that means "true"
@ rj_cmpcc i op → i {
    : i q % - op 56 10
    ? == q 0 { ^ 4 } {}
    ? == q 1 { ^ 5 } {}
    ? == q 2 { ^ 12 } {}
    ? == q 3 { ^ 2 } {}
    ? == q 4 { ^ 15 } {}
    ? == q 5 { ^ 7 } {}
    ? == q 6 { ^ 14 } {}
    ? == q 7 { ^ 6 } {}
    ? == q 8 { ^ 13 } {}
    ^ 3
}

// the nibble for the same test with the operands exchanged
@ rj_ccswap i cc → i {
    ? == cc 12 { ^ 15 } {}
    ? == cc 15 { ^ 12 } {}
    ? == cc 2 { ^ 7 } {}
    ? == cc 7 { ^ 2 } {}
    ? == cc 14 { ^ 13 } {}
    ? == cc 13 { ^ 14 } {}
    ? == cc 6 { ^ 3 } {}
    ? == cc 3 { ^ 6 } {}
    ^ cc
}

// ── what a record reads and writes ──────────────────────────────
// The template tier's memory-op table, verbatim: width*4 + signed*2 + store.
@ rj_memkind i op → i {
    ? | == op 18 == op 19 { ^ 32 } {}  // i64/f64.load
    ? == op 20 { ^ 18 } {}  // i32.load (sign-extends: the canonical i32)
    ? | == op 24 == op 182 { ^ 16 } {}  // f32.load, i64.load32_u
    ? == op 80 { ^ 18 } {}  // i64.load32_s
    ? | == op 23 == op 26 { ^ 8 } {}  // load16_u
    ? | == op 77 == op 79 { ^ 10 } {}  // load16_s
    ? | == op 21 == op 25 { ^ 4 } {}  // load8_u
    ? | == op 76 == op 78 { ^ 6 } {}  // load8_s
    ? | == op 27 == op 28 { ^ 33 } {}  // i64/f64.store
    ? | | == op 183 == op 31 == op 32 { ^ 17 } {}  // 4-byte stores
    ? | == op 178 == op 35 { ^ 9 } {}  // 2-byte stores
    ? | == op 29 == op 34 { ^ 5 } {}  // 1-byte stores
    ^ -1
}

// two-operand integer ALU: dst = B op C
@ rj_isalu i op → b { ^ | & >= op 0 <= op 12 | | | | == op 179 == op 180 == op 181 == op 184 == op 185 }

@ rj_isrot i op → b { ^ | | | == op 100 == op 101 == op 109 == op 110 }

// fused i64 pairs: dst = (B op1 C) op2 D
@ rj_isfused i op → b { ^ | & >= op 13 <= op 17 | | == op 22 == op 30 == op 33 }

// a record whose A field is a branch target (a word offset)
@ rj_hastarget i op → b {
    ? | | | == op 49 == op 54 == op 48 == op 45 { ^ T } {}
    ^ | | | == op 38 == op 177 == op 167 == op 168
}

// a record that leaves the block: anything with a target, or no fall-through
@ rj_isbranch i op → b {
    ? ( rj_hastarget op ) { ^ T } {}
    ^ | | | == op 169 == op 55 == op 172 == op 173
}

// a record whose emitted code calls out of the function (clobbers every
// caller-saved register)
@ rj_iscall i op → b { ^ | | | == op 50 == op 210 == op 170 | == op 163 == op 171 }

// The records this tier lowers; a function holding anything else stays on
// the template tier (or the interpreter).
@ rj_op_ok i op → b {
    ? | ( rj_isalu op ) ( rj_isfused op ) { ^ T } {}
    ? & >= op 56 <= op 75 { ^ T } {}  // integer compares
    ? | | | == op 43 == op 44 == op 36 == op 37 { ^ T } {}  // eqz, wrap, extend_u
    ? & >= op 157 <= op 161 { ^ T } {}  // extendN_s
    ? & >= op 153 <= op 156 { ^ T } {}  // reinterprets
    ? | | == op 46 == op 47 == op 51 { ^ T } {}  // SEL MOV CONST
    ? | == op 52 == op 53 { ^ T } {}  // globals
    ? >= ( rj_memkind op ) 0 { ^ T } {}
    ? | | & >= op 205 <= op 208 == op 211 == op 212 { ^ T } {}  // fused int loads
    ? | | | == op 49 == op 54 == op 48 == op 45 { ^ T } {}
    ? | | == op 38 == op 177 | == op 167 == op 168 { ^ T } {}
    ? | | == op 169 == op 55 == op 172 { ^ T } {}
    ? | == op 50 == op 210 { ^ T } {}
    ? | & >= op 96 <= op 99 & >= op 105 <= op 108 { ^ T } {}  // div / rem
    ? == op 93 { ^ T } {}  // i32.clz
    ? ( rj_isrot op ) { ^ T } {}
    ? ( rj_isfloat op ) { ^ T } {}
    ? | | | == op 94 == op 95 == op 102 | == op 103 == op 104 { ^ T } {}  // ctz popcnt, i64 clz ctz popcnt
    ? | | == op 162 == op 163 == op 166 { ^ T } {}  // memory.size / grow, ref.is_null
    ? | == op 170 == op 171 { ^ T } {}  // call_indirect, the 0xfc bridge
    ^ F
}

// the float records this tier lowers
@ rj_isfbin i op → b { ^ | & >= op 39 <= op 42 & >= op 118 <= op 121 }  // f64 / f32 + - * /

@ rj_isfcmp i op → b { ^ & >= op 81 <= op 92 }

@ rj_isfconv i op → b { ^ | & >= op 143 <= op 152 & >= op 135 <= op 142 }  // conversions to/from float

@ rj_isfminmax i op → b { ^ | & >= op 122 <= op 124 & >= op 132 <= op 134 }  // min max copysign

@ rj_isfloat i op → b {
    ? | | ( rj_isfbin op ) ( rj_isfcmp op ) ( rj_isfconv op ) { ^ T } {}
    ? | | | == op 131 == op 117 == op 125 == op 126 { ^ T } {}  // sqrt, f64 abs/neg
    ? | == op 111 == op 112 { ^ T } {}  // f32 abs/neg
    ? | & >= op 127 <= op 130 & >= op 113 <= op 116 { ^ T } {}  // ceil floor trunc nearest (roundsd/ss)
    ? ( rj_isfminmax op ) { ^ T } {}
    ^ & >= op 194 <= op 201  // the fused f64 family
}

@ rj_use Rj c i s → v { ( vec_push [i] . c uslot s ) ( vec_push [i] . c uweb -1 ) }

@ rj_def Rj c i s → v { ( vec_push [i] . c dslot s ) ( vec_push [i] . c dweb -1 ) }

// a call record's signature word: canon<<32 | nparams<<16 | nresults
// (canon: call_indirect's expected type, canonicalised; -1 = unknown)
@ rj_sig_np i sig → i { ^ ? < sig 0 0 & >> sig 16 65535 }

@ rj_sig_nr i sig → i { ^ ? < sig 0 0 & sig 65535 }

@ rj_sig_canon i sig → i { ^ ? < sig 0 -1 >> sig 32 }

// Decode record r's uses and defs, in the fixed per-op order the emitter
// reads them back in.
@ rj_decode Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i a ( rj_rw c r 1 )
    : i b ( rj_rw c r 2 )
    : i cc ( rj_rw c r 3 )
    : i d ( rj_rw c r 4 )
    : i w5 ( rj_rw c r 5 )
    ? | | | | ( rj_isalu op ) & >= op 56 <= op 75 & >= op 96 <= op 99 & >= op 105 <= op 108 ( rj_isrot op ) {
        ( rj_use c b ) ( rj_use c cc ) ( rj_def c a ) ^ v
    } {}
    ? | | ( rj_isfbin op ) ( rj_isfcmp op ) ( rj_isfminmax op ) { ( rj_use c b ) ( rj_use c cc ) ( rj_def c a ) ^ v } {}
    ? | | | | == op 94 == op 95 == op 102 == op 103 | == op 104 == op 166 { ( rj_use c b ) ( rj_def c a ) ^ v } {}
    ? | | == op 111 == op 112 & >= op 113 <= op 116 { ( rj_use c b ) ( rj_def c a ) ^ v } {}
    ? == op 162 { ( rj_def c a ) ^ v } {}
    ? == op 163 { ( rj_use c b ) ( rj_def c a ) ^ v } {}
    ? == op 171 {  // FCB: pops operands from C up, pushes one result back to C
        : ~ i k 0
        ~ < k >> d 1 { ( rj_use c + cc k ) = k + k 1 }
        ? != 0 & d 1 { ( rj_def c cc ) } {}
        ^ v
    } {}
    ? == op 170 {  // call_indirect: the args, then the table index (C)
        : i sig ( vec_at [i] . c rsig r )
        ? < sig 0 { ( rj_fail c 3 ) ^ v } {}
        : ~ i k 0
        ~ < k ( rj_sig_np sig ) { ( rj_use c + b k ) = k + k 1 }
        ( rj_use c cc )
        = k 0
        ~ < k ( rj_sig_nr sig ) { ( rj_def c + b k ) = k + k 1 }
        ^ v
    } {}
    ? | | ( rj_isfconv op ) | | == op 131 == op 117 | == op 125 == op 126 & >= op 127 <= op 130 { ( rj_use c b ) ( rj_def c a ) ^ v } {}
    ? | == op 194 | == op 195 == op 196 { ( rj_use c b ) ( rj_use c d ) ( rj_def c a ) ^ v } {}  // A=dst B=base D=x
    ? == op 197 { ( rj_use c a ) ( rj_use c b ) ( rj_use c cc ) ^ v } {}  // ADDSTOREF64: A=addr B C
    ? & >= op 198 <= op 201 { ( rj_use c b ) ( rj_use c cc ) ( rj_use c d ) ( rj_def c a ) ^ v } {}
    ? ( rj_isfused op ) { ( rj_use c b ) ( rj_use c cc ) ( rj_use c d ) ( rj_def c a ) ^ v } {}
    ? | | | | == op 43 == op 44 == op 36 == op 37 == op 47 { ( rj_use c b ) ( rj_def c a ) ^ v } {}
    ? | | & >= op 157 <= op 161 & >= op 153 <= op 156 == op 93 { ( rj_use c b ) ( rj_def c a ) ^ v } {}
    ? == op 46 { ( rj_use c b ) ( rj_use c cc ) ( rj_use c d ) ( rj_def c a ) ^ v } {}  // SEL: T F cond
    ? | == op 51 == op 52 { ( rj_def c a ) ^ v } {}  // CONST / global.get
    ? == op 53 { ( rj_use c b ) ^ v } {}  // global.set
    : i mk ( rj_memkind op )
    ? >= mk 0 {
        ? == 0 & mk 1 { ( rj_use c b ) ( rj_use c d ) ( rj_def c a ) } { ( rj_use c a ) ( rj_use c b ) }
        ^ v
    } {}
    ? | | == op 205 == op 206 | == op 211 == op 212 { ( rj_use c b ) ( rj_use c d ) ( rj_def c a ) ^ v } {}
    ? | == op 207 == op 208 { ( rj_use c b ) ( rj_use c d ) ( rj_use c w5 ) ( rj_def c a ) ^ v } {}
    ? | | == op 49 == op 167 == op 172 { ^ v } {}  // moves of BRM live on its edge block
    ? | | | == op 54 == op 48 == op 168 == op 169 { ( rj_use c b ) ^ v } {}
    ? == op 45 { ( rj_use c b ) ( rj_use c cc ) ^ v } {}
    ? | == op 38 == op 177 { ( rj_use c cc ) ( rj_use c d ) ( rj_use c & w5 2097151 ) ( rj_def c b ) ^ v } {}
    ? == op 55 {
        : ~ i k 0
        ~ < k b { ( rj_use c + a k ) = k + k 1 }
        ^ v
    } {}
    ? | == op 50 == op 210 {
        : i sig ( vec_at [i] . c rsig r )
        ? < sig 0 { ( rj_fail c 3 ) ^ v } {}
        : ~ i k 0
        ~ < k ( rj_sig_np sig ) { ( rj_use c + b k ) = k + k 1 }
        = k 0
        ~ < k ( rj_sig_nr sig ) { ( rj_def c + b k ) = k + k 1 }
        ^ v
    } {}
    ( rj_fail c 2 )
}

// ── blocks ──────────────────────────────────────────────────────
@ rj_tgtrec i w → i { ^ / w 6 }  // branch targets are word offsets

// branch target of a record with one (A field), else -1
@ rj_target Rj c i r → i {
    : i op ( rj_rw c r 0 )
    ? ( rj_hastarget op ) { ^ ( rj_tgtrec ( rj_rw c r 1 ) ) } {}
    ^ -1
}

// t is a branch target of record r: 2 marks a loop head (a backward target)
@ rj_mark Rj c i t i r → v {
    ? <= t r { ( vec_put [i] . c tgt t 2 ) } { ? == 0 ( vec_at [i] . c tgt t ) { ( vec_put [i] . c tgt t 1 ) } {} }
}

// new edge block for branch record r → target record t moving n values
@ rj_edge Rj c i r i t i dst i src i n → i {
    : i k ( vec_len [i] . c bfirst )
    ( vec_push [i] . c bfirst r ) ( vec_push [i] . c blast -1 ) ( vec_push [i] . c btgt t )
    ( vec_push [i] . c bmd dst ) ( vec_push [i] . c bms src ) ( vec_push [i] . c bmn n )
    ^ k
}

@ rj_blocks Rj c → v {
    : i n ( rj_get c ( rjs_n ) )
    : ~ i r 0
    ~ < r n { ( vec_push [i] . c tgt 0 ) ( vec_push [i] . c rblk -1 ) ( vec_push [i] . c eblk -1 ) = r + r 1 }
    // targets, validated: every one must be a real record
    = r 0
    ~ < r n {
        : i t ( rj_target c r )
        ? >= t 0 { ? < t n { ( rj_mark c t r ) } { ( rj_fail c 4 ) } } {}
        ? == ( rj_rw c r 0 ) 169 {
            : i ab ( rj_rw c r 1 )
            : i rows + ( rj_rw c r 3 ) 1
            : ~ i k 0
            ~ < k rows {
                : i tw ( vec_at [i] . c aux + ab * k 4 )
                : i t2 ? < tw 0 -1 ( rj_tgtrec tw )
                ? & >= t2 0 < t2 n { ( rj_mark c t2 r ) } { ( rj_fail c 4 ) }
                = k + k 1
            }
        } {}
        = r + r 1
    }
    ? ( rj_failed c ) { ^ v } {}
    // real blocks: a leader is record 0, a target, or follows a branch
    = r 0
    : ~ i start 0
    ~ < r n {
        : ~ b last T
        ? < + r 1 n { = last | ( rj_isbranch ( rj_rw c r 0 ) ) != 0 ( vec_at [i] . c tgt + r 1 ) } {}
        ? last {
            : i k ( vec_len [i] . c bfirst )
            ( vec_push [i] . c bfirst start ) ( vec_push [i] . c blast + r 1 ) ( vec_push [i] . c btgt -1 )
            ( vec_push [i] . c bmd 0 ) ( vec_push [i] . c bms 0 ) ( vec_push [i] . c bmn 0 )
            : ~ i q start
            ~ <= q r { ( vec_put [i] . c rblk q k ) = q + q 1 }
            = start + r 1
        } {}
        = r + r 1
    }
    : i nreal ( vec_len [i] . c bfirst )
    ( rj_set c ( rjs_nreal ) nreal )
    // successor lists; edge blocks are appended as they are needed
    : ( Vec i ) esucc ( vec_new [i] )  // target block of each edge block, in order
    : ~ i k 0
    ~ < k nreal {
        ( vec_push [i] . c soff ( vec_len [i] . c ssucc ) )
        : i lr - ( vec_at [i] . c blast k ) 1
        : i op ( rj_rw c lr 0 )
        : i fall + k 1
        ? == op 49 { ( vec_push [i] . c ssucc ( vec_at [i] . c rblk ( rj_target c lr ) ) ) } {
            ? | | | | == op 54 == op 48 == op 45 == op 38 == op 177 {
                ( vec_push [i] . c ssucc ( vec_at [i] . c rblk ( rj_target c lr ) ) )
                ( vec_push [i] . c ssucc fall )
            } {
                ? == op 167 {  // br with results: an edge block carries the moves
                    : i e ( rj_edge c lr ( rj_target c lr ) ( rj_rw c lr 2 ) ( rj_rw c lr 3 ) ( rj_rw c lr 4 ) )
                    ( vec_put [i] . c eblk lr e )
                    ( vec_push [i] esucc ( vec_at [i] . c rblk ( rj_target c lr ) ) )
                    ( vec_push [i] . c ssucc e )
                } {
                    ? == op 168 {
                        : i pk ( rj_rw c lr 3 )
                        : i e ( rj_edge c lr ( rj_target c lr ) >> pk 20 & pk 1048575 ( rj_rw c lr 4 ) )
                        ( vec_put [i] . c eblk lr e )
                        ( vec_push [i] esucc ( vec_at [i] . c rblk ( rj_target c lr ) ) )
                        ( vec_push [i] . c ssucc e )
                        ( vec_push [i] . c ssucc fall )
                    } {
                        ? == op 169 {
                            : i ab ( rj_rw c lr 1 )
                            : i rows + ( rj_rw c lr 3 ) 1
                            : ~ i q 0
                            ~ < q rows {
                                : i rb + ab * q 4
                                : i t ( rj_tgtrec ( vec_at [i] . c aux rb ) )
                                : i mn ( vec_at [i] . c aux + rb 3 )
                                ? > mn 0 {
                                    : i e ( rj_edge c lr t ( vec_at [i] . c aux + rb 1 ) ( vec_at [i] . c aux + rb 2 ) mn )
                                    ? < ( vec_at [i] . c eblk lr ) 0 { ( vec_put [i] . c eblk lr e ) } {}
                                    ( vec_push [i] esucc ( vec_at [i] . c rblk t ) )
                                    ( vec_push [i] . c ssucc e )
                                } { ( vec_push [i] . c ssucc ( vec_at [i] . c rblk t ) ) }
                                = q + q 1
                            }
                        } {
                            ? | | == op 55 == op 172 == op 173 {} {
                                ? < fall nreal { ( vec_push [i] . c ssucc fall ) } { ( rj_fail c 5 ) }  // fell off the end
                            }
                        }
                    }
                }
            }
        }
        = k + k 1
    }
    : i nb ( vec_len [i] . c bfirst )
    = k nreal
    ~ < k nb {
        ( vec_push [i] . c soff ( vec_len [i] . c ssucc ) )
        ( vec_push [i] . c ssucc ( vec_at [i] esucc - k nreal ) )
        = k + k 1
    }
    ( vec_push [i] . c soff ( vec_len [i] . c ssucc ) )
    ( rj_set c ( rjs_nb ) nb )
}

// ── liveness ────────────────────────────────────────────────────
@ rj_isconst Rj c i s → b { ^ & >= s ( rj_get c ( rjs_nl ) ) < s ( rj_get c ( rjs_sb ) ) }

// logical shift right (>> is arithmetic on i)
@ rj_shr i a i n → i { ^ ? == n 0 a & >> a n - << 1 - 64 n 1 }

@ rj_bit ( Vec i ) v i base i s → b { ^ != 0 & ( rj_shr ( vec_at [i] v + base >> s 6 ) & s 63 ) 1 }

@ rj_bset ( Vec i ) v i base i s → v {
    : i k + base >> s 6
    ( vec_put [i] v k | ( vec_at [i] v k ) << 1 & s 63 )
}

@ rj_gen1 Rj c ( Vec i ) gen ( Vec i ) kill i base i s → v {
    ? ( rj_isconst c s ) { ^ v } {}
    ? ( rj_bit kill base s ) {} { ( rj_bset gen base s ) }
}

@ rj_live Rj c → v {
    : i nb ( rj_get c ( rjs_nb ) )
    : i nreal ( rj_get c ( rjs_nreal ) )
    : i ns ( rj_get c ( rjs_ns ) )
    : i w / + ns 63 64
    ( rj_set c ( rjs_w ) w )
    : ( Vec i ) gen ( vec_new [i] )
    : ( Vec i ) kill ( vec_new [i] )
    : ~ i k 0
    : i tot * nb w
    ~ < k tot { ( vec_push [i] gen 0 ) ( vec_push [i] kill 0 ) ( vec_push [i] . c lin 0 ) ( vec_push [i] . c lout 0 ) = k + k 1 }
    = k 0
    ~ < k nb {
        : i base * k w
        ? < k nreal {
            : ~ i r ( vec_at [i] . c bfirst k )
            : i re ( vec_at [i] . c blast k )
            ~ < r re {
                : ~ i o ( vec_at [i] . c uoff r )
                : i oe ( vec_at [i] . c uoff + r 1 )
                ~ < o oe { ( rj_gen1 c gen kill base ( vec_at [i] . c uslot o ) ) = o + o 1 }
                = o ( vec_at [i] . c doff r )
                : i de ( vec_at [i] . c doff + r 1 )
                ~ < o de { ( rj_bset kill base ( vec_at [i] . c dslot o ) ) = o + o 1 }
                = r + r 1
            }
        } {
            : i ms ( vec_at [i] . c bms k )
            : i md ( vec_at [i] . c bmd k )
            : i mn ( vec_at [i] . c bmn k )
            : ~ i q 0
            ~ < q mn { ( rj_gen1 c gen kill base + ms q ) = q + q 1 }
            = q 0
            ~ < q mn { ( rj_bset kill base + md q ) = q + q 1 }
        }
        = k + k 1
    }
    // iterate to the fixed point, later blocks first (the records run forward)
    : ~ b changed T
    ~ changed {
        = changed F
        = k - nb 1
        ~ >= k 0 {
            : i base * k w
            : i s0 ( vec_at [i] . c soff k )
            : i s1 ( vec_at [i] . c soff + k 1 )
            : ~ i j 0
            ~ < j w {
                : ~ i o 0
                : ~ i q s0
                ~ < q s1 { = o | o ( vec_at [i] . c lin + * ( vec_at [i] . c ssucc q ) w j ) = q + q 1 }
                : i ni | ( vec_at [i] gen + base j ) & o ^^ ( vec_at [i] kill + base j ) -1
                ? | != ni ( vec_at [i] . c lin + base j ) != o ( vec_at [i] . c lout + base j ) {
                    ( vec_put [i] . c lin + base j ni ) ( vec_put [i] . c lout + base j o )
                    = changed T
                } {}
                = j + j 1
            }
            = k - k 1
        }
    }
}

// ── webs ────────────────────────────────────────────────────────
// A raw web id names one definition (or one block's live-in value of a
// slot); union-find merges the ids that reach a common use. Every id of a
// set belongs to the same slot — merges only ever join a block's live-out
// value of slot s with a successor's live-in value of s.
@ rj_newraw Rj c i s → i {
    : i id ( vec_len [i] . c uf )
    ( vec_push [i] . c uf id ) ( vec_push [i] . c nslot s )
    ^ id
}

@ rj_find Rj c i x0 → i {
    : ~ i x x0
    ~ != ( vec_at [i] . c uf x ) x {
        : i gp ( vec_at [i] . c uf ( vec_at [i] . c uf x ) )
        ( vec_put [i] . c uf x gp )  // path halving
        = x gp
    }
    ^ x
}

@ rj_union Rj c i a i bb → v {
    : i ra ( rj_find c a )
    : i rb ( rj_find c bb )
    ? < ra rb { ( vec_put [i] . c uf rb ra ) } { ? > ra rb { ( vec_put [i] . c uf ra rb ) } {} }
}

// a block's first and last position: 2r = record r's reads, 2r+1 its writes
@ rj_bpos0 Rj c i k → i { ^ * 2 ( vec_at [i] . c bfirst k ) }

@ rj_bpos1 Rj c i k → i {
    : i l ( vec_at [i] . c blast k )
    ^ ? < l 0 + * 2 ( vec_at [i] . c bfirst k ) 1 - * 2 l 1
}

// the set bits of words [base, base+w) of v, ascending
@ rj_bits ( Vec i ) v i base i w ( Vec i ) out → v {
    ( vec_clear [i] out )
    : ~ i j 0
    ~ < j w {
        : ~ i x ( vec_at [i] v + base j )
        : ~ i bit * j 64
        ~ != x 0 {
            ? != 0 & x 1 { ( vec_push [i] out bit ) } {}
            = x ( rj_shr x 1 )
            = bit + bit 1
        }
        = j + j 1
    }
}

@ rj_xpos Rj c i id i pos → v { ( vec_push [i] . c xpos id ) ( vec_push [i] . c xpos pos ) }

@ rj_webs Rj c → v {
    : i nb ( rj_get c ( rjs_nb ) )
    : i nreal ( rj_get c ( rjs_nreal ) )
    : i ns ( rj_get c ( rjs_ns ) )
    : i w ( rj_get c ( rjs_w ) )
    // in-nodes: one raw id per (block, live-in slot), slots ascending
    : ( Vec i ) inoff ( vec_new [i] )
    : ( Vec i ) inslot ( vec_new [i] )
    : ( Vec i ) inid ( vec_new [i] )
    : ( Vec i ) bits ( vec_new [i] )
    : ~ i k 0
    ~ < k nb {
        ( vec_push [i] inoff ( vec_len [i] inslot ) )
        ( rj_bits . c lin * k w w bits )
        : ~ i q 0
        : i nq ( vec_len [i] bits )
        ~ < q nq {
            : i s ( vec_at [i] bits q )
            ( vec_push [i] inslot s ) ( vec_push [i] inid ( rj_newraw c s ) )
            = q + q 1
        }
        = k + k 1
    }
    ( vec_push [i] inoff ( vec_len [i] inslot ) )
    // the entry block's live-in values are defined by the prologue
    : ~ i q ( vec_at [i] inoff 0 )
    ~ < q ( vec_at [i] inoff 1 ) { ( vec_push [i] . c entw ( vec_at [i] inid q ) ) = q + q 1 }
    : ( Vec i ) curw ( vec_new [i] )
    : ~ i z 0
    ~ < z ns { ( vec_push [i] curw -1 ) = z + z 1 }
    : ( Vec i ) touched ( vec_new [i] )
    = k 0
    ~ < k nb {
        ( vec_push [i] . c emoff ( vec_len [i] . c emu ) )
        : i p0 ( rj_bpos0 c k )
        : i p1 ( rj_bpos1 c k )
        = q ( vec_at [i] inoff k )
        ~ < q ( vec_at [i] inoff + k 1 ) {
            : i s ( vec_at [i] inslot q )
            ( vec_put [i] curw s ( vec_at [i] inid q ) ) ( vec_push [i] touched s )
            ( rj_xpos c ( vec_at [i] inid q ) p0 )
            = q + q 1
        }
        ? < k nreal {
            : ~ i r ( vec_at [i] . c bfirst k )
            : i re ( vec_at [i] . c blast k )
            ~ < r re {
                : ~ i o ( vec_at [i] . c uoff r )
                : i oe ( vec_at [i] . c uoff + r 1 )
                ~ < o oe {
                    : i s ( vec_at [i] . c uslot o )
                    ? ( rj_isconst c s ) {} {
                        : i cw ( vec_at [i] curw s )
                        ? < cw 0 { ( rj_fail c 6 ) } { ( vec_put [i] . c uweb o cw ) }
                    }
                    = o + o 1
                }
                = o ( vec_at [i] . c doff r )
                : i de ( vec_at [i] . c doff + r 1 )
                ~ < o de {
                    : i s ( vec_at [i] . c dslot o )
                    ? ( rj_isconst c s ) { ( rj_fail c 7 ) } {
                        : i id ( rj_newraw c s )
                        ( vec_put [i] . c dweb o id ) ( vec_put [i] curw s id ) ( vec_push [i] touched s )
                    }
                    = o + o 1
                }
                = r + r 1
            }
        } {
            : i ms ( vec_at [i] . c bms k )
            : i md ( vec_at [i] . c bmd k )
            : i mn ( vec_at [i] . c bmn k )
            : ~ i m 0
            ~ < m mn {  // a parallel copy: every source is read first
                : i s + ms m
                ? ( rj_isconst c s ) { ( vec_push [i] . c emu -1 ) } {
                    : i cw ( vec_at [i] curw s )
                    ? < cw 0 { ( rj_fail c 6 ) ( vec_push [i] . c emu -1 ) } { ( vec_push [i] . c emu cw ) }
                }
                = m + m 1
            }
            = m 0
            ~ < m mn {
                : i s + md m
                : i id ( rj_newraw c s )
                ( vec_push [i] . c emd id ) ( vec_put [i] curw s id ) ( vec_push [i] touched s )
                = m + m 1
            }
        }
        // join the values leaving this block with what each successor expects
        : ~ i sq ( vec_at [i] . c soff k )
        : i se ( vec_at [i] . c soff + k 1 )
        ~ < sq se {
            : i t ( vec_at [i] . c ssucc sq )
            : ~ i iq ( vec_at [i] inoff t )
            ~ < iq ( vec_at [i] inoff + t 1 ) {
                : i cw ( vec_at [i] curw ( vec_at [i] inslot iq ) )
                ? < cw 0 { ( rj_fail c 8 ) } { ( rj_union c cw ( vec_at [i] inid iq ) ) }
                = iq + iq 1
            }
            = sq + sq 1
        }
        ( rj_bits . c lout * k w w bits )
        = q 0
        : i nq2 ( vec_len [i] bits )
        ~ < q nq2 {
            : i cw ( vec_at [i] curw ( vec_at [i] bits q ) )
            ? >= cw 0 { ( rj_xpos c cw p1 ) } {}
            = q + q 1
        }
        : i nt ( vec_len [i] touched )
        = q 0
        ~ < q nt { ( vec_put [i] curw ( vec_at [i] touched q ) -1 ) = q + q 1 }
        ( vec_clear [i] touched )
        = k + k 1
    }
    ( vec_push [i] . c emoff ( vec_len [i] . c emu ) )
}

// ── per-web facts ───────────────────────────────────────────────
// Use k / the def of op: 1 when it is an integer value, 2 a float, 0 no
// opinion (moves, selects and calls carry whatever they are handed).
@ rj_ucls i op i k → i {
    ? | == op 28 == op 31 { ^ ? == k 1 2 1 } {}  // f64/f32.store: the value is a float
    ? | == op 153 == op 154 { ^ 2 } {}  // reinterpret float → int: reads a float
    ? | | ( rj_isfbin op ) ( rj_isfcmp op ) ( rj_isfminmax op ) { ^ 2 } {}
    ? | | & >= op 135 <= op 142 & >= op 113 <= op 117 | == op 111 == op 112 { ^ 2 } {}  // float-sourced truncations and unaries
    ? | | | | | == op 131 == op 117 == op 152 == op 147 & >= op 127 <= op 130 & >= op 198 <= op 201 { ^ 2 } {}
    ? | == op 125 == op 126 { ^ 0 } {}  // a sign-bit op works on either side
    ? & >= op 194 <= op 196 { ^ ? == k 1 2 1 } {}  // the base is an address, x a float
    ? == op 197 { ^ ? == k 0 1 2 } {}
    ? | | | == op 47 == op 46 == op 55 | == op 50 == op 210 { ^ 0 } {}
    ^ 1
}

@ rj_dcls i op → i {
    ? | | | == op 19 == op 24 == op 155 == op 156 { ^ 2 } {}  // float loads, reinterpret int → float
    ? & >= op 135 <= op 142 { ^ 1 } {}  // truncations produce integers
    ? | | ( rj_isfbin op ) ( rj_isfconv op ) | | == op 131 == op 117 & >= op 127 <= op 130 { ^ 2 } {}
    ? | | ( rj_isfminmax op ) & >= op 111 <= op 116 F { ^ 2 } {}
    ? | & >= op 194 <= op 196 & >= op 198 <= op 201 { ^ 2 } {}
    ? | == op 125 == op 126 { ^ 0 } {}
    ? | | | == op 47 == op 46 == op 51 | == op 50 == op 210 { ^ 0 } {}
    ^ 1
}

@ rj_vote Rj c i wv i cls i wt → v {
    ? == cls 1 { ( vec_put [i] . c wcls wv + ( vec_at [i] . c wcls wv ) * wt 65536 ) } {}
    ? == cls 2 { ( vec_put [i] . c wcls wv + ( vec_at [i] . c wcls wv ) wt ) } {}
}

@ rj_ext Rj c i wv i pos → v {
    ? < pos ( vec_at [i] . c wst wv ) { ( vec_put [i] . c wst wv pos ) } {}
    ? > pos ( vec_at [i] . c wen wv ) { ( vec_put [i] . c wen wv pos ) } {}
}

@ rj_addwt Rj c i wv i wt → v { ( vec_put [i] . c wwt wv + ( vec_at [i] . c wwt wv ) wt ) }

@ rj_hint Rj c i dw i sw → v { ? & >= dw 0 >= sw 0 { ? < ( vec_at [i] . c whint dw ) 0 { ( vec_put [i] . c whint dw sw ) } {} } {} }

@ rj_canon Rj c → v {
    : i nraw ( vec_len [i] . c uf )
    : ( Vec i ) dense ( vec_new [i] )
    : ~ i k 0
    ~ < k nraw { ( vec_push [i] dense -1 ) = k + k 1 }
    : ~ i nw 0
    = k 0
    ~ < k nraw {
        : i rt ( rj_find c k )
        ? < ( vec_at [i] dense rt ) 0 {
            ( vec_put [i] dense rt nw )
            ( vec_push [i] . c wslot ( vec_at [i] . c nslot rt ) )
            ( vec_push [i] . c wcls 0 ) ( vec_push [i] . c wwt 0 )
            ( vec_push [i] . c wst 2147483647 ) ( vec_push [i] . c wen -1 )
            ( vec_push [i] . c wuse 0 ) ( vec_push [i] . c wloc ( rjl_mem ) )
            ( vec_push [i] . c whint -1 ) ( vec_push [i] . c wcc 0 ) ( vec_push [i] . c wsens 0 ) ( vec_push [i] . c wdx 0 )
            = nw + nw 1
        } {}
        = k + k 1
    }
    ( rj_set c ( rjs_nw ) nw )
    // every id list now speaks dense web numbers
    : ~ i q 0
    : i nu ( vec_len [i] . c uweb )
    ~ < q nu { : i x ( vec_at [i] . c uweb q ) ? >= x 0 { ( vec_put [i] . c uweb q ( vec_at [i] dense ( rj_find c x ) ) ) } {} = q + q 1 }
    = q 0
    : i nd ( vec_len [i] . c dweb )
    ~ < q nd { : i x ( vec_at [i] . c dweb q ) ? >= x 0 { ( vec_put [i] . c dweb q ( vec_at [i] dense ( rj_find c x ) ) ) } {} = q + q 1 }
    = q 0
    : i ne ( vec_len [i] . c emu )
    ~ < q ne {
        : i x ( vec_at [i] . c emu q )
        ? >= x 0 { ( vec_put [i] . c emu q ( vec_at [i] dense ( rj_find c x ) ) ) } {}
        ( vec_put [i] . c emd q ( vec_at [i] dense ( rj_find c ( vec_at [i] . c emd q ) ) ) )
        = q + q 1
    }
    = q 0
    : i nen ( vec_len [i] . c entw )
    ~ < q nen { ( vec_put [i] . c entw q ( vec_at [i] dense ( rj_find c ( vec_at [i] . c entw q ) ) ) ) = q + q 1 }
    = q 0
    : i nx ( vec_len [i] . c xpos )
    ~ < q nx { ( vec_put [i] . c xpos q ( vec_at [i] dense ( rj_find c ( vec_at [i] . c xpos q ) ) ) ) = q + q 2 }
}

// loop weights: every backward branch multiplies the span it closes by 8
@ rj_depths Rj c → v {
    : i n ( rj_get c ( rjs_n ) )
    : ~ i r 0
    ~ < r n { ( vec_push [i] . c depth 1 ) = r + r 1 }
    = r 0
    ~ < r n {
        : i t ( rj_target c r )
        ? & >= t 0 <= t r {
            : ~ i k t
            ~ <= k r {
                : i dw ( vec_at [i] . c depth k )
                ? < dw 32768 { ( vec_put [i] . c depth k * dw 8 ) } {}
                = k + k 1
            }
        } {}
        = r + r 1
    }
}

// Does use k of op read bits 32..63 of its operand? Every i32 a slot holds
// is sign-extended (the predecoder drops i64.extend_i32_s on the strength
// of it), but only these consumers can tell: an i32 def whose web feeds none
// of them skips the movsxd. Copies (MOV, SEL's values, edge moves) pass the
// question on to their destination instead of answering it.
@ rj_usens i op i k → b {
    ? | | ( rj_isalu op ) & >= op 56 <= op 65 & >= op 96 <= op 101 {  // i32 ALU, compares, div/rem, rotates
        ? & & ( rj_isalu op ) <= op 8 >= op 0 { ^ T } {}  // the i64 half of the ALU set
        ^ F
    } {}
    ? | | | == op 43 == op 36 == op 37 & >= op 93 <= op 95 { ^ F } {}
    ? & >= op 157 <= op 161 { ^ F } {}  // extendN_s reads the low bits
    ? | | == op 148 == op 143 | == op 149 == op 144 { ^ F } {}  // i32 → float
    ? | | | == op 54 == op 168 == op 169 | == op 170 == op 163 { ^ F } {}  // i32 conditions / indices / deltas
    ? == op 48 { ^ T } {}  // IFZ: decided per record (C = 1: an i64 operand) in rj_sens
    ? == op 177 { ^ F } {}  // ADDBRIFC32
    ? == op 45 { ^ T } {}  // decided per record (the compare's width) in rj_sens
    : i mk ( rj_memkind op )
    ? >= mk 0 {
        ? == 0 & mk 1 { ^ F } {}  // a load's base and index are wrapped to 32 bits
        ? == k 0 { ^ F } {}  // a store's address
        ^ >= >> mk 2 8  // the stored value matters in full only at width 8
    } {}
    ? & >= op 205 <= op 208 { ^ F } {}
    ? | | == op 211 == op 212 & >= op 194 <= op 197 { ^ ? == k 0 F T } {}  // the base wraps; x is a full value
    ? == op 46 { ^ F } {}  // SEL: the condition is an i32 (tested 32-bit); the values are copies
    ^ T
}

// the sensitivity facts: direct consumers, then back through every copy
@ rj_sens Rj c → v {
    : i n ( rj_get c ( rjs_n ) )
    : ( Vec i ) csrc ( vec_new [i] )  // copy edges src → dst
    : ( Vec i ) cdst ( vec_new [i] )
    : ~ i r 0
    ~ < r n {
        : i op ( rj_rw c r 0 )
        : i u0 ( vec_at [i] . c uoff r )
        : ~ i o u0
        : i oe ( vec_at [i] . c uoff + r 1 )
        ~ < o oe {
            : i wv ( vec_at [i] . c uweb o )
            ? >= wv 0 {
                : i k - o u0
                : ~ b sens ( rj_usens op k )
                ? == op 45 { = sens >= ( rj_rw c r 4 ) 66 } {}  // BRIFC: an i64 compare reads the full value
                ? == op 48 { = sens != 0 ( rj_rw c r 3 ) } {}  // IFZ of an i64 (eqz fusion) tests all 64 bits
                ? | == op 47 & == op 46 < k 2 {  // a copy: the destination decides
                    = sens F
                    ( vec_push [i] csrc wv ) ( vec_push [i] cdst ( vec_at [i] . c dweb ( vec_at [i] . c doff r ) ) )
                } {}
                ? & >= op 153 <= op 156 { = sens T } {}
                ? sens { ( vec_put [i] . c wsens wv 1 ) } {}
            } {}
            = o + o 1
        }
        = r + r 1
    }
    : i nb ( rj_get c ( rjs_nb ) )
    : ~ i k ( rj_get c ( rjs_nreal ) )
    ~ < k nb {
        : ~ i q ( vec_at [i] . c emoff k )
        : i qe ( vec_at [i] . c emoff + k 1 )
        ~ < q qe {
            : i su ( vec_at [i] . c emu q )
            ? >= su 0 { ( vec_push [i] csrc su ) ( vec_push [i] cdst ( vec_at [i] . c emd q ) ) } {}
            = q + q 1
        }
        = k + k 1
    }
    // back through the copies until nothing changes
    : i ne ( vec_len [i] csrc )
    : ~ b changed T
    ~ changed {
        = changed F
        : ~ i q 0
        ~ < q ne {
            : i sw ( vec_at [i] csrc q )
            ? & != 0 ( vec_at [i] . c wsens ( vec_at [i] cdst q ) ) == 0 ( vec_at [i] . c wsens sw ) {
                ( vec_put [i] . c wsens sw 1 ) = changed T
            } {}
            = q + q 1
        }
    }
}

// must record r's i32 def number k come out sign-extended?
@ rj_dcanon Rj c i od → b { ^ != 0 ( vec_at [i] . c wsens ( vec_at [i] . c dweb od ) ) }

@ rj_facts Rj c → v {
    : i n ( rj_get c ( rjs_n ) )
    : i nl ( rj_get c ( rjs_nl ) )
    : ~ i r 0
    ~ < r n {
        : i op ( rj_rw c r 0 )
        : i dw ( vec_at [i] . c depth r )
        : i u0 ( vec_at [i] . c uoff r )
        : ~ i o u0
        : i oe ( vec_at [i] . c uoff + r 1 )
        ~ < o oe {
            : i wv ( vec_at [i] . c uweb o )
            ? >= wv 0 {
                ( rj_ext c wv * 2 r )
                ( rj_addwt c wv dw )
                ( vec_put [i] . c wuse wv + ( vec_at [i] . c wuse wv ) 1 )
                ( rj_vote c wv ( rj_ucls op - o u0 ) dw )
            } {}
            = o + o 1
        }
        = o ( vec_at [i] . c doff r )
        : i de ( vec_at [i] . c doff + r 1 )
        ~ < o de {
            : i wv ( vec_at [i] . c dweb o )
            ( rj_ext c wv + * 2 r 1 )
            ( rj_addwt c wv dw )
            ( rj_vote c wv ( rj_dcls op ) dw )
            = o + o 1
        }
        // copy hints: a MOV's or a two-address op's dst would like its source's register
        : i d0 ( vec_at [i] . c doff r )
        ? & < d0 de < u0 oe {
            ? | | ( rj_isalu op ) ( rj_isfused op ) == op 47 {
                ( rj_hint c ( vec_at [i] . c dweb d0 ) ( vec_at [i] . c uweb u0 ) )
            } {}
        } {}
        = r + r 1
    }
    // edge moves, at their branch record's position
    : i nb ( rj_get c ( rjs_nb ) )
    : ~ i k ( rj_get c ( rjs_nreal ) )
    ~ < k nb {
        : i br ( vec_at [i] . c bfirst k )
        : i dw ( vec_at [i] . c depth br )
        : ~ i q ( vec_at [i] . c emoff k )
        : i qe ( vec_at [i] . c emoff + k 1 )
        ~ < q qe {
            : i su ( vec_at [i] . c emu q )
            : i sd ( vec_at [i] . c emd q )
            ? >= su 0 {
                ( rj_ext c su * 2 br ) ( rj_addwt c su dw )
                ( vec_put [i] . c wuse su + ( vec_at [i] . c wuse su ) 1 )
            } {}
            ( rj_ext c sd + * 2 br 1 ) ( rj_addwt c sd dw )
            ( rj_hint c sd su )
            = q + q 1
        }
        = k + k 1
    }
    : i nx ( vec_len [i] . c xpos )
    : ~ i q 0
    ~ < q nx { ( rj_ext c ( vec_at [i] . c xpos q ) ( vec_at [i] . c xpos + q 1 ) ) = q + q 2 }
    // declared local types are the strongest class evidence there is
    : i nw ( rj_get c ( rjs_nw ) )
    : ~ i wv 0
    ~ < wv nw {
        : i s ( vec_at [i] . c wslot wv )
        ? & < s nl < s ( vec_len [i] . c ltype ) {
            : i ty ( vec_at [i] . c ltype s )
            ( rj_vote c wv ? >= ty 2 2 1 + 4 ( vec_at [i] . c wwt wv ) )
        } {}
        // votes → class: 1 = xmm when the float evidence outweighs the int
        : i vt ( vec_at [i] . c wcls wv )
        ( vec_put [i] . c wcls wv ? > % vt 65536 / vt 65536 1 0 )
        = wv + wv 1
    }
    // live across a call: some call record c with 2c ≥ start and 2c+2 ≤ end
    = r 0
    ~ < r n {
        : i op9 ( rj_rw c r 0 )
        ? ( rj_iscall op9 ) { ( vec_push [i] . c callr r ) } {}
        ? ( rj_clobdx op9 ) { ( vec_push [i] . c dxr r ) } {}
        = r + r 1
    }
    : i ndx ( vec_len [i] . c dxr )
    ? > ndx 0 {
        = wv 0
        ~ < wv nw {
            ? ( rj_crosses . c dxr ( vec_at [i] . c wst wv ) ( vec_at [i] . c wen wv ) ) { ( vec_put [i] . c wdx wv 1 ) } {}
            = wv + wv 1
        }
    } {}
    : i ncr ( vec_len [i] . c callr )
    ? > ncr 0 {
        = wv 0
        ~ < wv nw {
            : i ws ( vec_at [i] . c wst wv )
            : i we ( vec_at [i] . c wen wv )
            // first call record ≥ ws/2 (binary search)
            : ~ i lo 0
            : ~ i hi ncr
            ~ < lo hi {
                : i mid / + lo hi 2
                ? < * 2 ( vec_at [i] . c callr mid ) ws { = lo + mid 1 } { = hi mid }
            }
            ? < lo ncr { ? <= + * 2 ( vec_at [i] . c callr lo ) 2 we { ( vec_put [i] . c wcc wv 1 ) } {} } {}
            = wv + wv 1
        }
    } {}
}

// ── linear scan ─────────────────────────────────────────────────
// GPR order: caller-saved first (no prologue cost), callee-saved after;
// a web live across a call may only take a callee-saved one.
// Ordered by what a register costs the function that takes it: rsi and
// rdx cost nothing; r9/r10/r8 one instruction at every call and return;
// the callee-saved ones a push and a pop per invocation; rdi (the
// context) a push, a pop and a reload before every call.
@ rj_gpool i k → i {  // 11 entries
    ? == k 0 { ^ 6 } {}  // rsi
    ? == k 1 { ^ 2 } {}  // rdx (arg0 on calls; scratch of div/rem and the bit counts)
    ? == k 2 { ^ 9 } {}  // r9  (globals base: put back before calls)
    ? == k 3 { ^ 10 } {}  // r10 (memory bytes: put back before calls)
    ? == k 4 { ^ 8 } {}  // r8  (the anchor: rematerialised before calls)
    ? == k 5 { ^ 12 } {}
    ? == k 6 { ^ 13 } {}
    ? == k 7 { ^ 14 } {}
    ? == k 8 { ^ 15 } {}
    ? == k 9 { ^ 5 } {}  // rbp
    ^ 7  // rdi (the context: saved at entry, reloaded before calls)
}

@ rj_calleesaved i l → b { ^ | | == l 5 == l 12 | | == l 13 == l 14 == l 15 }

@ rj_allowed i l i cls i cross → b {
    ? == cls 1 { ^ & ( rj_isx l ) & == cross 0 >= l 18 } {}
    ? ! ( rj_isg l ) { ^ F } {}
    ? | | | | | == l 2 == l 6 == l 7 == l 8 == l 9 == l 10 { ^ == cross 0 } {}
    ^ ( rj_calleesaved l )
}

// records whose lowering uses rdx as scratch (its webs may not be live across them)
@ rj_clobdx i op → b { ^ | | | | & >= op 96 <= op 99 & >= op 105 <= op 108 == op 93 == op 94 | == op 102 == op 103 }

// is some record c of the ascending list `rs` inside (ws, we) — 2c ≥ ws, 2c+2 ≤ we?
@ rj_crosses ( Vec i ) rs i ws i we → b {
    : i nr ( vec_len [i] rs )
    : ~ i lo 0
    : ~ i hi nr
    ~ < lo hi {
        : i mid / + lo hi 2
        ? < * 2 ( vec_at [i] rs mid ) ws { = lo + mid 1 } { = hi mid }
    }
    ? < lo nr { ^ <= + * 2 ( vec_at [i] rs lo ) 2 we } {}
    ^ F
}

// spill priority: weight per unit of live length — a short temporary on a
// dependency chain keeps its register, a sparse long-lived value gives it up
@ rj_dens Rj c i wv → i {
    : i len - ( vec_at [i] . c wen wv ) ( vec_at [i] . c wst wv )
    ^ / * ( vec_at [i] . c wwt wv ) 256 + len 8
}

@ rj_alloc Rj c → v {
    : i nw ( rj_get c ( rjs_nw ) )
    : i n ( rj_get c ( rjs_n ) )
    : i npos + * 2 n 2
    : ( Vec i ) head ( vec_new [i] )
    : ~ i k 0
    ~ < k npos { ( vec_push [i] head -1 ) = k + k 1 }
    : ( Vec i ) nxt ( vec_new [i] )
    = k 0
    ~ < k nw { ( vec_push [i] nxt -1 ) = k + k 1 }
    = k - nw 1
    ~ >= k 0 {
        : ~ i p ( vec_at [i] . c wst k )
        ? < p 0 { = p 0 } {}
        ? >= p npos { = p - npos 1 } {}
        ( vec_put [i] nxt k ( vec_at [i] head p ) ) ( vec_put [i] head p k )
        = k - k 1
    }
    : ( Vec i ) occ ( vec_new [i] )
    = k 0
    ~ < k 32 { ( vec_push [i] occ -1 ) = k + k 1 }
    : ~ i used 0
    : ~ i p 0
    ~ < p npos {
        : ~ i wv ( vec_at [i] head p )
        ~ >= wv 0 {
            : b dead == 0 ( vec_at [i] . c wuse wv )  // a dead def still needs somewhere to land
            ? T {
                : i ws ( vec_at [i] . c wst wv )
                = k 0
                ~ < k 32 {
                    : i ow ( vec_at [i] occ k )
                    ? >= ow 0 { ? < ( vec_at [i] . c wen ow ) ws { ( vec_put [i] occ k -1 ) } {} } {}
                    = k + k 1
                }
                : i cls ( vec_at [i] . c wcls wv )
                : i cross ( vec_at [i] . c wcc wv )
                : i nodx ( vec_at [i] . c wdx wv )
                : ~ i pick -1
                : i h ( vec_at [i] . c whint wv )
                ? >= h 0 {
                    : i hl ( vec_at [i] . c wloc h )
                    ? & < hl 32 ( rj_allowed hl cls cross ) { ? < ( vec_at [i] occ hl ) 0 { = pick hl } {} } {}
                } {}
                : i npool ? == cls 1 14 11
                : i forbid ( rj_get c ( rjs_forbid ) )
                ? & >= pick 0 != 0 & ( rj_shr forbid pick ) 1 { = pick -1 } {}
                ? & == pick 2 != 0 nodx { = pick -1 } {}
                = k 0
                ~ & < pick 0 < k npool {
                    : i l ? == cls 1 + 18 k ( rj_gpool k )
                    ? & & & ( rj_allowed l cls cross ) < ( vec_at [i] occ l ) 0 == 0 & ( rj_shr forbid l ) 1 | != l 2 == 0 nodx { = pick l } {}
                    = k + k 1
                }
                ? & < pick 0 ! dead {  // full: evict the holder that uses its register least densely
                    : ~ i vl -1
                    : ~ i vw ( rj_dens c wv )
                    = k 0
                    ~ < k npool {
                        : i l ? == cls 1 + 18 k ( rj_gpool k )
                        : i ow ( vec_at [i] occ l )
                        ? & & & ( rj_allowed l cls cross ) >= ow 0 == 0 & ( rj_shr forbid l ) 1 | != l 2 == 0 nodx {
                            : i od ( rj_dens c ow )
                            ? < od vw { = vw od = vl l } {}
                        } {}
                        = k + k 1
                    }
                    ? >= vl 0 { ( vec_put [i] . c wloc ( vec_at [i] occ vl ) ( rjl_mem ) ) = pick vl } {}
                } {}
                ? >= pick 0 { ( vec_put [i] occ pick wv ) ( vec_put [i] . c wloc wv pick ) } {}
            } {}
            = wv ( vec_at [i] nxt wv )
        }
        = p + p 1
    }
    // frameless: no call or call-out, and no web in memory — nothing
    // addresses the frame, so no rbx and no slab bump
    : ~ b fl == 0 ( vec_len [i] . c callr )
    = k 0
    ~ & fl < k nw { ? == ( vec_at [i] . c wloc k ) ( rjl_mem ) { = fl F } {} = k + k 1 }
    ( rj_set c ( rjs_fl ) ? fl 1 0 )
    // the registers that ended up holding something (evictions included)
    = k 0
    ~ < k nw {
        : i l ( vec_at [i] . c wloc k )
        ? < l 32 { = used | used << 1 l } {}
        = k + k 1
    }
    ( rj_set c ( rjs_used ) used )
}

// ── operands ────────────────────────────────────────────────────
@ rj_uloc Rj c i o → i {
    : i wv ( vec_at [i] . c uweb o )
    ? < wv 0 { ^ ( rjl_imm ) } {}  // a constant-pool slot
    ^ ( vec_at [i] . c wloc wv )
}

@ rj_us Rj c i o → i { ^ ( vec_at [i] . c uslot o ) }

@ rj_dloc Rj c i o → i { ^ ( vec_at [i] . c wloc ( vec_at [i] . c dweb o ) ) }

@ rj_ds Rj c i o → i { ^ ( vec_at [i] . c dslot o ) }

@ rj_dlive Rj c i o → b { ^ > ( vec_at [i] . c wuse ( vec_at [i] . c dweb o ) ) 0 }

@ rj_kval Rj c i s → i { ^ ( vec_at [i] . c kv - s ( rj_get c ( rjs_nl ) ) ) }

// use #k / def #k of record r
@ rj_u Rj c i r i k → i { ^ + ( vec_at [i] . c uoff r ) k }

@ rj_dd Rj c i r i k → i { ^ + ( vec_at [i] . c doff r ) k }

// movq xmm, r64 / movq r64, xmm
@ rj_movq_xg Rj c i x i g → v { ( rj_rr c 102 1 1 110 x g 0 ) }

@ rj_movq_gx Rj c i g i x → v { ( rj_rr c 102 1 1 126 x g 0 ) }

// movsd xmm, [rbx+8s] / movsd [rbx+8s], xmm
@ rj_ldfx Rj c i x i s → v { ( rj_rm c 242 0 1 16 x 3 -1 0 ( rj_home s ) 0 ) }

@ rj_stfx Rj c i s i x → v { ( rj_rm c 242 0 1 17 x 3 -1 0 ( rj_home s ) 0 ) }

@ rj_movx Rj c i dst i src → v { ? != dst src { ( rj_rr c 0 0 1 40 dst src 0 ) } {} }  // movaps

// GPR reg ← operand (64-bit). keep = 1: the flags must survive.
@ rj_ldg Rj c i reg i loc i s i keep → v {
    ? ( rj_isg loc ) { ( rj_mov_rr c 1 reg loc ) ^ v } {}
    ? ( rj_isx loc ) { ( rj_movq_gx c reg - loc 16 ) ^ v } {}
    ? == loc ( rjl_mem ) { ( rj_ldf c 1 reg s ) ^ v } {}
    ( rj_mov_ri c reg ( rj_kval c s ) keep )
}

// XMM x ← operand
@ rj_ldx Rj c i x i loc i s → v {
    ? ( rj_isx loc ) { ( rj_movx c x - loc 16 ) ^ v } {}
    ? ( rj_isg loc ) { ( rj_movq_xg c x loc ) ^ v } {}
    ? == loc ( rjl_mem ) { ( rj_ldfx c x s ) ^ v } {}
    : i kq ( rj_kval c s )
    ? == kq 0 { ( rj_rr c 0 0 1 87 x x 0 ) } {  // xorps x,x
        ( rj_ripop c 242 0 1 16 x kq ) }  // movsd x,[rip+k]
}

// def location ← GPR reg
@ rj_stg Rj c i loc i s i reg → v {
    ? ( rj_isg loc ) { ( rj_mov_rr c 1 loc reg ) ^ v } {}
    ? ( rj_isx loc ) { ( rj_movq_xg c - loc 16 reg ) ^ v } {}
    ( rj_stf c 1 s reg )
}

// def location ← XMM x
@ rj_stx Rj c i loc i s i x → v {
    ? ( rj_isx loc ) { ( rj_movx c - loc 16 x ) ^ v } {}
    ? ( rj_isg loc ) { ( rj_movq_gx c loc x ) ^ v } {}
    ( rj_stfx c s x )
}

// a whole-value copy between two operand places (dl/ds ← sl/ss)
@ rj_move Rj c i dl i ds i sl i ss → v {
    ? == dl sl { ? | ( rj_isg dl ) ( rj_isx dl ) { ^ v } {} ? & == dl ( rjl_mem ) == ds ss { ^ v } {} } {}
    ? ( rj_isg dl ) { ( rj_ldg c dl sl ss 0 ) ^ v } {}
    ? ( rj_isx dl ) { ( rj_ldx c - dl 16 sl ss ) ^ v } {}
    ? ( rj_isg sl ) { ( rj_stf c 1 ds sl ) ^ v } {}
    ? ( rj_isx sl ) { ( rj_stfx c ds - sl 16 ) ^ v } {}
    ? == sl ( rjl_imm ) {
        : i kq ( rj_kval c ss )
        ? ( rj_fits32 kq ) { ( rj_rm c 0 1 0 199 0 3 -1 0 ( rj_home ds ) 0 ) ( rj_d c kq ) ^ v } {}  // mov qword [m], simm32
    } {}
    ( rj_ldg c 0 sl ss 0 ) ( rj_stf c 1 ds 0 )
}

// A register operand's GPR, or -1 when the operand lives elsewhere.
@ rj_greg i loc → i { ^ ? ( rj_isg loc ) loc -1 }

// `op R, operand` for the ALU group `ext`, width w. Uses rcx when the
// operand has no direct form.
@ rj_opsrc Rj c i w i ext i reg i loc i s → v {
    ? ( rj_isg loc ) { ( rj_alu_rr c w ext reg loc ) ^ v } {}
    ? ( rj_isx loc ) { ( rj_movq_gx c 1 - loc 16 ) ( rj_alu_rr c w ext reg 1 ) ^ v } {}
    ? == loc ( rjl_mem ) { ( rj_alu_rf c w ext reg s ) ^ v } {}
    : ~ i kq ( rj_kval c s )
    ? == w 0 { = kq >> << kq 32 32 } {}  // a 32-bit op reads the low half, sign-extended imm32
    ? ( rj_fits32 kq ) { ( rj_alu_ri c w ext reg kq ) ^ v } {}
    ? & == ext 4 == kq 4294967295 { ( rj_mov32 c reg reg ) ^ v } {}  // and r, 0xffffffff → mov r32, r32
    ( rj_ripop c 0 w 0 + * ext 8 3 reg kq )  // op r, [rip+k]
}

// ── lowering: integer arithmetic ────────────────────────────────
@ rj_sx32 i v → i { ^ >> << v 32 32 }

// dst = a OP b, OP one of the ALU groups (add 0, or 1, and 4, sub 5,
// xor 6); w = 1 for i64, 0 for i32 (the result is then sign-extended —
// every i32 a slot holds is canonical, and the predecoder relies on it).
@ rj_e_bin Rj c i r i ext i w → v {
    : i oa ( rj_u c r 0 )
    : i ob ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i _tr ( rj_alu3 c ext w ( rj_uloc c oa ) ( rj_us c oa ) ( rj_uloc c ob ) ( rj_us c ob ) ( rj_dloc c od ) ( rj_ds c od ) ( rj_dcanon c od ) )
}

// shifts and rotates: ext shl 4, shr 5, sar 7, rol 0, ror 1
@ rj_e_shift Rj c i r i ext i w → v {
    : i oa ( rj_u c r 0 )
    : i ob ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i al ( rj_uloc c oa )
    : i as ( rj_us c oa )
    : i bl ( rj_uloc c ob )
    : i bs ( rj_us c ob )
    : i dl ( rj_dloc c od )
    : i ds ( rj_ds c od )
    : i tr ? ( rj_isg dl ) dl 0
    ? == bl ( rjl_imm ) {
        ( rj_ldg c tr al as 0 )
        ( rj_shift_ri c w ext tr & ( rj_kval c bs ) ? == w 1 63 31 )
    } {
        ( rj_ldg c 1 bl bs 0 )  // the count first: dst may be the count's register
        ( rj_ldg c tr al as 0 )
        ( rj_shift_cl c w ext tr )
    }
    ? & == w 0 ( rj_dcanon c od ) { ( rj_movsxd c tr tr ) } {}
    ? != tr dl { ( rj_stg c dl ds tr ) } {}
}

// imul R, operand
@ rj_imulsrc Rj c i w i reg i loc i s → v {
    ? ( rj_isg loc ) { ( rj_imul_rr c w reg loc ) ^ v } {}
    ? == loc ( rjl_mem ) { ( rj_imul_rf c w reg s ) ^ v } {}
    ? == loc ( rjl_imm ) {
        : ~ i kq ( rj_kval c s )
        ? == w 0 { = kq ( rj_sx32 kq ) } {}
        ? ( rj_fits32 kq ) { ( rj_imul_rri c w reg reg kq ) } { ( rj_ripop c 0 w 1 175 reg kq ) }
        ^ v
    } {}
    ( rj_ldg c 1 loc s 0 ) ( rj_imul_rr c w reg 1 )
}

@ rj_e_mul Rj c i r i w → v {
    : i oa ( rj_u c r 0 )
    : i ob ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : ~ i al ( rj_uloc c oa )
    : ~ i as ( rj_us c oa )
    : ~ i bl ( rj_uloc c ob )
    : ~ i bs ( rj_us c ob )
    : i dl ( rj_dloc c od )
    : i ds ( rj_ds c od )
    : i tr ? ( rj_isg dl ) dl 0
    ? & == al ( rjl_imm ) != bl ( rjl_imm ) {  // constant on the right
        : i tl al : i ts as
        = al bl = as bs = bl tl = bs ts
    } {}
    : ~ b done F
    ? == bl ( rjl_imm ) {
        : ~ i kq ( rj_kval c bs )
        ? == w 0 { = kq ( rj_sx32 kq ) } {}
        ? ( rj_fits32 kq ) {
            ? ( rj_isg al ) { ( rj_imul_rri c w tr al kq ) } {
                ? == al ( rjl_mem ) {
                    ? ( rj_fits8 kq ) { ( rj_rm c 0 w 0 107 tr 3 -1 0 ( rj_home as ) 0 ) ( rj_b c kq ) } {
                        ( rj_rm c 0 w 0 105 tr 3 -1 0 ( rj_home as ) 0 ) ( rj_d c kq ) }
                } { ( rj_ldg c tr al as 0 ) ( rj_imul_rri c w tr tr kq ) }
            }
            = done T
        } {}
    } {}
    ? done {} {
        ? == tr al { ( rj_imulsrc c w tr bl bs ) } {
            ? == tr bl { ( rj_imulsrc c w tr al as ) } { ( rj_ldg c tr al as 0 ) ( rj_imulsrc c w tr bl bs ) }
        }
    }
    ? & == w 0 ( rj_dcanon c od ) { ( rj_movsxd c tr tr ) } {}
    ? != tr dl { ( rj_stg c dl ds tr ) } {}
}

// the fused i64 pairs: dst = (s1 op1 s2) op2 x
@ rj_fop1 Rj c i op i tr i l2 i s2 → v {  // tr op1= s2
    ? | | | == op 14 == op 15 == op 16 == op 22 { ( rj_opsrc c 1 0 tr l2 s2 ) ^ v } {}  // add
    ? == op 13 { ( rj_imulsrc c 1 tr l2 s2 ) ^ v } {}  // mul
    ? == op 33 { ( rj_opsrc c 1 6 tr l2 s2 ) ^ v } {}  // xor
    // shr_u by s2 (SHRUAND / SHRUXOR): the count is loaded before s1 lands
    ? == l2 ( rjl_imm ) { ( rj_shift_ri c 1 5 tr & ( rj_kval c s2 ) 63 ) } { ( rj_shift_cl c 1 5 tr ) }
}

@ rj_e_fused Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i o1 ( rj_u c r 0 )
    : i o2 ( rj_u c r 1 )
    : i o3 ( rj_u c r 2 )
    : i l1 ( rj_uloc c o1 )
    : i s1 ( rj_us c o1 )
    : i l2 ( rj_uloc c o2 )
    : i s2 ( rj_us c o2 )
    : i l3 ( rj_uloc c o3 )
    : i s3 ( rj_us c o3 )
    : i dl ( rj_dloc c od )
    : b shr1 | == op 17 == op 30
    : b comm2 ! == op 16  // the second op commutes except ADDSHRU's shift
    // dst already holds x and op2 commutes: t in rax, then one op into dst
    ? & & ( rj_isg dl ) == dl l3 comm2 {
        ? & shr1 != l2 ( rjl_imm ) { ( rj_ldg c 1 l2 s2 0 ) } {}
        ( rj_ldg c 0 l1 s1 0 )
        ( rj_fop1 c op 0 l2 s2 )
        ? | == op 13 == op 22 { ( rj_alu_rr c 1 0 dl 0 ) } {}
        ? | == op 14 == op 17 { ( rj_alu_rr c 1 4 dl 0 ) } {}
        ? | == op 15 == op 33 { ( rj_imul_rr c 1 dl 0 ) } {}
        ? == op 30 { ( rj_alu_rr c 1 6 dl 0 ) } {}
        ^ v
    } {}
    : i tr ? & & ( rj_isg dl ) != dl l2 != dl l3 dl 0
    ? & shr1 != l2 ( rjl_imm ) { ( rj_ldg c 1 l2 s2 0 ) } {}
    ( rj_ldg c tr l1 s1 0 )
    ( rj_fop1 c op tr l2 s2 )
    ? | == op 13 == op 22 { ( rj_opsrc c 1 0 tr l3 s3 ) } {}  // + x
    ? | == op 14 == op 17 { ( rj_opsrc c 1 4 tr l3 s3 ) } {}  // & x
    ? | == op 15 == op 33 { ( rj_imulsrc c 1 tr l3 s3 ) } {}  // * x
    ? == op 30 { ( rj_opsrc c 1 6 tr l3 s3 ) } {}  // ^ x
    ? == op 16 {  // >>u x
        ? == l3 ( rjl_imm ) { ( rj_shift_ri c 1 5 tr & ( rj_kval c s3 ) 63 ) } {
            ( rj_ldg c 1 l3 s3 0 ) ( rj_shift_cl c 1 5 tr ) }
    } {}
    ? != tr dl { ( rj_stg c dl ( rj_ds c od ) tr ) } {}
}

// ── compares and selects ────────────────────────────────────────
// cmp a, b (width w), a not an immediate
@ rj_cmp1 Rj c i w i al i as i bl i bs → v {
    ? ( rj_isg al ) { ( rj_opsrc c w 7 al bl bs ) ^ v } {}
    ? == al ( rjl_mem ) {
        ? ( rj_isg bl ) { ( rj_rm c 0 w 0 57 bl 3 -1 0 ( rj_home as ) 0 ) ^ v } {}  // cmp [m], reg
        ? == bl ( rjl_imm ) {
            : ~ i kq ( rj_kval c bs )
            ? == w 0 { = kq ( rj_sx32 kq ) } {}
            ? ( rj_fits32 kq ) { ( rj_alu_fi c w 7 as kq ) ^ v } {}
        } {}
    } {}
    ( rj_ldg c 0 al as 0 ) ( rj_opsrc c w 7 0 bl bs )
}

// cmp for the condition nibble cc; returns the nibble that holds after any
// operand exchange
@ rj_cmp Rj c i w i al i as i bl i bs i cc → i {
    ? & == al ( rjl_imm ) != bl ( rjl_imm ) { ( rj_cmp1 c w bl bs al as ) ^ ( rj_ccswap cc ) } {}
    ( rj_cmp1 c w al as bl bs ) ^ cc
}

// the fused-SEL run right behind a compare whose 0/1 is web wd
@ rj_selrun Rj c i r i wd → i {
    : i n ( rj_get c ( rjs_n ) )
    : ~ i nf 0
    : ~ i q + r 1
    : ~ b go T
    ~ & go < q n {
        = go F
        ? & == ( rj_rw c q 0 ) 46 == 0 ( vec_at [i] . c tgt q ) {
            ? == ( vec_at [i] . c uweb ( rj_u c q 2 ) ) wd { = nf + nf 1 = go T = q + q 1 } {}
        } {}
    }
    ^ nf
}

// materialise a compare's 0/1 into dst after the flags are set; pre = 1
// when dst was zeroed before the compare (then setcc alone finishes it)
@ rj_setbool Rj c i cc i dl i ds i pre → v {
    ? == pre 1 { ( rj_setcc c cc dl ) ^ v } {}
    ? ( rj_isg dl ) { ( rj_setcc c cc dl ) ( rj_movzx8 c dl dl ) ^ v } {}
    ( rj_setcc c cc 0 ) ( rj_movzx8 c 0 0 ) ( rj_stg c dl ds 0 )
}

@ rj_e_cmp Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i w ? >= op 66 1 0
    : i oa ( rj_u c r 0 )
    : i ob ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i wd ( vec_at [i] . c dweb od )
    : i al ( rj_uloc c oa )
    : i bl ( rj_uloc c ob )
    : i dl ( rj_dloc c od )
    : i nf ( rj_selrun c r wd )
    : i mat ? > ( vec_at [i] . c wuse wd ) nf 1 0
    : ~ i pre 0
    ? & == mat 1 ( rj_isg dl ) { ? & != dl al != dl bl { ( rj_rr c 0 0 0 49 dl dl 0 ) = pre 1 } {} } {}
    : i cc ( rj_cmp c w al ( rj_us c oa ) bl ( rj_us c ob ) ( rj_cmpcc op ) )
    ? == mat 1 { ( rj_setbool c cc dl ( rj_ds c od ) pre ) } {}
    ? > nf 0 { ( rj_set c ( rjs_fweb ) wd ) ( rj_set c ( rjs_fcc ) cc ) ( rj_set c ( rjs_fsel ) nf ) } {}
}

// test operand (w) — sets ZF from it; an immediate goes through rax
@ rj_testop Rj c i w i loc i s → v {
    ? ( rj_isg loc ) { ( rj_test_rr c w loc loc ) ^ v } {}
    ? == loc ( rjl_mem ) { ( rj_alu_fi c w 7 s 0 ) ^ v } {}
    ( rj_ldg c 0 loc s 0 ) ( rj_test_rr c w 0 0 )
}

@ rj_e_eqz Rj c i r i w → v {
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i al ( rj_uloc c oa )
    : i dl ( rj_dloc c od )
    : ~ i pre 0
    ? & ( rj_isg dl ) != dl al { ( rj_rr c 0 0 0 49 dl dl 0 ) = pre 1 } {}
    ( rj_testop c w al ( rj_us c oa ) )
    ( rj_setbool c 4 dl ( rj_ds c od ) pre )
}

// cmov<cc> R, operand (64-bit); immediates and xmm through rcx (flags kept)
@ rj_cmovsrc Rj c i cc i reg i loc i s → v {
    ? ( rj_isg loc ) { ( rj_cmov_rr c 1 cc reg loc ) ^ v } {}
    ? == loc ( rjl_mem ) { ( rj_cmov_rf c 1 cc reg s ) ^ v } {}
    ( rj_ldg c 1 loc s 1 ) ( rj_cmov_rr c 1 cc reg 1 )
}

@ rj_e_sel Rj c i r → v {
    : i ot ( rj_u c r 0 )
    : i of ( rj_u c r 1 )
    : i oc ( rj_u c r 2 )
    : i od ( rj_dd c r 0 )
    : i cw ( vec_at [i] . c uweb oc )
    : ~ i cc 5  // ne
    : i fsel ( rj_get c ( rjs_fsel ) )
    ? & & > fsel 0 >= cw 0 == cw ( rj_get c ( rjs_fweb ) ) {
        = cc ( rj_get c ( rjs_fcc ) )
        ( rj_set c ( rjs_fsel ) - fsel 1 )
    } {
        ( rj_set c ( rjs_fsel ) 0 ) ( rj_set c ( rjs_fweb ) -1 )
        ? ! ( rj_dlive c od ) { ^ v } {}
        ( rj_testop c 0 ( rj_uloc c oc ) ( rj_us c oc ) )  // the condition is an i32
    }
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i tl ( rj_uloc c ot )
    : i fl ( rj_uloc c of )
    : i dl ( rj_dloc c od )
    : i tr ? ( rj_isg dl ) dl 0
    ? == tr tl { ( rj_cmovsrc c ^^ cc 1 tr fl ( rj_us c of ) ) } {
        ? == tr fl { ( rj_cmovsrc c cc tr tl ( rj_us c ot ) ) } {
            ( rj_ldg c tr fl ( rj_us c of ) 1 )
            ( rj_cmovsrc c cc tr tl ( rj_us c ot ) )
        }
    }
    ? != tr dl { ( rj_stg c dl ( rj_ds c od ) tr ) } {}
}

// i32.wrap_i64 (dst = sign-extended low half), i64.extend_i32_u
// (zero-extended low half), the extendN_s family
@ rj_e_ext Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i al ( rj_uloc c oa )
    : i as ( rj_us c oa )
    : i dl ( rj_dloc c od )
    : i tr ? ( rj_isg dl ) dl 0
    ? == al ( rjl_imm ) {
        : i kq ( rj_kval c as )
        : ~ i rv kq
        ? | == op 36 == op 161 { = rv ( rj_sx32 kq ) } {}
        ? == op 37 { = rv & kq 4294967295 } {}
        ? | == op 157 == op 159 { = rv >> << kq 56 56 } {}
        ? | == op 158 == op 160 { = rv >> << kq 48 48 } {}
        ( rj_mov_ri c tr rv 0 )
    } {
        : ~ i sl al
        ? ( rj_isx al ) { ( rj_movq_gx c 1 - al 16 ) = sl 1 } {}
        : b memop == sl ( rjl_mem )
        // reg form: opcode bytes on the register; mem form: on the home
        ? | == op 36 == op 161 {  // movsxd
            ? memop { ( rj_rm c 0 1 0 99 tr 3 -1 0 ( rj_home as ) 0 ) } { ( rj_movsxd c tr sl ) }
        } {}
        ? == op 37 {  // mov r32, r/m32
            ? memop { ( rj_rm c 0 0 0 139 tr 3 -1 0 ( rj_home as ) 0 ) } { ( rj_mov32 c tr sl ) }
        } {}
        ? | == op 157 == op 159 {  // movsx r64, r/m8
            ? memop { ( rj_rm c 0 1 1 190 tr 3 -1 0 ( rj_home as ) 0 ) } { ( rj_rr c 0 1 1 190 tr sl 1 ) }
        } {}
        ? | == op 158 == op 160 {  // movsx r64, r/m16
            ? memop { ( rj_rm c 0 1 1 191 tr 3 -1 0 ( rj_home as ) 0 ) } { ( rj_rr c 0 1 1 191 tr sl 0 ) }
        } {}
    }
    ? != tr dl { ( rj_stg c dl ( rj_ds c od ) tr ) } {}
}

// i32.clz: bsr + cmov (baseline x86-64, no lzcnt)
@ rj_e_clz Rj c i r → v {
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    ( rj_ldg c 0 ( rj_uloc c oa ) ( rj_us c oa ) 0 )
    ( rj_b c 186 ) ( rj_d c -1 )  // mov edx,-1
    ( rj_b c 15 ) ( rj_b c 189 ) ( rj_b c 200 )  // bsr ecx,eax (ZF=1 on zero)
    ( rj_b c 15 ) ( rj_b c 68 ) ( rj_b c 202 )  // cmovz ecx,edx
    ( rj_b c 184 ) ( rj_d c 31 )  // mov eax,31
    ( rj_b c 41 ) ( rj_b c 200 )  // sub eax,ecx
    ( rj_stg c ( rj_dloc c od ) ( rj_ds c od ) 0 )
}

// ── lowering: linear memory (guard-page mode: no bounds checks) ──
// eax ← the wrapped 32-bit address (base + idx), idx an operand or none
@ rj_addr Rj c i bl i bs i xl i xs i hasx → v {
    ? | == hasx 0 == xl ( rjl_imm ) {
        : i xk ? == hasx 0 0 ( rj_rj32 c xs )
        ? == bl ( rjl_imm ) { ( rj_mov_ri c 0 & + ( rj_kval c bs ) xk 4294967295 0 ) ^ v } {}
        ? ( rj_isg bl ) {
            ? == xk 0 { ( rj_mov32 c 0 bl ) } { ( rj_lea c 0 0 bl -1 0 xk ) }
            ^ v
        } {}
        ? == bl ( rjl_mem ) { ( rj_rm c 0 0 0 139 0 3 -1 0 ( rj_home bs ) 0 ) } {  // mov eax, dword [home]
            ( rj_movq_gx c 0 - bl 16 ) ( rj_mov32 c 0 0 ) }
        ? != xk 0 { ( rj_alu_ri c 0 0 0 xk ) } {}
        ^ v
    } {}
    ? & ( rj_isg bl ) ( rj_isg xl ) { ( rj_lea c 0 0 bl xl 0 0 ) ^ v } {}
    ( rj_ldg c 0 bl bs 0 )
    ( rj_opsrc c 0 0 0 xl xs )  // add eax, idx — a 32-bit op zero-extends
}

// a constant's low 32 bits, sign-extended (a displacement / imm32)
@ rj_rj32 Rj c i s → i { ^ ( rj_sx32 ( rj_kval c s ) ) }

// [r11 + rax + off]
@ rj_mrm Rj c i pfx i w i esc i opc i reg i off i b8 → v { ( rj_rm c pfx w esc opc reg 11 0 0 off b8 ) }

// load wid bytes (sg: sign-extend) from [r11+rax+off] into GPR tr
@ rj_ldmem Rj c i tr i wid i sg i off → v {
    ? == wid 8 { ( rj_mrm c 0 1 0 139 tr off 0 ) ^ v } {}  // mov r64
    ? == wid 4 { ? == sg 1 { ( rj_mrm c 0 1 0 99 tr off 0 ) } { ( rj_mrm c 0 0 0 139 tr off 0 ) } ^ v } {}  // movsxd / mov r32
    ? == wid 2 { ? == sg 1 { ( rj_mrm c 0 1 1 191 tr off 0 ) } { ( rj_mrm c 0 0 1 183 tr off 0 ) } ^ v } {}  // movsx r64 / movzx r32
    ? == sg 1 { ( rj_mrm c 0 1 1 190 tr off 0 ) } { ( rj_mrm c 0 0 1 182 tr off 0 ) }  // byte
}

// the load into its def's place: xmm defs take an 8- or 4-byte float load directly
@ rj_ldto Rj c i od i wid i sg i off → v {
    : i dl ( rj_dloc c od )
    ? & ( rj_isx dl ) | == wid 8 & == wid 4 == sg 0 {
        ( rj_mrm c ? == wid 8 242 243 0 1 16 - dl 16 off 0 ) ^ v  // movsd / movss
    } {}
    : i tr ? ( rj_isg dl ) dl 0
    ( rj_ldmem c tr wid sg off )
    ? != tr dl { ( rj_stg c dl ( rj_ds c od ) tr ) } {}
}

@ rj_e_load Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i mk ( rj_memkind op )
    : i ob ( rj_u c r 0 )
    : i ox ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ( rj_addr c ( rj_uloc c ob ) ( rj_us c ob ) ( rj_uloc c ox ) ( rj_us c ox ) 1 )
    ( rj_ldto c od >> mk 2 & >> mk 1 1 ( rj_rw c r 3 ) )
}

@ rj_e_store Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i wid >> ( rj_memkind op ) 2
    : i oa ( rj_u c r 0 )
    : i ov ( rj_u c r 1 )
    : i off ( rj_rw c r 3 )
    ( rj_addr c ( rj_uloc c oa ) ( rj_us c oa ) 0 0 0 )
    : i vl ( rj_uloc c ov )
    : i vs ( rj_us c ov )
    ? & ( rj_isx vl ) | == wid 8 == wid 4 {
        ( rj_mrm c ? == wid 8 242 243 0 1 17 - vl 16 off 0 ) ^ v  // movsd / movss [m], x
    } {}
    ? == vl ( rjl_imm ) {
        : i kq ( rj_kval c vs )
        ? & == wid 8 ( rj_fits32 kq ) { ( rj_mrm c 0 1 0 199 0 off 0 ) ( rj_d c kq ) ^ v } {}
        ? == wid 4 { ( rj_mrm c 0 0 0 199 0 off 0 ) ( rj_d c kq ) ^ v } {}
        ? == wid 2 { ( rj_mrm c 102 0 0 199 0 off 0 ) ( rj_b c kq ) ( rj_b c >> kq 8 ) ^ v } {}
        ? == wid 1 { ( rj_mrm c 0 0 0 198 0 off 0 ) ( rj_b c kq ) ^ v } {}
    } {}
    : ~ i vr ( rj_greg vl )
    ? < vr 0 { ( rj_ldg c 1 vl vs 0 ) = vr 1 } {}
    ? == wid 8 { ( rj_mrm c 0 1 0 137 vr off 0 ) } {}
    ? == wid 4 { ( rj_mrm c 0 0 0 137 vr off 0 ) } {}
    ? == wid 2 { ( rj_mrm c 102 0 0 137 vr off 0 ) } {}
    ? == wid 1 { ( rj_mrm c 0 0 0 136 vr off 2 ) } {}
}

// LOADSHL: dst = mem[(x << k) w32 + off]; LOADSHLADD adds a base first
@ rj_e_loadshl Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : b add | == op 207 == op 208
    : i o1 ( rj_u c r 0 )  // LOADSHL: x ; LOADSHLADD: base
    : i o2 ( rj_u c r 1 )  // LOADSHL: k ; LOADSHLADD: x
    : i ok ? add ( rj_u c r 2 ) o2
    : i ox ? add o2 o1
    : i xl ( rj_uloc c ox )
    : i kl ( rj_uloc c ok )
    : ~ i kc -1
    ? == kl ( rjl_imm ) { = kc & ( rj_kval c ( rj_us c ok ) ) 31 } {}
    : ~ i bl -1
    ? add { = bl ( rj_uloc c o1 ) } {}
    ? & & >= kc 0 <= kc 3 & ( rj_isg xl ) | ! add ( rj_isg bl ) {
        // one 32-bit lea is the shift, the add and the wrap
        ( rj_lea c 0 0 ? add bl -1 xl kc 0 )
    } {
        ? >= kc 0 {} { ( rj_ldg c 1 kl ( rj_us c ok ) 0 ) }
        ( rj_ldg c 0 xl ( rj_us c ox ) 0 )
        ? >= kc 0 { ( rj_shift_ri c 0 4 0 kc ) } { ( rj_shift_cl c 0 4 0 ) }
        ? add { ( rj_opsrc c 0 0 0 bl ( rj_us c o1 ) ) } {}  // a 32-bit shl already zero-extended
    }
    : b is64 | == op 205 == op 207
    ( rj_ldto c ( rj_dd c r 0 ) ? is64 8 4 ? is64 0 1 ( rj_rw c r 3 ) )
}

// LOADMULI64 / LOADADDI64: dst = mem64[base w32 + off] * / + x
@ rj_e_loadop Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i ob ( rj_u c r 0 )
    : i ox ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ( rj_addr c ( rj_uloc c ob ) ( rj_us c ob ) 0 0 0 )
    : i dl ( rj_dloc c od )
    : i xl ( rj_uloc c ox )
    : i xs ( rj_us c ox )
    : i tr ? ( rj_isg dl ) dl 0  // rax: the address is dead once loaded
    ? == tr xl {  // dst holds x: fold the load in as the memory operand
        ? == op 211 { ( rj_mrm c 0 1 1 175 tr ( rj_rw c r 3 ) 0 ) } { ( rj_mrm c 0 1 0 3 tr ( rj_rw c r 3 ) 0 ) }
    } {
        ( rj_ldmem c tr 8 0 ( rj_rw c r 3 ) )
        ? == op 211 { ( rj_imulsrc c 1 tr xl xs ) } { ( rj_opsrc c 1 0 tr xl xs ) }
    }
    ? != tr dl { ( rj_stg c dl ( rj_ds c od ) tr ) } {}
}

// ── lowering: control ───────────────────────────────────────────
@ rj_goto Rj c i r i t → v { ? != t + r 1 { ( rj_jmp c t ) } {} }

// the destination of an edge move, as a place no other location aliases
@ rj_place i loc i s → i { ^ ? < loc 32 loc ? == loc ( rjl_mem ) + 64 s -1 }

// One parallel copy: dl[k]/ds[k] ← sl[k]/ss[k] for every k at once. A
// move goes once nothing still pending reads its destination; a cycle is
// broken through rcx.
@ rj_pmove Rj c ( Vec i ) dl ( Vec i ) ds ( Vec i ) sl ( Vec i ) ss → v {
    : ~ i left ( vec_len [i] dl )
    : ( Vec i ) done ( vec_new [i] )
    : ~ i q 0
    ~ < q left {
        ? == ( rj_place ( vec_at [i] dl q ) ( vec_at [i] ds q ) ) ( rj_place ( vec_at [i] sl q ) ( vec_at [i] ss q ) ) {
            ( vec_push [i] done 1 )  // already in place
        } { ( vec_push [i] done 0 ) }
        = q + q 1
    }
    : i tot left
    = left 0
    = q 0
    ~ < q tot { ? == 0 ( vec_at [i] done q ) { = left + left 1 } {} = q + q 1 }
    ~ > left 0 {
        : ~ b prog F
        = q 0
        ~ < q tot {
            ? == 0 ( vec_at [i] done q ) {
                : i pd ( rj_place ( vec_at [i] dl q ) ( vec_at [i] ds q ) )
                : ~ b blocked F
                : ~ i j 0
                ~ < j tot {
                    ? & != j q == 0 ( vec_at [i] done j ) {
                        ? == pd ( rj_place ( vec_at [i] sl j ) ( vec_at [i] ss j ) ) { = blocked T } {}
                    } {}
                    = j + j 1
                }
                ? blocked {} {
                    ( rj_move c ( vec_at [i] dl q ) ( vec_at [i] ds q ) ( vec_at [i] sl q ) ( vec_at [i] ss q ) )
                    ( vec_put [i] done q 1 )
                    = left - left 1
                    = prog T
                }
            } {}
            = q + q 1
        }
        ? prog {} {  // every pending move waits on another: park one source in rcx
            = q 0
            ~ < q tot {
                ? == 0 ( vec_at [i] done q ) {
                    ( rj_ldg c 1 ( vec_at [i] sl q ) ( vec_at [i] ss q ) 0 )
                    ( vec_put [i] sl q 1 ) ( vec_put [i] ss q -1 )
                    = q tot
                } { = q + q 1 }
            }
        }
    }
}

// An edge block's parallel copy.
@ rj_e_moves Rj c i e → v {
    : i q0 ( vec_at [i] . c emoff e )
    : i q1 ( vec_at [i] . c emoff + e 1 )
    : i md ( vec_at [i] . c bmd e )
    : i ms ( vec_at [i] . c bms e )
    : ( Vec i ) dl ( vec_new [i] )
    : ( Vec i ) ds ( vec_new [i] )
    : ( Vec i ) sl ( vec_new [i] )
    : ( Vec i ) ss ( vec_new [i] )
    : ~ i q q0
    ~ < q q1 {
        : i dw ( vec_at [i] . c emd q )
        ? > ( vec_at [i] . c wuse dw ) 0 {
            : i su ( vec_at [i] . c emu q )
            ( vec_push [i] dl ( vec_at [i] . c wloc dw ) ) ( vec_push [i] ds + md - q q0 )
            ( vec_push [i] sl ? < su 0 ( rjl_imm ) ( vec_at [i] . c wloc su ) ) ( vec_push [i] ss + ms - q q0 )
        } {}
        = q + q 1
    }
    ( rj_pmove c dl ds sl ss )
}

// the edge block a branch record owns (BRM / BRIFM)
@ rj_e_brm Rj c i r → v {
    : i e ( vec_at [i] . c eblk r )
    ( rj_e_moves c e )
    ( rj_goto c r ( vec_at [i] . c btgt e ) )
}

@ rj_e_brifm Rj c i r → v {
    : i oc ( rj_u c r 0 )
    ( rj_testop c 0 ( rj_uloc c oc ) ( rj_us c oc ) )  // an i32 condition
    : i skip ( rj_jcc_fwd c 4 )  // je past the moves
    ( rj_e_brm c r )
    ( rj_land c skip )
}

@ rj_e_brtbl Rj c i r → v {
    : i ab ( rj_rw c r 1 )
    : i last ( rj_rw c r 3 )  // the default row's index
    : i oi ( rj_u c r 0 )
    ( rj_ldg c 0 ( rj_uloc c oi ) ( rj_us c oi ) 0 )
    ( rj_mov32 c 0 0 )  // u32
    ( rj_b c 185 ) ( rj_d c last )  // mov ecx, last
    ( rj_alu_rr c 1 7 0 1 )  // cmp rax,rcx
    ( rj_cmov_rr c 1 3 0 1 )  // cmovae rax,rcx
    ( rj_b c 72 ) ( rj_b c 141 ) ( rj_b c 13 ) ( rj_d c 3 )  // lea rcx,[rip+3] → the table
    ( rj_b c 255 ) ( rj_b c 36 ) ( rj_b c 193 )  // jmp [rcx+rax*8]
    : i tabo ( rj_here c )
    : ~ i q 0
    ~ <= q last { ( rj_q c 0 ) = q + q 1 }
    : ~ i e ( vec_at [i] . c eblk r )
    = q 0
    ~ <= q last {
        : i rb + ab * q 4
        : i t ( rj_tgtrec ( vec_at [i] . c aux rb ) )
        ? > ( vec_at [i] . c aux + rb 3 ) 0 {
            ( vec_push [i] . c pta_off + tabo * q 8 ) ( vec_push [i] . c pta_stub ( rj_here c ) )
            ( rj_e_moves c e )
            ( rj_jmp c t )
            = e + e 1
        } { ( vec_push [i] . c ptr_off + tabo * q 8 ) ( vec_push [i] . c ptr_rec t ) }
        = q + q 1
    }
}

@ rj_e_brifc Rj c i r → v {
    : i oa ( rj_u c r 0 )
    : i ob ( rj_u c r 1 )
    : i cop ( rj_rw c r 4 )
    : i cc ( rj_cmp c ? >= cop 66 1 0 ( rj_uloc c oa ) ( rj_us c oa ) ( rj_uloc c ob ) ( rj_us c ob ) ( rj_cmpcc cop ) )
    ( rj_jcc c cc ( rj_tgtrec ( rj_rw c r 1 ) ) )
}

// dst = a OP b into dst's place; returns the GPR holding the result
@ rj_alu3 Rj c i ext i w i al i as i bl i bs i dl i ds b cn → i {
    : i comm ? | | | == ext 0 == ext 1 == ext 4 == ext 6 1 0
    : ~ i tr 0
    ? ( rj_isg dl ) {
        = tr dl
        ? == dl al { ( rj_opsrc c w ext dl bl bs ) } {
            ? == dl bl {
                ? == comm 1 { ( rj_opsrc c w ext dl al as ) } {
                    ( rj_rex c w 0 0 dl 0 ) ( rj_b c 247 ) ( rj_modrr c 3 dl )  // neg
                    ( rj_opsrc c w 0 dl al as )
                }
            } {
                : ~ b done F
                ? & == ext 0 ( rj_isg al ) {
                    ? ( rj_isg bl ) { ( rj_lea c w dl al bl 0 0 ) = done T } {
                        ? == bl ( rjl_imm ) {
                            : ~ i kq ( rj_kval c bs )
                            ? == w 0 { = kq ( rj_sx32 kq ) } {}
                            ? ( rj_fits32 kq ) { ( rj_lea c w dl al -1 0 kq ) = done T } {}
                        } {}
                    }
                } {}
                ? done {} { ( rj_ldg c dl al as 0 ) ( rj_opsrc c w ext dl bl bs ) }
            }
        }
    } { ( rj_ldg c 0 al as 0 ) ( rj_opsrc c w ext 0 bl bs ) }
    ? & == w 0 cn { ( rj_movsxd c tr tr ) } {}
    ? != tr dl { ( rj_stg c dl ds tr ) } {}
    ^ tr
}

// ADDBRIFC: dst = s1 + s2; branch when (dst cmp rhs) holds
@ rj_e_addbr Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i w ? == op 38 1 0
    : i o1 ( rj_u c r 0 )
    : i o2 ( rj_u c r 1 )
    : i orh ( rj_u c r 2 )
    : i od ( rj_dd c r 0 )
    : i dl ? ( rj_dlive c od ) ( rj_dloc c od ) ( rjl_mem )
    : i tr ( rj_alu3 c 0 w ( rj_uloc c o1 ) ( rj_us c o1 ) ( rj_uloc c o2 ) ( rj_us c o2 ) dl ( rj_ds c od ) ( rj_dcanon c od ) )
    : i cop >> ( rj_rw c r 5 ) 21
    ( rj_opsrc c w 7 tr ( rj_uloc c orh ) ( rj_us c orh ) )
    ( rj_jcc c ( rj_cmpcc cop ) ( rj_tgtrec ( rj_rw c r 1 ) ) )
}

// ── the register calling convention (tier 8 → tier 8) ──────────
// A callee with at most five parameters and at most one result gets a
// second, FAST entry: argument k arrives in rj_areg(k), the result leaves
// in rax, and nothing is stored to or reloaded from the caller's window.
// rcx is still the callee's frame base and rsi the window (the slab-full
// path spills the arguments there), rdi the context. Neither side keeps
// r8/r9/r10 as invariants across a fast call: tier 8 rematerialises the
// anchor wherever it reads it, reserves r9 for the globals base only in
// a function that touches globals (and reloads it after every call), and
// reads the memory size from the context. The memory entry (+28) — the
// driver's, the template tier's and the bridges' way in — is a wrapper:
// it loads the window into the argument registers, calls the fast entry,
// stores the result back and re-establishes the invariants its callers
// rely on.
@ rj_areg i k → i {
    ? == k 0 { ^ 2 } {}  // rdx
    ? == k 1 { ^ 0 } {}  // rax
    ? == k 2 { ^ 9 } {}  // r9
    ? == k 3 { ^ 10 } {}  // r10
    ^ 8  // r8
}

@ rj_fastsig i sig → b { ^ & & >= sig 0 <= ( rj_sig_np sig ) 5 <= ( rj_sig_nr sig ) 1 }

// rdi back to the context (a callee and every call-out need it there)
@ rj_restore_ctx Rj c → v {
    ? ( rj_uses c 7 ) { ( rj_b c 72 ) ( rj_b c 139 ) ( rj_b c 60 ) ( rj_b c 36 ) } {}  // mov rdi,[rsp]
}

// r9 back to the globals base after something may have clobbered it
@ rj_reglob Rj c → v {
    ? == 1 ( rj_get c ( rjs_glob ) ) { ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 79 ) ( rj_b c 24 ) } {}  // mov r9,[rdi+24]
}

// ── lowering: calls ─────────────────────────────────────────────
// the inline call-out into the runtime (the template tier's own sequence)
@ rj_callout Rj c i kind → v {
    ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 48 ) ( rj_d c kind )  // mov qword[rdi+48], kind
    ( rj_b c 72 ) ( rj_b c 137 ) ( rj_b c 31 )  // mov [rdi],rbx — the handler reads the frame base here
    ( rj_b c 87 ) ( rj_b c 85 )  // push rdi; push rbp
    ( rj_b c 72 ) ( rj_b c 137 ) ( rj_b c 229 )  // mov rbp,rsp
    ( rj_b c 72 ) ( rj_b c 131 ) ( rj_b c 228 ) ( rj_b c 240 )  // and rsp,-16
    ( rj_b c 72 ) ( rj_b c 191 ) ( rj_q c ( rj_get c ( rjs_coenv ) ) )  // movabs rdi, closure env
    ( rj_b c 72 ) ( rj_b c 184 ) ( rj_q c ( rj_get c ( rjs_cofn ) ) )  // movabs rax, closure fn
    ( rj_b c 255 ) ( rj_b c 208 )  // call rax
    ( rj_b c 72 ) ( rj_b c 137 ) ( rj_b c 236 )  // mov rsp,rbp
    ( rj_b c 93 ) ( rj_b c 95 )  // pop rbp; pop rdi
    ( rj_b c 73 ) ( rj_b c 184 ) ( rj_q c ( rj_get c ( rjs_spcell ) ) )  // movabs r8, anchor
    ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 95 ) ( rj_b c 8 )  // mov r11,[rdi+8]
    ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 87 ) ( rj_b c 16 )  // mov r10,[rdi+16]
    ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 79 ) ( rj_b c 24 )  // mov r9,[rdi+24]
    ( rj_b c 72 ) ( rj_b c 139 ) ( rj_b c 71 ) ( rj_b c 48 )  // mov rax,[rdi+48] — 0 ok / 1 trap recorded
    ( rj_b c 72 ) ( rj_b c 133 ) ( rj_b c 192 )  // test rax,rax
    ( rj_b c 116 ) ( rj_b c 10 )  // je +10 — over the trap exit
    ( rj_b c 191 ) ( rj_d c 11 )  // mov edi,11 (trap already recorded)
    ( rj_jmp c ( rj_stub_gate c ) )
}

// r9/r10 are cross-call invariants (globals base, memory bytes); a
// function that allocated them puts them back before control leaves it
@ rj_uses Rj c i l → b { ^ != 0 & ( rj_shr ( rj_get c ( rjs_used ) ) l ) 1 }

// The invariants a template-tier function, a bridge or a memory-entry
// caller expects: rdi the context, r8 the anchor, r9 the globals base, r10
// the memory size. Re-established before every memory-ABI call, call-out
// and memory-entry return — unconditionally, since a fast callee may have
// left anything in r8..r10.
@ rj_restore_inv Rj c → v {
    ( rj_restore_ctx c )
    ( rj_b c 73 ) ( rj_b c 184 ) ( rj_q c ( rj_get c ( rjs_spcell ) ) )  // movabs r8, anchor
    ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 79 ) ( rj_b c 24 )  // mov r9,[rdi+24]
    ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 87 ) ( rj_b c 16 )  // mov r10,[rdi+16]
}

// the args pointer's stack offset: above the saved context when rdi was handed out
@ rj_argsp Rj c → i { ^ ? ( rj_uses c 7 ) 8 0 }

@ rj_frameless Rj c → b { ^ == 1 ( rj_get c ( rjs_fl ) ) }

// lea rcx,[rbx + nslots*8] — the callee's frame base (the end of ours)
@ rj_frame_end Rj c → v { ( rj_lea c 1 1 3 -1 0 * ( rj_get c ( rjs_ns ) ) 8 ) }

@ rj_e_call Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i fx ( rj_rw c r 1 )
    : i ab ( rj_rw c r 2 )
    : i sig ( vec_at [i] . c rsig r )
    : i np ( rj_sig_np sig )
    : i nr ( rj_sig_nr sig )
    : ~ i k 0
    : i nimp ( rj_get c ( rjs_nimp ) )
    : b direct & == op 50 >= fx nimp
    : b fast & direct ( rj_fastsig sig )
    ? fast {
        // a register-argument call: the arguments go straight into rdx,
        // rax, r9, r10, r8 (one parallel copy), nothing through memory
        : ( Vec i ) dl ( vec_new [i] )
        : ( Vec i ) ds ( vec_new [i] )
        : ( Vec i ) sl ( vec_new [i] )
        : ( Vec i ) ss ( vec_new [i] )
        = k 0
        ~ < k np {
            : i o ( rj_u c r k )
            ( vec_push [i] dl ( rj_areg k ) ) ( vec_push [i] ds -1 )
            ( vec_push [i] sl ( rj_uloc c o ) ) ( vec_push [i] ss ( rj_us c o ) )
            = k + k 1
        }
        ( rj_pmove c dl ds sl ss )
        ( rj_restore_ctx c )
        ( rj_frame_end c )
        ( rj_lea c 1 6 3 -1 0 * ab 8 )  // lea rsi,[rbx+argbase*8] — the window, for the slab-full path
        ( rj_b c 232 ) ( rj_d c 0 )  // call rel32
        ? == fx ( rj_get c ( rjs_fidx ) ) {
            ( vec_push [i] . c pat_at - ( rj_here c ) 4 ) ( vec_push [i] . c pat_rec ( rj_lab_fast c ) )
        } {
            ( vec_push [i] . c cs_off - ( rj_here c ) 4 ) ( vec_push [i] . c cs_fx fx )
            ( vec_push [i] . c cs_ab ab ) ( vec_push [i] . c cs_nr nr ) ( vec_push [i] . c cs_kind 1 ) ( vec_push [i] . c cs_np np )
        }
        ( rj_reglob c )
    } {
        // arguments to their homes: the callee and every bridge read them there
        = k 0
        ~ < k np {
            : i o ( rj_u c r k )
            ( rj_move c ( rjl_mem ) + ab k ( rj_uloc c o ) ( rj_us c o ) )
            = k + k 1
        }
        ? & direct == np 1 { : i o0 ( rj_u c r 0 ) ( rj_ldg c 2 ( rj_uloc c o0 ) ( rj_us c o0 ) 0 ) } {}  // arg0 rides in rdx
        ( rj_restore_inv c )
        ( rj_frame_end c )
        ? direct {
            // a direct memory-ABI call: rel32 to the callee's memory entry
            // once it is compiled, to this site's stub until then
            ( rj_lea c 1 6 3 -1 0 * ab 8 )  // lea rsi,[rbx+argbase*8]
            ( rj_b c 232 ) ( rj_d c 0 )  // call rel32
            ? == fx ( rj_get c ( rjs_fidx ) ) {
                ( vec_push [i] . c pat_at - ( rj_here c ) 4 ) ( vec_push [i] . c pat_rec ( rj_lab_entry c ) )
            } {
                ( vec_push [i] . c cs_off - ( rj_here c ) 4 ) ( vec_push [i] . c cs_fx fx )
                ( vec_push [i] . c cs_ab ab ) ( vec_push [i] . c cs_nr nr ) ( vec_push [i] . c cs_kind 0 ) ( vec_push [i] . c cs_np np )
            }
        } {
            ( rj_b c 73 ) ( rj_b c 137 ) ( rj_b c 8 )  // mov [r8],rcx — the driver may run guest code above us
            ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 32 ) ( rj_d c fx )  // mov qword[rdi+32], fidx
            ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 40 ) ( rj_d c ab )  // mov qword[rdi+40], argbase
            ( rj_callout c 16 )
            ? == nr 1 { ( rj_ldf c 1 0 ab ) } {}  // the bridge left result 0 in memory only
        }
    }
    // results: result 0 is in rax on both paths; the rest are in their homes
    = k 0
    ~ < k nr {
        : i o ( rj_dd c r k )
        ? ( rj_dlive c o ) {
            : i dl ( rj_dloc c o )
            ? == nr 1 { ? != dl ( rjl_mem ) { ( rj_stg c dl ( rj_ds c o ) 0 ) } {} } {
                ? != dl ( rjl_mem ) { ( rj_move c dl ( rj_ds c o ) ( rjl_mem ) + ab k ) } {}
            }
        } {}
        = k + k 1
    }
}

@ rj_e_ret Rj c i r → v {
    : i nres ( rj_rw c r 2 )
    ? == 1 ( rj_get c ( rjs_fast ) ) {  // the register ABI: result 0 in rax, nothing else
        ? > nres 0 { : i o0 ( rj_u c r 0 ) ( rj_ldg c 0 ( rj_uloc c o0 ) ( rj_us c o0 ) 0 ) } {}
        ( rj_epilogue c )
        ^ v
    } {}
    // the args pointer: still in rsi when a frameless function never took
    // rsi, else saved on the stack
    : i ap ? & ( rj_frameless c ) ! ( rj_uses c 6 ) 6 1
    ? == ap 1 { ( rj_rm c 0 1 0 139 1 4 -1 0 ( rj_argsp c ) 0 ) } {}  // mov rcx,[rsp(+8)]
    : ~ i k 0
    ~ < k nres {
        : i o ( rj_u c r k )
        : i l ( rj_uloc c o )
        : i s ( rj_us c o )
        : i disp * k 8
        ? ( rj_isx l ) { ( rj_rm c 242 0 1 17 - l 16 ap -1 0 disp 0 ) } {  // movsd [ap+8k], x
            : ~ i vr ( rj_greg l )
            ? < vr 0 { ( rj_ldg c 0 l s 0 ) = vr 0 } {}
            ( rj_rm c 0 1 0 137 vr ap -1 0 disp 0 )  // mov [ap+8k], r
        }
        = k + k 1
    }
    ? > nres 0 { : i o0 ( rj_u c r 0 ) ( rj_ldg c 0 ( rj_uloc c o0 ) ( rj_us c o0 ) 0 ) } {}  // result 0 also in rax
    ( rj_restore_inv c )
    ( rj_epilogue c )
}

// ── lowering: the rest ──────────────────────────────────────────
@ rj_e_div Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i w ? >= op 105 1 0
    : i oa ( rj_u c r 0 )
    : i ob ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ( rj_ldg c 1 ( rj_uloc c ob ) ( rj_us c ob ) 0 )
    ( rj_ldg c 0 ( rj_uloc c oa ) ( rj_us c oa ) 0 )
    : b uns | | | == op 97 == op 99 == op 106 == op 108
    ? & == w 0 uns { ( rj_mov32 c 0 0 ) } {}  // the unsigned view of an i32
    ( rj_test_rr c w 1 1 )
    ( rj_jcc c 4 ( rj_stub_div0 c ) )
    ? uns {
        ( rj_rr c 0 0 0 49 2 2 0 )  // xor edx,edx
        ( rj_rex c w 0 0 1 0 ) ( rj_b c 247 ) ( rj_modrr c 6 1 )  // div rcx/ecx
        ? | == op 99 == op 108 { ( rj_mov_rr c 1 0 2 ) } {}  // the remainder
    } {
        ( rj_alu_ri c w 7 1 -1 )  // cmp rcx,-1
        : i ne ( rj_jcc_fwd c 5 )
        : ~ i skip -1
        ? | == op 96 == op 105 {  // MIN / -1 overflows
            ? == w 1 { ( rj_mov_ri c 2 -9223372036854775808 0 ) ( rj_alu_rr c 1 7 0 2 ) } {
                ( rj_alu_ri c 0 7 0 -2147483648 ) }
            ( rj_jcc c 4 ( rj_stub_iovf c ) )
        } {  // x rem -1 = 0
            ( rj_rr c 0 0 0 49 0 0 0 )  // xor eax,eax
            = skip ( rj_jmp_fwd c )
        }
        ( rj_land c ne )
        ( rj_rex c w 0 0 0 0 ) ( rj_b c 153 )  // cqo / cdq
        ( rj_rex c w 0 0 1 0 ) ( rj_b c 247 ) ( rj_modrr c 7 1 )  // idiv rcx/ecx
        ? | == op 98 == op 107 { ( rj_mov_rr c 1 0 2 ) } {}
        ? >= skip 0 { ( rj_land c skip ) } {}
    }
    ? & == w 0 ( rj_dcanon c od ) { ( rj_movsxd c 0 0 ) } {}
    ( rj_stg c ( rj_dloc c od ) ( rj_ds c od ) 0 )
}

@ rj_e_gget Rj c i r → v {
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i disp * ( rj_rw c r 2 ) 8
    : i dl ( rj_dloc c od )
    ? ( rj_isx dl ) { ( rj_rm c 242 0 1 16 - dl 16 9 -1 0 disp 0 ) ^ v } {}  // movsd x,[r9+8g]
    : i tr ? ( rj_isg dl ) dl 0
    ( rj_rm c 0 1 0 139 tr 9 -1 0 disp 0 )  // mov r,[r9+8g]
    ? != tr dl { ( rj_stg c dl ( rj_ds c od ) tr ) } {}
}

@ rj_e_gset Rj c i r → v {
    : i o ( rj_u c r 0 )
    : i l ( rj_uloc c o )
    : i disp * ( rj_rw c r 1 ) 8
    ? ( rj_isx l ) { ( rj_rm c 242 0 1 17 - l 16 9 -1 0 disp 0 ) ^ v } {}  // movsd [r9+8g],x
    : ~ i vr ( rj_greg l )
    ? < vr 0 { ( rj_ldg c 0 l ( rj_us c o ) 0 ) = vr 0 } {}
    ( rj_rm c 0 1 0 137 vr 9 -1 0 disp 0 )  // mov [r9+8g],r
}

@ rj_e_const Rj c i r → v {
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i dl ( rj_dloc c od )
    : i kq ( rj_rw c r 2 )
    ? ( rj_isg dl ) { ( rj_mov_ri c dl kq 0 ) ^ v } {}
    ? ( rj_isx dl ) {
        ? == kq 0 { ( rj_rr c 0 0 1 87 - dl 16 - dl 16 0 ) } { ( rj_mov_ri c 0 kq 0 ) ( rj_movq_xg c - dl 16 0 ) }
        ^ v
    } {}
    : i ds ( rj_ds c od )
    ? ( rj_fits32 kq ) { ( rj_rm c 0 1 0 199 0 3 -1 0 ( rj_home ds ) 0 ) ( rj_d c kq ) } {
        ( rj_mov_ri c 0 kq 0 ) ( rj_stf c 1 ds 0 ) }
}

@ rj_e_mov Rj c i r → v {
    : i o ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    ( rj_move c ( rj_dloc c od ) ( rj_ds c od ) ( rj_uloc c o ) ( rj_us c o ) )
}

// ── prologue, epilogue, stubs ───────────────────────────────────
@ rj_saved i k → i {  // push order of the callee-saved registers
    ? == k 0 { ^ 5 } {}
    ^ + 11 k  // r12..r15
}

@ rj_epilogue Rj c → v {
    : i used ( rj_get c ( rjs_used ) )
    ? ( rj_uses c 7 ) { ( rj_pop c 7 ) } {}  // the context, back in rdi for the caller
    ? ( rj_frameless c ) { ? ( rj_uses c 6 ) { ( rj_pop c 6 ) } {} } { ( rj_pop c 6 ) ( rj_pop c 3 ) }  // rsi, rbx
    : ~ i k 4
    ~ >= k 0 {
        : i l ( rj_saved k )
        ? != 0 & ( rj_shr used l ) 1 { ( rj_pop c l ) } {}
        = k - k 1
    }
    ( rj_b c 195 )  // ret
}

// one entry web's initial value: a parameter from the caller's window
// (arg0 in rdx when there is exactly one), anything else zero
@ rj_entry1 Rj c i wv → v {
    : i s ( vec_at [i] . c wslot wv )
    : i l ( vec_at [i] . c wloc wv )
    : i np ( rj_get c ( rjs_np ) )
    ? < s np {
        ? == np 1 {
            ? ( rj_isg l ) { ( rj_mov_rr c 1 l 2 ) } {
                ? ( rj_isx l ) { ( rj_movq_xg c - l 16 2 ) } { ( rj_stf c 1 s 2 ) } }
        } {
            : i disp * s 8
            ? ( rj_isg l ) { ( rj_rm c 0 1 0 139 l 6 -1 0 disp 0 ) } {  // mov r,[rsi+8s]
                ? ( rj_isx l ) { ( rj_rm c 242 0 1 16 - l 16 6 -1 0 disp 0 ) } {  // movsd x,[rsi+8s]
                    ( rj_rm c 0 1 0 139 0 6 -1 0 disp 0 ) ( rj_stf c 1 s 0 ) } }
        }
    } {
        ? ( rj_isg l ) { ( rj_rr c 0 0 0 49 l l 0 ) } {
            ? ( rj_isx l ) { ( rj_rr c 0 0 1 87 - l 16 - l 16 0 ) } {
                ( rj_rm c 0 1 0 199 0 3 -1 0 ( rj_home s ) 0 ) ( rj_d c 0 ) } }
    }
}

@ rj_prologue Rj c → v {
    : i np ( rj_get c ( rjs_np ) )
    // the driver entry: the invariant registers, then the 28-byte mark
    ( rj_b c 73 ) ( rj_b c 184 ) ( rj_q c ( rj_get c ( rjs_spcell ) ) )  // movabs r8, anchor
    ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 95 ) ( rj_b c 8 )  // mov r11,[rdi+8]
    ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 87 ) ( rj_b c 16 )  // mov r10,[rdi+16]
    ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 79 ) ( rj_b c 24 )  // mov r9,[rdi+24]
    ? == np 1 { ( rj_b c 72 ) ( rj_b c 139 ) ( rj_b c 22 ) } { ( rj_b c 15 ) ( rj_b c 31 ) ( rj_b c 0 ) }  // mov rdx,[rsi] / nop3
    ( rj_b c 73 ) ( rj_b c 139 ) ( rj_b c 8 )  // mov rcx,[r8]
    // the memory entry (+28); a register-argument function's is a wrapper:
    // window → argument registers, the fast entry, result → window, and
    // the invariants a memory-ABI caller relies on
    : b fast == 1 ( rj_get c ( rjs_fast ) )
    ? fast {
        : i nr ( rj_get c ( rjs_nr ) )
        : ~ i k 0
        ~ < k np {
            ? | != k 0 != np 1 { ( rj_rm c 0 1 0 139 ( rj_areg k ) 6 -1 0 * k 8 0 ) } {}  // mov A[k],[rsi+8k]
            = k + k 1
        }
        ( rj_b c 232 ) ( rj_d c 0 )  // call the fast entry
        ( vec_push [i] . c pat_at - ( rj_here c ) 4 ) ( vec_push [i] . c pat_rec ( rj_lab_fast c ) )
        ? == nr 1 { ( rj_rm c 0 1 0 137 0 6 -1 0 0 0 ) } {}  // mov [rsi],rax
        // rdi is the context again (the fast body gave it back)
        ( rj_b c 73 ) ( rj_b c 184 ) ( rj_q c ( rj_get c ( rjs_spcell ) ) )  // movabs r8, anchor
        ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 79 ) ( rj_b c 24 )  // mov r9,[rdi+24]
        ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 87 ) ( rj_b c 16 )  // mov r10,[rdi+16]
        ( rj_b c 195 )  // ret
        ( rj_align16 c )
        ( rj_set c ( rjs_fastoff ) ( rj_here c ) )
    } {}
    : i used ( rj_get c ( rjs_used ) )
    : ~ i k 0
    ~ < k 5 {
        : i l ( rj_saved k )
        ? != 0 & ( rj_shr used l ) 1 { ( rj_push c l ) } {}
        = k + k 1
    }
    ? ( rj_frameless c ) {
        ? ( rj_uses c 6 ) { ( rj_push c 6 ) } {}  // rsi only when a web takes it
        ? ( rj_uses c 7 ) { ( rj_push c 7 ) } {}
    } {
        ( rj_push c 3 ) ( rj_push c 6 )  // rbx, rsi (the args pointer, read back at RET)
        ? ( rj_uses c 7 ) { ( rj_push c 7 ) } {}  // the context, when rdi is handed out
        ( rj_mov_rr c 1 3 1 )  // mov rbx,rcx
        ( rj_frame_end c )
        ( rj_rm c 0 1 0 59 1 7 -1 0 64 0 )  // cmp rcx,[rdi+64] — the slab end (ctx[8])
        ( rj_jcc c 7 ( rj_stub_ovf c ) )  // ja
    }
    // a register-argument entry's parameters: one parallel copy out of the
    // argument registers (before anything else lands in them)
    ? fast {
        : ( Vec i ) dl ( vec_new [i] )
        : ( Vec i ) ds ( vec_new [i] )
        : ( Vec i ) sl ( vec_new [i] )
        : ( Vec i ) ss ( vec_new [i] )
        : i ne0 ( vec_len [i] . c entw )
        : ~ i q0 0
        ~ < q0 ne0 {
            : i wv ( vec_at [i] . c entw q0 )
            : i sp ( vec_at [i] . c wslot wv )
            ? & > ( vec_at [i] . c wuse wv ) 0 < sp np {
                ( vec_push [i] dl ( vec_at [i] . c wloc wv ) ) ( vec_push [i] ds sp )
                ( vec_push [i] sl ( rj_areg sp ) ) ( vec_push [i] ss -1 )
            } {}
            = q0 + q0 1
        }
        ( rj_pmove c dl ds sl ss )
        // r9 = the globals base (r9 may have carried an argument)
        ? == 1 ( rj_get c ( rjs_glob ) ) {
            ? ( rj_uses c 7 ) { ( rj_rm c 0 1 0 139 9 4 -1 0 0 0 ) ( rj_rm c 0 1 0 139 9 9 -1 0 24 0 ) } {  // mov r9,[rsp]; mov r9,[r9+24]
                ( rj_reglob c ) }
        } {}
    } {}
    // entry values; whatever took rsi goes last — rsi is the window
    // pointer — and with one parameter, its web goes first: it arrives in
    // rdx, which another entry value may be about to take
    : i ne ( vec_len [i] . c entw )
    : ~ i q 0
    ? fast {  // the parameters are placed: zero the live-in locals
        ~ < q ne {
            : i wv ( vec_at [i] . c entw q )
            ? & > ( vec_at [i] . c wuse wv ) 0 >= ( vec_at [i] . c wslot wv ) np { ( rj_entry1 c wv ) } {}
            = q + q 1
        }
        ^ v
    } {}
    ? == np 1 {
        ~ < q ne {
            : i wv ( vec_at [i] . c entw q )
            ? & & > ( vec_at [i] . c wuse wv ) 0 == ( vec_at [i] . c wslot wv ) 0 != ( vec_at [i] . c wloc wv ) 6 { ( rj_entry1 c wv ) } {}
            = q + q 1
        }
        = q 0
    } {}
    ~ < q ne {
        : i wv ( vec_at [i] . c entw q )
        ? & & > ( vec_at [i] . c wuse wv ) 0 != ( vec_at [i] . c wloc wv ) 6 | != np 1 != ( vec_at [i] . c wslot wv ) 0 { ( rj_entry1 c wv ) } {}
        = q + q 1
    }
    = q 0
    ~ < q ne {
        : i wv ( vec_at [i] . c entw q )
        ? & > ( vec_at [i] . c wuse wv ) 0 == ( vec_at [i] . c wloc wv ) 6 { ( rj_entry1 c wv ) } {}
        = q + q 1
    }
}

@ rj_stubs Rj c → v {
    : i trapfn ( rj_get c ( rjs_trapfn ) )
    ( vec_push [i] . c lab ( rj_here c ) )  // n: out of bounds → status 1
    ( rj_b c 191 ) ( rj_d c 1 ) ( rj_jmp c ( rj_stub_gate c ) )
    ( vec_push [i] . c lab ( rj_here c ) )  // n+1: divide by zero → status 4
    ( rj_b c 191 ) ( rj_d c 4 ) ( rj_jmp c ( rj_stub_gate c ) )
    ( vec_push [i] . c lab ( rj_here c ) )  // n+2: the longjmp gate
    ( rj_b c 72 ) ( rj_b c 131 ) ( rj_b c 228 ) ( rj_b c 240 )  // and rsp,-16
    ( rj_b c 72 ) ( rj_b c 184 ) ( rj_q c trapfn )  // movabs rax, trap entry
    ( rj_b c 255 ) ( rj_b c 208 )  // call rax (never returns)
    // n+3: the slab is full — this call runs on the interpreter (kind 20)
    // with the raw args pointer as its frame base; nothing was allocated
    // and no callee-saved register touched, so the entry pushes unwind
    ( vec_push [i] . c lab ( rj_here c ) )
    ? == 1 ( rj_get c ( rjs_fast ) ) {  // register arguments → the window rsi still points at
        : i np ( rj_get c ( rjs_np ) )
        : ~ i k 0
        ~ < k np { ( rj_rm c 0 1 0 137 ( rj_areg k ) 6 -1 0 * k 8 0 ) = k + k 1 }
    } {}
    ( rj_rm c 0 1 0 139 3 4 -1 0 ( rj_argsp c ) 0 )  // mov rbx,[rsp(+8)] — the args pointer
    ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 32 ) ( rj_d c ( rj_get c ( rjs_fidx ) ) )  // mov qword[rdi+32], fidx
    ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 40 ) ( rj_d c 0 )  // mov qword[rdi+40], 0
    ( rj_callout c 20 )
    ( rj_b c 72 ) ( rj_b c 139 ) ( rj_b c 3 )  // mov rax,[rbx] — result 0 for a direct caller
    ( rj_epilogue c )
    ( vec_push [i] . c lab ( rj_here c ) )  // n+4: signed-division overflow → status 10
    ( rj_b c 191 ) ( rj_d c 10 ) ( rj_jmp c ( rj_stub_gate c ) )
    ( vec_push [i] . c lab ( rj_here c ) )  // n+5: NaN to integer → status 12
    ( rj_b c 191 ) ( rj_d c 12 ) ( rj_jmp c ( rj_stub_gate c ) )
    ( vec_push [i] . c lab 28 )  // n+6: the memory entry
    ( vec_push [i] . c lab ? > ( rj_get c ( rjs_fastoff ) ) 0 ( rj_get c ( rjs_fastoff ) ) 28 )  // n+7: the fast entry
    // one stub per direct call site, the target of its rel32 until the
    // callee is linked; [rsp] holds the site's return address. A site's
    // stub only spills its register arguments (a fast site) and names the
    // callee and the window; one shared tail per function either
    // tail-jumps into the callee's memory entry or runs the call on the
    // bridge and returns with result 0 in rax, exactly as the callee would.
    : i nimp ( rj_get c ( rjs_nimp ) )
    : i ncs ( vec_len [i] . c cs_off )
    : ( Vec i ) tojoin ( vec_new [i] )
    : ~ i k 0
    ~ < k ncs {
        ( rj_patch32 c ( vec_at [i] . c cs_off k ) ( rj_here c ) )
        : i ab ( vec_at [i] . c cs_ab k )
        ? == 1 ( vec_at [i] . c cs_kind k ) {  // register arguments → the caller's window
            : i snp ( vec_at [i] . c cs_np k )
            : ~ i j 0
            ~ < j snp { ( rj_stf c 1 + ab j ( rj_areg j ) ) = j + j 1 }
        } {}
        ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 40 ) ( rj_d c ab )  // mov qword[rdi+40], argbase
        ( rj_b c 184 ) ( rj_d c ( vec_at [i] . c cs_fx k ) )  // mov eax, fidx
        ( vec_push [i] tojoin ( rj_jmp_fwd c ) )
        = k + k 1
    }
    ? > ncs 0 {
        : i nj ( vec_len [i] tojoin )
        = k 0
        ~ < k nj { ( rj_land c ( vec_at [i] tojoin k ) ) = k + k 1 }
        ( rj_b c 72 ) ( rj_b c 137 ) ( rj_b c 71 ) ( rj_b c 32 )  // mov [rdi+32],rax — the callee, for the bridge
        ( rj_b c 73 ) ( rj_b c 184 ) ( rj_q c ( rj_get c ( rjs_spcell ) ) )  // movabs r8, anchor
        ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 79 ) ( rj_b c 24 )  // mov r9,[rdi+24]
        ( rj_b c 76 ) ( rj_b c 139 ) ( rj_b c 87 ) ( rj_b c 16 )  // mov r10,[rdi+16]
        ( rj_rm c 0 1 0 139 0 8 0 3 - 16 * nimp 8 0 )  // mov rax,[r8+rax*8+16-8*nimp] — its memory entry
        ( rj_test_rr c 1 0 0 )
        : i jz ( rj_jcc_fwd c 4 )
        ( rj_b c 255 ) ( rj_b c 224 )  // jmp rax
        ( rj_land c jz )
        ( rj_b c 73 ) ( rj_b c 137 ) ( rj_b c 8 )  // mov [r8],rcx — the frame end, for the driver
        ( rj_callout c 16 )
        ( rj_rm c 0 1 0 139 0 7 -1 0 40 0 )  // mov rax,[rdi+40] — the argbase
        ( rj_rm c 0 1 0 139 0 3 0 3 0 0 )  // mov rax,[rbx+rax*8] — result 0
        ( rj_b c 195 )  // ret
    } {}
}

// multi-byte NOPs up to the next 16-byte boundary
@ rj_align16 Rj c → v {
    : ~ i pad & - 16 & ( rj_here c ) 15 15
    ~ > pad 0 {
        : i k ? > pad 8 8 pad
        ? == k 1 { ( rj_b c 144 ) } {}
        ? == k 2 { ( rj_b c 102 ) ( rj_b c 144 ) } {}
        ? == k 3 { ( rj_b c 15 ) ( rj_b c 31 ) ( rj_b c 0 ) } {}
        ? == k 4 { ( rj_b c 15 ) ( rj_b c 31 ) ( rj_b c 64 ) ( rj_b c 0 ) } {}
        ? == k 5 { ( rj_b c 15 ) ( rj_b c 31 ) ( rj_b c 68 ) ( rj_b c 0 ) ( rj_b c 0 ) } {}
        ? == k 6 { ( rj_b c 102 ) ( rj_b c 15 ) ( rj_b c 31 ) ( rj_b c 68 ) ( rj_b c 0 ) ( rj_b c 0 ) } {}
        ? == k 7 { ( rj_b c 15 ) ( rj_b c 31 ) ( rj_b c 128 ) ( rj_d c 0 ) } {}
        ? == k 8 { ( rj_b c 15 ) ( rj_b c 31 ) ( rj_b c 132 ) ( rj_b c 0 ) ( rj_d c 0 ) } {}
        = pad - pad k
    }
}

// ── the record walk ─────────────────────────────────────────────
@ rj_e_rec Rj c i r → v {
    : i op ( rj_rw c r 0 )
    ? != op 46 { ( rj_set c ( rjs_fsel ) 0 ) ( rj_set c ( rjs_fweb ) -1 ) } {}  // flags feed only the fused SELs
    ? | == op 0 == op 9 { ( rj_e_bin c r 0 ? == op 0 1 0 ) ^ v } {}
    ? | == op 1 == op 181 { ( rj_e_mul c r ? == op 1 1 0 ) ^ v } {}
    ? | == op 2 == op 11 { ( rj_e_bin c r 4 ? == op 2 1 0 ) ^ v } {}
    ? | == op 4 == op 180 { ( rj_e_bin c r 6 ? == op 4 1 0 ) ^ v } {}
    ? | == op 5 == op 185 { ( rj_e_bin c r 5 ? == op 5 1 0 ) ^ v } {}
    ? | == op 7 == op 184 { ( rj_e_bin c r 1 ? == op 7 1 0 ) ^ v } {}
    ? | == op 3 == op 12 { ( rj_e_shift c r 5 ? == op 3 1 0 ) ^ v } {}
    ? | == op 6 == op 179 { ( rj_e_shift c r 7 ? == op 6 1 0 ) ^ v } {}
    ? | == op 8 == op 10 { ( rj_e_shift c r 4 ? == op 8 1 0 ) ^ v } {}
    ? | == op 109 == op 100 { ( rj_e_shift c r 0 ? == op 109 1 0 ) ^ v } {}
    ? | == op 110 == op 101 { ( rj_e_shift c r 1 ? == op 110 1 0 ) ^ v } {}
    ? ( rj_isfused op ) { ( rj_e_fused c r ) ^ v } {}
    ? & >= op 56 <= op 75 { ( rj_e_cmp c r ) ^ v } {}
    ? | == op 43 == op 44 { ( rj_e_eqz c r ? == op 44 1 0 ) ^ v } {}
    ? == op 46 { ( rj_e_sel c r ) ^ v } {}
    ? | | | == op 36 == op 37 & >= op 157 <= op 161 == op 175 { ( rj_e_ext c r ) ^ v } {}
    ? | == op 47 & >= op 153 <= op 156 { ( rj_e_mov c r ) ^ v } {}
    ? == op 51 { ( rj_e_const c r ) ^ v } {}
    ? == op 52 { ( rj_e_gget c r ) ^ v } {}
    ? == op 53 { ( rj_e_gset c r ) ^ v } {}
    : i mk ( rj_memkind op )
    ? >= mk 0 { ? == 0 & mk 1 { ( rj_e_load c r ) } { ( rj_e_store c r ) } ^ v } {}
    ? & >= op 205 <= op 208 { ( rj_e_loadshl c r ) ^ v } {}
    ? | == op 211 == op 212 { ( rj_e_loadop c r ) ^ v } {}
    ? == op 49 { ( rj_goto c r ( rj_tgtrec ( rj_rw c r 1 ) ) ) ^ v } {}
    ? | == op 54 == op 48 {
        : i o ( rj_u c r 0 )
        ( rj_testop c ? | == op 54 == 0 ( rj_rw c r 3 ) 0 1 ( rj_uloc c o ) ( rj_us c o ) )  // i32 conditions; an IFZ fused from i64.eqz says so in C
        ( rj_jcc c ? == op 54 5 4 ( rj_tgtrec ( rj_rw c r 1 ) ) )
        ^ v
    } {}
    ? == op 45 { ( rj_e_brifc c r ) ^ v } {}
    ? | == op 38 == op 177 { ( rj_e_addbr c r ) ^ v } {}
    ? == op 167 { ( rj_e_brm c r ) ^ v } {}
    ? == op 168 { ( rj_e_brifm c r ) ^ v } {}
    ? == op 169 { ( rj_e_brtbl c r ) ^ v } {}
    ? == op 55 { ( rj_e_ret c r ) ^ v } {}
    ? == op 172 { ( rj_b c 191 ) ( rj_d c 3 ) ( rj_jmp c ( rj_stub_gate c ) ) ^ v } {}  // unreachable → status 3
    ? | == op 50 == op 210 { ( rj_e_call c r ) ^ v } {}
    ? | & >= op 96 <= op 99 & >= op 105 <= op 108 { ( rj_e_div c r ) ^ v } {}
    ? == op 93 { ( rj_e_clz c r ) ^ v } {}
    ? ( rj_isfbin op ) { ( rj_e_fbin c r ) ^ v } {}
    ? ( rj_isfcmp op ) { ( rj_e_fcmp c r ) ^ v } {}
    ? & ( rj_isfconv op ) | | & >= op 143 <= op 145 & >= op 147 <= op 150 == op 152 { ( rj_e_fconv c r ) ^ v } {}
    ? | == op 131 == op 117 { ( rj_e_fsqrt c r ) ^ v } {}
    ? | == op 125 == op 126 { ( rj_e_fsign c r ) ^ v } {}
    ? & >= op 127 <= op 130 { ( rj_e_fround c r ) ^ v } {}
    ? & >= op 194 <= op 201 { ( rj_e_ffused c r ) ^ v } {}
    ? | | | | == op 94 == op 95 == op 102 == op 103 == op 104 { ( rj_e_bits c r ) ^ v } {}
    ? == op 166 { ( rj_e_isnull c r ) ^ v } {}
    ? | == op 111 == op 112 { ( rj_e_f32sign c r ) ^ v } {}
    ? & >= op 113 <= op 116 { ( rj_e_f32round c r ) ^ v } {}
    ? ( rj_isfminmax op ) { ( rj_e_fminmax c r ) ^ v } {}
    ? & >= op 135 <= op 142 { ( rj_e_trunc c r ) ^ v } {}
    ? | == op 146 == op 151 { ( rj_e_cvtu64 c r ) ^ v } {}
    ? == op 162 { ( rj_e_memsize c r ) ^ v } {}
    ? == op 163 { ( rj_e_memgrow c r ) ^ v } {}
    ? == op 170 { ( rj_e_callind c r ) ^ v } {}
    ? == op 171 { ( rj_e_fcb c r ) ^ v } {}
    ( rj_fail c 9 )
}

@ rj_emit Rj c → v {
    : i n ( rj_get c ( rjs_n ) )
    ( rj_set c ( rjs_fweb ) -1 ) ( rj_set c ( rjs_fsel ) 0 )
    ( rj_prologue c )
    : ~ i r 0
    ~ < r n {
        : i tg ( vec_at [i] . c tgt r )
        ? == tg 2 { ( rj_align16 c ) } {}  // a loop head: its speed must not depend on where code ended
        ( vec_push [i] . c lab ( rj_here c ) )
        ? != tg 0 { ( rj_set c ( rjs_fsel ) 0 ) ( rj_set c ( rjs_fweb ) -1 ) } {}
        ( rj_e_rec c r )
        = r + r 1
    }
    ( rj_stubs c )
    // the literal pool, 8-aligned, after everything that executes
    : i nlit ( vec_len [i] . c litv )
    ? > nlit 0 {
        ~ != 0 & ( rj_here c ) 7 { ( rj_b c 204 ) }  // int3 padding
        : i pool ( rj_here c )
        : ~ i q 0
        ~ < q nlit { ( rj_q c ( vec_at [i] . c litv q ) ) = q + q 1 }
        : i nsite ( vec_len [i] . c lsite )
        = q 0
        ~ < q nsite {
            ( rj_patch32 c ( vec_at [i] . c lsite q ) + pool * 8 ( vec_at [i] . c lidx q ) )
            = q + q 1
        }
    } {}
    // rel32s, now that every label is known
    : i np ( vec_len [i] . c pat_at )
    : ~ i k 0
    ~ < k np {
        ( rj_patch32 c ( vec_at [i] . c pat_at k ) ( vec_at [i] . c lab ( vec_at [i] . c pat_rec k ) ) )
        = k + k 1
    }
    : i nr ( vec_len [i] . c ptr_off )
    = k 0
    ~ < k nr {
        ( vec_push [i] . c pta_off ( vec_at [i] . c ptr_off k ) )
        ( vec_push [i] . c pta_stub ( vec_at [i] . c lab ( vec_at [i] . c ptr_rec k ) ) )
        = k + k 1
    }
}

// ── entry ───────────────────────────────────────────────────────
@ rj_new ( Vec i ) code ( Vec i ) aux ( Vec i ) kv ( Vec i ) ltype i n i nl i ns i np i nr i sb → Rj {
    : ( Vec i ) st ( vec_new [i] )
    : ~ i k 0
    ~ < k ( rjs_nst ) { ( vec_push [i] st 0 ) = k + k 1 }
    ( vec_put [i] st ( rjs_n ) n ) ( vec_put [i] st ( rjs_nl ) nl ) ( vec_put [i] st ( rjs_ns ) ns )
    ( vec_put [i] st ( rjs_np ) np ) ( vec_put [i] st ( rjs_nr ) nr ) ( vec_put [i] st ( rjs_sb ) sb )
    ( vec_put [i] st ( rjs_fweb ) -1 )
    ^ @ Rj {
        ( vec_new [u] ) st ( vec_clone [i] code ) ( vec_clone [i] aux ) ( vec_clone [i] kv ) ( vec_clone [i] ltype )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
    }
}

// Compile the context's records. rsig: per record, a call's callee
// nparams*65536 + nresults (-1 for every other record). True when `buf` holds the
// function — record and stub labels in `lab`, absolute jump-table entries in
// pta_off/pta_stub (page-relative) — false to leave it to the template tier
// (`rjs_fail` says why).
@ rj_compile Rj c ( Vec i ) rsig i nimp i spcell i trapfn i cofn i coenv i fidx i sigoff i tbloff → b {
    ( rj_set c ( rjs_sigoff ) sigoff ) ( rj_set c ( rjs_tbloff ) tbloff )
    ( rj_set c ( rjs_nimp ) nimp ) ( rj_set c ( rjs_spcell ) spcell ) ( rj_set c ( rjs_trapfn ) trapfn )
    ( rj_set c ( rjs_cofn ) cofn ) ( rj_set c ( rjs_coenv ) coenv ) ( rj_set c ( rjs_fidx ) fidx )
    : i n ( rj_get c ( rjs_n ) )
    ? == n 0 { ( rj_fail c 1 ) ^ F } {}
    : ~ i forbid 0
    : ~ i r 0
    ~ < r n {
        : i op ( rj_rw c r 0 )
        ? ! ( rj_op_ok op ) { ( rj_fail c + 1000 op ) ^ F } {}
        // every constant memory offset must fit a disp32 together with the width
        ? | | >= ( rj_memkind op ) 0 & >= op 205 <= op 208 | == op 211 == op 212 {
            : i moff ( rj_rw c r 3 )
            ? | < moff 0 > moff 2147483639 { ( rj_fail c 10 ) ^ F } {}
        } {}
        ? | == op 52 == op 53 { = forbid | forbid 512 ( rj_set c ( rjs_glob ) 1 ) } {}  // r9 is the globals base
        ( vec_push [i] . c rsig ? < r ( vec_len [i] rsig ) ( vec_at [i] rsig r ) -1 )
        = r + r 1
    }
    ( rj_set c ( rjs_forbid ) forbid )
    ( rj_set c ( rjs_fast ) ? & <= ( rj_get c ( rjs_np ) ) 5 <= ( rj_get c ( rjs_nr ) ) 1 1 0 )
    = r 0
    ~ < r n {
        ( vec_push [i] . c uoff ( vec_len [i] . c uslot ) ) ( vec_push [i] . c doff ( vec_len [i] . c dslot ) )
        ( rj_decode c r )
        = r + r 1
    }
    ( vec_push [i] . c uoff ( vec_len [i] . c uslot ) ) ( vec_push [i] . c doff ( vec_len [i] . c dslot ) )
    ? ( rj_failed c ) { ^ F } {}
    ( rj_blocks c )
    ? ( rj_failed c ) { ^ F } {}
    ( rj_live c )
    ( rj_webs c )
    ? ( rj_failed c ) { ^ F } {}
    ( rj_canon c )
    ( rj_depths c )
    ( rj_facts c )
    ( rj_sens c )
    ( rj_alloc c )
    ( rj_emit c )
    ^ ! ( rj_failed c )
}

// ── lowering: floats (scalar SSE2) ──────────────────────────────
// An f32 web keeps its value in the low 32 bits of an xmm register with
// bits 32..127 zero — the same zero-extended pattern a slot holds — so a
// 64-bit move between xmm, GPR and memory never needs to know the width.
// pf: 242 = the sd forms, 243 = ss.

// x op= operand (opc: 88 add, 89 mul, 92 sub, 94 div, 81 sqrt)
@ rj_fsrc Rj c i pf i opc i x i loc i s → v {
    ? ( rj_isx loc ) { ( rj_rr c pf 0 1 opc x - loc 16 0 ) ^ v } {}
    ? == loc ( rjl_mem ) { ( rj_rm c pf 0 1 opc x 3 -1 0 ( rj_home s ) 0 ) ^ v } {}
    ? == loc ( rjl_imm ) { ( rj_ripop c pf 0 1 opc x ( rj_kval c s ) ) ^ v } {}
    ( rj_movq_xg c 1 loc ) ( rj_rr c pf 0 1 opc x 1 0 )  // a GPR holding the bits: through xmm1
}

@ rj_fopc i op → i {  // record → the SSE opcode byte
    : i q ? <= op 42 - op 39 - op 118
    ? <= op 42 { ? == q 0 { ^ 89 } {} ? == q 1 { ^ 88 } {} ? == q 2 { ^ 92 } {} ^ 94 } {}  // f64: mul add sub div
    ? == q 0 { ^ 88 } {}  // f32: add sub mul div
    ? == q 1 { ^ 92 } {}
    ? == q 2 { ^ 89 } {}
    ^ 94
}

// dst = a op b into dst's place
@ rj_fbin3 Rj c i pf i opc i al i as i bl i bs i dl i ds → v {
    : b comm | == opc 88 == opc 89
    ? ( rj_isx dl ) {
        : i x - dl 16
        ? == dl al { ( rj_fsrc c pf opc x bl bs ) ^ v } {}
        ? == dl bl {
            ? comm { ( rj_fsrc c pf opc x al as ) ^ v } {}
            ( rj_ldx c 0 al as ) ( rj_fsrc c pf opc 0 bl bs ) ( rj_movx c x 0 ) ^ v
        } {}
        ( rj_ldx c x al as ) ( rj_fsrc c pf opc x bl bs ) ^ v
    } {}
    ( rj_ldx c 0 al as ) ( rj_fsrc c pf opc 0 bl bs ) ( rj_stx c dl ds 0 )
}

@ rj_e_fbin Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i ob ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    ( rj_fbin3 c ? <= op 42 242 243 ( rj_fopc op ) ( rj_uloc c oa ) ( rj_us c oa ) ( rj_uloc c ob ) ( rj_us c ob ) ( rj_dloc c od ) ( rj_ds c od ) )
}

// a one-operand float result computed in place: x ← a (a full-register
// write, which also breaks the false dependency the scalar forms carry on
// their destination's upper bits), then `body` runs on x
@ rj_fun_dst Rj c i od → i {  // the xmm the result is built in
    : i dl ( rj_dloc c od )
    ^ ? ( rj_isx dl ) - dl 16 0
}

@ rj_fun_fin Rj c i od i x → v {
    : i dl ( rj_dloc c od )
    ? != + x 16 dl { ( rj_stx c dl ( rj_ds c od ) x ) } {}
}

@ rj_e_fsqrt Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i x ( rj_fun_dst c od )
    ( rj_ldx c x ( rj_uloc c oa ) ( rj_us c oa ) )
    ( rj_rr c ? == op 131 242 243 0 1 81 x x 0 )  // sqrtsd / sqrtss x,x
    ( rj_fun_fin c od x )
}

// f64.abs / f64.neg: clear / flip the sign bit, on whichever side the web lives
@ rj_e_fsign Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i dl ( rj_dloc c od )
    ? ( rj_isx dl ) {
        : i x - dl 16
        ( rj_ldx c x ( rj_uloc c oa ) ( rj_us c oa ) )
        ( rj_rr c 102 0 1 118 1 1 0 )  // pcmpeqd xmm1,xmm1
        ( rj_rr c 102 0 1 115 ? == op 125 2 6 1 0 ) ( rj_b c ? == op 125 1 63 )  // psrlq 1 / psllq 63
        ( rj_rr c 102 0 1 ? == op 125 84 87 x 1 0 )  // andpd / xorpd
        ^ v
    } {}
    : i tr ? ( rj_isg dl ) dl 0
    ( rj_ldg c tr ( rj_uloc c oa ) ( rj_us c oa ) 0 )
    ( rj_rr c 0 1 1 186 ? == op 125 6 7 tr 0 ) ( rj_b c 63 )  // btr / btc r,63
    ? != tr dl { ( rj_stg c dl ( rj_ds c od ) tr ) } {}
}

// f64 ceil / floor / trunc / nearest: roundsd (SSE4.1)
@ rj_e_fround Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i x ( rj_fun_dst c od )
    ( rj_ldx c x ( rj_uloc c oa ) ( rj_us c oa ) )
    : i mode ? == op 127 10 ? == op 128 9 ? == op 129 11 8  // ceil floor trunc nearest, inexact suppressed
    ( rj_b c 102 ) ( rj_rex c 0 x 0 x 0 ) ( rj_b c 15 ) ( rj_b c 58 ) ( rj_b c 11 ) ( rj_modrr c x x ) ( rj_b c mode )  // roundsd x,x,mode
    ( rj_fun_fin c od x )
}

// ucomisd/ucomiss a, b with a in an xmm register
@ rj_fcmp1 Rj c i pf i al i as i bl i bs → v {
    : ~ i xa 0
    ? ( rj_isx al ) { = xa - al 16 } { ( rj_ldx c 0 al as ) }
    : i p66 ? == pf 242 102 0
    ? ( rj_isx bl ) { ( rj_rr c p66 0 1 46 xa - bl 16 0 ) ^ v } {}
    ? == bl ( rjl_mem ) { ( rj_rm c p66 0 1 46 xa 3 -1 0 ( rj_home bs ) 0 ) ^ v } {}
    ? == bl ( rjl_imm ) { ( rj_ripop c p66 0 1 46 xa ( rj_kval c bs ) ) ^ v } {}
    ( rj_movq_xg c 1 bl ) ( rj_rr c p66 0 1 46 xa 1 0 )
}

@ rj_e_fcmp Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i ob ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i pf ? >= op 87 242 243
    : i q - op ? >= op 87 87 81  // eq ne lt gt le ge
    : i al ( rj_uloc c oa )
    : i as ( rj_us c oa )
    : i bl ( rj_uloc c ob )
    : i bs ( rj_us c ob )
    : i dl ( rj_dloc c od )
    ? | == q 2 == q 4 { ( rj_fcmp1 c pf bl bs al as ) } { ( rj_fcmp1 c pf al as bl bs ) }  // lt/le test b > a, b >= a
    ? | == q 0 == q 1 {  // unordered: eq is ZF & !PF, ne is !ZF | PF
        ( rj_setcc c ? == q 0 4 5 0 ) ( rj_setcc c ? == q 0 11 10 1 )
        ( rj_rr c 0 0 0 ? == q 0 32 8 1 0 1 ) ( rj_movzx8 c 0 0 )  // and/or al,cl
        ( rj_stg c dl ( rj_ds c od ) 0 )
        ^ v
    } {}
    ( rj_setbool c ? | == q 2 == q 3 7 3 dl ( rj_ds c od ) 0 )  // seta / setae: CF and ZF clear on unordered fail
}

// int → float and float ↔ float conversions
@ rj_e_fconv Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i al ( rj_uloc c oa )
    : i as ( rj_us c oa )
    : i x ( rj_fun_dst c od )
    ? | == op 152 == op 147 {  // promote (cvtss2sd) / demote (cvtsd2ss)
        : ~ i xs 1
        ? ( rj_isx al ) { = xs - al 16 } { ( rj_ldx c 1 al as ) }
        ( rj_rr c 0 0 1 87 x x 0 )  // xorps x,x — the f32 result's upper bits must be zero
        ( rj_rr c ? == op 152 243 242 0 1 90 x xs 0 )
        ( rj_fun_fin c od x )
        ^ v
    } {}
    // from an integer: 148/143 i32_s, 149/144 i32_u, 150/145 i64_s
    : b f32 <= op 145
    : i k ? f32 - op 143 - op 148
    ( rj_ldg c 0 al as 0 )
    ? == k 1 { ( rj_mov32 c 0 0 ) } {}  // u32: zero-extend, then convert as i64
    ( rj_rr c 0 0 1 87 x x 0 )  // xorps x,x
    ( rj_rr c ? f32 243 242 ? == k 0 0 1 1 42 x 0 0 )  // cvtsi2sd/ss x, eax/rax
    ( rj_fun_fin c od x )
}

// the fused f64 records
@ rj_e_ffused Rj c i r → v {
    : i op ( rj_rw c r 0 )
    ? == op 197 {  // ADDSTOREF64: mem[a + off] = b + c
        : i oa ( rj_u c r 0 )
        : i ob ( rj_u c r 1 )
        : i oc ( rj_u c r 2 )
        ( rj_ldx c 0 ( rj_uloc c ob ) ( rj_us c ob ) )
        ( rj_fsrc c 242 88 0 ( rj_uloc c oc ) ( rj_us c oc ) )
        ( rj_addr c ( rj_uloc c oa ) ( rj_us c oa ) 0 0 0 )
        ( rj_mrm c 242 0 1 17 0 ( rj_rw c r 4 ) 0 )  // movsd [r11+rax+off],xmm0
        ^ v
    } {}
    : i od ( rj_dd c r 0 )
    : i dl ( rj_dloc c od )
    : i ds ( rj_ds c od )
    ? | | == op 194 == op 195 == op 196 {  // mem[b + off] op x
        : i ob ( rj_u c r 0 )
        : i ox ( rj_u c r 1 )
        : i xl ( rj_uloc c ox )
        : i xs ( rj_us c ox )
        ( rj_addr c ( rj_uloc c ob ) ( rj_us c ob ) 0 0 0 )
        : i off ( rj_rw c r 3 )
        : i opc ? == op 194 89 ? == op 195 88 92
        ? & ( rj_isx dl ) == dl xl {  // dst holds x: the load is the memory operand
            ( rj_mrm c 242 0 1 opc - dl 16 off 0 ) ^ v
        } {}
        : i x ? & ( rj_isx dl ) != dl xl - dl 16 0
        ? == op 196 {  // x - mem
            ( rj_ldx c x xl xs ) ( rj_mrm c 242 0 1 92 x off 0 )
        } {
            ( rj_mrm c 242 0 1 16 x off 0 )  // movsd x,[mem]
            ( rj_fsrc c 242 opc x xl xs )
        }
        ? != + x 16 dl { ( rj_stx c dl ds x ) } {}
        ^ v
    } {}
    // 198 (s1*s2)+x, 199 (s1*s2)-x, 200 x-(s1*s2), 201 (s1-s2)*x
    : i o1 ( rj_u c r 0 )
    : i o2 ( rj_u c r 1 )
    : i o3 ( rj_u c r 2 )
    : i l1 ( rj_uloc c o1 )
    : i l2 ( rj_uloc c o2 )
    : i l3 ( rj_uloc c o3 )
    : i s3 ( rj_us c o3 )
    : i op1 ? == op 201 92 89
    : i op2 ? == op 198 88 ? == op 201 89 92
    ? == op 200 {  // t = s1*s2 in xmm0; dst = x - t
        ( rj_ldx c 0 l1 ( rj_us c o1 ) ) ( rj_fsrc c 242 89 0 l2 ( rj_us c o2 ) )
        ? & ( rj_isx dl ) == dl l3 { ( rj_rr c 242 0 1 92 - dl 16 0 0 ) ^ v } {}
        ( rj_ldx c 1 l3 s3 ) ( rj_rr c 242 0 1 92 1 0 0 ) ( rj_stx c dl ds 17 )
        ^ v
    } {}
    ? & & ( rj_isx dl ) == dl l3 | == op2 88 == op2 89 {  // dst holds x and op2 commutes
        ( rj_ldx c 0 l1 ( rj_us c o1 ) ) ( rj_fsrc c 242 op1 0 l2 ( rj_us c o2 ) )
        ( rj_rr c 242 0 1 op2 - dl 16 0 0 )
        ^ v
    } {}
    : i x ? & & ( rj_isx dl ) != dl l2 != dl l3 - dl 16 0
    ( rj_ldx c x l1 ( rj_us c o1 ) )
    ( rj_fsrc c 242 op1 x l2 ( rj_us c o2 ) )
    ( rj_fsrc c 242 op2 x l3 s3 )
    ? != + x 16 dl { ( rj_stx c dl ds x ) } {}
}

// ── lowering: the remaining integer unaries ─────────────────────
// ctz / popcnt / clz on 32 or 64 bits; bsf/bsr + cmov, popcnt (POPCNT)
@ rj_e_bits Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i w ? >= op 102 1 0
    ( rj_ldg c 0 ( rj_uloc c oa ) ( rj_us c oa ) 0 )
    ? | == op 95 == op 104 {  // popcnt rax,rax / eax,eax
        ( rj_rr c 243 w 1 184 0 0 0 )
    } {
        ? == op 102 {  // i64.clz: 63 - bsr, 64 for zero
            ( rj_rr c 0 1 1 189 1 0 0 ) ( rj_mov_ri c 2 -1 0 ) ( rj_cmov_rr c 1 4 1 2 )  // bsr rcx,rax; mov rdx,-1; cmovz rcx,rdx
            ( rj_mov_ri c 0 63 0 ) ( rj_alu_rr c 1 5 0 1 )  // mov eax,63; sub rax,rcx
        } {  // ctz: bsf, the width for zero
            ( rj_rr c 0 w 1 188 1 0 0 ) ( rj_mov_ri c 2 ? == w 1 64 32 0 ) ( rj_cmov_rr c 1 4 1 2 )  // bsf; mov edx,W; cmovz rcx,rdx
            ( rj_mov_rr c 1 0 1 )
        }
    }
    ( rj_stg c ( rj_dloc c od ) ( rj_ds c od ) 0 )
}

@ rj_e_isnull Rj c i r → v {  // ref.is_null: a null reference is -1
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i al ( rj_uloc c oa )
    ( rj_ldg c 0 al ( rj_us c oa ) 0 )
    ( rj_alu_ri c 1 7 0 -1 )  // cmp rax,-1
    ( rj_setbool c 4 ( rj_dloc c od ) ( rj_ds c od ) 0 )
}

// ── lowering: f32 sign / rounding, min / max / copysign ─────────
@ rj_e_f32sign Rj c i r → v {  // abs / neg on the zero-extended bits, in eax
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    ( rj_ldg c 0 ( rj_uloc c oa ) ( rj_us c oa ) 0 )
    ? == op 111 { ( rj_alu_ri c 0 4 0 2147483647 ) } { ( rj_alu_ri c 0 6 0 -2147483648 ) }  // and / xor eax (32-bit ops zero-extend)
    ( rj_stg c ( rj_dloc c od ) ( rj_ds c od ) 0 )
}

@ rj_e_f32round Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i x ( rj_fun_dst c od )
    ( rj_ldx c x ( rj_uloc c oa ) ( rj_us c oa ) )
    : i mode ? == op 113 10 ? == op 114 9 ? == op 115 11 8
    ( rj_b c 102 ) ( rj_rex c 0 x 0 x 0 ) ( rj_b c 15 ) ( rj_b c 58 ) ( rj_b c 10 ) ( rj_modrr c x x ) ( rj_b c mode )  // roundss x,x,mode
    ( rj_fun_fin c od x )
}

// min / max with wasm semantics (any NaN → the canonical NaN; equal
// operands combine bitwise so min(±0,∓0) = -0 and max(±0,∓0) = +0);
// copysign on the bits
@ rj_e_fminmax Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i ob ( rj_u c r 1 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : b f64 >= op 132
    : i q - op ? f64 132 122  // 0 min, 1 max, 2 copysign
    ? == q 2 {
        ( rj_ldg c 0 ( rj_uloc c oa ) ( rj_us c oa ) 0 )
        ( rj_ldg c 1 ( rj_uloc c ob ) ( rj_us c ob ) 0 )
        ? f64 {
            ( rj_rr c 0 1 1 186 6 0 0 ) ( rj_b c 63 )  // btr rax,63
            ( rj_shift_ri c 1 5 1 63 ) ( rj_shift_ri c 1 4 1 63 )  // rcx = sign bit of b
            ( rj_alu_rr c 1 1 0 1 )  // or rax,rcx
        } {
            ( rj_alu_ri c 0 4 0 2147483647 ) ( rj_alu_ri c 0 4 1 -2147483648 ) ( rj_alu_rr c 0 1 0 1 )
        }
        ( rj_stg c ( rj_dloc c od ) ( rj_ds c od ) 0 )
        ^ v
    } {}
    : i pf ? f64 242 243
    : i p66 ? f64 102 0
    ( rj_ldx c 0 ( rj_uloc c oa ) ( rj_us c oa ) )
    ( rj_ldx c 1 ( rj_uloc c ob ) ( rj_us c ob ) )
    ( rj_rr c p66 0 1 46 0 1 0 )  // ucomisd/ss xmm0,xmm1
    : i jnan ( rj_jcc_fwd c 10 )  // jp
    : i jne ( rj_jcc_fwd c 5 )
    ( rj_rr c p66 0 1 ? == q 0 86 84 0 1 0 )  // equal: orpd (min) / andpd (max)
    : i jd1 ( rj_jmp_fwd c )
    ( rj_land c jne )
    ( rj_rr c pf 0 1 ? == q 0 93 95 0 1 0 )  // minsd/maxsd xmm0,xmm1 (ordered, distinct)
    : i jd2 ( rj_jmp_fwd c )
    ( rj_land c jnan )
    ( rj_ripop c 242 0 1 16 0 ? f64 9221120237041090560 2143289344 )  // the canonical NaN
    ( rj_land c jd1 ) ( rj_land c jd2 )
    ( rj_stx c ( rj_dloc c od ) ( rj_ds c od ) 0 )
}

// ── lowering: truncations and the unsigned 64-bit conversions ───
// float → int, trapping: NaN → "invalid conversion to integer", a value
// whose truncation leaves the target range → "integer overflow". An f32
// source is widened to f64 first (exact), so one set of bounds serves.
@ rj_e_trunc Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    : b src32 | | | == op 135 == op 136 == op 139 == op 140
    ( rj_ldx c 0 ( rj_uloc c oa ) ( rj_us c oa ) )
    ? src32 { ( rj_rr c 243 0 1 90 0 0 0 ) } {}  // cvtss2sd xmm0,xmm0
    ( rj_rr c 102 0 1 46 0 0 0 )  // ucomisd xmm0,xmm0
    ( rj_jcc c 10 ( rj_stub_inval c ) )  // jp → NaN
    // bounds (exclusive below unless noted, exclusive above)
    : b i64r | | | == op 139 == op 140 == op 141 == op 142
    : b uns | | | == op 136 == op 138 == op 140 == op 142
    : i lo ? uns -4616189618054758400 ? i64r -4332462841530417152 -4476578029604175872  // -1.0, -2^63 (inclusive), -2^31-1
    : i hi ? uns ? i64r 4895412794951729152 4751297606875873280 ? i64r 4890909195324358656 4746794007248502784  // 2^64, 2^32, 2^63, 2^31
    ( rj_ripop c 102 0 1 46 0 lo )  // ucomisd xmm0,[lo]
    ( rj_jcc c ? & ! uns i64r 2 6 ( rj_stub_iovf c ) )  // jb (−2^63 itself is fine) / jbe
    ( rj_ripop c 102 0 1 46 0 hi )
    ( rj_jcc c 3 ( rj_stub_iovf c ) )  // jae
    ? & uns i64r {  // u64: values ≥ 2^63 go through the subtract-and-flip
        ( rj_ripop c 102 0 1 46 0 4890909195324358656 )  // ucomisd xmm0,[2^63]
        : i small ( rj_jcc_fwd c 2 )  // jb
        ( rj_ripop c 242 0 1 92 0 4890909195324358656 )  // subsd xmm0,[2^63]
        ( rj_rr c 242 1 1 44 0 0 0 )  // cvttsd2si rax,xmm0
        ( rj_rr c 0 1 1 186 7 0 0 ) ( rj_b c 63 )  // btc rax,63
        : i done ( rj_jmp_fwd c )
        ( rj_land c small )
        ( rj_rr c 242 1 1 44 0 0 0 )
        ( rj_land c done )
    } {
        ( rj_rr c 242 1 1 44 0 0 0 )  // cvttsd2si rax,xmm0 (64-bit: covers u32 too)
        ? ! i64r { ( rj_movsxd c 0 0 ) } {}  // the canonical i32
    }
    ( rj_stg c ( rj_dloc c od ) ( rj_ds c od ) 0 )
}

// f32/f64.convert_i64_u: halve with a sticky bit, convert, double
@ rj_e_cvtu64 Rj c i r → v {
    : i op ( rj_rw c r 0 )
    : i oa ( rj_u c r 0 )
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    : i pf ? == op 151 242 243
    : i x ( rj_fun_dst c od )
    ( rj_ldg c 0 ( rj_uloc c oa ) ( rj_us c oa ) 0 )
    ( rj_rr c 0 0 1 87 x x 0 )  // xorps x,x
    ( rj_test_rr c 1 0 0 )
    : i big ( rj_jcc_fwd c 8 )  // js
    ( rj_rr c pf 1 1 42 x 0 0 )  // cvtsi2sd/ss x,rax
    : i done ( rj_jmp_fwd c )
    ( rj_land c big )
    ( rj_mov_rr c 1 1 0 ) ( rj_shift_ri c 1 5 1 1 )  // rcx = rax >> 1
    ( rj_alu_ri c 0 4 0 1 ) ( rj_alu_rr c 1 1 1 0 )  // rcx |= rax & 1
    ( rj_rr c pf 1 1 42 x 1 0 )
    ( rj_rr c pf 0 1 88 x x 0 )  // add x,x
    ( rj_land c done )
    ( rj_fun_fin c od x )
}

// ── lowering: call-outs (memory.grow, call_indirect, the 0xfc bridge) ──
// Every call-out reads its operands from frame homes and leaves its
// results there.
@ rj_reload_defs Rj c i r → v {
    : ~ i o ( vec_at [i] . c doff r )
    : i oe ( vec_at [i] . c doff + r 1 )
    ~ < o oe {
        ? ( rj_dlive c o ) {
            : i dl ( rj_dloc c o )
            ? != dl ( rjl_mem ) { ( rj_move c dl ( rj_ds c o ) ( rjl_mem ) ( rj_ds c o ) ) } {}
        } {}
        = o + o 1
    }
}

@ rj_e_memsize Rj c i r → v {
    : i od ( rj_dd c r 0 )
    ? ! ( rj_dlive c od ) { ^ v } {}
    ? ( rj_uses c 7 ) { ( rj_rm c 0 1 0 139 0 4 -1 0 0 0 ) ( rj_rm c 0 1 0 139 0 0 -1 0 16 0 ) } {  // rax = ctx[2] via the saved context
        ( rj_rm c 0 1 0 139 0 7 -1 0 16 0 ) }  // mov rax,[rdi+16]
    ( rj_shift_ri c 1 5 0 16 )  // pages = bytes >> 16
    ( rj_stg c ( rj_dloc c od ) ( rj_ds c od ) 0 )
}

@ rj_e_memgrow Rj c i r → v {
    : i oa ( rj_u c r 0 )
    ( rj_ldg c 0 ( rj_uloc c oa ) ( rj_us c oa ) 0 )
    ( rj_mov32 c 0 0 )  // the delta, zero-extended (the handler reads ctx[4])
    ( rj_restore_inv c )
    ( rj_b c 72 ) ( rj_b c 137 ) ( rj_b c 71 ) ( rj_b c 32 )  // mov [rdi+32],rax
    ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 56 ) ( rj_d c ( rj_ds c ( rj_dd c r 0 ) ) )  // mov qword[rdi+56], dst slot
    ( rj_frame_end c ) ( rj_b c 73 ) ( rj_b c 137 ) ( rj_b c 8 )  // mov [r8],rcx
    ( rj_callout c 18 )
    ( rj_reload_defs c r )
}

// call_indirect: resolve the table entry inline and call the callee's
// direct entry; an index out of range, a null entry, a signature
// mismatch, an import or a callee not compiled yet all take the bridge,
// which traps with the interpreter's own message or runs the call there.
@ rj_e_callind Rj c i r → v {
    : i ab ( rj_rw c r 2 )
    : i sig ( vec_at [i] . c rsig r )
    : i np ( rj_sig_np sig )
    : i nr ( rj_sig_nr sig )
    : i canon ( rj_sig_canon sig )
    : ~ i k 0
    ~ < k np {
        : i o ( rj_u c r k )
        ( rj_move c ( rjl_mem ) + ab k ( rj_uloc c o ) ( rj_us c o ) )
        = k + k 1
    }
    // the index first: arg0's load into rdx would clobber an index living there
    : i oi ( rj_u c r np )
    ( rj_ldg c 0 ( rj_uloc c oi ) ( rj_us c oi ) 0 )
    ( rj_mov32 c 0 0 )
    ? == np 1 { : i o0 ( rj_u c r 0 ) ( rj_ldg c 2 ( rj_uloc c o0 ) ( rj_us c o0 ) 0 ) } {}  // arg0 rides in rdx
    ( rj_restore_inv c )
    ( rj_b c 72 ) ( rj_b c 137 ) ( rj_b c 71 ) ( rj_b c 32 )  // mov [rdi+32],rax — the index, for the bridge
    : ( Vec i ) toBridge ( vec_new [i] )
    : ~ i okj -1
    ? >= canon 0 {
        : i nimp ( rj_get c ( rjs_nimp ) )
        ( rj_rm c 0 1 0 139 1 8 -1 0 ( rj_get c ( rjs_tbloff ) ) 0 )  // mov rcx,[r8+tbl] — the table's Vec
        ( rj_rm c 0 1 0 59 0 1 -1 0 8 0 )  // cmp rax,[rcx+8] — its length
        ( vec_push [i] toBridge ( rj_jcc_fwd c 3 ) )  // jae
        ( rj_rm c 0 1 0 139 1 1 -1 0 0 0 )  // mov rcx,[rcx] — its data
        ( rj_rm c 0 1 0 139 0 1 0 3 0 0 )  // mov rax,[rcx+rax*8] — the function index
        ( rj_test_rr c 1 0 0 )
        ( vec_push [i] toBridge ( rj_jcc_fwd c 8 ) )  // js — a null entry
        ( rj_rm c 0 1 0 129 7 8 0 3 ( rj_get c ( rjs_sigoff ) ) 0 ) ( rj_d c canon )  // cmp qword[r8+sig+rax*8], canon
        ( vec_push [i] toBridge ( rj_jcc_fwd c 5 ) )  // jne — a signature mismatch
        ( rj_alu_ri c 1 5 0 nimp )  // sub rax, nimp
        ( vec_push [i] toBridge ( rj_jcc_fwd c 2 ) )  // jb — an import
        ( rj_rm c 0 1 0 139 0 8 0 3 16 0 )  // mov rax,[r8+16+rax*8] — its direct entry
        ( rj_test_rr c 1 0 0 )
        ( vec_push [i] toBridge ( rj_jcc_fwd c 4 ) )  // jz — not compiled yet
        ( rj_frame_end c )
        ( rj_lea c 1 6 3 -1 0 * ab 8 )  // lea rsi,[rbx+argbase*8]
        ( rj_b c 255 ) ( rj_b c 208 )  // call rax
        = okj ( rj_jmp_fwd c )
    } {}
    : i nbj ( vec_len [i] toBridge )
    = k 0
    ~ < k nbj { ( rj_land c ( vec_at [i] toBridge k ) ) = k + k 1 }
    ( rj_frame_end c ) ( rj_b c 73 ) ( rj_b c 137 ) ( rj_b c 8 )  // mov [r8],rcx
    ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 40 ) ( rj_d c ab )  // mov qword[rdi+40], argbase
    ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 56 ) ( rj_d c ( rj_rw c r 1 ) )  // mov qword[rdi+56], typeidx
    ( rj_callout c 17 )
    ? == nr 1 { ( rj_ldf c 1 0 ab ) } {}  // result 0 into rax, as the direct path leaves it
    ? >= okj 0 { ( rj_land c okj ) } {}
    = k 0
    ~ < k nr {
        : i o ( rj_dd c r k )
        ? ( rj_dlive c o ) {
            : i dl ( rj_dloc c o )
            ? == nr 1 { ? != dl ( rjl_mem ) { ( rj_stg c dl ( rj_ds c o ) 0 ) } {} } {
                ? != dl ( rjl_mem ) { ( rj_move c dl ( rj_ds c o ) ( rjl_mem ) + ab k ) } {}
            }
        } {}
        = k + k 1
    }
}

@ rj_e_fcb Rj c i r → v {
    : i cb ( rj_rw c r 3 )
    : i d ( rj_rw c r 4 )
    : ~ i k 0
    ~ < k >> d 1 {
        : i o ( rj_u c r k )
        ( rj_move c ( rjl_mem ) + cb k ( rj_uloc c o ) ( rj_us c o ) )
        = k + k 1
    }
    ( rj_restore_inv c )
    ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 32 ) ( rj_d c ( rj_rw c r 1 ) )  // mov qword[rdi+32], sub-op
    ( rj_b c 72 ) ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 40 ) ( rj_d c ( rj_rw c r 2 ) )  // mov qword[rdi+40], immediate
    ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 56 ) ( rj_d c cb )  // mov dword[rdi+56], srcbase
    ( rj_b c 199 ) ( rj_b c 71 ) ( rj_b c 60 ) ( rj_d c d )  // mov dword[rdi+60], pops<<1|push
    ( rj_frame_end c ) ( rj_b c 73 ) ( rj_b c 137 ) ( rj_b c 8 )  // mov [r8],rcx
    ( rj_callout c 19 )
    ( rj_reload_defs c r )
}
