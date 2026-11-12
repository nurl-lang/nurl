// field_of_a_temporary_as_a_join_arm.nu — a field read out of a call's
// temporary, or out of a `( mem_dup x )` copy, as a value of its own
// (Agora #771): bound, handed to a `sink`, as an arm of a `?` join (bare
// or as a block's tail), in a loop, two fields deep, beside a field a
// `vec_at` call lends. The field the read takes is the reader's own where
// the call handed its result over (always, for a copy); the rest of the
// temporary is dropped at the read. Each String is released once.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name String tag i n }
: O { S inner i k }

@ mks s t → S { ^ @ S { ( string_from t ) ( string_from `a tag string long enough for the heap buf` ) 1 } }

@ eat sink String s → i { ^ ( string_len s ) }

@ of_call S o b c → String { ^ ? c . ( mks `a fresh struct name long enough heap` ) name ( string_from `a fresh one long enough for the heap buffer` ) }

@ of_copy S o b c → String { ^ ? c . ( mem_dup o ) name ( string_from `a fresh one long enough for the heap buffer` ) }

@ of_copy_block S o b c → String { ^ ? c { . ( mem_dup o ) name } ( string_from `a fresh one long enough for the heap buffer` ) }

@ of_lent ( Vec S ) v b c → String { ^ ? c . ( vec_at [S] v 0 ) name ( string_from `a fresh one long enough for the heap buffer` ) }

@ main → i {
    : S o ( mks `the owner string, long enough for the heap` )
    ( nurl_println ( string_data ( of_call o T ) ) )
    ( nurl_println ( string_data ( of_call o F ) ) )
    ( nurl_println ( string_data ( of_copy o T ) ) )
    ( nurl_println ( string_data ( of_copy_block o T ) ) )
    ( nurl_println ( string_data ( of_copy_block o F ) ) )
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks `an element name long enough for the heap` ) )
    ( nurl_println ( string_data ( of_lent v T ) ) )
    : i k . ( mem_dup o ) n
    : String s . ( mem_dup o ) tag
    ( nurl_println_int + k ( eat . ( mem_dup o ) name ) )
    ( nurl_println ( string_data s ) )
    : ~ i acc 0
    : ~ i j 0
    ~ < j 20 {
        : String r ? == % j 2 0 . ( mem_dup o ) name . ( mks `loop fresh string long enough for heap` ) tag
        = acc + acc ( string_len r )
        = j + j 1
    }
    ( nurl_println_int acc )
    : O w @ O { ( mks `an inner name long enough for the heap buffer` ) 2 }
    : String deep . . ( mem_dup w ) inner name
    ( nurl_println ( string_data deep ) )
    ^ 0
}
