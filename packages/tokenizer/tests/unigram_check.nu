// tests/unigram_check.nu — encode each line of a corpus file with the
// Unigram tokenizer and print  ids-as-csv  per line, for oracle compare.
//   unigram_check <tokenizer.json> <corpus.txt>
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `src/unigram.nu`

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? >= ( vec_len [String] av ) 3 {} { ( nurl_print `usage: unigram_check <tokenizer.json> <corpus>\n` ) ^ 2 }
    : String tp ?? ( vec_get [String] av 1 ) { T x → x F → ( string_new ) }
    : String cp ?? ( vec_get [String] av 2 ) { T x → x F → ( string_new ) }
    ?? ( uni_load ( string_data tp ) ) {
        T u → {
            ?? ( read_file ( string_data cp ) ) {
                T corpus → {
                    : s d ( string_data corpus )
                    : i n ( string_len corpus )
                    : ~ i p 0
                    : ~ i ls 0
                    ~ <= p n {
                        ? | == p n == ( nurl_str_get d p ) 10 {
                            : String line ( string_new )
                            ( string_push_bytes line # *u + # i d ls - p ls )
                            : ( Vec i ) ids ( vec_new [i] )
                            : b _ok ( uni_encode u ( string_data line ) T ids )
                            : String o ( string_new )
                            : i cnt ( vec_len [i] ids )
                            : ~ i k 0
                            ~ < k cnt {
                                ? > k 0 { ( string_push_char o 44 ) } {}
                                ?? ( vec_get [i] ids k ) { T id → { ( string_push_int o id ) } F → {} }
                                = k + k 1
                            }
                            ( nurl_print ( string_data o ) ) ( nurl_print `\n` )
                            ( string_free o )
                            ( vec_free [i] ids )
                            ( string_free line )
                            = ls + p 1
                        } {}
                        = p + p 1
                    }
                    ( string_free corpus )
                }
                F _ → { ( nurl_print `corpus read fail\n` ) ^ 1 }
            }
            ( uni_free u )
        }
        F e → { ( nurl_print `load fail: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e ) ^ 1 }
    }
    : ~ i k 0
    ~ < k ( vec_len [String] av ) {
        ?? ( vec_get [String] av k ) { T s2 → { ( string_free s2 ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] av )
    ^ 0
}
