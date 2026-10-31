// closure_kept_by_callee: a closure capturing a String handed to a callee that keeps it; String freed; closure run.
// map: §2.11 | A2 | rejected | h05 | closure capturing String kept by callee in struct; String freed, closure run
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Job { ( @ v ) f }
: Keeper { ( Vec Job ) jobs }

@ keep inout Keeper k ( @ v ) f → v { ( vec_push [Job] . k jobs @ Job { f } ) }

@ main → i {
    : ~ Keeper kp @ Keeper { ( vec_new [Job] ) }
    : String t ( string_from `captured string on the heap, long` )
    ( keep kp \ → v { ( nurl_println ( string_data t ) ) } )
    ( string_free t )
    ?? ( vec_get [Job] . kp jobs 0 ) { T j → { : ( @ v ) g . j f ( g ) } F → {} }
    ^ 0
}
