// value_block_locals_live_to_the_enclosing_scope_runs_clean: the guard — a view of a value block's binding read in the same scope, the same through a call, a closure over one run there, a block's owned tail handed back (directly and through a call), one per round of a loop, and a scalar block.
// map: §1 | A2 | runs-clean | - | guard: what a value block binds lives to the end of the enclosing scope (agora #846)
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

@ id s x → s { ^ x }

@ mk i k → String { ^ ( string_from `a heap string long enough for the heap buffer` ) }

@ idS String x → String { ^ x }

@ f2 i k → String { ^ ( idS { : String t ( mk k ) t } ) }

@ f3 i k → String { ^ { : String t ( mk k ) t } }

@ main → i {
    : s d { : String t ( string_from `view read in the same scope` ) ( string_data t ) }
    ( nurl_println d )
    : s e ( id { : String t2 ( string_from `through a call, same scope` ) ( string_data t2 ) } )
    ( nurl_println e )
    : ( @ i i ) g { : String s ( string_from `abcdefghijklmnopqrstuvwxyz` ) : ( @ i i ) f \ i j → i { ^ + j ( string_len s ) } f }
    ( nurl_println_int ( g 1 ) )
    : String r ( f2 1 )
    ( nurl_println ( string_data r ) )
    : String r3 ( f3 1 )
    ( nurl_println ( string_data r3 ) )
    : ~ i k 0
    ~ < k 3 {
        : s v { : String t ( mk k ) ( string_data t ) }
        ( nurl_println v )
        = k + k 1
    }
    : i n { : String q ( mk 0 ) ( string_len q ) }
    ( nurl_println_int n )
    ^ 0
}
