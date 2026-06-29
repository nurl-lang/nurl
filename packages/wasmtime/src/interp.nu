// packages/wasmtime/src/interp.nu — a small WebAssembly interpreter (pure NURL).
//
// Executes wasm: i32/i64/f32/f64 const, locals, globals, the integer and float
// arithmetic/comparison/bitwise ops, all int↔float conversions, structured
// control flow (block / loop / if / else / br / br_if / return), drop / select,
// direct and indirect calls, and linear memory load/store. Each value occupies
// one 64-bit cell; i32 wraps + sign-extends to 32 bits, and floats are held as
// their IEEE-754 bit pattern (reinterpreted via std/floatbits for arithmetic).
// Imports (the WASI surface) are the remaining milestone — so this runs
// self-contained compute modules today.
//
// Control flow uses an explicit control stack. Entering a block/if computes its
// matching `end` by a one-pass immediate-skipping scan; `br` to a loop re-enters
// at the loop start, to a block jumps past its `end`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/fs.nu`
$ `module.nu`

// round-to-nearest-even (wasm f*.nearest) — libm rint honours the default mode.
& `m` @ rint f x → f

// ── value + control stacks ───────────────────────────────────────

: Arg { ( Vec u ) bytes }

: Ctrl { i is_loop i start_pc i end_pc i height i arity }

// A WASI file descriptor. kind: 0 closed, 1 stdio, 2 preopened dir, 3 file.
// For a file, `data` holds the contents (read) or the bytes written so far,
// `pos` the read/write offset, `host` the on-disk path (for open/flush), and
// `name` (a dir) the guest-visible preopen name reported by fd_prestat_*.
: WFd { i kind ( Vec u ) data i pos ( Vec u ) host ( Vec u ) name b writable b dirty }

: Interp {
    s mod  // *Module
    ( Vec i ) vs  // value stack
    ( Vec u ) mem  // linear memory (bytes)
    i mem_pages  // current size in 64 KiB pages
    ( Vec i ) globals  // mutable global values
    ( Vec s ) argv  // *( Vec u ) — WASI program arguments (argv[0] = program)
    ( Vec s ) fds  // *WFd — file-descriptor table (0/1/2 stdio, 3 preopen, …)
    b exited  // set after proc_exit
    i exit_code
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
    = . it argv ( vec_new [s] )
    = . it fds ( vec_new [s] )
    // fds 0/1/2 = stdin/stdout/stderr (kind 1); higher slots filled by preopen.
    : ~ i sfd 0
    ~ < sfd 3 { ( vec_push [s] . it fds # s ( __mkfd 1 ) ) = sfd + sfd 1 }
    = . it exited F
    = . it exit_code 0
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

// Allocate a fresh file-descriptor record of the given kind.
@ __mkfd i kind → s {
    : *WFd f # *WFd ( nurl_alloc Z WFd )
    = . f kind kind
    = . f data ( vec_new [u] )
    = . f pos 0
    = . f host ( vec_new [u] )
    = . f name ( vec_new [u] )
    = . f writable F
    = . f dirty F
    ^ # s f
}

@ __freefd s pp → v {
    ? == # i pp 0 { ^ v } {}
    : *WFd f # *WFd pp
    ( vec_free [u] . f data ) ( vec_free [u] . f host ) ( vec_free [u] . f name )
    ( nurl_free # s f )
}

@ interp_free * Interp it → v {
    ( vec_free [i] . it vs )
    ( vec_free [u] . it mem )
    ( vec_free [i] . it globals )
    : i an ( vec_len [s] . it argv )
    : ~ i ai 0
    ~ < ai an { ?? ( vec_get [s] . it argv ai ) { T pp → ?!= # i pp 0 { : *Arg a # *Arg pp ( vec_free [u] . a bytes ) ( nurl_free # s a ) } {} F → {} } = ai + ai 1 }
    ( vec_free [s] . it argv )
    : i fn ( vec_len [s] . it fds )
    : ~ i fi 0
    ~ < fi fn { ?? ( vec_get [s] . it fds fi ) { T pp → ( __freefd pp ) F → {} } = fi + fi 1 }
    ( vec_free [s] . it fds )
    ( vec_free [u] . it trapmsg )
    ( nurl_free # s it )
}

// Append a program argument (copied from a NUL-terminated host string).
@ interp_push_arg * Interp it s str → v {
    : *Arg a # *Arg ( nurl_alloc Z Arg )
    = . a bytes ( bytes_from_str str )
    ( vec_push [s] . it argv # s a )
}

// Grant the module one preopened host directory, visible to it as `guest_name`
// (the path it resolves opens against). Installed as fd 3.
@ interp_set_preopen * Interp it s host_path s guest_name → v {
    : *WFd f # *WFd ( __mkfd 2 )
    ( vec_free [u] . f host ) = . f host ( bytes_from_str host_path )
    ( vec_free [u] . f name ) = . f name ( bytes_from_str guest_name )
    ( vec_push [s] . it fds # s f )
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

// Read n little-endian bytes from the cursor into an i (zero-extended).
@ __read_le * Wc c i n → i {
    : ~ i bits 0
    : ~ i k 0
    ~ < k n { = bits | bits << ( wc_u8 c ) * 8 k = k + k 1 }
    ^ bits
}

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
    // 0xfc prefix (bulk memory / saturating trunc): sub-opcode + its immediates
    ? == op 252 {
        : i sub ( wc_uleb c )
        ? == sub 8 { ( wc_uleb c ) ( wc_u8 c ) } {  // memory.init: dataidx + memidx
            ? == sub 9 { ( wc_uleb c ) } {  // data.drop
                ? == sub 10 { ( wc_u8 c ) ( wc_u8 c ) } {  // memory.copy: 2 memidx
                    ? == sub 11 { ( wc_u8 c ) } {} } } }  // memory.fill: 1 memidx
        ^ v
    } {}
    // sign-extension ops (0xc0..0xc4): no immediates (fall through)
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

// ── unsigned helpers (NURL's `/ % >> < …` are signed; wasm needs unsigned) ──

// Low 32 bits as a non-negative i64.
@ __u32 i x → i { ^ & x 4294967295 }

// Logical (zero-filling) right shift of a full 64-bit value by n (0..63).
@ __lshr64 i a i n → i { ^ ? == n 0 a & >> a n - << 1 - 64 n 1 }

// Unsigned 64-bit less-than (flip sign bits → signed order matches unsigned).
@ __ultb i a i b → b { ^ < ^^ a << 1 63 ^^ b << 1 63 }

// Unsigned 64-bit division / remainder by bitwise long division.
@ __udiv64 i a i b → i {
    ? == b 0 { ^ 0 } {}
    : ~ i q 0
    : ~ i r 0
    : ~ i k 63
    ~ >= k 0 { = r | << r 1 & ( __lshr64 a k ) 1 ? ! ( __ultb r b ) { = r - r b = q | q << 1 k } {} = k - k 1 }
    ^ q
}

@ __urem64 i a i b → i {
    ? == b 0 { ^ 0 } {}
    : ~ i r 0
    : ~ i k 63
    ~ >= k 0 { = r | << r 1 & ( __lshr64 a k ) 1 ? ! ( __ultb r b ) { = r - r b } {} = k - k 1 }
    ^ r
}

// Rotates (n masked to the type width by the caller).
@ __rotl32 i a i n → i { : i s & n 31 ^ ? == s 0 ( __w32 a ) ( __w32 | << ( __u32 a ) s >> ( __u32 a ) - 32 s ) }
@ __rotr32 i a i n → i { ^ ( __rotl32 a - 32 & n 31 ) }
@ __rotl64 i a i n → i { : i s & n 63 ^ ? == s 0 a | << a s ( __lshr64 a - 64 s ) }
@ __rotr64 i a i n → i { ^ ( __rotl64 a - 64 & n 63 ) }

// Count leading / trailing zeros and population count.
@ __clz32 i x → i { : i v ( __u32 x ) ? == v 0 { ^ 32 } {} : ~ i n 0 : ~ i k 31 ~ & >= k 0 == 0 & >> v k 1 { = n + n 1 = k - k 1 } ^ n }
@ __ctz32 i x → i { : i v ( __u32 x ) ? == v 0 { ^ 32 } {} : ~ i n 0 : ~ i k 0 ~ & < k 32 == 0 & >> v k 1 { = n + n 1 = k + k 1 } ^ n }
@ __popc32 i x → i { : i v ( __u32 x ) : ~ i n 0 : ~ i k 0 ~ < k 32 { = n + n & >> v k 1 = k + k 1 } ^ n }
@ __clz64 i x → i { ? == x 0 { ^ 64 } {} : ~ i n 0 : ~ i k 63 ~ & >= k 0 == 0 & ( __lshr64 x k ) 1 { = n + n 1 = k - k 1 } ^ n }
@ __ctz64 i x → i { ? == x 0 { ^ 64 } {} : ~ i n 0 : ~ i k 0 ~ & < k 64 == 0 & ( __lshr64 x k ) 1 { = n + n 1 = k + k 1 } ^ n }
@ __popc64 i x → i { : ~ i n 0 : ~ i k 0 ~ < k 64 { = n + n & ( __lshr64 x k ) 1 = k + k 1 } ^ n }

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
        ? == op 56 { ( __mem_store it ea 4 val ) } {}  // f32.store
        ? == op 57 { ( __mem_store it ea 8 val ) } {}  // f64.store
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
    ? == op 42 { ( __push it ( __mem_load it ea 4 0 ) ) } {}  // f32.load (raw 4-byte pattern)
    ? == op 43 { ( __push it ( __mem_load it ea 8 0 ) ) } {}  // f64.load
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
    ? | . it trap . it exited { ^ v } {}
    : *Module m # *Module . it mod
    // Imported functions occupy the low indices → dispatch to the host (WASI).
    ? < fidx . m num_import_funcs {
        : s wp ?? ( vec_get [s] . m imports fidx ) { T x → x F → # s 0 }
        ? != # i wp 0 { : *WImport w # *WImport wp ( __wasi_dispatch it . w field ) } { = . it trap T }
        ^ v
    } {}
    : s fp ?? ( vec_get [s] . m funcs - fidx . m num_import_funcs ) { T x → x F → # s 0 }
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

    ~ & & ! ret ! . it exited & ! . it trap < . c pos . f code_end {
        : i op ( wc_u8 c )
        ( __exec_op it m c ctrl locals op )
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
    ? == op 14 {  // br_table: read n labels + default, branch to labels[idx] or default
        : i n ( wc_uleb c )
        : i ui ( __u32 ( __pop it ) )
        : i pick ? < ui n ui n
        : ~ i chosen 0
        : ~ i k 0
        ~ <= k n { : i t ( wc_uleb c ) ? == k pick { = chosen t } {} = k + k 1 }
        ( __do_branch it ctrl c chosen )
        ^ v
    } {}
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
    ? == op 67 { ( __push it ( __read_le c 4 ) ) ^ v } {}  // f32.const (raw 4-byte pattern)
    ? == op 68 { ( __push it ( __read_le c 8 ) ) ^ v } {}  // f64.const (raw 8-byte pattern)
    // ── linear memory (loads/stores, size/grow) ──
    ? & >= op 40 <= op 64 { ( __exec_mem it c op ) ^ v } {}
    // ── floats: cmp (91..102), unary/binary (139..166), conversions (167..191) ──
    ? | & >= op 91 <= op 102 | & >= op 139 <= op 166 & >= op 167 <= op 191 { ( __exec_float it op ) ^ v } {}
    // ── sign-extension ops (0xc0..0xc4) and the 0xfc prefix (bulk memory) ──
    ? & >= op 192 <= op 196 { ( __exec_signext it op ) ^ v } {}
    ? == op 252 { ( __exec_fc it c ) ^ v } {}
    // ── the rest: integer numeric ops ──
    ( __exec_num it c op )
}

// Numeric/comparison/bitwise ops (both i32 and i64). i32 results are wrapped to
// 32 bits; comparisons push 0/1.
@ __exec_num * Interp it * Wc c i op → v {
    // i32 unary: eqz
    ? == op 69 { ( __push it ? == ( __pop it ) 0 1 0 ) ^ v } {}
    // i64 unary: eqz
    ? == op 80 { ( __push it ? == ( __pop it ) 0 1 0 ) ^ v } {}
    // i32/i64 unary: clz / ctz / popcnt
    ? == op 103 { ( __push it ( __clz32 ( __pop it ) ) ) ^ v } {}
    ? == op 104 { ( __push it ( __ctz32 ( __pop it ) ) ) ^ v } {}
    ? == op 105 { ( __push it ( __popc32 ( __pop it ) ) ) ^ v } {}
    ? == op 121 { ( __push it ( __clz64 ( __pop it ) ) ) ^ v } {}
    ? == op 122 { ( __push it ( __ctz64 ( __pop it ) ) ) ^ v } {}
    ? == op 123 { ( __push it ( __popc64 ( __pop it ) ) ) ^ v } {}
    // (i32.wrap_i64 / i64.extend_i32_* live in __exec_float's conversion block)
    // binary ops: pop b, a
    : i b ( __pop it )
    : i a ( __pop it )
    // ── i32 comparisons (0x46..0x4f) ──
    ? == op 70 { ( __push it ? == ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 71 { ( __push it ? != ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 72 { ( __push it ? < ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 73 { ( __push it ? < ( __u32 a ) ( __u32 b ) 1 0 ) ^ v } {}  // lt_u
    ? == op 74 { ( __push it ? > ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 75 { ( __push it ? > ( __u32 a ) ( __u32 b ) 1 0 ) ^ v } {}  // gt_u
    ? == op 76 { ( __push it ? <= ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 77 { ( __push it ? <= ( __u32 a ) ( __u32 b ) 1 0 ) ^ v } {}  // le_u
    ? == op 78 { ( __push it ? >= ( __w32 a ) ( __w32 b ) 1 0 ) ^ v } {}
    ? == op 79 { ( __push it ? >= ( __u32 a ) ( __u32 b ) 1 0 ) ^ v } {}  // ge_u
    // ── i32 arithmetic/bitwise (0x6a..0x78) → wrap 32 ──
    ? == op 106 { ( __push it ( __w32 + a b ) ) ^ v } {}
    ? == op 107 { ( __push it ( __w32 - a b ) ) ^ v } {}
    ? == op 108 { ( __push it ( __w32 * a b ) ) ^ v } {}
    ? == op 109 { ( __push it ( __w32 ( __idiv ( __w32 a ) ( __w32 b ) ) ) ) ^ v } {}
    ? == op 110 { ( __push it ( __w32 ( __idiv ( __u32 a ) ( __u32 b ) ) ) ) ^ v } {}  // div_u
    ? == op 111 { ( __push it ( __w32 ( __irem ( __w32 a ) ( __w32 b ) ) ) ) ^ v } {}
    ? == op 112 { ( __push it ( __w32 ( __irem ( __u32 a ) ( __u32 b ) ) ) ) ^ v } {}  // rem_u
    ? == op 113 { ( __push it ( __w32 & a b ) ) ^ v } {}
    ? == op 114 { ( __push it ( __w32 | a b ) ) ^ v } {}
    ? == op 115 { ( __push it ( __w32 ^^ a b ) ) ^ v } {}
    ? == op 116 { ( __push it ( __w32 << a & b 31 ) ) ^ v } {}
    ? == op 117 { ( __push it ( __w32 >> ( __w32 a ) & b 31 ) ) ^ v } {}  // shr_s
    ? == op 118 { ( __push it ( __w32 >> ( __u32 a ) & b 31 ) ) ^ v } {}  // shr_u
    ? == op 119 { ( __push it ( __rotl32 a b ) ) ^ v } {}  // rotl
    ? == op 120 { ( __push it ( __rotr32 a b ) ) ^ v } {}  // rotr
    // ── i64 comparisons (0x51..0x5a) ──
    ? == op 81 { ( __push it ? == a b 1 0 ) ^ v } {}
    ? == op 82 { ( __push it ? != a b 1 0 ) ^ v } {}
    ? == op 83 { ( __push it ? < a b 1 0 ) ^ v } {}
    ? == op 84 { ( __push it ? ( __ultb a b ) 1 0 ) ^ v } {}  // lt_u
    ? == op 85 { ( __push it ? > a b 1 0 ) ^ v } {}
    ? == op 86 { ( __push it ? ( __ultb b a ) 1 0 ) ^ v } {}  // gt_u
    ? == op 87 { ( __push it ? <= a b 1 0 ) ^ v } {}
    ? == op 88 { ( __push it ? ! ( __ultb b a ) 1 0 ) ^ v } {}  // le_u
    ? == op 89 { ( __push it ? >= a b 1 0 ) ^ v } {}
    ? == op 90 { ( __push it ? ! ( __ultb a b ) 1 0 ) ^ v } {}  // ge_u
    // ── i64 arithmetic/bitwise (0x7c..0x8a) ──
    ? == op 124 { ( __push it + a b ) ^ v } {}
    ? == op 125 { ( __push it - a b ) ^ v } {}
    ? == op 126 { ( __push it * a b ) ^ v } {}
    ? == op 127 { ( __push it ( __idiv a b ) ) ^ v } {}
    ? == op 128 { ( __push it ( __udiv64 a b ) ) ^ v } {}  // div_u
    ? == op 129 { ( __push it ( __irem a b ) ) ^ v } {}
    ? == op 130 { ( __push it ( __urem64 a b ) ) ^ v } {}  // rem_u
    ? == op 131 { ( __push it & a b ) ^ v } {}
    ? == op 132 { ( __push it | a b ) ^ v } {}
    ? == op 133 { ( __push it ^^ a b ) ^ v } {}
    ? == op 134 { ( __push it << a & b 63 ) ^ v } {}
    ? == op 135 { ( __push it >> a & b 63 ) ^ v } {}  // shr_s
    ? == op 136 { ( __push it ( __lshr64 a & b 63 ) ) ^ v } {}  // shr_u
    ? == op 137 { ( __push it ( __rotl64 a b ) ) ^ v } {}  // rotl
    ? == op 138 { ( __push it ( __rotr64 a b ) ) ^ v } {}  // rotr
    // unsupported opcode → trap
    = . it trap T
    = . it trapmsg ( bytes_from_str `unsupported opcode` )
}

// ── floats (values held as their IEEE-754 bit pattern in the i64 cell) ──
// abs/neg/copysign are done on the bits (NaN-sign correct); the rest reinterpret
// via std/floatbits, compute with libm / native float arithmetic, and re-encode.

@ __f64_unary * Interp it i op → v {
    : i ab ( __pop it )
    ? == op 153 { ( __push it & ab 9223372036854775807 ) ^ v } {}  // f64.abs (clear sign)
    ? == op 154 { ( __push it ^^ ab -9223372036854775808 ) ^ v } {}  // f64.neg (flip sign)
    : f x ( bits_to_f64 ab )
    ? == op 155 { ( __push it ( f64_to_bits ( ceil x ) ) ) ^ v } {}  // f64.ceil
    ? == op 156 { ( __push it ( f64_to_bits ( floor x ) ) ) ^ v } {}  // f64.floor
    ? == op 157 { ( __push it ( f64_to_bits ( trunc x ) ) ) ^ v } {}  // f64.trunc
    ? == op 158 { ( __push it ( f64_to_bits ( rint x ) ) ) ^ v } {}  // f64.nearest
    ? == op 159 { ( __push it ( f64_to_bits ( sqrt x ) ) ) ^ v } {}  // f64.sqrt
}

@ __f64_binary * Interp it i op → v {
    : i bb ( __pop it )
    : i ab ( __pop it )
    ? == op 166 { ( __push it | & ab 9223372036854775807 & bb -9223372036854775808 ) ^ v } {}  // copysign
    : f a ( bits_to_f64 ab )
    : f b ( bits_to_f64 bb )
    ? == op 160 { ( __push it ( f64_to_bits + a b ) ) ^ v } {}
    ? == op 161 { ( __push it ( f64_to_bits - a b ) ) ^ v } {}
    ? == op 162 { ( __push it ( f64_to_bits * a b ) ) ^ v } {}
    ? == op 163 { ( __push it ( f64_to_bits / a b ) ) ^ v } {}
    ? == op 164 { ( __push it ( f64_to_bits ? < a b a b ) ) ^ v } {}  // min (NaN-naive)
    ? == op 165 { ( __push it ( f64_to_bits ? > a b a b ) ) ^ v } {}  // max
}

@ __f64_cmp * Interp it i op → v {
    : f b ( bits_to_f64 ( __pop it ) )
    : f a ( bits_to_f64 ( __pop it ) )
    ? == op 97 { ( __push it ? == a b 1 0 ) ^ v } {}
    ? == op 98 { ( __push it ? != a b 1 0 ) ^ v } {}
    ? == op 99 { ( __push it ? < a b 1 0 ) ^ v } {}
    ? == op 100 { ( __push it ? > a b 1 0 ) ^ v } {}
    ? == op 101 { ( __push it ? <= a b 1 0 ) ^ v } {}
    ? == op 102 { ( __push it ? >= a b 1 0 ) ^ v } {}
}

@ __f32_unary * Interp it i op → v {
    : i ab ( __pop it )
    ? == op 139 { ( __push it & ab 2147483647 ) ^ v } {}  // f32.abs
    ? == op 140 { ( __push it & ^^ ab 2147483648 4294967295 ) ^ v } {}  // f32.neg
    : f x # f ( bits_to_f32 ab )
    ? == op 141 { ( __push it ( f32_to_bits # f32 ( ceil x ) ) ) ^ v } {}
    ? == op 142 { ( __push it ( f32_to_bits # f32 ( floor x ) ) ) ^ v } {}
    ? == op 143 { ( __push it ( f32_to_bits # f32 ( trunc x ) ) ) ^ v } {}
    ? == op 144 { ( __push it ( f32_to_bits # f32 ( rint x ) ) ) ^ v } {}
    ? == op 145 { ( __push it ( f32_to_bits # f32 ( sqrt x ) ) ) ^ v } {}
}

@ __f32_binary * Interp it i op → v {
    : i bb ( __pop it )
    : i ab ( __pop it )
    ? == op 152 { ( __push it & | & ab 2147483647 & bb 2147483648 4294967295 ) ^ v } {}  // copysign
    : f32 a ( bits_to_f32 ab )
    : f32 b ( bits_to_f32 bb )
    ? == op 146 { ( __push it ( f32_to_bits + a b ) ) ^ v } {}
    ? == op 147 { ( __push it ( f32_to_bits - a b ) ) ^ v } {}
    ? == op 148 { ( __push it ( f32_to_bits * a b ) ) ^ v } {}
    ? == op 149 { ( __push it ( f32_to_bits / a b ) ) ^ v } {}
    ? == op 150 { ( __push it ( f32_to_bits ? < a b a b ) ) ^ v } {}
    ? == op 151 { ( __push it ( f32_to_bits ? > a b a b ) ) ^ v } {}
}

@ __f32_cmp * Interp it i op → v {
    : f32 b ( bits_to_f32 ( __pop it ) )
    : f32 a ( bits_to_f32 ( __pop it ) )
    ? == op 91 { ( __push it ? == a b 1 0 ) ^ v } {}
    ? == op 92 { ( __push it ? != a b 1 0 ) ^ v } {}
    ? == op 93 { ( __push it ? < a b 1 0 ) ^ v } {}
    ? == op 94 { ( __push it ? > a b 1 0 ) ^ v } {}
    ? == op 95 { ( __push it ? <= a b 1 0 ) ^ v } {}
    ? == op 96 { ( __push it ? >= a b 1 0 ) ^ v } {}
}

// Float ops + all int/float conversions. Reinterpret (0xbc..0xbf) is a no-op
// because values already live as their bit pattern.
@ __exec_float * Interp it i op → v {
    ? == op 167 { ( __push it ( __w32 ( __pop it ) ) ) ^ v } {}  // i32.wrap_i64
    ? == op 172 { ( __push it ( __w32 ( __pop it ) ) ) ^ v } {}  // i64.extend_i32_s
    ? == op 173 { ( __push it & ( __pop it ) 4294967295 ) ^ v } {}  // i64.extend_i32_u
    ? & >= op 188 <= op 191 { ^ v } {}  // *.reinterpret_* : no-op
    ? == op 168 { ( __push it ( __w32 # i # f ( bits_to_f32 ( __pop it ) ) ) ) ^ v } {}  // i32.trunc_f32_s
    ? == op 169 { ( __push it ( __w32 # i # f ( bits_to_f32 ( __pop it ) ) ) ) ^ v } {}  // i32.trunc_f32_u (approx)
    ? == op 170 { ( __push it ( __w32 # i ( bits_to_f64 ( __pop it ) ) ) ) ^ v } {}  // i32.trunc_f64_s
    ? == op 171 { ( __push it ( __w32 # i ( bits_to_f64 ( __pop it ) ) ) ) ^ v } {}  // i32.trunc_f64_u (approx)
    ? | == op 174 == op 175 { ( __push it # i # f ( bits_to_f32 ( __pop it ) ) ) ^ v } {}  // i64.trunc_f32_*
    ? | == op 176 == op 177 { ( __push it # i ( bits_to_f64 ( __pop it ) ) ) ^ v } {}  // i64.trunc_f64_*
    ? == op 178 { ( __push it ( f32_to_bits # f32 ( __w32 ( __pop it ) ) ) ) ^ v } {}  // f32.convert_i32_s
    ? == op 179 { ( __push it ( f32_to_bits # f32 & ( __pop it ) 4294967295 ) ) ^ v } {}  // f32.convert_i32_u
    ? | == op 180 == op 181 { ( __push it ( f32_to_bits # f32 ( __pop it ) ) ) ^ v } {}  // f32.convert_i64_*
    ? == op 182 { ( __push it ( f32_to_bits # f32 ( bits_to_f64 ( __pop it ) ) ) ) ^ v } {}  // f32.demote_f64
    ? == op 183 { ( __push it ( f64_to_bits # f ( __w32 ( __pop it ) ) ) ) ^ v } {}  // f64.convert_i32_s
    ? == op 184 { ( __push it ( f64_to_bits # f & ( __pop it ) 4294967295 ) ) ^ v } {}  // f64.convert_i32_u
    ? | == op 185 == op 186 { ( __push it ( f64_to_bits # f ( __pop it ) ) ) ^ v } {}  // f64.convert_i64_*
    ? == op 187 { ( __push it ( f64_to_bits # f # f ( bits_to_f32 ( __pop it ) ) ) ) ^ v } {}  // f64.promote_f32
    ? & >= op 153 <= op 159 { ( __f64_unary it op ) ^ v } {}
    ? & >= op 160 <= op 166 { ( __f64_binary it op ) ^ v } {}
    ? & >= op 97 <= op 102 { ( __f64_cmp it op ) ^ v } {}
    ? & >= op 139 <= op 145 { ( __f32_unary it op ) ^ v } {}
    ? & >= op 146 <= op 152 { ( __f32_binary it op ) ^ v } {}
    ? & >= op 91 <= op 96 { ( __f32_cmp it op ) ^ v } {}
    = . it trap T
    = . it trapmsg ( bytes_from_str `unsupported float opcode` )
}

// ── WASI host functions (wasi_snapshot_preview1) ─────────────────
// Each takes its args from the value stack (last arg on top) and pushes the
// i32 errno result. Pointer args index linear memory.

@ __feq ( Vec u ) field s name → b {
    : i n ( vec_len [u] field )
    ? != n ( nurl_str_len name ) { ^ F } {}
    : ~ b eq T : ~ i k 0
    ~ & eq < k n {
        ? != ?? ( vec_get [u] field k ) { T x → # i x F → -1 } ( nurl_str_get name k ) { = eq F } {}
        = k + k 1
    }
    ^ eq
}

@ __m_get_u32 * Interp it i a → i { ^ & ( __mem_load it a 4 0 ) 4294967295 }

@ __m_put_u32 * Interp it i a i val → v { ( __mem_store it a 4 val ) }

// Write `len` bytes of memory at `ptr` to fd: 1 stdout, 2 stderr, else a file
// descriptor's buffer (flushed to disk on close).
@ __wasi_write_bytes * Interp it i fd i ptr i len → v {
    ? <= len 0 { ^ v } {}
    : ( Vec u ) buf ( vec_with_cap [u] len )
    : ~ i k 0
    ~ < k len { ( vec_push [u] buf # u & ( __mem_load it + ptr k 1 0 ) 255 ) = k + k 1 }
    ? | == fd 1 == fd 2 {
        : String s ( bytes_to_str buf )
        ? == fd 2 { ( nurl_eprint ( string_data s ) ) } { ( nurl_print ( string_data s ) ) }
        ( string_free s )
    } {
        : s fp ( __fd_at it fd )
        ? != # i fp 0 { : *WFd f # *WFd fp = . f dirty T : i bn ( vec_len [u] buf ) : ~ i bi 0 ~ < bi bn { ( vec_push [u] . f data ?? ( vec_get [u] buf bi ) { T x → # i x F → 0 } ) = bi + bi 1 } } {}
    }
    ( vec_free [u] buf )
}

@ __wasi_proc_exit * Interp it → v {
    = . it exit_code ( __pop it )
    = . it exited T
}

@ __wasi_fd_write * Interp it → v {
    : i nwritten ( __pop it )
    : i iovs_len ( __pop it )
    : i iovs ( __pop it )
    : i fd ( __pop it )
    : ~ i total 0
    : ~ i i 0
    ~ < i iovs_len {
        : i bufp ( __m_get_u32 it + iovs * i 8 )
        : i buflen ( __m_get_u32 it + + iovs * i 8 4 )
        ( __wasi_write_bytes it fd bufp buflen )
        = total + total buflen
        = i + i 1
    }
    ( __m_put_u32 it nwritten total )
    ( __push it 0 )
}

// Fetch the fd record for descriptor `fd`, or #s 0 if out of range / closed.
@ __fd_at * Interp it i fd → s {
    ? | < fd 0 >= fd ( vec_len [s] . it fds ) { ^ # s 0 } {}
    ^ ?? ( vec_get [s] . it fds fd ) { T x → x F → # s 0 }
}

// Read `len` bytes of linear memory at `ptr` into a fresh byte vector.
@ __mem_slice * Interp it i ptr i len → ( Vec u ) {
    : ( Vec u ) b ( vec_with_cap [u] ? > len 0 len 1 )
    : ~ i k 0
    ~ < k len { ( vec_push [u] b # u & ( __mem_load it + ptr k 1 0 ) 255 ) = k + k 1 }
    ^ b
}

// path_open(dirfd, dirflags, path_ptr, path_len, oflags, rights_base,
//   rights_inheriting, fdflags, opened_fd_ptr) → errno. Opens a file under the
// preopened directory by slurping it into a new file descriptor.
@ __wasi_path_open * Interp it → v {
    : i ofd_p ( __pop it )
    ( __pop it )  // fdflags
    ( __pop it )  // fs_rights_inheriting (i64 cell)
    : i rights ( __pop it )  // fs_rights_base (i64 cell)
    : i oflags ( __pop it )
    : i path_len ( __pop it )
    : i path_p ( __pop it )
    ( __pop it )  // dirflags
    : i dirfd ( __pop it )
    : s dp ( __fd_at it dirfd )
    ? == # i dp 0 { ( __push it 8 ) ^ v } {}  // EBADF
    : *WFd d # *WFd dp
    ? != . d kind 2 { ( __push it 8 ) ^ v } {}  // not a preopen dir
    // join host dir + "/" + requested relative path
    : ( Vec u ) full ( vec_new [u] )
    : i hn ( vec_len [u] . d host )
    : ~ i k 0
    ~ < k hn { ( vec_push [u] full ?? ( vec_get [u] . d host k ) { T x → # i x F → 0 } ) = k + k 1 }
    ? & > hn 0 != ?? ( vec_get [u] . d host - hn 1 ) { T x → # i x F → 0 } 47 { ( vec_push [u] full # u 47 ) } {}
    : ( Vec u ) rel ( __mem_slice it path_p path_len )
    : i rn ( vec_len [u] rel )
    : ~ i j 0
    ~ < j rn { ( vec_push [u] full ?? ( vec_get [u] rel j ) { T x → # i x F → 0 } ) = j + j 1 }
    ( vec_free [u] rel )
    : i writing & oflags 9  // bit0 creat | bit3 trunc → opening to write
    : String hs ( bytes_to_str full )
    : ~ i rc 0
    ? != writing 0 {
        // create/truncate: start an empty writable buffer
        : *WFd nf # *WFd ( __mkfd 3 )
        ( vec_free [u] . nf host ) = . nf host ( bytes_from_str ( string_data hs ) )
        = . nf writable T
        ( __m_put_u32 it ofd_p ( vec_len [s] . it fds ) )
        ( vec_push [s] . it fds # s nf )
    } {
        : !( Vec u ) IoErr fr ( read_file_bytes ( string_data hs ) )
        ?? fr {
            T bytes → {
                : *WFd nf # *WFd ( __mkfd 3 )
                ( vec_free [u] . nf data ) = . nf data bytes
                ( vec_free [u] . nf host ) = . nf host ( bytes_from_str ( string_data hs ) )
                ( __m_put_u32 it ofd_p ( vec_len [s] . it fds ) )
                ( vec_push [s] . it fds # s nf )
            }
            F e → { = rc 44 }  // ENOENT
        }
    }
    ( string_free hs ) ( vec_free [u] full )
    ( __push it rc )
}

@ __wasi_fd_read * Interp it → v {
    : i nread_p ( __pop it )
    : i iovs_len ( __pop it )
    : i iovs ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __m_put_u32 it nread_p 0 ) ( __push it 0 ) ^ v } {}
    : *WFd f # *WFd fp
    ? != . f kind 3 { ( __m_put_u32 it nread_p 0 ) ( __push it 0 ) ^ v } {}  // stdin/dir → EOF
    : i dn ( vec_len [u] . f data )
    : ~ i total 0
    : ~ i iv 0
    ~ < iv iovs_len {
        : i bufp ( __m_get_u32 it + iovs * iv 8 )
        : i buflen ( __m_get_u32 it + + iovs * iv 8 4 )
        : ~ i c 0
        ~ & < c buflen < . f pos dn {
            ( __mem_store it + bufp c 1 ?? ( vec_get [u] . f data . f pos ) { T x → # i x F → 0 } )
            = . f pos + . f pos 1
            = c + c 1
        }
        = total + total c
        = iv + iv 1
    }
    ( __m_put_u32 it nread_p total )
    ( __push it 0 )
}

@ __wasi_fd_seek * Interp it → v {
    : i noff_p ( __pop it )
    : i whence ( __pop it )
    : i offset ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __mem_store it noff_p 8 0 ) ( __push it 0 ) ^ v } {}
    : *WFd f # *WFd fp
    : i dn ( vec_len [u] . f data )
    : i base ? == whence 0 0 ? == whence 1 . f pos dn  // SET / CUR / END
    : i np + base offset
    = . f pos ? < np 0 0 np
    ( __mem_store it noff_p 8 . f pos )
    ( __push it 0 )
}

@ __wasi_args_sizes_get * Interp it → v {
    : i bufsz_p ( __pop it )
    : i argc_p ( __pop it )
    : i argc ( vec_len [s] . it argv )
    : ~ i bufsz 0
    : ~ i k 0
    ~ < k argc {
        : *Arg a # *Arg ?? ( vec_get [s] . it argv k ) { T x → x F → # s 0 }
        = bufsz + bufsz + ( vec_len [u] . a bytes ) 1
        = k + k 1
    }
    ( __m_put_u32 it argc_p argc )
    ( __m_put_u32 it bufsz_p bufsz )
    ( __push it 0 )
}

@ __wasi_args_get * Interp it → v {
    : i buf_p ( __pop it )
    : i argv_p ( __pop it )
    : i argc ( vec_len [s] . it argv )
    : ~ i cur buf_p
    : ~ i k 0
    ~ < k argc {
        : *Arg a # *Arg ?? ( vec_get [s] . it argv k ) { T x → x F → # s 0 }
        ( __m_put_u32 it + argv_p * k 4 cur )
        : i blen ( vec_len [u] . a bytes )
        : ~ i j 0
        ~ < j blen { ( __mem_store it + cur j 1 ?? ( vec_get [u] . a bytes j ) { T x → # i x F → 0 } ) = j + j 1 }
        ( __mem_store it + cur blen 1 0 )  // NUL terminator
        = cur + cur + blen 1
        = k + k 1
    }
    ( __push it 0 )
}

@ __wasi_fd_prestat_get * Interp it → v {
    : i buf ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}  // EBADF: ends libc's preopen scan
    : *WFd f # *WFd fp
    ? != . f kind 2 { ( __push it 8 ) ^ v } {}
    ( __mem_store it buf 1 0 )  // pr_type = dir
    ( __m_put_u32 it + buf 4 ( vec_len [u] . f name ) )  // pr_name_len
    ( __push it 0 )
}

@ __wasi_fd_prestat_dir_name * Interp it → v {
    : i plen ( __pop it )
    : i pptr ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? == # i fp 0 { ( __push it 8 ) ^ v } {}
    : *WFd f # *WFd fp
    : i nn ( vec_len [u] . f name )
    : i n ? < plen nn plen nn
    : ~ i k 0
    ~ < k n { ( __mem_store it + pptr k 1 ?? ( vec_get [u] . f name k ) { T x → # i x F → 0 } ) = k + k 1 }
    ( __push it 0 )
}

// filetype byte for a fd kind: stdio→char device(2), dir→directory(3), file→regular(4).
@ __filetype_of i kind → i { ^ ? == kind 2 3 ? == kind 3 4 2 }

@ __wasi_fd_fdstat_get * Interp it → v {
    : i stat_p ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    : ~ i k 0
    ~ < k 24 { ( __mem_store it + stat_p k 1 0 ) = k + k 1 }
    : ~ i kind 1
    ? != # i fp 0 { : *WFd f # *WFd fp = kind . f kind } {}
    ( __mem_store it stat_p 1 ( __filetype_of kind ) )
    // grant all rights so libc never refuses an operation
    ( __mem_store it + stat_p 8 8 -1 )
    ( __mem_store it + stat_p 16 8 -1 )
    ( __push it 0 )
}

@ __wasi_fd_filestat_get * Interp it → v {
    : i st_p ( __pop it )
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    : ~ i k 0
    ~ < k 64 { ( __mem_store it + st_p k 1 0 ) = k + k 1 }
    ? != # i fp 0 {
        : *WFd f # *WFd fp
        ( __mem_store it + st_p 16 1 ( __filetype_of . f kind ) )  // filetype
        ( __mem_store it + st_p 32 8 ( vec_len [u] . f data ) )  // file size
    } {}
    ( __push it 0 )
}

@ __wasi_fd_close * Interp it → v {
    : i fd ( __pop it )
    : s fp ( __fd_at it fd )
    ? != # i fp 0 {
        : *WFd f # *WFd fp
        ? & . f writable . f dirty {  // flush a written file to disk
            : String hs ( bytes_to_str . f host )
            : !v IoErr wr ( write_file_bytes ( string_data hs ) . f data )
            ?? wr { T x → {} F e → {} }
            ( string_free hs )
        } {}
        ? >= fd 3 { ( __freefd fp ) ( vec_set [s] . it fds fd # s 0 ) } {}  // keep stdio
    } {}
    ( __push it 0 )
}

// environ_sizes_get / environ_get: no environment is exposed.
@ __wasi_environ_sizes_get * Interp it → v {
    : i bufsz_p ( __pop it )
    : i cnt_p ( __pop it )
    ( __m_put_u32 it cnt_p 0 ) ( __m_put_u32 it bufsz_p 0 )
    ( __push it 0 )
}

// clock_time_get(id, precision, time_ptr) → write 0; random_get(buf,len) → zeros.
@ __wasi_clock_time_get * Interp it → v {
    : i t_p ( __pop it )
    ( __pop it ) ( __pop it )  // precision (i64), clock id
    ( __mem_store it t_p 8 0 )
    ( __push it 0 )
}

@ __wasi_random_get * Interp it → v {
    : i len ( __pop it )
    : i buf ( __pop it )
    : ~ i k 0
    ~ < k len { ( __mem_store it + buf k 1 0 ) = k + k 1 }
    ( __push it 0 )
}

@ __wasi_dispatch * Interp it ( Vec u ) field → v {
    ? ( __feq field `proc_exit` ) { ( __wasi_proc_exit it ) ^ v } {}
    ? ( __feq field `fd_write` ) { ( __wasi_fd_write it ) ^ v } {}
    ? ( __feq field `fd_read` ) { ( __wasi_fd_read it ) ^ v } {}
    ? ( __feq field `fd_seek` ) { ( __wasi_fd_seek it ) ^ v } {}
    ? ( __feq field `fd_close` ) { ( __wasi_fd_close it ) ^ v } {}
    ? ( __feq field `path_open` ) { ( __wasi_path_open it ) ^ v } {}
    ? ( __feq field `args_sizes_get` ) { ( __wasi_args_sizes_get it ) ^ v } {}
    ? ( __feq field `args_get` ) { ( __wasi_args_get it ) ^ v } {}
    ? ( __feq field `fd_prestat_get` ) { ( __wasi_fd_prestat_get it ) ^ v } {}
    ? ( __feq field `fd_prestat_dir_name` ) { ( __wasi_fd_prestat_dir_name it ) ^ v } {}
    ? ( __feq field `fd_fdstat_get` ) { ( __wasi_fd_fdstat_get it ) ^ v } {}
    ? ( __feq field `fd_filestat_get` ) { ( __wasi_fd_filestat_get it ) ^ v } {}
    ? ( __feq field `environ_sizes_get` ) { ( __wasi_environ_sizes_get it ) ^ v } {}
    ? ( __feq field `environ_get` ) { ( __pop it ) ( __pop it ) ( __push it 0 ) ^ v } {}
    ? ( __feq field `clock_time_get` ) { ( __wasi_clock_time_get it ) ^ v } {}
    ? ( __feq field `random_get` ) { ( __wasi_random_get it ) ^ v } {}
    ? ( __feq field `fd_fdstat_set_flags` ) { ( __pop it ) ( __pop it ) ( __push it 0 ) ^ v } {}
    ? ( __feq field `sched_yield` ) { ( __push it 0 ) ^ v } {}
    = . it trap T
    = . it trapmsg ( bytes_from_str `unsupported wasi import` )
}

// ── sign-extension ops + 0xfc-prefixed bulk memory / saturating trunc ──

// Sign-extend the low `nbits` of v.
@ __sext i v i nbits → i {
    : i mask - << 1 nbits 1
    : i lo & v mask
    ? != 0 & lo << 1 - nbits 1 { ^ - lo << 1 nbits } { ^ lo }
}

@ __exec_signext * Interp it i op → v {
    : i x ( __pop it )
    ? == op 192 { ( __push it ( __w32 ( __sext x 8 ) ) ) ^ v } {}  // i32.extend8_s
    ? == op 193 { ( __push it ( __w32 ( __sext x 16 ) ) ) ^ v } {}  // i32.extend16_s
    ? == op 194 { ( __push it ( __sext x 8 ) ) ^ v } {}  // i64.extend8_s
    ? == op 195 { ( __push it ( __sext x 16 ) ) ^ v } {}  // i64.extend16_s
    ? == op 196 { ( __push it ( __sext x 32 ) ) ^ v } {}  // i64.extend32_s
}

@ __mem_copy * Interp it i dst i src i n → v {
    ? <= n 0 { ^ v } {}
    ? > dst src {
        : ~ i k - n 1
        ~ >= k 0 { ( __mem_store it + dst k 1 ( __mem_load it + src k 1 0 ) ) = k - k 1 }
    } {
        : ~ i k 0
        ~ < k n { ( __mem_store it + dst k 1 ( __mem_load it + src k 1 0 ) ) = k + k 1 }
    }
}

@ __mem_fill * Interp it i dst i val i n → v {
    : ~ i k 0
    ~ < k n { ( __mem_store it + dst k 1 val ) = k + k 1 }
}

@ __exec_fc * Interp it * Wc c → v {
    : i sub ( wc_uleb c )
    ? == sub 10 {  // memory.copy
        ( wc_u8 c ) ( wc_u8 c )
        : i n & ( __pop it ) 4294967295
        : i src & ( __pop it ) 4294967295
        : i dst & ( __pop it ) 4294967295
        ( __mem_copy it dst src n )
        ^ v
    } {}
    ? == sub 11 {  // memory.fill
        ( wc_u8 c )
        : i n & ( __pop it ) 4294967295
        : i val & ( __pop it ) 255
        : i dst & ( __pop it ) 4294967295
        ( __mem_fill it dst val n )
        ^ v
    } {}
    // saturating float→int truncation (0..7): approximated by plain truncation
    ? == sub 0 { ( __push it ( __w32 # i # f ( bits_to_f32 ( __pop it ) ) ) ) ^ v } {}
    ? == sub 1 { ( __push it ( __w32 # i # f ( bits_to_f32 ( __pop it ) ) ) ) ^ v } {}
    ? == sub 2 { ( __push it ( __w32 # i ( bits_to_f64 ( __pop it ) ) ) ) ^ v } {}
    ? == sub 3 { ( __push it ( __w32 # i ( bits_to_f64 ( __pop it ) ) ) ) ^ v } {}
    ? == sub 4 { ( __push it # i # f ( bits_to_f32 ( __pop it ) ) ) ^ v } {}
    ? == sub 5 { ( __push it # i # f ( bits_to_f32 ( __pop it ) ) ) ^ v } {}
    ? == sub 6 { ( __push it # i ( bits_to_f64 ( __pop it ) ) ) ^ v } {}
    ? == sub 7 { ( __push it # i ( bits_to_f64 ( __pop it ) ) ) ^ v } {}
    = . it trap T
    = . it trapmsg ( bytes_from_str `unsupported 0xfc op` )
}
