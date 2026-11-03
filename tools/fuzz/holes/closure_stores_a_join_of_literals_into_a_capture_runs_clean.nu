// closure_stores_a_join_of_literals_into_a_capture_runs_clean: a closure binds a join of two literals, then stores it into a struct it captures.
// Must keep compiling and running clean beside agora #448's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #448: a closure binds a join of two literals, then stores it into a struct it captures
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: V { s v }

@ setv inout V x s t → v { = x @ V { t } }

@ main → i {
    : ~ V w @ V { `lit` }
    : ( @ v s ) setw \ s p → v { : s t ? > ( nurl_str_len p ) 0 `a` `x` = w @ V { t } }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        ( setw ( string_data b ) )
    }
    ( nurl_println . w v )
    ^ 0
}
