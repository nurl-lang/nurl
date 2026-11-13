// arc_payload_read_and_sent_through_by_closures.nu — closures that only
// read an Arc's payload, or change it through a handle that synchronises
// itself, are accepted and run on many threads (Agora #657's guard).
// A closure value called on the payload, or a closure that captured a view
// of it, is asked what it changes, as a named function is: a read, or a
// send on the payload's channel (a `% Sync` handle, #639), is no change of
// the payload. Neither is a change to a Vec of the thread's own, or to a
// value no Arc holds.
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v ( Channel i ) h i n }

// A closure value that reads the payload.
@ reads_value ( Arc App ) mine → i {
    : ( @ i App ) g \ App y → i { ^ ( vec_len [i] . y v ) }
    ^ ( g ( arc_get [App] mine ) )
}

// …that sends on its channel.
@ sends_value ( Arc App ) mine → v {
    : ( @ v App ) g \ App y → v { ( chan_send [i] . y h 1 ) }
    ( g ( arc_get [App] mine ) )
}

// A closure over a view of the payload that reads it.
@ reads_capture ( Arc App ) mine → i {
    : App p ( arc_get [App] mine )
    : ( @ i ) c \ → i { ^ ( vec_len [i] . p v ) }
    ^ ( c )
}

// …that sends on its channel.
@ sends_capture ( Arc App ) mine → v {
    : App p ( arc_get [App] mine )
    : ( @ v ) c \ → v { ( chan_send [i] . p h 1 ) }
    ( c )
}

// …that changes a Vec of its own beside it.
@ changes_own ( Arc App ) mine → i {
    : App p ( arc_get [App] mine )
    : ~ ( Vec i ) mine2 ( vec_new [i] )
    : ( @ v ) c \ → v { ( vec_push [i] mine2 ( vec_len [i] . p v ) ) }
    ( c )
    ( c )
    ^ ( vec_len [i] mine2 )
}

// A changing closure value called on a value no Arc holds.
@ changes_local ( Arc App ) mine → i {
    : ( @ v App ) g \ App y → v { ( vec_push [i] . y v 1 ) }
    : App loc @ App { ( vec_new [i] ) ( chan_new [i] ) 0 }
    ( g loc )
    ( g loc )
    ^ + ( vec_len [i] . loc v ) ( vec_len [i] . ( arc_get [App] mine ) v )
}

// A closure parameter every caller hands a reader.
@ apply ( @ i App ) g ( Arc App ) mine → i {
    ^ ( g ( arc_get [App] mine ) )
}

@ worker ( Arc App ) mine i n → i {
    : ~ i k 0
    : ~ i s 0
    ~ < k n {
        = s + s ( reads_value mine )
        ( sends_value mine )
        = s + s ( reads_capture mine )
        ( sends_capture mine )
        = s + s ( changes_own mine )
        = s + s ( changes_local mine )
        = s + s ( apply \ App y → i { ^ + 1 ( vec_len [i] . y v ) } mine )
        = k + k 1
    }
    ^ s
}

@ main → i {
    : ~ ( Vec i ) v0 ( vec_new [i] )
    ( vec_push [i] v0 5 )
    ( vec_push [i] v0 6 )
    : ( Arc App ) a ( arc_new [App] @ App { v0 ( chan_new [i] ) 0 } )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 4 {
        : ( Arc App ) mine ( arc_clone [App] a )
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : i s ( worker mine 500 )
            ? != s * 500 13 { ( nurl_println `wrong sum` ) } {}
        } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F e → {} }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    // (Each round sends twice: 4 threads × 500 rounds.)
    : ~ i got 0
    ~ < got 4000 {
        ?? ( chan_recv [i] . ( arc_get [App] a ) h ) { T x → { = got + got x } F → { = got 4000 } }
    }
    ( nurl_println_int got )
    ( nurl_println_int ( vec_len [i] . ( arc_get [App] a ) v ) )
    ^ 0
}
