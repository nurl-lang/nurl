// packages/f5tts/tests/name_test.nu — how a model name is read.
//
// Three forms, and the difference between them is one character. A name with
// a separator in it is a repository reference and the vocabulary is derived
// from it by replacing the last segment; a name without one is a directory
// under the models dir, where the vocabulary sits beside the checkpoint
// already. Getting this wrong fetches the wrong file, or fetches nothing and
// reports a model that is not there.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `src/registry.nu`

@ __c s in s want → i {
    : String got ( f5_vocab_beside in )
    : b ok != 0 ( nurl_str_eq ( string_data got ) want )
    ( nurl_print ? ok `  ok   ` `  FAIL ` )
    ( nurl_print in )
    ( nurl_print ` -> ` )
    ( nurl_println ( string_data got ) )
    ( string_free got )
    ^ ? ok 0 1
}

@ __r s in b want → i {
    : b got ( f5_is_reference in )
    : b ok == got want
    ( nurl_print ? ok `  ok   ` `  FAIL ` )
    ( nurl_print `is_reference ` )
    ( nurl_print in )
    ( nurl_println ? got ` = true` ` = false` )
    ^ ? ok 0 1
}

@ main → i {
    : ~ i bad 0
    = bad + bad ( __c `owner/repo/dir/model.safetensors` `owner/repo/dir/vocab.txt` )
    = bad + bad ( __c `owner/repo/model_1250000.safetensors` `owner/repo/vocab.txt` )
    = bad + bad ( __c `/home/x/.f5tts/models/mine/model.pt` `/home/x/.f5tts/models/mine/vocab.txt` )
    = bad + bad ( __c `model.safetensors` `vocab.txt` )
    = bad + bad ( __r `owner/repo/model.safetensors` T )
    = bad + bad ( __r `my_local_model` F )
    = bad + bad ( __r `` F )
    ? == bad 0 { ( nurl_println `all ok` ) } { ( nurl_println `FAILURES` ) }
    ^ bad
}
