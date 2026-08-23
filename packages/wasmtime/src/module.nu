// packages/wasmtime/src/module.nu — WebAssembly binary decoder (pure NURL).
//
// Decodes a wasm32 module's structure: the magic/version header and the
// sections this runtime understands (type, function, table, memory, global,
// export, element, code, data). Imports and the custom/start sections are
// skipped. The byte cursor + LEB128 readers here are reused by the interpreter
// (interp.nu) to walk instruction streams.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// ── byte cursor + LEB128 ─────────────────────────────────────────

: Wc { ( Vec u ) buf i pos i len }

@ wc_new ( Vec u ) buf → *Wc {
    : *Wc c # *Wc ( nurl_alloc Z Wc )
    = . c buf buf
    = . c pos 0
    = . c len ( vec_len [u] buf )
    ^ c
}

// Wc does not own `buf` (the module bytes outlive it); free only the struct.
@ wc_free * Wc c → v { ( nurl_free # s c ) }

@ wc_eof * Wc c → b { ^ >= . c pos . c len }

@ wc_u8 * Wc c → i {
    : i v ?? ( vec_get [u] . c buf . c pos ) { T x → # i x F → 0 }
    = . c pos + . c pos 1
    ^ v
}

@ wc_peek * Wc c → i { ^ ?? ( vec_get [u] . c buf . c pos ) { T x → # i x F → 0 } }

// Unsigned LEB128 → i (NURL i is 64-bit, covers u32/u64).
//
// Only the first ten groups can carry a 64-bit value. A longer encoding
// is malformed wasm, and `<< x shift` with shift >= 64 is poison in LLVM
// (docs/spec.md, § operators) — a corrupted continuation byte turning a
// terminal group into a running one is exactly how a module reaches it.
// Groups past the tenth are consumed, so `pos` still lands after the
// encoding, but they contribute nothing: the value stays inside 64 bits
// and every caller's range check still sees a number it can judge.
@ wc_uleb * Wc c → i {
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
@ wc_sleb * Wc c → i {
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
@ wc_skip * Wc c i n → v { = . c pos + . c pos n }

// Bytes physically remaining in the input (never negative).
@ wc_avail * Wc c → i { : i r - . c len . c pos ? < r 0 { ^ 0 } {} ^ r }

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

: Module {
    ( Vec s ) types  // *FuncType
    ( Vec i ) functypes  // type index per defined function
    ( Vec s ) funcs  // *WFunc
    ( Vec s ) exports  // *WExport
    ( Vec u ) code  // the whole module byte image (functions index into it)
    i has_mem
    i mem_min  // initial pages (64 KiB each)
    i mem_max  // 0 if unbounded
    i mem_shared  // 1 = threads-proposal shared memory (max is mandatory)
    ( Vec s ) datas  // *DataSeg
    ( Vec i ) global_init  // initial value per global
    ( Vec i ) global_mut  // 1 if mutable
    i has_table
    ( Vec i ) table  // initial table image: function indices (−1 = null)
    i table_max  // declared table maximum (0 = none)
    ( Vec s ) elems  // *ElemSeg — element segments, in order
    ( Vec s ) imports  // *WImport (imported functions, in index order)
    i num_import_funcs  // imported funcs occupy func indices 0..n-1
    i start_func  // start-section function index (-1 = none)
    ( Vec i ) name_idx  // function indices with a "name"-section entry…
    ( Vec s ) name_str  // …and their names (*( Vec u )), parallel (sparse)
    b ok
    ( Vec u ) err
}

@ __ft_free * FuncType ft → v { ( vec_free [i] . ft params ) ( vec_free [i] . ft results ) ( nurl_free # s ft ) }

@ module_free * Module m → v {
    : i tn ( vec_len [s] . m types )
    : ~ i k 0
    ~ < k tn { ?? ( vec_get [s] . m types k ) { T pp → ? != # i pp 0 { ( __ft_free # *FuncType pp ) } {} F → {} } = k + k 1 }
    ( vec_free [s] . m types )
    ( vec_free [i] . m functypes )
    : i fn ( vec_len [s] . m funcs )
    : ~ i j 0
    ~ < j fn { ?? ( vec_get [s] . m funcs j ) { T pp → ? != # i pp 0 { : *WFunc f # *WFunc pp ( vec_free [i] . f locals ) ( nurl_free # s f ) } {} F → {} } = j + j 1 }
    ( vec_free [s] . m funcs )
    : i en ( vec_len [s] . m exports )
    : ~ i e 0
    ~ < e en { ?? ( vec_get [s] . m exports e ) { T pp → ? != # i pp 0 { : *WExport x # *WExport pp ( vec_free [u] . x name ) ( nurl_free # s x ) } {} F → {} } = e + e 1 }
    ( vec_free [s] . m exports )
    : i dn ( vec_len [s] . m datas )
    : ~ i d 0
    ~ < d dn { ?? ( vec_get [s] . m datas d ) { T pp → ? != # i pp 0 { : *DataSeg ds # *DataSeg pp ( vec_free [u] . ds bytes ) ( nurl_free # s ds ) } {} F → {} } = d + d 1 }
    ( vec_free [s] . m datas )
    ( vec_free [i] . m global_init )
    ( vec_free [i] . m global_mut )
    ( vec_free [i] . m table )
    : i eln ( vec_len [s] . m elems )
    : ~ i el 0
    ~ < el eln { ?? ( vec_get [s] . m elems el ) { T pp → ? != # i pp 0 { : *ElemSeg es # *ElemSeg pp ( vec_free [i] . es funcs ) ( nurl_free # s es ) } {} F → {} } = el + el 1 }
    ( vec_free [s] . m elems )
    : i in ( vec_len [s] . m imports )
    : ~ i ii 0
    ~ < ii in { ?? ( vec_get [s] . m imports ii ) { T pp → ? != # i pp 0 { : *WImport w # *WImport pp ( vec_free [u] . w module ) ( vec_free [u] . w field ) ( nurl_free # s w ) } {} F → {} } = ii + ii 1 }
    ( vec_free [s] . m imports )
    ( vec_free [i] . m name_idx )
    : i nn ( vec_len [s] . m name_str )
    : ~ i ni 0
    ~ < ni nn { ?? ( vec_get [s] . m name_str ni ) { T pp → ? != # i pp 0 { : *NameBuf nb # *NameBuf pp ( vec_free [u] . nb bytes ) ( nurl_free # s nb ) } {} F → {} } = ni + ni 1 }
    ( vec_free [s] . m name_str )
    ( vec_free [u] . m code )
    ( vec_free [u] . m err )
    ( nurl_free # s m )
}

// Record a decode error (first error wins; frees the previous message).
@ __mod_err * Module m s msg → v {
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
@ __chk_count * Wc c * Module m i cnt s what → i {
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
@ __const_expr * Wc c * Module m → i {
    : i op0 ( wc_u8 c )
    : ~ i val 0
    ? | == op0 65 == op0 66 { = val ( wc_sleb c ) } {
        ? == op0 35 { ( wc_uleb c ) ( __mod_err m `constant expression uses global.get (imported globals unsupported)` ) } {} }
    // Consume through the terminating 0x0b `end`. Bounded by EOF: past the end
    // of input wc_u8 returns 0 forever, so an unterminated expression must not
    // spin — a truncated global/data/elem offset expr is a decode error.
    : ~ b done F
    ~ & ! done ! ( wc_eof c ) { ? == ( wc_u8 c ) 11 { = done T } {} }
    ? ! done { ( __mod_err m `truncated constant expression (no end)` ) } {}
    ^ val
}

// ── section decoders ─────────────────────────────────────────────

@ __read_functype * Wc c * Module m → *FuncType {
    ( wc_u8 c )  // 0x60 form byte (assumed)
    : i np ( __chk_count c m ( wc_uleb c ) `bad param count` )
    : ( Vec i ) params ( vec_new [i] )
    : ~ i a 0
    ~ < a np { ( vec_push [i] params ( wc_u8 c ) ) = a + a 1 }
    : i nr ( __chk_count c m ( wc_uleb c ) `bad result count` )
    : ( Vec i ) results ( vec_new [i] )
    : ~ i b 0
    ~ < b nr { ( vec_push [i] results ( wc_u8 c ) ) = b + b 1 }
    : *FuncType ft # *FuncType ( nurl_alloc Z FuncType )
    = . ft params params
    = . ft results results
    ^ ft
}

@ __decode_type_sec * Wc c * Module m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad type count` )
    : ~ i k 0
    ~ < k n { ( vec_push [s] . m types # s ( __read_functype c m ) ) = k + k 1 }
}

@ __decode_func_sec * Wc c * Module m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad function count` )
    : ~ i k 0
    ~ < k n { ( vec_push [i] . m functypes ( wc_uleb c ) ) = k + k 1 }
}

@ __decode_export_sec * Wc c * Module m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad export count` )
    : ~ i k 0
    ~ < k n {
        : i nl ( __chk_count c m ( wc_uleb c ) `bad export name length` )
        : ( Vec u ) nm ( vec_new [u] )
        : ~ i a 0
        ~ < a nl { ( vec_push [u] nm ( wc_u8 c ) ) = a + a 1 }
        : i kind ( wc_u8 c )
        : i idx ( wc_uleb c )
        : *WExport x # *WExport ( nurl_alloc Z WExport )
        = . x name nm
        = . x kind kind
        = . x index idx
        ( vec_push [s] . m exports # s x )
        = k + k 1
    }
}

// Memory section: limits (flag, min [, max]). Records the first memory.
// flag bit 0 = a maximum follows; bit 1 = SHARED (the threads proposal),
// where the maximum is mandatory because every thread must agree on where
// the buffer can end.
@ __decode_mem_sec * Wc c * Module m → v {
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
@ __decode_data_sec * Wc c * Module m → v {
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
        : ( Vec u ) bytes ( vec_with_cap [u] blen )
        ? > blen 0 {
            : s src # s + # i ( vec_data [u] . c buf ) . c pos
            ( nurl_memcpy # s ( vec_data [u] bytes ) src blen )
            : b _ok ( vec_set_len [u] bytes blen )
            ( wc_skip c blen )
        } {}
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
        : *DataSeg ds # *DataSeg ( nurl_alloc Z DataSeg )
        = . ds offset offset
        = . ds bytes bytes
        = . ds passive ? == flag 1 1 0
        ( vec_push [s] . m datas ds )
        = k + k 1
    }
}

// Import section: record imported FUNCTIONS (module + field name resolve to a
// host/WASI implementation at call time). A table / memory / global import is
// a hard decode error — this runtime has nothing to satisfy it with, and
// running anyway would silently corrupt the module's own state.
@ __decode_import_sec * Wc c * Module m → v {
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
            : *WImport w # *WImport ( nurl_alloc Z WImport )
            = . w module mnm
            = . w field fld
            = . w typeidx ti
            ( vec_push [s] . m imports # s w )
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
@ __decode_global_sec * Wc c * Module m → v {
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
// recording its declared maximum for table.grow. Only funcref tables are
// supported — an externref table is a decode error.
@ __decode_table_sec * Wc c * Module m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad table count` )
    : ~ i k 0
    ~ < k n {
        : i et ( wc_u8 c )  // elemtype: 0x70 funcref / 0x6f externref
        ? != et 112 { ( __mod_err m `unsupported table element type (externref)` ) } {}
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
@ __elem_expr * Wc c → i {
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
@ __decode_elem_sec * Wc c * Module m → v {
    : i n ( __chk_count c m ( wc_uleb c ) `bad element count` )
    : ~ i k 0
    ~ < k n {
        : i flag ( wc_uleb c )
        : i active ? == & flag 1 0 1 0
        : ~ i off 0
        ? == active 1 {
            ? == & flag 2 2 { ( wc_uleb c ) } {}  // explicit table index (0)
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
            : ~ i a 0
            ~ < a cnt {
                : i tgt + off a
                ? & >= tgt 0 < tgt ( vec_len [i] . m table ) {
                    ( vec_set [i] . m table tgt ?? ( vec_get [i] funcs a ) { T x → x F → -1 } )
                } {}
                = a + a 1
            }
        } {}
        : *ElemSeg es # *ElemSeg ( nurl_alloc Z ElemSeg )
        = . es funcs funcs
        // active (and declared, flag 3/7) segments are dropped at instantiation
        = . es passive ? | == flag 1 == flag 5 1 0
        ( vec_push [s] . m elems # s es )
        = k + k 1
    }
}

// Code section: for each function, parse local declarations and record the
// [start,end) byte range of its instruction stream (ending at the final `end`).
@ __decode_code_sec * Wc c * Module m → v {
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
        : *WFunc f # *WFunc ( nurl_alloc Z WFunc )
        = . f typeidx ?? ( vec_get [i] . m functypes k ) { T x → x F → 0 }
        = . f locals locals
        = . f code_start code_start
        = . f code_end body_end
        ( vec_push [s] . m funcs # s f )
        = . c pos body_end  // skip to next body
        = k + k 1
    }
}

// Custom section: if it is the "name" section, harvest subsection 1
// (function names) for diagnostics; anything else is skipped.
@ __decode_custom_sec * Wc c * Module m i sec_end → v {
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
                    : *NameBuf nb # *NameBuf ( nurl_alloc Z NameBuf )
                    = . nb bytes nm
                    ( vec_push [i] . m name_idx fi )
                    ( vec_push [s] . m name_str # s nb )
                    = k + k 1
                }
            } {}
            = . c pos sub_end }
    }
}

// The name-section name of function `fidx` as a fresh byte vector (empty if
// unknown). Cold path — linear scan is fine (used only for trap backtraces).
@ module_func_name * Module m i fidx → ( Vec u ) {
    : i n ( vec_len [i] . m name_idx )
    : ~ i k 0
    ~ < k n {
        ? == ?? ( vec_get [i] . m name_idx k ) { T x → x F → -1 } fidx {
            : s pp ?? ( vec_get [s] . m name_str k ) { T x → x F → # s 0 }
            ? != # i pp 0 {
                : *NameBuf nb # *NameBuf pp
                : ( Vec u ) out ( vec_with_cap [u] ( vec_len [u] . nb bytes ) )
                : i bn ( vec_len [u] . nb bytes )
                : ~ i b 0
                ~ < b bn { ( vec_push [u] out ?? ( vec_get [u] . nb bytes b ) { T x → x F → # u 0 } ) = b + b 1 }
                ^ out
            } {}
        } {}
        = k + k 1
    }
    ^ ( vec_new [u] )
}

// Decode a whole module. On error, .ok is F and .err carries a message.
@ module_decode ( Vec u ) bytes → *Module {
    : *Module m # *Module ( nurl_alloc Z Module )
    = . m types ( vec_new [s] )
    = . m functypes ( vec_new [i] )
    = . m funcs ( vec_new [s] )
    = . m exports ( vec_new [s] )
    = . m code bytes
    = . m has_mem 0
    = . m mem_min 0
    = . m mem_max 0
    = . m mem_shared 0
    = . m datas ( vec_new [s] )
    = . m global_init ( vec_new [i] )
    = . m global_mut ( vec_new [i] )
    = . m has_table 0
    = . m table ( vec_new [i] )
    = . m table_max 0
    = . m elems ( vec_new [s] )
    = . m imports ( vec_new [s] )
    = . m num_import_funcs 0
    = . m start_func -1
    = . m name_idx ( vec_new [i] )
    = . m name_str ( vec_new [s] )
    = . m ok T
    = . m err ( vec_new [u] )
    : *Wc c ( wc_new bytes )
    // header: 00 61 73 6d 01 00 00 00
    ? < . c len 8 { ( __mod_err m `not a wasm module` ) ( wc_free c ) ^ m } {}
    ? ! & == ( wc_u8 c ) 0 & == ( wc_u8 c ) 97 & == ( wc_u8 c ) 115 == ( wc_u8 c ) 109 {
        ( __mod_err m `bad wasm magic` ) ( wc_free c ) ^ m
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
    ( wc_free c )
    ^ m
}

// Find an exported GLOBAL's index by name (-1 if absent). wasi-threads
// needs one: `__stack_pointer` is what gives a spawned thread its own
// stack, and only the host can set it before the thread's first call.
@ module_export_global * Module m s name → i {
    : i n ( vec_len [s] . m exports )
    : ~ i found -1
    : ~ i k 0
    ~ & == found -1 < k n {
        : s pp ?? ( vec_get [s] . m exports k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *WExport x # *WExport pp
            ? & == . x kind 3 ( __name_eq . x name name ) { = found . x index } {}
        } {}
        = k + k 1
    }
    ^ found
}

// Find an exported function index by name (-1 if absent).
@ module_export_func * Module m s name → i {
    : i n ( vec_len [s] . m exports )
    : ~ i found -1
    : ~ i k 0
    ~ & == found -1 < k n {
        : s pp ?? ( vec_get [s] . m exports k ) { T x → x F → # s 0 }
        ? != # i pp 0 {
            : *WExport x # *WExport pp
            ? & == . x kind 0 ( __name_eq . x name name ) { = found . x index } {}
        } {}
        = k + k 1
    }
    ^ found
}

// The *FuncType of any function index — imported (low indices) or defined —
// as an opaque pointer; #s 0 if out of range.
@ module_func_type * Module m i fidx → s {
    ? < fidx 0 { ^ # s 0 } {}
    : ~ i ti -1
    ? < fidx . m num_import_funcs {
        : s wp ?? ( vec_get [s] . m imports fidx ) { T x → x F → # s 0 }
        ? == # i wp 0 { ^ # s 0 } {}
        : *WImport w # *WImport wp
        = ti . w typeidx
    } {
        : s fp ?? ( vec_get [s] . m funcs - fidx . m num_import_funcs ) { T x → x F → # s 0 }
        ? == # i fp 0 { ^ # s 0 } {}
        : *WFunc f # *WFunc fp
        = ti . f typeidx
    }
    ^ ?? ( vec_get [s] . m types ti ) { T x → x F → # s 0 }
}

// Structural function-type equality (the call_indirect runtime check): same
// parameter and result valtypes, in order.
@ functype_eq * FuncType a * FuncType b → b {
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
    : i n ( vec_len [u] nm )
    ? != n ( nurl_str_len want ) { ^ F } {}
    : ~ b eq T : ~ i k 0
    ~ & eq < k n {
        : i a ?? ( vec_get [u] nm k ) { T x → # i x F → -1 }
        ? != a ( nurl_str_get want k ) { = eq F } {}
        = k + k 1
    }
    ^ eq
}
