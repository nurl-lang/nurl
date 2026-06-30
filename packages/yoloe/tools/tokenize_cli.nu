// tokenize_cli.nu — print CLIP BPE token ids for each input line.
//   tokenize_cli <clip_merges.txt> <names.txt>
// Emits one line per name: the space-separated encode() ids (no sot/eot).

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

@ main → i {
    : ( Vec String ) av ( env_args_list )
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_from `assets/clip_merges.txt` ) }
    : String np ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
    : Tokenizer tk ( tokenizer_load ( string_data mp ) )
    ? < . tk sot 0 { ( nurl_print `load failed\n` ) ^ 1 } {}
    : ( Vec String ) names ( read_lines ( string_data np ) )
    : i nn ( vec_len [String] names )
    : ~ i i 0
    ~ < i nn {
        : s nm ?? ( vec_get [String] names i ) { T s → ( string_data s ) F _ → `` }
        : ( Vec i ) ids ( bpe_encode tk nm )
        : i ng ( vec_len [i] ids )
        : ~ i k 0
        ~ < k ng { ( nurl_print ( nurl_str_int ( __ig ids k ) ) ) ? < k - ng 1 { ( nurl_print ` ` ) } {} = k + k 1 }
        ( nurl_print `\n` )
        ( vec_free [i] ids )
        = i + i 1
    }
    ^ 0
}
