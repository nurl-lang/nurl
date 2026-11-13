// arc_payload_read_or_sent_through_by_closures_runs_clean: 8 threads call closure values that read the Arc's payload or send on its channel, and run closures over a payload view that read it, send on it, or push into a Vec of their own
// Guard for agora #657's fix: a closure is asked what it changes, as a named function is; a read, or a change through a % Sync handle (#639), is no change of the payload.
// main ff75baea: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #657 guard: closures reading or sending through an Arc's payload
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v ( Channel i ) h i n }

@ by_value ( Arc App ) mine → i {
    : ( @ i App ) g \ App y → i { ^ ( vec_len [i] . y v ) }
    : ( @ v App ) s \ App y → v { ( chan_send [i] . y h 1 ) }
    : i t ( g ( arc_get [App] mine ) )
    ( s ( arc_get [App] mine ) )
    ^ t
}

@ by_capture ( Arc App ) mine → i {
    : App p ( arc_get [App] mine )
    : ( @ i ) c \ → i { ^ ( vec_len [i] . p v ) }
    : ( @ v ) d \ → v { ( chan_send [i] . p h 1 ) }
    : ~ ( Vec i ) own ( vec_new [i] )
    : ( @ v ) e \ → v { ( vec_push [i] own ( vec_len [i] . p v ) ) }
    ( e )
    ( e )
    : i t + ( c ) ( vec_len [i] own )
    ( d )
    ^ t
}

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    : ~ i t 0
    ~ < k n {
        = t + t + ( by_value mine ) ( by_capture mine )
        = k + k 1
    }
    ? != t * n 6 { ( nurl_println `wrong` ) } {}
}

@ main → i {
    : ~ ( Vec i ) v0 ( vec_new [i] )
    ( vec_push [i] v0 1 )
    ( vec_push [i] v0 2 )
    : ( Arc App ) a ( arc_new [App] @ App { v0 ( chan_new [i] ) 0 } )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 8 {
        : ( Arc App ) mine ( arc_clone [App] a )
        : !Thread ThreadErr r ( thread_spawn \ → v { ( reader mine 3000 ) } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F e → {} }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    : ~ i got 0
    : ~ i want * 8 * 3000 2
    ~ < got want {
        ?? ( chan_recv [i] . ( arc_get [App] a ) h ) { T x → { = got + got x } F → { = want got } }
    }
    ( nurl_println_int got )
    ^ 0
}
