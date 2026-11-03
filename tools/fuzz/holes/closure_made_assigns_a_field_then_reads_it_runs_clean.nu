// closure_made_assigns_a_field_then_reads_it_runs_clean: a closure assigns a field of its capture and then reads that field, made after the capture's borrow ended.
// Must keep compiling and running clean beside agora #444's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #444: a closure assigns a field of its capture and then reads that field, made after the capture's borrow ended
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: W { s v }
: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        = w @ W { ( string_data b ) }
    }
    : ( @ v ) f \ → v { = . w v `fresh` ( nurl_println . w v ) }
    ( f )
    ^ 0
}
