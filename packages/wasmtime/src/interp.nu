// packages/wasmtime/src/interp.nu — a small WebAssembly interpreter (pure NURL).
//
// Executes the integer core of wasm: i32/i64 const, locals, the integer
// arithmetic/comparison/bitwise ops, the structured control flow (block / loop
// / if / else / br / br_if / return), drop / select, and direct call. Values
// are held as 64-bit ints; i32 ops wrap + sign-extend to 32 bits. Floats,
// linear memory, globals, tables and imports (WASI) are future milestones — so
// this runs self-contained integer compute modules (add, loop-sum, …) today.
//
// Control flow uses an explicit control stack. Entering a block/if computes its
// matching `end` by a one-pass immediate-skipping scan; `br` to a loop re-enters
// at the loop start, to a block jumps past its `end`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `module.nu`

// ── value + control stacks ───────────────────────────────────────

: Ctrl { i is_loop i start_pc i end_pc i height i arity }

: Interp {
    s mod  // *Module
    ( Vec i ) vs  // value stack
    ( Vec u ) mem  // linear memory (bytes)
    i mem_pages  // current size in 64 KiB pages
    ( Vec i ) globals  // mutable global values
    b trap
    ( Vec u ) trapmsg
}

@ __page → i { ^ 65536 }

@ interp_new * Module m → *Interp {
    : *Interp it # *Interp ( nurl_alloc Z Interp )
    = . it mod # s m
    = . it vs ( vec_new [i] )
    = . it mem ( vec_new [u] )
    = . it mem_pages 0
    = . it globals ( vec_new [i] )
    = . it trap F
    = . it trapmsg ( vec_new [u] )
    // copy global initial values
    : i ng ( vec_len [i] . m global_init )
    : ~ i gi 0
    ~ < gi ng { ( vec_push [i] . it globals ?? ( vec_get [i] . m global_init gi ) { T x → x F → 0 } ) = gi + gi 1 }
    ? == . m has_mem 1 {
        : i bytes * . m mem_min ( __page )
        : ~ i k 0
        ~ < k bytes { ( vec_push [u] . it mem # u 0 ) = k + k 1 }
        = . it mem_pages . m mem_min
        // copy active data segments into memory
        : i nd ( vec_len [s] . m datas )
        : ~ i di 0
        ~ < di nd {
            : s dp ?? ( vec_get [s] . m datas di ) { T x → x F → # s 0 }
            ? != # i dp 0 {
                : *DataSeg ds # *DataSeg dp
                : i dn ( vec_len [u] . ds bytes )
                : ~ i bi 0
                ~ < bi dn {
                    : i tgt + . ds offset bi
                    ? < tgt ( vec_len [u] . it mem ) {
                        ( vec_set [u] . it mem tgt ?? ( vec_get [u] . ds bytes bi ) { T x → x F → # u 0 } )
                    } {}
                    = bi + bi 1
                }
            } {}
            = di + di 1
        }
    } {}
    ^ it
}

@ interp_free * Interp it → v {
    ( vec_free [i] . it vs )
    ( vec_free [u] . it mem )
    ( vec_free [i] . it globals )
    ( vec_free [u] . it trapmsg )
    ( nurl_free # s it )
}

@ __push * Interp it i v → v { ( vec_push [i] . it vs v ) }

@ __pop * Interp it → i {
    : i n ( vec_len [i] . it vs )
    ? <= n 0 { = . it trap T ^ 0 } {}
    : i v ?? ( vec_get [i] . it vs - n 1 ) { T x → x F → 0 }
    ( vec_pop [i] . it vs )
    ^ v
}

@ __vsh * Interp it → i { ^ ( vec_len [i] . it vs ) }

// Truncate the value stack back to height h.
@ __vtrunc * Interp it i h → v {
    ~ > ( vec_len [i] . it vs ) h { ( vec_pop [i] . it vs ) }
}

// Sign-extend the low 32 bits (i32 value semantics in a 64-bit cell).
@ __w32 i v → i { : i lo & v 4294967295 ^ ? != 0 & lo 2147483648 | lo -4294967296 lo }

// ── immediate skipping (for matching `end`) ──────────────────────
// Advance `c` past the immediates of the instruction whose opcode is `op`.

@ __skip_imm * Wc c i op → v {
    // block / loop / if : 1-byte block type
    ? | == op 2 | == op 3 == op 4 { ( wc_u8 c ) ^ v } {}
    // br / br_if / call / local.* / global.* : one uleb
    ? | == op 12 | == op 13 | == op 16 | == op 32 | == op 33 | == op 34 | == op 35 == op 36 { ( wc_uleb c ) ^ v } {}
    // call_indirect : two ulebs
    ? == op 17 { ( wc_uleb c ) ( wc_uleb c ) ^ v } {}
    // br_table : vec of ulebs + default
    ? == op 14 { : i n ( wc_uleb c ) : ~ i k 0 ~ <= k n { ( wc_uleb c ) = k + k 1 } ^ v } {}
    // i32.const / i64.const : one sleb
    ? | == op 65 == op 66 { ( wc_sleb c ) ^ v } {}
    // f32.const : 4 bytes ; f64.const : 8 bytes
    ? == op 67 { ( wc_skip c 4 ) ^ v } {}
    ? == op 68 { ( wc_skip c 8 ) ^ v } {}
    // memory load/store (0x28..0x3e) : align + offset ulebs
    ? & >= op 40 <= op 62 { ( wc_uleb c ) ( wc_uleb c ) ^ v } {}
    // memory.size / memory.grow : 1 reserved byte
    ? | == op 63 == op 64 { ( wc_u8 c ) ^ v } {}
    // everything else: no immediates
}

// From a cursor positioned just after a block/loop/if's block-type, return the
// byte position of its matching `end` (and optionally its `else`). Uses a
// throwaway cursor so the caller's position is untouched.
@ __find_end ( Vec u ) buf i from i limit → i {
    : *Wc c ( wc_new buf )
    = . c pos from
    = . c len limit
    : ~ i depth 0
    : ~ i result limit
    : ~ b done F
    ~ & ! done < . c pos limit {
        : i op ( wc_u8 c )
        ? | == op 2 | == op 3 == op 4 { = depth + depth 1 ( __skip_imm c op ) } {
            ? == op 11 {
                ? == depth 0 { = result - . c pos 1 = done T } { = depth - depth 1 }
            } {
                ( __skip_imm c op )
            } }
    }
    ( wc_free c )
    ^ result
}

@ __find_else ( Vec u ) buf i from i limit → i {
    : *Wc c ( wc_new buf )
    = . c pos from
    = . c len limit
    : ~ i depth 0
    : ~ i result -1
    : ~ b done F
    ~ & ! done < . c pos limit {
        : i op ( wc_u8 c )
        ? | == op 2 | == op 3 == op 4 { = depth + depth 1 ( __skip_imm c op ) } {
            ? == op 11 { ? == depth 0 { = done T } { = depth - depth 1 } } {
                ? & == op 5 == depth 0 { = result - . c pos 1 = done T } {
                    ( __skip_imm c op )
                } } }
    }
    ( wc_free c )
    ^ result
}

// Result arity of a block type byte (0x40 void → 0; a valtype → 1).
@ __bt_arity i bt → i { ^ ? == bt 64 0 1 }

// ── arithmetic helpers ───────────────────────────────────────────

@ __idiv i a i b → i { ^ ? == b 0 0 / a b }

@ __irem i a i b → i { ^ ? == b 0 0 % a b }

// ── linear memory ────────────────────────────────────────────────
// Read n bytes little-endian from mem[ea]; sign-extend when `signed` and n<8.
@ __mem_load * Interp it i ea i n i signed → i {
    ? | < ea 0 > + ea n ( vec_len [u] . it mem ) {
        = . it trap T = . it trapmsg ( bytes_from_str `memory load out of bounds` ) ^ 0
    } {}
    : ~ i v 0
    : ~ i k 0
    ~ < k n {
        : i byte ?? ( vec_get [u] . it mem + ea k ) { T x → # i x F → 0 }
        = v | v << byte * 8 k
        = k + k 1
    }
    ? & == signed 1 < n 8 {
        : i bits * 8 n
        ? != 0 & v << 1 - bits 1 { = v - v << 1 bits } {}
    } {}
    ^ v
}

// Write the low n bytes of val little-endian to mem[ea].
@ __mem_store * Interp it i ea i n i val → v {
    ? | < ea 0 > + ea n ( vec_len [u] . it mem ) {
        = . it trap T = . it trapmsg ( bytes_from_str `memory store out of bounds` ) ^ v
    } {}
    : ~ i k 0
    ~ < k n {
        ( vec_set [u] . it mem + ea k # u & >> val * 8 k 255 )
        = k + k 1
    }
}

@ __mem_grow * Interp it i delta → v {
    ? <= delta 0 { ^ v } {}
    : i add * delta ( __page )
    : ~ i k 0
    ~ < k add { ( vec_push [u] . it mem # u 0 ) = k + k 1 }
    = . it mem_pages + . it mem_pages delta
}

// Execute a memory instruction (0x28..0x40). memarg = align + offset ulebs.
@ __exec_mem * Interp it * Wc c i op → v {
    ? == op 63 { ( wc_u8 c ) ( __push it . it mem_pages ) ^ v } {}  // memory.size
    ? == op 64 { ( wc_u8 c ) : i d ( __pop it ) : i old . it mem_pages ( __mem_grow it d ) ( __push it old ) ^ v } {}  // memory.grow
    : i align ( wc_uleb c )
    : i off ( wc_uleb c )
    ? & >= op 54 <= op 62 {  // stores: pop value, then addr
        : i val ( __pop it )
        : i ea + & ( __pop it ) 4294967295 off
        ? == op 54 { ( __mem_store it ea 4 val ) } {}  // i32.store
        ? == op 55 { ( __mem_store it ea 8 val ) } {}  // i64.store
        ? == op 58 { ( __mem_store it ea 1 val ) } {}  // i32.store8
        ? == op 59 { ( __mem_store it ea 2 val ) } {}  // i32.store16
        ? == op 60 { ( __mem_store it ea 1 val ) } {}  // i64.store8
        ? == op 61 { ( __mem_store it ea 2 val ) } {}  // i64.store16
        ? == op 62 { ( __mem_store it ea 4 val ) } {}  // i64.store32
        ^ v
    } {}
    : i ea + & ( __pop it ) 4294967295 off
    ? == op 40 { ( __push it ( __w32 ( __mem_load it ea 4 0 ) ) ) } {}  // i32.load
    ? == op 41 { ( __push it ( __mem_load it ea 8 0 ) ) } {}  // i64.load
    ? == op 44 { ( __push it ( __w32 ( __mem_load it ea 1 1 ) ) ) } {}  // i32.load8_s
    ? == op 45 { ( __push it ( __mem_load it ea 1 0 ) ) } {}  // i32.load8_u
    ? == op 46 { ( __push it ( __w32 ( __mem_load it ea 2 1 ) ) ) } {}  // i32.load16_s
    ? == op 47 { ( __push it ( __mem_load it ea 2 0 ) ) } {}  // i32.load16_u
    ? == op 48 { ( __push it ( __mem_load it ea 1 1 ) ) } {}  // i64.load8_s
    ? == op 49 { ( __push it ( __mem_load it ea 1 0 ) ) } {}  // i64.load8_u
    ? == op 50 { ( __push it ( __mem_load it ea 2 1 ) ) } {}  // i64.load16_s
    ? == op 51 { ( __push it ( __mem_load it ea 2 0 ) ) } {}  // i64.load16_u
    ? == op 52 { ( __push it ( __mem_load it ea 4 1 ) ) } {}  // i64.load32_s
    ? == op 53 { ( __push it ( __mem_load it ea 4 0 ) ) } {}  // i64.load32_u
}

// ── control-stack helpers ────────────────────────────────────────

@ __ctrl_push ( Vec s ) ctrl i is_loop i start_pc i end_pc i height i arity → v {
    : *Ctrl e # *Ctrl ( nurl_alloc Z Ctrl )
    = . e is_loop is_loop
    = . e start_pc start_pc
    = . e end_pc end_pc
    = . e height height
    = . e arity arity
    ( vec_push [s] ctrl # s e )
}

@ __ctrl_pop ( Vec s ) ctrl → v {
    : i n ( vec_len [s] ctrl )
    ? <= n 0 { ^ v } {}
    ?? ( vec_get [s] ctrl - n 1 ) { T pp → ?!= # i pp 0 { ( nurl_free pp ) } {} F → {} }
    ( vec_pop [s] ctrl )
}

@ __ctrl_at ( Vec s ) ctrl i k → s {
    : i ix - - ( vec_len [s] ctrl ) 1 k
    ? < ix 0 { ^ # s 0 } {}
    ^ ?? ( vec_get [s] ctrl ix ) { T x → x F → # s 0 }
}

// Take branch to label depth k: re-enter a loop, or exit a block past its end.
@ __do_branch * Interp it ( Vec s ) ctrl * Wc c i k → v {
    : s tp ( __ctrl_at ctrl k )
    ? == # i tp 0 { = . it trap T ^ v } {}
    : *Ctrl target # *Ctrl tp
    ? == . target is_loop 1 {
        ( __vtrunc it . target height )
        : ~ i pops k
        ~ > pops 0 { ( __ctrl_pop ctrl ) = pops - pops 1 }
        = . c pos . target start_pc
    } {
        ? == . target arity 1 {
            : i rv ( __pop it ) ( __vtrunc it . target height ) ( __push it rv )
        } { ( __vtrunc it . target height ) }
        : ~ i pops + k 1
        ~ > pops 0 { ( __ctrl_pop ctrl ) = pops - pops 1 }
        = . c pos + . target end_pc 1
    }
}

// ── the executor ─────────────────────────────────────────────────
// Execute function `fidx`. Arguments are already on the value stack; on return
// the function's results are left on top. Recurses for `call`.

@ exec_func * Interp it i fidx → v {
    ? . it trap { ^ v } {}
    : *Module m # *Module . it mod
    : s fp ?? ( vec_get [s] . m funcs fidx ) { T x → x F → # s 0 }
    ? == # i fp 0 { = . it trap T ^ v } {}
    : *WFunc f # *WFunc fp
    : s tp ?? ( vec_get [s] . m types . f typeidx ) { T x → x F → # s 0 }
    : *FuncType ft # *FuncType tp
    : i nparams ( vec_len [i] . ft params )
    : i nlocals_decl ( vec_len [i] . f locals )

    // frame locals = params (popped in order) ++ declared locals (zeroed)
    : ( Vec i ) locals ( vec_new [i] )
    : ~ i k 0
    ~ < k + nparams nlocals_decl { ( vec_push [i] locals 0 ) = k + k 1 }
    : ~ i p nparams
    ~ > p 0 { = p - p 1 ( vec_set [i] locals p ( __pop it ) ) }

    : ( Vec s ) ctrl ( vec_new [s] )
    : *Wc c ( wc_new . m code )
    = . c pos . f code_start
    = . c len . f code_end
    : ~ b ret F

    ~ & ! ret & ! . it trap < . c pos . f code_end {
        : i op ( wc_u8 c )
        ( __exec_op it m c ctrl locals op )
        // an `end` with an empty control stack ends the function
        ? & == op 11 == ( vec_len [s] ctrl ) 0 { = ret T } {}
        ? == op 15 { = ret T } {}  // return
    }

    : i cn ( vec_len [s] ctrl )
    : ~ i ci 0
    ~ < ci cn { ?? ( vec_get [s] ctrl ci ) { T pp → ?!= # i pp 0 { ( nurl_free pp ) } {} F → {} } = ci + ci 1 }
    ( vec_free [s] ctrl )
    ( vec_free [i] locals )
    ( wc_free c )
}

// Execute one instruction (opcode already read into `op`). Mutates the value
// stack, locals, control stack and cursor.
@ __exec_op * Interp it * Module m * Wc c ( Vec s ) ctrl ( Vec i ) locals i op → v {
    // ── control flow ──
    ? == op 0 { = . it trap T = . it trapmsg ( bytes_from_str `unreachable` ) ^ v } {}  // unreachable
    ? == op 1 { ^ v } {}  // nop
    ? | == op 2 == op 3 {  // block / loop
        : i bt ( wc_u8 c )
        : i endp ( __find_end . m code . c pos . c len )
        ? == op 3 { ( __ctrl_push ctrl 1 . c pos endp ( __vsh it ) ( __bt_arity bt ) ) }
        { ( __ctrl_push ctrl 0 0 endp ( __vsh it ) ( __bt_arity bt ) ) }
        ^ v
    } {}
    ? == op 4 {  // if
        : i bt ( wc_u8 c )
        : i endp ( __find_end . m code . c pos . c len )
        : i elsep ( __find_else . m code . c pos . c len )
        : i cond ( __pop it )
        ( __ctrl_push ctrl 0 0 endp ( __vsh it ) ( __bt_arity bt ) )
        ? == cond 0 { = . c pos ? >= elsep 0 + elsep 1 endp } {}
        ^ v
    } {}
    ? == op 5 {  // else: reached at end of the then-arm → skip to end
        : s tp ( __ctrl_at ctrl 0 )
        ? != # i tp 0 { : *Ctrl e # *Ctrl tp = . c pos . e end_pc } {}
        ^ v
    } {}
    ? == op 11 { ( __ctrl_pop ctrl ) ^ v } {}  // end
    ? == op 12 { : i lbl ( wc_uleb c ) ( __do_branch it ctrl c lbl ) ^ v } {}  // br
    ? == op 13 { : i lbl ( wc_uleb c ) : i cond ( __pop it ) ? != cond 0 { ( __do_branch it ctrl c lbl ) } {} ^ v } {}  // br_if
    ? == op 15 { ^ v } {}  // return (handled by caller loop)
    ? == op 16 { : i fi ( wc_uleb c ) ( exec_func it fi ) ^ v } {}  // call
    ? == op 17 {  // call_indirect typeidx tableidx
        : i typeidx ( wc_uleb c )
        : i tblidx ( wc_uleb c )
        : i ei & ( __pop it ) 4294967295
        ? | < ei 0 >= ei ( vec_len [i] . m table ) {
            = . it trap T = . it trapmsg ( bytes_from_str `call_indirect: index out of range` ) ^ v
        } {}
        : i fi ?? ( vec_get [i] . m table ei ) { T x → x F → -1 }
        ? < fi 0 { = . it trap T = . it trapmsg ( bytes_from_str `call_indirect: null table element` ) ^ v } {}
        ( exec_func it fi )
        ^ v
    } {}
    ? == op 26 { ( __pop it ) ^ v } {}  // drop
    ? == op 27 { : i cc ( __pop it ) : i b2 ( __pop it ) : i a2 ( __pop it ) ( __push it ? != cc 0 a2 b2 ) ^ v } {}  // select
    // ── locals ──
    ? == op 32 { : i li ( wc_uleb c ) ( __push it ?? ( vec_get [i] locals li ) { T x → x F → 0 } ) ^ v } {}
    ? == op 33 { : i li ( wc_uleb c ) ( vec_set [i] locals li ( __pop it ) ) ^ v } {}
    ? == op 34 { : i li ( wc_uleb c ) : i tv ?? ( vec_get [i] . it vs - ( vec_len [i] . it vs ) 1 ) { T x → x F → 0 } ( vec_set [i] locals li tv ) ^ v } {}  // local.tee
    // ── globals ──
    ? == op 35 { : i gi ( wc_uleb c ) ( __push it ?? ( vec_get [i] . it globals gi ) { T x → x F → 0 } ) ^ v } {}  // global.get
    ? == op 36 { : i gi ( wc_uleb c ) ( vec_set [i] . it globals gi ( __pop it ) ) ^ v } {}  // global.set
    // ── constants ──
    ? == op 65 { ( __push it ( __w32 ( wc_sleb c ) ) ) ^ v } {}  // i32.const
    ? == op 66 { ( __push it ( wc_sleb c ) ) ^ v } {}  // i64.const
    // ── linear memory (loads/stores, size/grow) ──
    ? & >= op 40 <= op 64 { ( __exec_mem it c op ) ^ v } {}
    // ── the rest: numeric ops ──
    ( __exec_num it c op )
}

// Numeric/comparison/bitwise ops (both i32 and i64). i32 results are wrapped to
// 32 bits; comparisons push 0/1.
@ __exec_num * Interp it * Wc c i op → v {
    // i32 unary: eqz
    ? == op 69 { ( __push it ? == ( __pop it ) 0 1 0 ) ^ v } {}
    // i64 unary: eqz
    ? == op 80 { ( __push it ? == ( __pop it ) 0 1 0 ) ^ v } {}
    // i32.wrap_i64
    ? == op 167 { ( __push it ( __w32 ( __pop it ) ) ) ^ v } {}
    // i64.extend_i32_s
    ? == op 172 { ( __push it ( __w32 ( __pop it ) ) ) ^ v } {}
    // i64.extend_i32_u
    ? == op 173 { ( __push it & ( __pop it ) 4294967295 ) ^ v } {}
    // binary ops: pop b, a
    : i b ( __pop it )
    : i a ( __pop it )
    // ── i32 comparisons (0x46..0x4f) ──
    ? == op 70 { ( __push it ? == ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 71 { ( __push it ? != ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 72 { ( __push it ? < ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 74 { ( __push it ? > ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 76 { ( __push it ? <= ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 78 { ( __push it ? >= ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    // ── i32 arithmetic/bitwise (0x6a..0x78) → wrap 32 ──
    ? == op 106 { ( __push it ( __w32 + a b ) ) ^ v } {}
    ? == op 107 { ( __push it ( __w32 - a b ) ) ^ v } {}
    ? == op 108 { ( __push it ( __w32 * a b ) ) ^ v } {}
    ? == op 109 { ( __push it ( __w32 ( __idiv ( __w32 a ) ( __w32 b ) ) ) ) ^ v } {}
    ? == op 111 { ( __push it ( __w32 ( __irem ( __w32 a ) ( __w32 b ) ) ) ) ^ v } {}
    ? == op 113 { ( __push it ( __w32 & a b ) ) ^ v } {}
    ? == op 114 { ( __push it ( __w32 | a b ) ) ^ v } {}
    ? == op 115 { ( __push it ( __w32 ^^ a b ) ) ^ v } {}
    ? == op 116 { ( __push it ( __w32 << a & b 31 ) ) ^ v } {}
    ? == op 117 { ( __push it ( __w32 >> ( __w32 a ) & b 31 ) ) ^ v } {}
    // ── i64 comparisons (0x51..0x5a) ──
    ? == op 81 { ( __push it ? == a b 1 0 ) ^ v } {}
    ? == op 82 { ( __push it ? != a b 1 0 ) ^ v } {}
    ? == op 83 { ( __push it ? < a b 1 0 ) ^ v } {}
    ? == op 85 { ( __push it ? > a b 1 0 ) ^ v } {}
    ? == op 87 { ( __push it ? <= a b 1 0 ) ^ v } {}
    ? == op 89 { ( __push it ? >= a b 1 0 ) ^ v } {}
    // ── i64 arithmetic/bitwise (0x7c..0x8a) ──
    ? == op 124 { ( __push it + a b ) ^ v } {}
    ? == op 125 { ( __push it - a b ) ^ v } {}
    ? == op 126 { ( __push it * a b ) ^ v } {}
    ? == op 127 { ( __push it ( __idiv a b ) ) ^ v } {}
    ? == op 129 { ( __push it ( __irem a b ) ) ^ v } {}
    ? == op 131 { ( __push it & a b ) ^ v } {}
    ? == op 132 { ( __push it | a b ) ^ v } {}
    ? == op 133 { ( __push it ^^ a b ) ^ v } {}
    ? == op 134 { ( __push it << a & b 63 ) ^ v } {}
    ? == op 135 { ( __push it >> a & b 63 ) ^ v } {}
    // unsupported opcode → trap
    = . it trap T
    = . it trapmsg ( bytes_from_str `unsupported opcode` )
}
