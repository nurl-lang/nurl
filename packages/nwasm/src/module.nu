// packages/nwasm/src/module.nu — WebAssembly binary decoder (pure NURL).
//
// Decodes a wasm32 module's structure: the magic/version header and the
// sections this runtime understands (type, function, table, memory, global,
// export, element, code, data). Imports and the custom/start sections are
// skipped. The byte cursor + LEB128 readers here are reused by the interpreter
// (interp.nu) to walk instruction streams.
//
// Memory model: a `Module` is a handle on the decoded module in an Arc
// (stdlib/std/arc.nu) — every copy is the same module, and the last owner
// releases it (module_free is an early release, optional). A `Wc` cursor is a
// plain value that owns nothing.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/slice.nu`

// ── byte cursor + LEB128 ─────────────────────────────────────────

// A cursor over bytes it does not own (the module image outlives it): a
// value in a mutable local, passed `inout`, so there is nothing to release.
// `len` is where the cursor's input ends (wc_eof / wc_avail; callers narrow
// it to one function body), `cap` the buffer's real end, which bounds every
// read — past it a read yields 0, as an out-of-range vec_get did.
: Wc { ( Slice u ) data i pos i len i cap }

@ wc_new ( Vec u ) buf → Wc {
    : i n ( vec_len [u] buf )
    ^ @ Wc { ( slice_from_vec [u] buf ) 0 n n }
}

// Nothing to release: a Wc owns no memory.
@ wc_free sink Wc c → v {}

@ wc_eof inout Wc c → b { ^ >= . c pos . c len }

@ wc_u8 inout Wc c → i {
    : i p . c pos
    = . c pos + p 1
    ? | < p 0 >= p . c cap { ^ 0 } {}
    ^ ( slice_byte . c data p )
}

@ wc_peek inout Wc c → i {
    : i p . c pos
    ? | < p 0 >= p . c cap { ^ 0 } {}
    ^ ( slice_byte . c data p )
}

// Unsigned LEB128 → i (NURL i is 64-bit, covers u32/u64).
//
// Only the first ten groups can carry a 64-bit value. A longer encoding
// is malformed wasm, and `<< x shift` with shift >= 64 is poison in LLVM
// (docs/spec.md, § operators) — a corrupted continuation byte turning a
// terminal group into a running one is exactly how a module reaches it.
// Groups past the tenth are consumed, so `pos` still lands after the
// encoding, but they contribute nothing: the value stays inside 64 bits
// and every caller's range check still sees a number it can judge.
@ wc_uleb inout Wc c → i {
    : ~ i result 0
    : ~ i shift 0
    : ~ b more T
    ~ more {
        : i b ( wc_u8 c )
        ? < shift 64 { = result | result << & b 127 shift } {}
        = shift + shift 7
        ? == 0 & b 128 { = more F } {}
    }
    ^ result
}

// Signed LEB128 → i (sign-extended).
@ wc_sleb inout Wc c → i {
    : ~ i result 0
    : ~ i shift 0
    : ~ i b 0
    : ~ b more T
    ~ more {
        = b ( wc_u8 c )
        ? < shift 64 { = result | result << & b 127 shift } {}
        = shift + shift 7
        ? == 0 & b 128 { = more F } {}
    }
    // sign-extend if the sign bit of the last group is set and we read < 64 bits
    ? & < shift 64 != 0 & b 64 { = result | result << -1 shift } {}
    ^ result
}

// Skip n bytes.
@ wc_skip inout Wc c i n → v { = . c pos + . c pos n }

// Bytes physically remaining in the input (never negative).
@ wc_avail inout Wc c → i { : i r - . c len . c pos ? < r 0 { ^ 0 } {} ^ r }

// ── module model ─────────────────────────────────────────────────

: FuncType { ( Vec i ) params ( Vec i ) results }

// A defined function: its type index, its declared (non-param) local valtypes
// expanded flat, and the [start,end) byte range of its instruction stream.
: WFunc { i typeidx ( Vec i ) locals i code_start i code_end }

: WExport { ( Vec u ) name i kind i index }

// A data segment. Active (passive=0): copied to memory at `offset` during
// instantiation. Passive (passive=1): source material for memory.init only.
: DataSeg { i offset ( Vec u ) bytes i passive }

// An element segment: function indices (−1 = null ref). Active segments are
// applied to the table at decode; passive ones feed table.init; declared
// (and applied active) ones count as dropped at instantiation.
: ElemSeg { ( Vec i ) funcs i passive }

// An owned byte buffer behind an opaque pointer (name-section entries).
: NameBuf { ( Vec u ) bytes }

// An imported function (the only import kind this runtime resolves): module +
// field name select the host (WASI) implementation; typeidx gives its
// signature. Non-function imports are a decode error (nothing satisfies them).
: WImport { ( Vec u ) module ( Vec u ) field i typeidx }

: ModuleImpl {
    ( Vec ( Box FuncType ) ) types
    ( Vec i ) functypes  // type index per defined function
    ( Vec ( Box WFunc ) ) funcs
    ( Vec ( Box WExport ) ) exports
    ( Vec u ) code  // the whole module byte image (functions index into it)
    i has_mem
    i mem_min  // initial pages (64 KiB each)
    i mem_max  // 0 if unbounded
    i mem_shared  // 1 = threads-proposal shared memory (max is mandatory)
    ( Vec ( Box DataSeg ) ) datas
    ( Vec i ) global_init  // initial value per global
    ( Vec i ) global_mut  // 1 if mutable
    i has_table
    ( Vec i ) table  // initial table image: function indices (−1 = null)
    i table_max  // declared table maximum (0 = none)
    ( Vec ( Box ElemSeg ) ) elems  // element segments, in order
    ( Vec ( Box WImport ) ) imports  // imported functions, in index order
    i num_import_funcs  // imported funcs occupy func indices 0..n-1
    i start_func  // start-section function index (-1 = none)
    ( Vec i ) name_idx  // function indices with a "name"-section entry…
    ( Vec ( Box NameBuf ) ) name_str  // …and their names, parallel (sparse)
    b ok
    ( Vec u ) err
}

// A Module is a handle on its decoded state in an Arc (stdlib/std/arc.nu):
// every copy is the same module, and the last owner releases it.
: Module { ( Arc ModuleImpl ) a }

@ Module_share Module h → Module { ^ @ Module { ( arc_clone [ModuleImpl] . h a ) } }

@ Module_drop sink Module h → v {}

// The decoded state, read-only (a Module is frozen once decoded).
@ module_impl Module h → ModuleImpl { ^ ( arc_get [ModuleImpl] . h a ) }

// The decoded state's address, for the interpreter's predecoded records,
// which point into it: nothing writes a decoded module, and an instance
// holds a share of it for as long as it runs.
unsafe @ _Module_ptr Module h → *ModuleImpl { ^ ( arc_ptr [ModuleImpl] . h a ) }

// The section records are boxed in their tables (a *FuncType, a *WFunc …
// into one stays put while the table grows); the last owner of the Module
// drops them with the tables.

// Let go of `m` now rather than at the end of its owner's scope.
@ module_free sink Module m → v {}

// Did the module decode? When not, module_err says why.
@ module_ok Module p__h → b {
    : ModuleImpl p ( module_impl p__h )
    ^ . p ok
}

// The decode error message (empty when module_ok) — the module's own bytes, lent.
@ module_err Module p__h → ( Vec u ) {
    : ModuleImpl p ( module_impl p__h )
    ^ . p err
}

// Imported functions occupy function indices 0 .. this-1.
@ module_num_import_funcs Module p__h → i {
    : ModuleImpl p ( module_impl p__h )
    ^ . p num_import_funcs
}

// Record a decode error (first error wins; frees the previous message).
@ __mod_err inout ModuleImpl m s msg → v {
    ? ! . m ok { ^ v } {}
    = . m ok F
    ( vec_free [u] . m err )
    = . m err ( bytes_from_str msg )
}

// Validate a decoded count/length against the bytes physically remaining.
// A vector of `cnt` items needs at least `cnt` bytes (every element occupies
// ≥ 1 byte on the wire); a raw byte-length needs exactly `cnt` bytes. Anything
// larger than the remaining input is a hostile / truncated count — reject the
// module (recording the first error) and return 0 so the caller's loop does
// not allocate or iterate on it. This single discipline bounds every
// decode-time allocation and loop to the size of the input, closing the
// unbounded-allocation / count-overflow class.
@ __chk_count inout Wc c inout ModuleImpl m i cnt s what → i {
    ? | < cnt 0 > cnt ( wc_avail c ) {
        ( __mod_err m what )
        ^ 0
    } {}
    ^ cnt
}

// Evaluate a constant init expr (i32/i64.const N … end). `global.get` in a
// constant expression may only reference an imported global (spec), and those
// are rejected at decode — so hitting one here is itself a decode error.
// Consumes through the trailing `end`.
@ __const_expr inout Wc c inout ModuleImpl m → i {
    : i op0 ( wc_u8 c )
    : ~ i val 0
    // Every immediate must be CONSUMED, not scanned over: an f32/f64 bit
    // pattern (or a ref.func index) may contain 0x0b, and a scanner that
    // stops there desyncs the whole section — every later global reads
    // garbage. Floats keep their raw bit patterns (the slot convention).
    ? | == op0 65 == op0 66 { = val ( wc_sleb c ) } {
        ? == op0 67 { : ~ i fk 0 ~ < fk 4 { = val | val << ( wc_u8 c ) * fk 8 = fk + fk 1 } } {  // f32.const: 4 raw bytes
            ? == op0 68 { : ~ i dk 0 ~ < dk 8 { = val | val << ( wc_u8 c ) * dk 8 = dk + dk 1 } } {  // f64.const: 8 raw bytes
                ? == op0 208 { ( wc_u8 c ) = val -1 } {  // ref.null ht → null
                    ? == op0 210 { = val ( wc_uleb c ) } {  // ref.func n
                        ? == op0 35 { ( wc_uleb c ) ( __mod_err m `constant expression uses global.get (imported globals unsupported)` ) } {} } } } } }
    // Consume through the terminating 0x0b `end`. Bounded by EOF: past the end
    // of input wc_u8 returns 0 forever, so an unterminated expression must not
    // spin — a truncated global/data/elem offset expr is a decode error.
    : ~ b done F
    ~ & ! done ! ( wc_eof c ) { ? == ( wc_u8 c ) 11 { = done T } {} }
    ? ! done { ( __mod_err m `truncated constant expression (no end)` ) } {}
    ^ val
}

// ── section decoders ─────────────────────────────────────────────

@ __read_functype inout Wc c inout ModuleImpl m → ( Box FuncType ) {
    ( wc_u8 c )  // 0x60 form byte (assumed)
    : i np ( __chk_count c m ( wc_uleb c ) `bad param count` )
    : ( Vec i ) params ( vec_new [i] )
    : ~ i a 0
    ~ < a np { ( vec_push [i] params ( wc_u8 c ) ) = a + a 1 }
    : i nr ( __chk_count c m ( wc_uleb c ) `bad result count` )
    : ( Vec i ) results ( vec_new [i] )
    : ~ i b 0
    ~ < b nr { ( vec_push [i] results ( wc_u8 c ) ) = b + b 1 }
    ^ ( box_new [FuncType] @ FuncType { params results } )
}

@ __decode_type_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad type count` )
    : ~ i k 0
    ~ < k n { ( vec_push [( Box FuncType )] . m types ( __read_functype c m ) ) = k + k 1 }
}

@ __decode_func_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad function count` )
    : ~ i k 0
    ~ < k n { ( vec_push [i] . m functypes ( wc_uleb c ) ) = k + k 1 }
}

@ __decode_export_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad export count` )
    : ~ i k 0
    ~ < k n {
        : i nl ( __chk_count c m ( wc_uleb c ) `bad export name length` )
        : ( Vec u ) nm ( vec_new [u] )
        : ~ i a 0
        ~ < a nl { ( vec_push [u] nm ( wc_u8 c ) ) = a + a 1 }
        : i kind ( wc_u8 c )
        : i idx ( wc_uleb c )
        ( vec_push [( Box WExport )] . m exports ( box_new [WExport] @ WExport { nm kind idx } ) )
        = k + k 1
    }
}

// Memory section: limits (flag, min [, max]). Records the first memory.
// flag bit 0 = a maximum follows; bit 1 = SHARED (the threads proposal),
// where the maximum is mandatory because every thread must agree on where
// the buffer can end.
@ __decode_mem_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad memory count` )
    : ~ i k 0
    ~ < k n {
        : i flag ( wc_u8 c )
        : ~ i mn ( wc_uleb c )
        : i mx ? != 0 & flag 1 ( wc_uleb c ) 0
        : i shared ? != 0 & flag 2 1 0
        ? & != shared 0 == mx 0 { ( __mod_err m `shared memory without a maximum` ) } {}
        // wasm32 caps a memory at 65536 pages (4 GiB). A larger declared
        // minimum would make instantiation allocate past the address space —
        // reject it here rather than OOM/hang trying to zero-fill it.
        ? | < mn 0 > mn 65536 { ( __mod_err m `memory minimum exceeds wasm32 limit` ) = mn 0 } {}
        ? == k 0 { = . m has_mem 1 = . m mem_min mn = . m mem_max mx = . m mem_shared shared } {}
        = k + k 1
    }
}

// Data section: active segments (flag 0/2) carry an i32.const offset expr then
// raw bytes; passive segments (flag 1) carry bytes only (memory.init source).
@ __decode_data_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad data count` )
    : ~ i k 0
    ~ < k n {
        : i flag ( wc_uleb c )
        ? == flag 2 { ( wc_uleb c ) } {}  // explicit memidx
        : i offset ? != flag 1 ( __const_expr c m ) 0
        : i blen ( __chk_count c m ( wc_uleb c ) `bad data segment length` )
        // One memcpy for the payload. `__chk_count` has already bounded
        // blen by the bytes that remain, so the source range is in-bounds;
        // a push per byte cost nurlc.wasm 110 000 of them.
        : ( Vec u ) bytes ( slice_to_vec [u] ( slice_window [u] . c data . c pos blen ) )
        ( wc_skip c blen )
        // An active segment is copied into the INITIAL memory at
        // instantiation, so whether it fits is decidable right here: the
        // offset and the length are both in hand and the declared minimum
        // cannot shrink. The spec makes an overhanging segment an
        // instantiation failure; saying so at decode keeps it one clean
        // rejection instead of a half-built instance.
        ? == flag 1 {} {
            ? | < offset 0 > offset - * . m mem_min 65536 blen {
                ( __mod_err m `data segment does not fit in linear memory` )
            } {}
        }
        : i passive ? == flag 1 1 0
        ( vec_push [( Box DataSeg )] . m datas ( box_new [DataSeg] @ DataSeg { offset bytes passive } ) )
        = k + k 1
    }
}

// Import section: record imported FUNCTIONS (module + field name resolve to a
// host/WASI implementation at call time). A table / memory / global import is
// a hard decode error — this runtime has nothing to satisfy it with, and
// running anyway would silently corrupt the module's own state.
@ __decode_import_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad import count` )
    : ~ i k 0
    ~ < k n {
        : i mlen ( __chk_count c m ( wc_uleb c ) `bad import module length` )
        : ( Vec u ) mnm ( vec_with_cap [u] mlen )
        : ~ i b 0
        ~ < b mlen { ( vec_push [u] mnm ( wc_u8 c ) ) = b + b 1 }
        : i flen ( __chk_count c m ( wc_uleb c ) `bad import field length` )
        : ( Vec u ) fld ( vec_with_cap [u] flen )
        : ~ i a 0
        ~ < a flen { ( vec_push [u] fld ( wc_u8 c ) ) = a + a 1 }
        : i kind ( wc_u8 c )
        ? == kind 0 {
            : i ti ( wc_uleb c )
            ( vec_push [( Box WImport )] . m imports ( box_new [WImport] @ WImport { mnm fld ti } ) )
            = . m num_import_funcs + . m num_import_funcs 1
        } {
            ( vec_free [u] mnm )
            ( vec_free [u] fld )
            ? . m ok {
                = . m ok F
                = . m err ( bytes_from_str ? == kind 1 `unsupported import: table` ? == kind 2 `unsupported import: memory` ? == kind 3 `unsupported import: global` `unsupported import kind` )
            } {}
            // consume the entry's immediates so the cursor stays coherent
            ? == kind 1 { ( wc_u8 c ) : i fl ( wc_u8 c ) ( wc_uleb c ) ? == fl 1 { ( wc_uleb c ) } {} } {
                ? == kind 2 { : i fl ( wc_u8 c ) ( wc_uleb c ) ? == fl 1 { ( wc_uleb c ) } {} } {
                    ? == kind 3 { ( wc_u8 c ) ( wc_u8 c ) } {} } }
        }
        = k + k 1
    }
}

// Global section: each global = valtype, mutability, const init expr.
@ __decode_global_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad global count` )
    : ~ i k 0
    ~ < k n {
        ( wc_u8 c )  // valtype
        : i mut ( wc_u8 c )
        ( vec_push [i] . m global_init ( __const_expr c m ) )
        ( vec_push [i] . m global_mut mut )
        = k + k 1
    }
}

// Table section: allocate the first table (size = min, slots null = −1),
// recording its declared maximum for table.grow. funcref and externref
// tables share the representation: entries are function indices or −1
// for null — and without the GC proposal a module can only ever put
// null (ref.null extern) into an externref table, so −1 covers it.
@ __decode_table_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad table count` )
    // One table is materialised; accepting more would let table-1 ops
    // silently operate on table 0 — reject instead of misexecute.
    ? > n 1 { ( __mod_err m `multiple tables unsupported` ) } {}
    : ~ i k 0
    ~ < k n {
        : i et ( wc_u8 c )  // elemtype: 0x70 funcref / 0x6f externref
        ? & != et 112 != et 111 { ( __mod_err m `unsupported table element type` ) } {}
        : i flag ( wc_u8 c )
        : ~ i mn ( wc_uleb c )
        : i mx ? == flag 1 ( wc_uleb c ) 0
        // A table's initial size is materialised as a null-filled image; cap it
        // to the same 10M-slot ceiling table.grow enforces so a bogus minimum
        // cannot exhaust memory at decode.
        ? | < mn 0 > mn 10000000 { ( __mod_err m `table minimum exceeds limit` ) = mn 0 } {}
        ? == k 0 {
            = . m has_table 1
            = . m table_max mx
            : ~ i j 0
            ~ < j mn { ( vec_push [i] . m table -1 ) = j + j 1 }
        } {}
        = k + k 1
    }
}

// One element expression: (ref.func N end) → N, (ref.null ht end) → −1.
@ __elem_expr inout Wc c → i {
    : i op ( wc_u8 c )
    : ~ i val -1
    ? == op 210 { = val ( wc_uleb c ) } {  // ref.func
        ? == op 208 { ( wc_u8 c ) } {} }  // ref.null: heap type byte
    // Consume through the terminating 0x0b; bounded by EOF (see __const_expr).
    : ~ b done F
    ~ & ! done ! ( wc_eof c ) { ? == ( wc_u8 c ) 11 { = done T } {} }
    ^ val
}

// Element section, all MVP+reftype encodings (flags 0–7):
//   bit0 passive/declared (1) vs active (0); bit1 explicit tableidx (active)
//   or declared (passive); bit2 element EXPRS instead of func indices.
// Active segments are applied to the table image here and then count as
// dropped; passive ones are stored for table.init.
@ __decode_elem_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad element count` )
    : ~ i k 0
    ~ < k n {
        : i flag ( wc_uleb c )
        : i active ? == & flag 1 0 1 0
        : ~ i off 0
        ? == active 1 {
            ? == & flag 2 2 { ? != 0 ( wc_uleb c ) { ( __mod_err m `element segment targets a nonzero table` ) } {} } {}  // explicit table index
            = off ( __const_expr c m )
        } {}
        // elemkind / reftype byte is present unless flag is 0 or 4
        ? & != flag 0 != flag 4 { ( wc_u8 c ) } {}
        : i cnt ( __chk_count c m ( wc_uleb c ) `bad element entry count` )
        : ( Vec i ) funcs ( vec_with_cap [i] cnt )
        : ~ i j 0
        ~ < j cnt {
            ? >= flag 4 { ( vec_push [i] funcs ( __elem_expr c ) ) } { ( vec_push [i] funcs ( wc_uleb c ) ) }
            = j + j 1
        }
        ? == active 1 {
            // The spec makes an overhanging active segment an instantiation
            // failure — the offset is a u32, so a negative canonical i32 is
            // far out of bounds, and even an EMPTY segment must trap when
            // its offset lies past the table end. Same shape as the data-
            // segment check: decidable here, rejected here.
            : i uoff & off 4294967295
            ? > + uoff cnt ( vec_len [i] . m table ) {
                ( __mod_err m `element segment does not fit its table` )
            } {
                : ~ i a 0
                ~ < a cnt {
                    ( vec_set [i] . m table + uoff a ?? ( vec_get [i] funcs a ) { T x → x F → -1 } )
                    = a + a 1
                }
            }
        } {}
        // active (and declared, flag 3/7) segments are dropped at instantiation
        : i passive ? | == flag 1 == flag 5 1 0
        ( vec_push [( Box ElemSeg )] . m elems ( box_new [ElemSeg] @ ElemSeg { funcs passive } ) )
        = k + k 1
    }
}

// Code section: for each function, parse local declarations and record the
// [start,end) byte range of its instruction stream (ending at the final `end`).
@ __decode_code_sec inout Wc c inout ModuleImpl m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad code count` )
    : ~ i k 0
    ~ < k n {
        : i bodysize ( __chk_count c m ( wc_uleb c ) `bad function body size` )
        : i body_end + . c pos bodysize
        : i ndecl ( __chk_count c m ( wc_uleb c ) `bad local-declaration count` )
        : ( Vec i ) locals ( vec_new [i] )
        : ~ i d 0
        ~ < d ndecl {
            // A local run expands to `cnt` slots. Route the count through
            // `__chk_count` first: it is a LEB the module chose, so without
            // the bytes-remaining bound `vec_len + cnt` can overflow to a
            // negative and walk straight past the ceiling below — 2^62
            // pushes, which is a hang, not a decode error.
            : ~ i cnt ( __chk_count c m ( wc_uleb c ) `bad local run length` )
            : i ty ( wc_u8 c )
            // Cap the running total so a huge count cannot exhaust memory
            // building the locals vector.
            ? > + ( vec_len [i] locals ) cnt 1000000 { ( __mod_err m `too many locals` ) = cnt 0 } {}
            : ~ i j 0
            ~ < j cnt { ( vec_push [i] locals ty ) = j + j 1 }
            = d + d 1
        }
        : i code_start . c pos
        : i typeidx ?? ( vec_get [i] . m functypes k ) { T x → x F → 0 }
        ( vec_push [( Box WFunc )] . m funcs ( box_new [WFunc] @ WFunc { typeidx locals code_start body_end } ) )
        = . c pos body_end  // skip to next body
        = k + k 1
    }
}

// Custom section: if it is the "name" section, harvest subsection 1
// (function names) for diagnostics; anything else is skipped.
@ __decode_custom_sec inout Wc c inout ModuleImpl m i sec_end → v {
    : i nlen ( wc_uleb c )
    ? != nlen 4 { ^ v } {}
    : b isname & & & == ( wc_u8 c ) 110 == ( wc_u8 c ) 97 == ( wc_u8 c ) 109 == ( wc_u8 c ) 101
    ? ! isname { ^ v } {}
    ~ < . c pos sec_end {
        : i sub ( wc_u8 c )
        : i ssize ( wc_uleb c )
        // A negative (overlong-LEB) or over-long subsection size would drive
        // sub_end before pos and spin this loop; abandon the name section then.
        ? | < ssize 0 > ssize ( wc_avail c ) { = . c pos sec_end } {
            : i sub_end + . c pos ssize
            ? == sub 1 {  // function names: count, then (funcidx, name) pairs
                : i n ( __chk_count c m ( wc_uleb c ) `bad name count` )
                : ~ i k 0
                ~ < k n {
                    : i fi ( wc_uleb c )
                    : i ln ( __chk_count c m ( wc_uleb c ) `bad name length` )
                    : ( Vec u ) nm ( vec_with_cap [u] ln )
                    : ~ i a 0
                    ~ < a ln { ( vec_push [u] nm ( wc_u8 c ) ) = a + a 1 }
                    ( vec_push [i] . m name_idx fi )
                    ( vec_push [( Box NameBuf )] . m name_str ( box_new [NameBuf] @ NameBuf { nm } ) )
                    = k + k 1
                }
            } {}
            = . c pos sub_end }
    }
}

// The name-section name of function `fidx` as a fresh byte vector (empty if
// unknown). Cold path — linear scan is fine (used only for trap backtraces).
@ _module_func_name ModuleImpl m i fidx → ( Vec u ) {
    : i n ( vec_len [i] . m name_idx )
    : ~ i k 0
    ~ < k n {
        ? == ?? ( vec_get [i] . m name_idx k ) { T x → x F → -1 } fidx {
            ?? ( vec_get [( Box NameBuf )] . m name_str k ) {
                T bx → {
                    : NameBuf nb ( box_get [NameBuf] bx )
                    : ( Vec u ) out ( vec_with_cap [u] ( vec_len [u] . nb bytes ) )
                    : i bn ( vec_len [u] . nb bytes )
                    : ~ i b 0
                    ~ < b bn { ( vec_push [u] out ?? ( vec_get [u] . nb bytes b ) { T x → x F → # u 0 } ) = b + b 1 }
                    ^ out
                }
                F → {}
            }
        } {}
        = k + k 1
    }
    ^ ( vec_new [u] )
}

@ module_func_name Module m__h i fidx → ( Vec u ) { ^ ( _module_func_name ( module_impl m__h ) fidx ) }

// Decode a whole module. On error, module_ok is F and module_err says why.
// The module takes over `bytes` as its image (functions index into it).
@ module_decode sink ( Vec u ) bytes → Module {
    : ~ ModuleImpl m @ ModuleImpl {
        ( vec_new [( Box FuncType )] ) ( vec_new [i] ) ( vec_new [( Box WFunc )] ) ( vec_new [( Box WExport )] )
        ( vec_new [u] ) 0 0 0 0 ( vec_new [( Box DataSeg )] ) ( vec_new [i] ) ( vec_new [i] )
        0 ( vec_new [i] ) 0 ( vec_new [( Box ElemSeg )] ) ( vec_new [( Box WImport )] ) 0 -1
        ( vec_new [i] ) ( vec_new [( Box NameBuf )] ) T ( vec_new [u] )
    }
    // The image stays out of `m` while it is read (the cursor borrows it)
    // and becomes the module's code when the decode is done.
    ( __mod_decode_into m bytes )
    ^ @ Module { ( arc_new [ModuleImpl] m ) }
}

@ __mod_decode_into inout ModuleImpl m sink ( Vec u ) img → v {
    ( __mod_decode_sections m img )
    = . m code img
}

@ __mod_decode_sections inout ModuleImpl m ( Vec u ) img → v {
    : ~ Wc c ( wc_new img )
    // header: 00 61 73 6d 01 00 00 00
    ? < . c len 8 { ( __mod_err m `not a wasm module` ) ^ } {}
    ? ! & == ( wc_u8 c ) 0 & == ( wc_u8 c ) 97 & == ( wc_u8 c ) 115 == ( wc_u8 c ) 109 {
        ( __mod_err m `bad wasm magic` ) ^
    } {}
    ( wc_skip c 4 )  // version
    ~ & . m ok ! ( wc_eof c ) {
        : i id ( wc_u8 c )
        : i size ( wc_uleb c )
        // A section can be no larger than the input that remains, and never
        // negative. An over-long LEB (10 bytes, high bit set) decodes to a
        // negative i64; without the `< size 0` guard `pos + size` lands before
        // pos and the outer loop re-decodes earlier bytes forever.
        ? | < size 0 > size ( wc_avail c ) { ( __mod_err m `bad section size` ) = . c pos . c len } {}
        : i sec_end + . c pos size
        ? == id 0 { ( __decode_custom_sec c m sec_end ) } {}
        ? == id 1 { ( __decode_type_sec c m ) } {
            ? == id 2 { ( __decode_import_sec c m ) } {
                ? == id 3 { ( __decode_func_sec c m ) } {
                    ? == id 4 { ( __decode_table_sec c m ) } {
                        ? == id 5 { ( __decode_mem_sec c m ) } {
                            ? == id 6 { ( __decode_global_sec c m ) } {
                                ? == id 7 { ( __decode_export_sec c m ) } {
                                    ? == id 8 { = . m start_func ( wc_uleb c ) } {
                                        ? == id 9 { ( __decode_elem_sec c m ) } {
                                            ? == id 10 { ( __decode_code_sec c m ) } {
                                                ? == id 11 { ( __decode_data_sec c m ) } {} } } } } } } } } } }
        = . c pos sec_end  // robust against partially-read / skipped sections
    }
}

// Find an exported GLOBAL's index by name (-1 if absent). wasi-threads
// needs one: `__stack_pointer` is what gives a spawned thread its own
// stack, and only the host can set it before the thread's first call.
@ _module_export_global ModuleImpl m s name → i {
    : i n ( vec_len [( Box WExport )] . m exports )
    : ~ i found -1
    : ~ i k 0
    ~ & == found -1 < k n {
        ?? ( vec_get [( Box WExport )] . m exports k ) {
            T bx → {
                : WExport x ( box_get [WExport] bx )
                ? & == . x kind 3 ( __name_eq . x name name ) { = found . x index } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ found
}

@ module_export_global Module m__h s name → i { ^ ( _module_export_global ( module_impl m__h ) name ) }

// Find an exported function index by name (-1 if absent).
@ _module_export_func ModuleImpl m s name → i {
    : i n ( vec_len [( Box WExport )] . m exports )
    : ~ i found -1
    : ~ i k 0
    ~ & == found -1 < k n {
        ?? ( vec_get [( Box WExport )] . m exports k ) {
            T bx → {
                : WExport x ( box_get [WExport] bx )
                ? & == . x kind 0 ( __name_eq . x name name ) { = found . x index } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ found
}

@ module_export_func Module m__h s name → i { ^ ( _module_export_func ( module_impl m__h ) name ) }

// The *FuncType of any function index — imported (low indices) or defined —
// as an opaque pointer; #s 0 if out of range.
// (`inout` only so the record is passed by address: it is read, never
// written, and on the import-call path a by-value copy of it per call
// showed up as 2 % of the instructions.)
unsafe @ _module_func_type inout ModuleImpl m i fidx → s {
    ? < fidx 0 { ^ # s 0 } {}
    : ~ i ti -1
    ? < fidx . m num_import_funcs {
        : s wp ?? ( vec_get [( Box WImport )] . m imports fidx ) { T x → # s ( box_ptr [WImport] x ) F → # s 0 }
        ? == # i wp 0 { ^ # s 0 } {}
        : *WImport w # *WImport wp
        = ti . w typeidx
    } {
        : s fp ?? ( vec_get [( Box WFunc )] . m funcs - fidx . m num_import_funcs ) { T x → # s ( box_ptr [WFunc] x ) F → # s 0 }
        ? == # i fp 0 { ^ # s 0 } {}
        : *WFunc f # *WFunc fp
        = ti . f typeidx
    }
    ^ ?? ( vec_get [( Box FuncType )] . m types ti ) { T x → # s ( box_ptr [FuncType] x ) F → # s 0 }
}

// The type of function `fidx` (imported or defined), copied out of the
// module — what a caller outside the interpreter (the CLI parsing its
// arguments) reads; F when the index is out of range.
@ module_func_sig Module m__h i fidx → ?FuncType { ^ ( __module_func_sig ( module_impl m__h ) fidx ) }

@ __module_func_sig ModuleImpl m i fidx → ?FuncType {
    ? < fidx 0 { ^ @ ?FuncType { F } } {}
    : ~ i ti -1
    ? < fidx . m num_import_funcs {
        ?? ( vec_get [( Box WImport )] . m imports fidx ) { T x → { = ti . ( box_get [WImport] x ) typeidx } F → {} }
    } {
        ?? ( vec_get [( Box WFunc )] . m funcs - fidx . m num_import_funcs ) { T x → { = ti . ( box_get [WFunc] x ) typeidx } F → {} }
    }
    ?? ( vec_get [( Box FuncType )] . m types ti ) {
        T x → {
            : FuncType ft ( box_get [FuncType] x )
            ^ @ ?FuncType { T @ FuncType { ( vec_clone [i] . ft params ) ( vec_clone [i] . ft results ) } }
        }
        F → {}
    }
    ^ @ ?FuncType { F }
}

// Structural function-type equality (the call_indirect runtime check): same
// parameter and result valtypes, in order.
@ functype_eq FuncType a FuncType b → b {
    : i np ( vec_len [i] . a params )
    ? != np ( vec_len [i] . b params ) { ^ F } {}
    : i nr ( vec_len [i] . a results )
    ? != nr ( vec_len [i] . b results ) { ^ F } {}
    : ~ b eq T
    : ~ i k 0
    ~ & eq < k np {
        ? != ?? ( vec_get [i] . a params k ) { T x → x F → -1 } ?? ( vec_get [i] . b params k ) { T x → x F → -2 } { = eq F } {}
        = k + k 1
    }
    = k 0
    ~ & eq < k nr {
        ? != ?? ( vec_get [i] . a results k ) { T x → x F → -1 } ?? ( vec_get [i] . b results k ) { T x → x F → -2 } { = eq F } {}
        = k + k 1
    }
    ^ eq
}

@ __name_eq ( Vec u ) nm s want → b {
    : ( Slice u ) want_v ( slice_of_str want )
    : i n ( vec_len [u] nm )
    ? != n ( nurl_str_len want ) { ^ F } {}
    : ~ b eq T : ~ i k 0
    ~ & eq < k n {
        : i a ?? ( vec_get [u] nm k ) { T x → # i x F → -1 }
        ? != a ( slice_byte want_v k ) { = eq F } {}
        = k + k 1
    }
    ^ eq
}
