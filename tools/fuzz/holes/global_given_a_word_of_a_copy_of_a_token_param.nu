// global_given_a_word_of_a_copy_of_a_token_param: a string global given the word of mem_dup of a token parameter.
// Closed: what a parameter holds, its pseudo `%p`, is views into its caller's storage: a global given them, or another thread, outlives that storage as it outlives a view parameter's own (MEMORY.md §1, §6.5), unless the parameter escapes there whole and its caller is asked; a bare view handed back holding them answers `%k`.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §1 | A2 | rejected | - | Family G review: a string global given the word of mem_dup of a token parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

: ~ s g_last `init`

@ remember Tok t → v {
    : Tok c ( mem_dup t )
    ?? c { Word w → { = g_last w } Num n → {} Bad b → {} }
}

@ main → i {
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        ( remember @ Tok { Word ( string_data line ) } )
    }
    ( nurl_println g_last )
    ^ 0
}
