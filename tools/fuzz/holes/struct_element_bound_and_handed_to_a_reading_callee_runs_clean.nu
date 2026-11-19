// struct_element_bound_and_handed_to_a_reading_callee_runs_clean: `: H e ( vec_at [H] hs 0 )  ( look e )` in top, look only reading the field
// AGORA-495 guard: accepted - reading drops nothing
// map: §2.10 | A2 | runs-clean | - | AGORA-495
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) rows ( Vec String ) names }
: P { H h }

@ wipe H h → v { ( vec_clear [String] . h rows ) }

@ look H h → i { ^ ( vec_len [String] . h rows ) }

@ top ( Vec H ) hs → i { : H e ( vec_at [H] hs 0 ) ^ ( look e ) }

@ main → i {
    : ( Vec H ) hs ( vec_new [H] )
    : ( Vec String ) r ( vec_new [String] )
    ( vec_push [String] r ( string_from `a heap string long enough to be on the heap for sure` ) )
    : ( Vec String ) nm ( vec_new [String] )
    ( vec_push [String] nm ( string_from `another heap string long enough to be on the heap for sure` ) )
    ( vec_push [H] hs @ H { r nm } )
    : String v ( vec_at [String] . ( vec_at [H] hs 0 ) rows 0 )
    ( nurl_println_int ( top hs ) )
    ( nurl_println ( string_data v ) )
    ^ 0
}
