// closure_made_assigns_in_a_branch_then_reads_there_runs_clean: a closure assigns its capture in a branch and reads it in that branch, made after the capture's borrow ended.
// Must keep compiling and running clean beside agora #444's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #444: a closure assigns its capture in a branch and reads it in that branch, made after the capture's borrow ended
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: V { s v }
: T2 { s v String o }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        = w @ W { ( string_data b ) }
    }
    : ( @ v b ) f \ b k → v { ? k { = w @ W { `fresh` } ( nurl_println . w v ) } {} }
    ( f T )
    ^ 0
}
