// gen_tpe.nu — words → text prompt embeddings (tpe), entirely in pure NURL.
//
//   gen_tpe <clip_merges.txt> <text_encoder.onnx> <names.txt> <out_base>
//
// Replaces the Python tools/gen_tpe.py: the CLIP BPE tokenizer (src/bpe.nu)
// turns each class name into tokens[1,77], the MobileCLIP text-encoder ONNX
// graph (run by the pure-NURL onnx GPU runtime) turns those into a 512-d
// text feature, and we stack them into a [1, K, 512] float32 `tpe` tensor —
// exactly the runtime input src/prompt.nu feeds the YOLOE detector. Writes
// <out_base>.f32 (the tpe) and <out_base>.txt (the names).
//
// The text encoder must be the FIXED batch=1 export (tools/export_text1.py):
// one prompt per forward, stacked here.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`
$ `../src/bpe.nu`

@ p s m → v { ( nurl_print m ) }
@ pn i n → v { ( nurl_print ( nurl_str_int n ) ) }

@ read_lines s path → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( read_file_bytes path ) {
        T buf → {
            : i n ( vec_len [u] buf )
            : ~ ( Vec u ) cur ( vec_new [u] )
            : ~ i k 0
            ~ < k n {
                : i b ?? ( vec_get [u] buf k ) { T x → # i x F _ → 0 }
                ? == b 10 { ( vec_push [String] out ( bytes_to_str cur ) ) = cur ( vec_new [u] ) }
                { ? != b 13 { ( vec_push [u] cur # u b ) } {} }
                = k + k 1
            }
            ? > ( vec_len [u] cur ) 0 { ( vec_push [String] out ( bytes_to_str cur ) ) } { ( vec_free [u] cur ) }
        }
        F _ → {}
    }
    ^ out
}

// Append `v` (an i64) as 8 little-endian bytes.
@ push_i64_le ( Vec u ) out i v → v {
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] out # u & >> v * k 8 255 ) = k + k 1 }
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 5 { ( p `usage: gen_tpe <clip_merges.txt> <text_encoder.onnx> <names.txt> <out_base>\n` ) ^ 2 } {}
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : String modp ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
    : String np ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
    : String ob ?? ( vec_get [String] av 4 ) { T x → x F _ → ( string_new ) }

    : Tokenizer tk ( tokenizer_load ( string_data mp ) )
    ? < . tk sot 0 { ( p `failed to load merges (` ) ( p ( string_data mp ) ) ( p `)\n` ) ^ 1 } {}

    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes ( string_data modp ) ) { T mb → = g ( onnx_parse mb ) F _ → { ( p `model read fail\n` ) ^ 1 } }

    : ( Vec String ) names ( read_lines ( string_data np ) )
    : i nc ( vec_len [String] names )
    ? == nc 0 { ( p `no names\n` ) ^ 1 } {}

    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( p `gpu/kernels failed\n` ) ^ 1 } {}
    ( p `device: ` ) ( p ( rt_name e ) ) ( p `\n` )

    // Run each prompt through the batch=1 text encoder, stack into tpe bytes.
    : ( Vec u ) tpe ( vec_new [u] )
    : ~ i i 0
    ~ < i nc {
        : s nm ?? ( vec_get [String] names i ) { T s → ( string_data s ) F _ → `` }
        // tokens[1,77] as an int64 LE byte buffer, kept alive across the run
        : ( Vec i ) row ( bpe_tokenize tk nm 77 )
        : ( Vec u ) tb ( vec_new [u] )
        : ~ i t2 0
        ~ < t2 77 { ( push_i64_le tb ( __ig row t2 ) ) = t2 + t2 1 }
        ( vec_free [i] row )

        : RTensor out ( rt_run_tokens e g # *u ( vec_data [u] tb ) 1 77 )
        : *u feat ( rt_download e out )
        : i fn . out nelem
        // the download buffer is raw f32 little-endian: copy its bytes verbatim,
        // 8 bytes (one i64 word) at a time (512 floats = 256 words).
        : i nwords / * fn 4 8
        : ~ i k 0
        ~ < k nwords { ( push_i64_le tpe ( nurl_peek feat k ) ) = k + k 1 }
        ( vec_free [u] tb )
        ( p `  ` ) ( p nm ) ( p ` -> ` ) ( pn fn ) ( p ` floats\n` )
        = i + i 1
    }
    ( rt_close e )

    : String fp ( string_from ( string_data ob ) )
    ( string_push_str fp `.f32` )
    : String tp ( string_from ( string_data ob ) )
    ( string_push_str tp `.txt` )
    ?? ( write_file_bytes ( string_data fp ) tpe ) {
        T _ → { ( p `wrote ` ) ( p ( string_data fp ) ) ( p ` ([1,` ) ( pn nc ) ( p `,512])\n` ) }
        F _ → { ( p `tpe write failed\n` ) ^ 1 }
    }
    : String body ( string_new )
    : ~ i z 0
    ~ < z nc { ?? ( vec_get [String] names z ) { T s → { ( string_push_str body ( string_data s ) ) ( string_push_char body 10 ) } F _ → {} } = z + z 1 }
    ?? ( write_file ( string_data tp ) ( string_data body ) ) {
        T _ → ( p `wrote names\n` )
        F _ → ( p `names write failed\n` )
    }
    ^ 0
}
