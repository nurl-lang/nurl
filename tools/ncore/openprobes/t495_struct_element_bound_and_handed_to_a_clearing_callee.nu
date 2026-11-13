// map: §2.10 | A2 | rejected | - | agora #495: `: H e ( vec_at [H] hs 0 ) ( wipe e )` inside a callee
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) rows }

@ wipe H h → v { ( vec_clear [String] . h rows ) }

@ top ( Vec H ) hs → v { : H e ( vec_at [H] hs 0 ) ( wipe e ) }

@ main → i {
    : ( Vec H ) hs ( vec_new [H] )
    : ( Vec String ) r ( vec_new [String] )
    ( vec_push [String] r ( string_from `a heap string long enough to be on the heap for sure` ) )
    ( vec_push [H] hs @ H { r } )
    : String v ( vec_at [String] . ( vec_at [H] hs 0 ) rows 0 )
    ( top hs )
    ( nurl_println ( string_data v ) )
    ^ 0
}
