// closure_made_while_a_holders_source_lives_runs_clean: the closure made and called while the String lives.
// Must keep compiling and running clean beside agora #358's rule.
// main's compiler: compiled, ran clean.
// map: §2.11 | A2 | runs-clean | - | agora #358: the closure made and called while the String lives
$ `stdlib/core/string.nu`

: W { s v }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        = w @ W { ( string_data b ) }
        : ( @ v ) f \ → v { ( nurl_println . w v ) }
        ( f )
    }
    ^ 0
}
