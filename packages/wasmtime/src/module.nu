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
@ wc_uleb * Wc c → i {
    : ~ i result 0
    : ~ i shift 0
    : ~ b more T
    ~ more {
        : i b ( wc_u8 c )
        = result | result << & b 127 shift
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
        = result | result << & b 127 shift
        = shift + shift 7
        ? == 0 & b 128 { = more F } {}
    }
    // sign-extend if the sign bit of the last group is set and we read < 64 bits
    ? & < shift 64 != 0 & b 64 { = result | result << -1 shift } {}
    ^ result
}

// Skip n bytes.
@ wc_skip * Wc c i n → v { = . c pos + . c pos n }

// ── module model ─────────────────────────────────────────────────

: FuncType { ( Vec i ) params ( Vec i ) results }

// A defined function: its type index, its declared (non-param) local valtypes
// expanded flat, and the [start,end) byte range of its instruction stream.
: WFunc { i typeidx ( Vec i ) locals i code_start i code_end }

: WExport { ( Vec u ) name i kind i index }

// An active data segment: raw bytes to copy into linear memory at `offset`.
: DataSeg { i offset ( Vec u ) bytes }

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
    ( Vec s ) datas  // *DataSeg
    ( Vec i ) global_init  // initial value per global
    ( Vec i ) global_mut  // 1 if mutable
    i has_table
    ( Vec i ) table  // function indices (−1 = empty slot)
    ( Vec s ) imports  // *WImport (imported functions, in index order)
    i num_import_funcs  // imported funcs occupy func indices 0..n-1
    i start_func  // start-section function index (-1 = none)
    b ok
    ( Vec u ) err
}

@ __ft_free * FuncType ft → v { ( vec_free [i] . ft params ) ( vec_free [i] . ft results ) ( nurl_free # s ft ) }

@ module_free * Module m → v {
    : i tn ( vec_len [s] . m types )
    : ~ i k 0
    ~ < k tn { ?? ( vec_get [s] . m types k ) { T pp → ?!= # i pp 0 { ( __ft_free # *FuncType pp ) } {} F → {} } = k + k 1 }
    ( vec_free [s] . m types )
    ( vec_free [i] . m functypes )
    : i fn ( vec_len [s] . m funcs )
    : ~ i j 0
    ~ < j fn { ?? ( vec_get [s] . m funcs j ) { T pp → ?!= # i pp 0 { : *WFunc f # *WFunc pp ( vec_free [i] . f locals ) ( nurl_free # s f ) } {} F → {} } = j + j 1 }
    ( vec_free [s] . m funcs )
    : i en ( vec_len [s] . m exports )
    : ~ i e 0
    ~ < e en { ?? ( vec_get [s] . m exports e ) { T pp → ?!= # i pp 0 { : *WExport x # *WExport pp ( vec_free [u] . x name ) ( nurl_free # s x ) } {} F → {} } = e + e 1 }
    ( vec_free [s] . m exports )
    : i dn ( vec_len [s] . m datas )
    : ~ i d 0
    ~ < d dn { ?? ( vec_get [s] . m datas d ) { T pp → ?!= # i pp 0 { : *DataSeg ds # *DataSeg pp ( vec_free [u] . ds bytes ) ( nurl_free # s ds ) } {} F → {} } = d + d 1 }
    ( vec_free [s] . m datas )
    ( vec_free [i] . m global_init )
    ( vec_free [i] . m global_mut )
    ( vec_free [i] . m table )
    : i in ( vec_len [s] . m imports )
    : ~ i ii 0
    ~ < ii in { ?? ( vec_get [s] . m imports ii ) { T pp → ?!= # i pp 0 { : *WImport w # *WImport pp ( vec_free [u] . w module ) ( vec_free [u] . w field ) ( nurl_free # s w ) } {} F → {} } = ii + ii 1 }
    ( vec_free [s] . m imports )
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

// Evaluate a constant init expr (i32/i64.const N … end). `global.get` in a
// constant expression may only reference an imported global (spec), and those
// are rejected at decode — so hitting one here is itself a decode error.
// Consumes through the trailing `end`.
@ __const_expr * Wc c * Module m → i {
    : i op0 ( wc_u8 c )
    : ~ i val 0
    ? | == op0 65 == op0 66 { = val ( wc_sleb c ) } {
        ? == op0 35 { ( wc_uleb c ) ( __mod_err m `constant expression uses global.get (imported globals unsupported)` ) } {} }
    ~ != ( wc_u8 c ) 11 {}
    ^ val
}

// ── section decoders ─────────────────────────────────────────────

@ __read_functype * Wc c → *FuncType {
    ( wc_u8 c )  // 0x60 form byte (assumed)
    : i np ( wc_uleb c )
    : ( Vec i ) params ( vec_new [i] )
    : ~ i a 0
    ~ < a np { ( vec_push [i] params ( wc_u8 c ) ) = a + a 1 }
    : i nr ( wc_uleb c )
    : ( Vec i ) results ( vec_new [i] )
    : ~ i b 0
    ~ < b nr { ( vec_push [i] results ( wc_u8 c ) ) = b + b 1 }
    : *FuncType ft # *FuncType ( nurl_alloc Z FuncType )
    = . ft params params
    = . ft results results
    ^ ft
}

@ __decode_type_sec * Wc c * Module m → v {
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n { ( vec_push [s] . m types # s ( __read_functype c ) ) = k + k 1 }
}

@ __decode_func_sec * Wc c * Module m → v {
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n { ( vec_push [i] . m functypes ( wc_uleb c ) ) = k + k 1 }
}

@ __decode_export_sec * Wc c * Module m → v {
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n {
        : i nl ( wc_uleb c )
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
@ __decode_mem_sec * Wc c * Module m → v {
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n {
        : i flag ( wc_u8 c )
        : i mn ( wc_uleb c )
        : i mx ? == flag 1 ( wc_uleb c ) 0
        ? == k 0 { = . m has_mem 1 = . m mem_min mn = . m mem_max mx } {}
        = k + k 1
    }
}

// Data section: active segments (flag 0/2) carry an i32.const offset expr then
// raw bytes; passive segments (flag 1) carry bytes only (offset 0, ignored).
@ __decode_data_sec * Wc c * Module m → v {
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n {
        : i flag ( wc_uleb c )
        ? == flag 2 { ( wc_uleb c ) } {}  // explicit memidx
        : i offset ? != flag 1 ( __const_expr c m ) 0
        : i blen ( wc_uleb c )
        : ( Vec u ) bytes ( vec_with_cap [u] blen )
        : ~ i bi 0
        ~ < bi blen { ( vec_push [u] bytes ( wc_u8 c ) ) = bi + bi 1 }
        : *DataSeg ds # *DataSeg ( nurl_alloc Z DataSeg )
        = . ds offset offset
        = . ds bytes bytes
        ( vec_push [s] . m datas ds )
        = k + k 1
    }
}

// Import section: record imported FUNCTIONS (module + field name resolve to a
// host/WASI implementation at call time). A table / memory / global import is
// a hard decode error — this runtime has nothing to satisfy it with, and
// running anyway would silently corrupt the module's own state.
@ __decode_import_sec * Wc c * Module m → v {
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n {
        : i mlen ( wc_uleb c )
        : ( Vec u ) mnm ( vec_with_cap [u] mlen )
        : ~ i b 0
        ~ < b mlen { ( vec_push [u] mnm ( wc_u8 c ) ) = b + b 1 }
        : i flen ( wc_uleb c )
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
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n {
        ( wc_u8 c )  // valtype
        : i mut ( wc_u8 c )
        ( vec_push [i] . m global_init ( __const_expr c m ) )
        ( vec_push [i] . m global_mut mut )
        = k + k 1
    }
}

// Table section: allocate the first table (size = min, slots empty = −1).
@ __decode_table_sec * Wc c * Module m → v {
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n {
        ( wc_u8 c )  // elemtype (0x70 funcref)
        : i flag ( wc_u8 c )
        : i mn ( wc_uleb c )
        ? == flag 1 { ( wc_uleb c ) } {}  // max
        ? == k 0 {
            = . m has_table 1
            : ~ i j 0
            ~ < j mn { ( vec_push [i] . m table -1 ) = j + j 1 }
        } {}
        = k + k 1
    }
}

// Element section: active segments (flag 0) fill the table with function indices
// at a const offset.
@ __decode_elem_sec * Wc c * Module m → v {
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n {
        : i flag ( wc_uleb c )
        ? == flag 0 {
            : i off ( __const_expr c m )
            : i cnt ( wc_uleb c )
            : ~ i j 0
            ~ < j cnt {
                : i fi ( wc_uleb c )
                : i tgt + off j
                ? & >= tgt 0 < tgt ( vec_len [i] . m table ) { ( vec_set [i] . m table tgt fi ) } {}
                = j + j 1
            }
        } {}
        = k + k 1
    }
}

// Code section: for each function, parse local declarations and record the
// [start,end) byte range of its instruction stream (ending at the final `end`).
@ __decode_code_sec * Wc c * Module m → v {
    : i n ( wc_uleb c )
    : ~ i k 0
    ~ < k n {
        : i bodysize ( wc_uleb c )
        : i body_end + . c pos bodysize
        : i ndecl ( wc_uleb c )
        : ( Vec i ) locals ( vec_new [i] )
        : ~ i d 0
        ~ < d ndecl {
            : i cnt ( wc_uleb c )
            : i ty ( wc_u8 c )
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
    = . m datas ( vec_new [s] )
    = . m global_init ( vec_new [i] )
    = . m global_mut ( vec_new [i] )
    = . m has_table 0
    = . m table ( vec_new [i] )
    = . m imports ( vec_new [s] )
    = . m num_import_funcs 0
    = . m start_func -1
    = . m ok T
    = . m err ( vec_new [u] )
    : *Wc c ( wc_new bytes )
    // header: 00 61 73 6d 01 00 00 00
    ? < . c len 8 { ( __mod_err m `not a wasm module` ) ( wc_free c ) ^ m } {}
    ? ! & == ( wc_u8 c ) 0 & == ( wc_u8 c ) 97 & == ( wc_u8 c ) 115 == ( wc_u8 c ) 109 {
        ( __mod_err m `bad wasm magic` ) ( wc_free c ) ^ m
    } {}
    ( wc_skip c 4 )  // version
    ~ ! ( wc_eof c ) {
        : i id ( wc_u8 c )
        : i size ( wc_uleb c )
        : i sec_end + . c pos size
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
