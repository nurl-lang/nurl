// packages/onnx/src/model.nu — ONNX schema parsing over pb.nu.
//
// Decodes the subset of the ONNX protobuf needed for feed-forward
// inference: ModelProto → GraphProto → { NodeProto[], TensorProto
// initializers, graph input/output names }. Field numbers are the stable
// ONNX wire layout. Weights (TensorProto.raw_data, little-endian f32) are
// read straight into a host buffer ready to upload to the GPU.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`
$ `pb.nu`

// ── in-memory graph ───────────────────────────────────────────────
// One attribute. Captures the value forms used by the ops we run:
// f (FLOAT, e.g. alpha/epsilon), i (INT, e.g. group), s (STRING, e.g.
// auto_pad), and ints (INTS, e.g. kernel_shape/strides). `kind` is unused
// (the consumer asks by name + form via node_attr_*).
: OAttr { String name i kind f f i i String s ( Vec i ) ints }

: ONode {
    String op_type
    ( Vec String ) inputs
    ( Vec String ) outputs
    ( Vec OAttr ) attrs
}

// A tensor: name, shape, element count, ONNX data_type, and host data —
// f32 (4-byte) for FLOAT(1) weights, or i64 (8-byte) for INT64(7) shape /
// size / anchor tensors. host == 0 for a graph value placeholder.
: OTensor {
    String name
    ( Vec i ) dims
    i nelem
    i dtype  // ONNX DataType: 1=FLOAT, 7=INT64
    i host  // *u as i64 (0 = no data)
}

: OGraph {
    ( Vec ONode ) nodes
    ( Vec OTensor ) inits
    String input_name
    String output_name
    String output1_name
}

// String equality as a bool (nurl_str_eq returns i).
@ streq s a s b → b { ^ != ( nurl_str_eq a b ) 0 }

// ── attribute access ──────────────────────────────────────────────
@ node_attr_f ONode n s name f dflt → f {
    : ( Vec OAttr ) as . n attrs
    : ~ f r dflt
    : ~ i k 0
    ~ < k ( vec_len [OAttr] as ) {
        ?? ( vec_get [OAttr] as k ) {
            T a → ? ( streq ( string_data . a name ) name ) { = r . a f } {} F _ → {}
        }
        = k + k 1
    }
    ^ r
}

@ node_attr_i ONode n s name i dflt → i {
    : ( Vec OAttr ) as . n attrs
    : ~ i r dflt
    : ~ i k 0
    ~ < k ( vec_len [OAttr] as ) {
        ?? ( vec_get [OAttr] as k ) {
            T a → ? ( streq ( string_data . a name ) name ) { = r . a i } {} F _ → {}
        }
        = k + k 1
    }
    ^ r
}

// Find the named attribute and return its OAttr (kind=-1 sentinel if absent).
@ __find_attr ONode n s name → OAttr {
    : ( Vec OAttr ) as . n attrs
    : ~ i k 0
    ~ < k ( vec_len [OAttr] as ) {
        ?? ( vec_get [OAttr] as k ) {
            T a → ? ( streq ( string_data . a name ) name ) { ^ a } {} F _ → {}
        }
        = k + k 1
    }
    ^ @ OAttr { ( string_new ) - 0 1 0.0 0 ( string_new ) ( vec_new [i] ) }
}

// The k-th element of an INTS attribute (dflt if attr/element absent).
@ node_attr_int_at ONode n s name i k i dflt → i {
    : OAttr a ( __find_attr n name )
    ?? ( vec_get [i] . a ints k ) { T v → ^ v F _ → ^ dflt }
}

@ node_attr_ints_len ONode n s name → i {
    : OAttr a ( __find_attr n name )
    ^ ( vec_len [i] . a ints )
}

// A STRING attribute's value (dflt if absent/empty).
@ node_attr_s ONode n s name s dflt → s {
    : OAttr a ( __find_attr n name )
    ? == ( string_len . a s ) 0 { ^ dflt } { ^ ( string_data . a s ) }
}

// ── AttributeProto ────────────────────────────────────────────────
@ __parse_attr * PbR r → OAttr {
    : ~ String name ( string_new )
    : ~ f fv 0.0
    : ~ i iv 0
    : ~ String sv ( string_new )
    : ( Vec i ) ints ( vec_new [i] )
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 { ( string_free name ) = name ( pb_string r ) }  // name
        ? == fld 2 { = fv # f ( bits_to_f32 ( pb_i32 r ) ) }  // f (float, wire 5)
        ? == fld 3 { = iv ( pb_varint r ) }  // i (int, varint)
        ? == fld 4 { ( string_free sv ) = sv ( pb_string r ) }  // s (string/bytes)
        ? == fld 8 {  // ints: packed or single
            ? == wt 2 {
                : *PbR is ( pb_submsg r )
                ~ ( pb_more is ) { ( vec_push [i] ints ( pb_varint is ) ) }
                ( pb_free is )
            } { ( vec_push [i] ints ( pb_varint r ) ) }
        }
        { ( pb_skip r wt ) }
    }
    ^ @ OAttr { name 0 fv iv sv ints }
}

// ── NodeProto ─────────────────────────────────────────────────────
@ __parse_node * PbR r → ONode {
    : ( Vec String ) ins ( vec_new [String] )
    : ( Vec String ) outs ( vec_new [String] )
    : ( Vec OAttr ) attrs ( vec_new [OAttr] )
    : ~ String op ( string_new )
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 { ( vec_push [String] ins ( pb_string r ) ) }  // input
        ? == fld 2 { ( vec_push [String] outs ( pb_string r ) ) }  // output
        ? == fld 4 { ( string_free op ) = op ( pb_string r ) }  // op_type
        ? == fld 5 { : *PbR sub ( pb_submsg r ) ( vec_push [OAttr] attrs ( __parse_attr sub ) ) ( pb_free sub ) }
        { ( pb_skip r wt ) }
    }
    ^ @ ONode { op ins outs attrs }
}

// ── TensorProto (initializer) ─────────────────────────────────────
@ __parse_tensor * PbR r → OTensor {
    : ( Vec i ) dims ( vec_new [i] )
    : ~ String name ( string_new )
    : ~ i dtype 0
    : ~ i raw_start - 0 1
    : ~ i raw_len 0
    : ( Vec i ) i64vals ( vec_new [i] )
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 {  // dims (int64): packed (wire 2) or single varint
            ? == wt 2 {
                : *PbR ds ( pb_submsg r )
                ~ ( pb_more ds ) { ( vec_push [i] dims ( pb_varint ds ) ) }
                ( pb_free ds )
            } { ( vec_push [i] dims ( pb_varint r ) ) }
        }
        ? == fld 2 { = dtype ( pb_varint r ) }  // data_type
        ? == fld 8 { ( string_free name ) = name ( pb_string r ) }  // name
        ? == fld 4 {  // float_data (packed f32)
            ? == wt 2 {
                : i len ( pb_varint r )
                = raw_start ( pb_pos r )
                = raw_len len
                ( pb_set_pos r + ( pb_pos r ) len )
            } { ( pb_skip r wt ) }
        }
        ? == fld 7 {  // int64_data (packed varints — onnxsim writes these)
            ? == wt 2 {
                : *PbR ds ( pb_submsg r )
                ~ ( pb_more ds ) { ( vec_push [i] i64vals ( pb_varint ds ) ) }
                ( pb_free ds )
            } { ( vec_push [i] i64vals ( pb_varint r ) ) }
        }
        ? == fld 9 {  // raw_data (LE f32 bytes)
            : i len ( pb_varint r )
            = raw_start ( pb_pos r )
            = raw_len len
            ( pb_set_pos r + ( pb_pos r ) len )
        }
        { ( pb_skip r wt ) }
    }
    : i nelem ( __nelem dims )
    : ~ i host 0
    // int64_data field (no raw block): materialise the varints as the
    // same 8-byte LE host block the raw path produces.
    ? & & < raw_start 0 > ( vec_len [i] i64vals ) 0 == dtype 7 {
        : i nv ( vec_len [i] i64vals )
        : *u h64 ( nurl_alloc * nv 8 )
        : ~ i q 0
        ~ < q nv {
            ( nurl_poke h64 q ?? ( vec_get [i] i64vals q ) { T x → x F _ → 0 } )
            = q + q 1
        }
        = host # i h64
    } {}
    ( vec_free [i] i64vals )
    ? & >= raw_start 0 > raw_len 0 {
        ? == dtype 7 {  // INT64: 8-byte LE values
            : *u h ( nurl_alloc * nelem 8 )
            ( pb_set_pos r raw_start )
            ( pb_read_i64_into r h nelem )
            = host # i h
        } {  // FLOAT (default): f32
            : *u h ( nurl_alloc * nelem 4 )
            ( pb_set_pos r raw_start )
            ( pb_read_f32_into r h nelem )
            = host # i h
        }
    } {}
    ^ @ OTensor { name dims nelem dtype host }
}

@ __nelem ( Vec i ) dims → i {
    : ~ i p 1
    : ~ i k 0
    ~ < k ( vec_len [i] dims ) {
        ?? ( vec_get [i] dims k ) { T d → = p * p d F _ → {} }
        = k + k 1
    }
    ^ p
}

// ValueInfoProto → its name (field 1).
@ __parse_valueinfo_name * PbR r → String {
    : ~ String name ( string_new )
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 { ( string_free name ) = name ( pb_string r ) } { ( pb_skip r wt ) }
    }
    ^ name
}

// ── GraphProto ────────────────────────────────────────────────────
@ __parse_graph * PbR r → OGraph {
    : ( Vec ONode ) nodes ( vec_new [ONode] )
    : ( Vec OTensor ) inits ( vec_new [OTensor] )
    : ~ String inp ( string_new )
    : ~ String outp ( string_new )
    : ~ String outp1 ( string_new )
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 { : *PbR s ( pb_submsg r ) ( vec_push [ONode] nodes ( __parse_node s ) ) ( pb_free s ) }
        ? == fld 5 { : *PbR s ( pb_submsg r ) ( vec_push [OTensor] inits ( __parse_tensor s ) ) ( pb_free s ) }
        ? == fld 11 {
            // graph.input often also lists every initializer (older exporters).
            // The real model input is the FIRST entry; keep it, ignore the rest.
            : *PbR s ( pb_submsg r )
            : String nm ( __parse_valueinfo_name s )
            ? == ( string_len inp ) 0 { ( string_free inp ) = inp nm } { ( string_free nm ) }
            ( pb_free s )
        }
        ? == fld 12 {
            // first graph.output is the primary head (detection output0); the
            // second is the segmentation proto (output1) — both are kept so a
            // seg model can return its mask prototypes.
            : *PbR s ( pb_submsg r )
            : String onm ( __parse_valueinfo_name s )
            ? == ( string_len outp ) 0 { ( string_free outp ) = outp onm }
            { ? == ( string_len outp1 ) 0 { ( string_free outp1 ) = outp1 onm } { ( string_free onm ) } }
            ( pb_free s )
        }
        { ( pb_skip r wt ) }
    }
    ^ @ OGraph { nodes inits inp outp outp1 }
}

// ── ModelProto (top level) ────────────────────────────────────────
@ onnx_parse ( Vec u ) bytes → OGraph {
    : *PbR r ( pb_new bytes )
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 7 { : *PbR s ( pb_submsg r ) ( graph_free g ) = g ( __parse_graph s ) ( pb_free s ) } { ( pb_skip r wt ) }
    }
    ( pb_free r )
    ^ g
}

// ── lookups ───────────────────────────────────────────────────────
@ graph_find_init OGraph g s name → i {  // index into inits, -1 if none
    : ( Vec OTensor ) inits . g inits
    : ~ i k 0
    ~ < k ( vec_len [OTensor] inits ) {
        ?? ( vec_get [OTensor] inits k ) {
            T t → ? ( streq ( string_data . t name ) name ) { ^ k } {} F _ → {}
        }
        = k + k 1
    }
    ^ - 0 1
}

// ── Teardown ──────────────────────────────────────────────────────────

// Free everything a parsed graph owns: every node (op string, input /
// output name vectors, attributes incl. their strings and int vectors),
// every initializer (name, dims, host data buffer), and the graph's
// input/output name strings. The OGraph value itself is by-value — after
// graph_free it must not be used again.
@ __attr_free OAttr a → v {
    ( string_free . a name )
    ( string_free . a s )
    ( vec_free [i] . a ints )
}

@ __node_free ONode n → v {
    ( string_free . n op_type )
    ( vec_free_with [String] . n inputs \ String x → v { ( string_free x ) } )
    ( vec_free_with [String] . n outputs \ String x → v { ( string_free x ) } )
    : i na ( vec_len [OAttr] . n attrs )
    : ~ i k 0
    ~ < k na {
        ?? ( vec_get [OAttr] . n attrs k ) { T a → { ( __attr_free a ) } F _ → {} }
        = k + k 1
    }
    ( vec_free [OAttr] . n attrs )
}

@ __otensor_free OTensor t → v {
    ( string_free . t name )
    ( vec_free [i] . t dims )
    ? != . t host 0 { ( nurl_free # *u . t host ) } {}
}

@ graph_free OGraph g → v {
    : i nn ( vec_len [ONode] . g nodes )
    : ~ i k 0
    ~ < k nn {
        ?? ( vec_get [ONode] . g nodes k ) { T n → { ( __node_free n ) } F _ → {} }
        = k + k 1
    }
    ( vec_free [ONode] . g nodes )
    : i ni ( vec_len [OTensor] . g inits )
    = k 0
    ~ < k ni {
        ?? ( vec_get [OTensor] . g inits k ) { T t → { ( __otensor_free t ) } F _ → {} }
        = k + k 1
    }
    ( vec_free [OTensor] . g inits )
    ( string_free . g input_name )
    ( string_free . g output_name )
    ( string_free . g output1_name )
}
