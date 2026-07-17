// tests/embed_check.nu — embed each line of a corpus file, print the full
// vector as CSV per line (for the sentence-transformers oracle compare).
//   embed_check <model-dir> <corpus.txt>
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `src/model.nu`

@ main → i {
    : ( Vec String ) av ( env_args_list )
    : ~ i rc 0
    ? >= ( vec_len [String] av ) 3 {} { ( nurl_print `usage: embed_check <model-dir> <corpus>\n` ) ^ 2 }
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F → ( string_new ) }
    : String cp ?? ( vec_get [String] av 2 ) { T x → x F → ( string_new ) }
    ?? ( embed_open ( string_data mp ) ) {
        T e → {
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
                            ? > ( string_len line ) 0 {
                                : ( Vec f ) emb ( vec_new [f] )
                                ? ( embed_encode e ( string_data line ) emb ) {
                                    : String o ( string_new )
                                    : i cnt ( vec_len [f] emb )
                                    : ~ i k 0
                                    ~ < k cnt {
                                        ? > k 0 { ( string_push_char o 44 ) } {}
                                        ?? ( vec_get [f] emb k ) { T x → { ( string_push_float o x ) } F → {} }
                                        = k + k 1
                                    }
                                    ( nurl_print ( string_data o ) ) ( nurl_print `\n` )
                                    ( string_free o )
                                } { ( nurl_print `ENCODE FAIL\n` ) = rc 1 }
                                ( vec_free [f] emb )
                            } {}
                            ( string_free line )
                            = ls + p 1
                        } {}
                        = p + p 1
                    }
                    ( string_free corpus )
                }
                F _ → { ( nurl_print `corpus read fail\n` ) = rc 1 }
            }
            ( embed_close e )
        }
        F err → { ( nurl_print `open fail: ` ) ( nurl_print ( string_data err ) ) ( nurl_print `\n` ) ( string_free err ) = rc 1 }
    }
    : ~ i k 0
    ~ < k ( vec_len [String] av ) {
        ?? ( vec_get [String] av k ) { T s2 → { ( string_free s2 ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] av )
    ^ rc
}
