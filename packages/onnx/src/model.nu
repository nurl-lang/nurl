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
// Scalar attribute (ONNX AttributeType: 1=FLOAT, 2=INT). Gemm's
// alpha/beta/transA/transB are all scalar — enough for the PoC.
: OAttr { String name  i kind  f f  i i }

: ONode {
    String op_type
    ( Vec String ) inputs
    ( Vec String ) outputs
    ( Vec OAttr ) attrs
}

// A tensor: name, shape, element count, and host f32 data (raw 32-bit
// patterns, 4-byte stride) — or host == 0 for graph value placeholders.
: OTensor {
    String name
    ( Vec i ) dims
    i nelem
    i host        // *u as i64 (0 = no data)
}

: OGraph {
    ( Vec ONode ) nodes
    ( Vec OTensor ) inits
    String input_name
    String output_name
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

// ── AttributeProto ────────────────────────────────────────────────
@ __parse_attr *PbR r → OAttr {
    : ~ String name ( string_new )
    : ~ f fv 0.0
    : ~ i iv 0
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 { = name ( pb_string r ) }             // name
        ? == fld 2 { = fv # f ( bits_to_f32 ( pb_i32 r ) ) }  // f (float, wire 5)
        ? == fld 3 { = iv ( pb_varint r ) }               // i (int, varint)
        { ( pb_skip r wt ) }
    }
    ^ @ OAttr { name 0 fv iv }
}

// ── NodeProto ─────────────────────────────────────────────────────
@ __parse_node *PbR r → ONode {
    : ( Vec String ) ins ( vec_new [String] )
    : ( Vec String ) outs ( vec_new [String] )
    : ( Vec OAttr ) attrs ( vec_new [OAttr] )
    : ~ String op ( string_new )
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 { ( vec_push [String] ins ( pb_string r ) ) }   // input
        ? == fld 2 { ( vec_push [String] outs ( pb_string r ) ) }  // output
        ? == fld 4 { = op ( pb_string r ) }                        // op_type
        ? == fld 5 { : *PbR sub ( pb_submsg r ) ( vec_push [OAttr] attrs ( __parse_attr sub ) ) ( pb_free sub ) }
        { ( pb_skip r wt ) }
    }
    ^ @ ONode { op ins outs attrs }
}

// ── TensorProto (initializer) ─────────────────────────────────────
@ __parse_tensor *PbR r → OTensor {
    : ( Vec i ) dims ( vec_new [i] )
    : ~ String name ( string_new )
    : ~ i dtype 0
    : ~ i raw_start - 0 1
    : ~ i raw_len 0
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 {            // dims (int64): packed (wire 2) or single varint
            ? == wt 2 {
                : *PbR ds ( pb_submsg r )
                ~ ( pb_more ds ) { ( vec_push [i] dims ( pb_varint ds ) ) }
                ( pb_free ds )
            } { ( vec_push [i] dims ( pb_varint r ) ) }
        }
        ? == fld 2 { = dtype ( pb_varint r ) }         // data_type
        ? == fld 8 { = name ( pb_string r ) }          // name
        ? == fld 9 {                                   // raw_data
            : i len ( pb_varint r )
            = raw_start ( pb_pos r )
            = raw_len len
            ( pb_set_pos r + ( pb_pos r ) len )
        }
        { ( pb_skip r wt ) }
    }
    : i nelem ( __nelem dims )
    : ~ i host 0
    ? & >= raw_start 0 > raw_len 0 {
        : *u h ( nurl_alloc * nelem 4 )
        ( pb_set_pos r raw_start )
        ( pb_read_f32_into r h nelem )
        = host # i h
    } {}
    ^ @ OTensor { name dims nelem host }
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
@ __parse_valueinfo_name *PbR r → String {
    : ~ String name ( string_new )
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 { = name ( pb_string r ) } { ( pb_skip r wt ) }
    }
    ^ name
}

// ── GraphProto ────────────────────────────────────────────────────
@ __parse_graph *PbR r → OGraph {
    : ( Vec ONode ) nodes ( vec_new [ONode] )
    : ( Vec OTensor ) inits ( vec_new [OTensor] )
    : ~ String inp ( string_new )
    : ~ String outp ( string_new )
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 1 { : *PbR s ( pb_submsg r ) ( vec_push [ONode] nodes ( __parse_node s ) ) ( pb_free s ) }
        ? == fld 5 { : *PbR s ( pb_submsg r ) ( vec_push [OTensor] inits ( __parse_tensor s ) ) ( pb_free s ) }
        ? == fld 11 { : *PbR s ( pb_submsg r ) = inp ( __parse_valueinfo_name s ) ( pb_free s ) }
        ? == fld 12 { : *PbR s ( pb_submsg r ) = outp ( __parse_valueinfo_name s ) ( pb_free s ) }
        { ( pb_skip r wt ) }
    }
    ^ @ OGraph { nodes inits inp outp }
}

// ── ModelProto (top level) ────────────────────────────────────────
@ onnx_parse ( Vec u ) bytes → OGraph {
    : *PbR r ( pb_new bytes )
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) }
    ~ ( pb_more r ) {
        : i tag ( pb_tag r )
        : i fld ( pb_field tag )
        : i wt ( pb_wire tag )
        ? == fld 7 { : *PbR s ( pb_submsg r ) = g ( __parse_graph s ) ( pb_free s ) } { ( pb_skip r wt ) }
    }
    ( pb_free r )
    ^ g
}

// ── lookups ───────────────────────────────────────────────────────
@ graph_find_init OGraph g s name → i {   // index into inits, -1 if none
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
