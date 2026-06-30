// gen_tokens.nu — pure-NURL replacement for the Python tokenize step.
//   gen_tokens <clip_merges.txt> <names.txt> <out.i64> [ctx=77]
// Writes an [n_names, ctx] int64 little-endian token tensor (the input the
// MobileCLIP text-encoder ONNX graph consumes — see tests/text_fwd.nu).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `../src/bpe.nu`

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

// Append `v` (an i64) as 8 little-endian bytes to `out`.
@ push_i64_le ( Vec u ) out i v → v {
    : ~ i k 0
    ~ < k 8 {
        ( vec_push [u] out # u & >> v * k 8 255 )
        = k + k 1
    }
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 4 { ( nurl_print `usage: gen_tokens <merges> <names.txt> <out.i64> [ctx]\n` ) ^ 2 } {}
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : String np ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
    : String op ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
    : i ctx ?? ( vec_get [String] av 4 ) { T x → ( nurl_str_to_int ( string_data x ) ) F _ → 77 }

    : Tokenizer tk ( tokenizer_load ( string_data mp ) )
    ? < . tk sot 0 { ( nurl_print `load failed\n` ) ^ 1 } {}
    : ( Vec String ) names ( read_lines ( string_data np ) )
    : i nn ( vec_len [String] names )

    : ( Vec u ) bytes ( vec_new [u] )
    : ~ i i 0
    ~ < i nn {
        : s nm ?? ( vec_get [String] names i ) { T s → ( string_data s ) F _ → `` }
        : ( Vec i ) row ( bpe_tokenize tk nm ctx )
        : ~ i k 0
        ~ < k ctx { ( push_i64_le bytes ( __ig row k ) ) = k + k 1 }
        ( vec_free [i] row )
        = i + i 1
    }
    ?? ( write_file_bytes ( string_data op ) bytes ) {
        T _ → { ( nurl_print `wrote ` ) ( nurl_print ( string_data op ) ) ( nurl_print ` (` )
                ( nurl_print ( nurl_str_int nn ) ) ( nurl_print ` x ` ) ( nurl_print ( nurl_str_int ctx ) )
                ( nurl_print ` int64)\n` ) ^ 0 }
        F _ → { ( nurl_print `write failed\n` ) ^ 1 }
    }
}
