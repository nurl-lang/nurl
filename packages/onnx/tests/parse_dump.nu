// packages/onnx/tests/parse_dump.nu — canonical text dump of a parsed graph.
//
// Prints every node, attribute and initializer of a parsed ONNX model as
// deterministic text, including a position-sensitive checksum over each
// weight block. Two parser implementations can then be compared byte for
// byte over a whole model corpus:
//
//   parse_dump <model.onnx>
//
// No device is needed — this exercises model.nu (and its protobuf reader)
// only, so it runs on a GPU-less box. Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/parse_dump.nu /tmp/pd

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/protobuf.nu`
$ `src/model.nu`

& `c` @ nurl_peek_i32 *u base i idx → i32

@ p s x → v { ( nurl_print x ) }

@ pi i x → v { ( nurl_print ( nurl_str_int x ) ) }

@ pstr String x → v { ( nurl_print ( string_data x ) ) }

// Position-sensitive checksum over a weight block: every element is mixed
// with its own index, so a reordering is as visible as a changed value.
@ __checksum i host i dtype i nelem → v {
    ? == host 0 { ( p `none` ) ^ {} } {}
    : *u b # *u host
    : ~ i hx 0
    : ~ i hs 0
    : ~ i first 0
    : ~ i last 0
    : ~ i k 0
    ~ < k nelem {
        : ~ i value 0
        ? == dtype 7 { = value ( nurl_peek b k ) } { = value # i ( nurl_peek_i32 b k ) }
        ? == k 0 { = first value } {}
        = last value
        = hx ^^ hx ^^ value k
        = hs + hs value
        = k + k 1
    }
    ( p `xor=` ) ( pi hx ) ( p ` sum=` ) ( pi hs )
    ( p ` first=` ) ( pi first ) ( p ` last=` ) ( pi last )
}

@ __dump_ints ( Vec i ) v → v {
    ( p `[` )
    : ~ i k 0
    ~ < k ( vec_len [i] v ) {
        ? > k 0 { ( p `,` ) } {}
        ?? ( vec_get [i] v k ) { T x → ( pi x ) F _ → ( p `?` ) }
        = k + k 1
    }
    ( p `]` )
}

@ __dump_strs ( Vec String ) v → v {
    ( p `[` )
    : ~ i k 0
    ~ < k ( vec_len [String] v ) {
        ? > k 0 { ( p `,` ) } {}
        ?? ( vec_get [String] v k ) { T x → ( pstr x ) F _ → ( p `?` ) }
        = k + k 1
    }
    ( p `]` )
}

@ __dump_attr OAttr a → v {
    ( p `    attr name=` ) ( pstr . a name )
    ( p ` kind=` ) ( pi . a kind )
    ( p ` fbits=` ) ( pi ( f64_to_bits . a f ) )
    ( p ` i=` ) ( pi . a i )
    ( p ` s=` ) ( pstr . a s )
    ( p ` ints=` ) ( __dump_ints . a ints )
    ( p `\n` )
}

@ __dump_node ONode n i k → v {
    ( p `  node ` ) ( pi k )
    ( p ` op=` ) ( pstr . n op_type )
    ( p ` in=` ) ( __dump_strs . n inputs )
    ( p ` out=` ) ( __dump_strs . n outputs )
    ( p ` attrs=` ) ( pi ( vec_len [OAttr] . n attrs ) )
    ( p `\n` )
    : ~ i j 0
    ~ < j ( vec_len [OAttr] . n attrs ) {
        ?? ( vec_get [OAttr] . n attrs j ) { T a → ( __dump_attr a ) F _ → {} }
        = j + j 1
    }
}

@ __dump_init OTensor t i k → v {
    ( p `  init ` ) ( pi k )
    ( p ` name=` ) ( pstr . t name )
    ( p ` dtype=` ) ( pi . t dtype )
    ( p ` nelem=` ) ( pi . t nelem )
    ( p ` dims=` ) ( __dump_ints . t dims )
    ( p ` data=` ) ( __checksum . t host . t dtype . t nelem )
    ( p `\n` )
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    : ~ b have F
    : ~ ( Vec u ) mb ( vec_new [u] )
    ?? ( vec_get [String] av 1 ) {
        T pathstr → {
            ?? ( read_file_bytes ( string_data pathstr ) ) {
                T bytes → { ( vec_free [u] mb ) = mb bytes = have T }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( vec_free_with [String] av \ String x → v { ( string_free x ) } )
    ? ! have { ( p `usage: parse_dump <model.onnx>\n` ) ( vec_free [u] mb ) ^ 1 } {}
    : ~ OGraph g ( onnx_empty_graph )
    : ~ b bad F
    : ~ ProtoError perr @ ProtoError { ProtoTruncated 0 }
    ?? ( onnx_parse_checked mb ) {
        T parsed → { ( graph_free g ) = g parsed }
        F e → { = bad T = perr e }
    }
    ( vec_free [u] mb )
    ? bad {
        ( p `parse-error=` ) ( p ( proto_error_name . perr code ) )
        ( p ` offset=` ) ( pi . perr offset ) ( p `\n` )
        ( graph_free g ) ^ 3
    } {}
    ( p `input=` ) ( pstr . g input_name ) ( p `\n` )
    ( p `output=` ) ( pstr . g output_name ) ( p `\n` )
    ( p `output1=` ) ( pstr . g output1_name ) ( p `\n` )
    ( p `nodes=` ) ( pi ( vec_len [ONode] . g nodes ) ) ( p `\n` )
    : ~ i k 0
    ~ < k ( vec_len [ONode] . g nodes ) {
        ?? ( vec_get [ONode] . g nodes k ) { T n → ( __dump_node n k ) F _ → {} }
        = k + k 1
    }
    ( p `inits=` ) ( pi ( vec_len [OTensor] . g inits ) ) ( p `\n` )
    = k 0
    ~ < k ( vec_len [OTensor] . g inits ) {
        ?? ( vec_get [OTensor] . g inits k ) { T t → ( __dump_init t k ) F _ → {} }
        = k + k 1
    }
    ( graph_free g )
    ^ 0
}
