// bpe_test.nu — verify the pure-NURL CLIP BPE tokenizer against open_clip's
// SimpleTokenizer reference (the tokenizer MobileCLIP wraps).
//   bpe_test <clip_merges.txt>

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `../src/bpe.nu`

@ p s m → v { ( nurl_print m ) }
@ pn i n → v { ( nurl_print ( nurl_str_int n ) ) }

// Compare encode(text) against a space-free expected id list (Vec i).
@ check Tokenizer tk s text ( Vec i ) exp → i {
    : ( Vec i ) got ( bpe_encode tk text )
    ( p `  ` ) ( p text ) ( p ` -> ` )
    : i ng ( vec_len [i] got )
    : ~ i k 0
    ~ < k ng { ( pn ( __ig got k ) ) ( p ` ` ) = k + k 1 }
    : ~ i ok 1
    ? != ng ( vec_len [i] exp ) { = ok 0 } {
        : ~ i j 0
        ~ < j ng { ? != ( __ig got j ) ( __ig exp j ) { = ok 0 } {} = j + j 1 }
    }
    ( p ? == ok 1 `[ok]\n` `[FAIL]\n` )
    ( vec_free [i] got )
    ^ ok
}

@ mk → ( Vec i ) { ^ ( vec_new [i] ) }
@ add ( Vec i ) v i x → ( Vec i ) { ( vec_push [i] v x ) ^ v }

@ main → i {
    : ( Vec String ) av ( env_args_list )
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_from `assets/clip_merges.txt` ) }

    : Tokenizer tk ( tokenizer_load ( string_data mp ) )
    ? < . tk sot 0 { ( p `failed to load merges (` ) ( p ( string_data mp ) ) ( p `)\n` ) ^ 1 } {}
    ( p `loaded: sot ` ) ( pn . tk sot ) ( p ` eot ` ) ( pn . tk eot ) ( p `\n` )

    : ~ i fails 0
    = fails + fails ? == 0 ( check tk `dog`              ( add ( mk ) 1929 ) ) 1 0
    = fails + fails ? == 0 ( check tk `bicycle`          ( add ( mk ) 11652 ) ) 1 0
    = fails + fails ? == 0 ( check tk `potted plant`     ( add ( add ( mk ) 48581 ) 3912 ) ) 1 0
    = fails + fails ? == 0 ( check tk `traffic light`    ( add ( add ( mk ) 3399 ) 1395 ) ) 1 0
    = fails + fails ? == 0 ( check tk `cell phone`       ( add ( add ( mk ) 5533 ) 1951 ) ) 1 0
    = fails + fails ? == 0 ( check tk `person`           ( add ( mk ) 2533 ) ) 1 0
    = fails + fails ? == 0 ( check tk `a photo of a cat` ( add ( add ( add ( add ( add ( mk ) 320 ) 1125 ) 539 ) 320 ) 2368 ) ) 1 0
    = fails + fails ? == 0 ( check tk `hot-dog`          ( add ( add ( add ( mk ) 2069 ) 268 ) 1929 ) ) 1 0
    = fails + fails ? == 0 ( check tk `don't`            ( add ( add ( mk ) 847 ) 713 ) ) 1 0

    ? == fails 0 { ( p `BPE TOKENIZER MATCH\n` ) ^ 0 } { ( p `MISMATCH fails=` ) ( pn fails ) ( p `\n` ) ^ 1 }
}
