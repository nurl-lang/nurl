// closure_local_bound_from_its_parameter_only_read_runs_clean: a local bound from the parameter and only read.
// Must keep compiling and running clean beside agora #332's rule.
// main's compiler: compiled, ran clean.
// map: §2.11 | A2 | runs-clean | - | agora #332: a local bound from the parameter and only read
$ `stdlib/core/string.nu`

: V { s v }

@ main → i {
    : ~ V w @ V { `lit` }
    : ( @ v s ) show \ s p → v { : s t p ( nurl_println t ) }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        ( show ( string_data b ) )
    }
    ( nurl_println . w v )
    ^ 0
}
