// packages/wasmtime/src/module.nu — WebAssembly binary decoder (pure NURL).
//
// Decodes a wasm32 module's structure: the magic/version header and the
// sections this runtime understands so far (type, function, export, code).
// Imports, tables, globals, data, etc. are skipped for now — enough to load
// and run a self-contained compute module. The byte cursor + LEB128 readers
// here are reused by the interpreter (interp.nu) to walk instruction streams.

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

: Module {
    ( Vec s ) types  // *FuncType
    ( Vec i ) functypes  // type index per defined function
    ( Vec s ) funcs  // *WFunc
    ( Vec s ) exports  // *WExport
    ( Vec u ) code  // the whole module byte image (functions index into it)
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
    ( vec_free [u] . m code )
    ( vec_free [u] . m err )
    ( nurl_free # s m )
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
    = . m ok T
    = . m err ( vec_new [u] )
    : *Wc c ( wc_new bytes )
    // header: 00 61 73 6d 01 00 00 00
    ? < . c len 8 { = . m ok F = . m err ( bytes_from_str `not a wasm module` ) ( wc_free c ) ^ m } {}
    ? ! & == ( wc_u8 c ) 0 & == ( wc_u8 c ) 97 & == ( wc_u8 c ) 115 == ( wc_u8 c ) 109 {
        = . m ok F = . m err ( bytes_from_str `bad wasm magic` ) ( wc_free c ) ^ m
    } {}
    ( wc_skip c 4 )  // version
    ~ ! ( wc_eof c ) {
        : i id ( wc_u8 c )
        : i size ( wc_uleb c )
        : i sec_end + . c pos size
        ? == id 1 { ( __decode_type_sec c m ) } {
            ? == id 3 { ( __decode_func_sec c m ) } {
                ? == id 7 { ( __decode_export_sec c m ) } {
                    ? == id 10 { ( __decode_code_sec c m ) } {} } } }
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
