// thread_sync_handle_through_calls.nu — a handle that synchronises itself
// is the same handle wherever it was read out of (docs/MEMORY.md §6.5;
// agora #639). A closure several threads run may send on a Channel it
// captured: so may one that captured a struct holding the Channel, and so
// may the function it hands that struct to, however many calls on. The
// change is the Channel's own, made under its own lock; what the Channel
// was read out of is not changed by it.
//
// The control for diag_sync_handle_beside_plain_field.nu, which pins the
// other half: the plain field beside the handle is still nobody's to
// change — and for diag_sync_closure_helper_grows_read_out_handle.nu
// (agora #646): a change made through a plain handle read out of a
// parameter is a change of that parameter; reading one out is not, and a
// Channel read out the same way is still its own.
//
// Spawns real pthreads, so it carries the same declaration as
// thread_basic / arc_threads.
// requires: live

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: App { ( Channel i ) jobs Atomic hits ( Vec ( Channel i ) ) lanes i n }

// Two calls deep, through a field and through an element of a Vec field.
@ note App a i k → v {
    : b sent ( chan_send [i] . a jobs k )
    : b laned ( chan_send [i] ( vec_at [( Channel i )] . a lanes 0 ) k )
    : i before ( atomic_add . a hits 1 )
}

@ deep App a i k → v { ( note a k ) }

// A struct the program asserts synchronises itself, with an operation
// written in NURL: the assertion covers what is done through it.
: Tally { Atomic sum }

unsafe % Sync Tally {}

@ tally_add Tally t i k → v { : i before ( atomic_add . t sum k ) }

: Board { Tally tally i n }

@ score Board b i k → v { ( tally_add . b tally k ) }

// Handles read out of the parameter: an element bound to a name and only
// read, the payload of a `??` over a field, an element of what an accessor
// lends. The Channels are sent on; the row is not changed.
: Desk { ( Vec ( Vec i ) ) rows ? ( Channel i ) spare ( Vec ( Channel i ) ) lanes }

@ lanes_of Desk d → ( Vec ( Channel i ) ) { ^ . d lanes }

@ file Desk d i k → v {
    : ( Vec i ) row ( vec_at [( Vec i )] . d rows 0 )
    : i seen ( vec_len [i] row )
    ?? . d spare { T c → { : b sent ( chan_send [i] c + k seen ) } F → {} }
    : ( Channel i ) lane ( vec_at [( Channel i )] ( lanes_of d ) 0 )
    : b laned ( chan_send [i] lane k )
}

@ mkdesk → Desk {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    : ( Vec i ) row ( vec_new [i] )
    ( vec_push [i] row 7 )
    ( vec_push [( Vec i )] rows row )
    : ( Vec ( Channel i ) ) lanes ( vec_new [( Channel i )] )
    ( vec_push [( Channel i )] lanes ( chan_new [i] ) )
    ^ @ Desk { rows @ ?( Channel i ) { T ( chan_new [i] ) } lanes }
}

@ drain ( Channel i ) ch → i {
    : ~ i total 0
    : ~ b more T
    ~ more {
        ?? ( chan_try_recv [i] ch ) {
            T x → { = total + total x }
            F → { = more F }
        }
    }
    ^ total
}

@ main → i {
    : ( Vec ( Channel i ) ) lanes ( vec_new [( Channel i )] )
    ( vec_push [( Channel i )] lanes ( chan_new [i] ) )
    : App app @ App { ( chan_new [i] ) ( atomic_new 0 ) lanes 1 }
    : Board board @ Board { @ Tally { ( atomic_new 0 ) } 1 }

    // 1 — a closure kept in an Arc: every thread holding a copy runs it.
    : ( @ v i ) work \ i k → v {
        ( deep app k )
        ( score board k )
    }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i w 0
    ~ < w 4 {
        : ( Arc ( @ v i ) ) mine ( arc_clone [( @ v i )] shared )
        : ( @ v ) body \ → v {
            : ~ i j 0
            ~ < j 250 {
                : ( @ v i ) run ( arc_get [( @ v i )] mine )
                ( run 1 )
                = j + j 1
            }
        }
        ?? ( thread_spawn body ) {
            T t → { ( vec_push [Thread] ts t ) }
            F e → { ( nurl_print `spawn fail\n` ) }
        }
        = w + w 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
    ( nurl_print ( nurl_str_int ( drain . app jobs ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( drain ( vec_at [( Channel i )] . app lanes 0 ) ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( atomic_load . app hits ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( atomic_load . . board tally sum ) ) ) ( nurl_print `\n` )

    // 2 — an Arc's payload is frozen; the Channel it holds is not.
    : ( Vec ( Channel i ) ) lanes2 ( vec_new [( Channel i )] )
    ( vec_push [( Channel i )] lanes2 ( chan_new [i] ) )
    : ( Arc App ) held ( arc_new [App] @ App { ( chan_new [i] ) ( atomic_new 0 ) lanes2 2 } )
    ( deep ( arc_get [App] held ) 5 )
    ( nurl_print ( nurl_str_int ( drain . ( arc_get [App] held ) jobs ) ) ) ( nurl_print `\n` )

    // 3 — handles read out of the capture, in the function it is handed to
    // and in the closure's own body.
    : Desk desk ( mkdesk )
    : ( @ v i ) filing \ i k → v {
        ( file desk k )
        ?? . desk spare { T c → { : b sent ( chan_send [i] c k ) } F → {} }
    }
    : ( Arc ( @ v i ) ) filed ( arc_new [( @ v i )] filing )
    : ( Vec Thread ) fs ( vec_new [Thread] )
    : ~ i f 0
    ~ < f 4 {
        : ( Arc ( @ v i ) ) mine ( arc_clone [( @ v i )] filed )
        : ( @ v ) body \ → v {
            : ~ i j 0
            ~ < j 250 {
                : ( @ v i ) run ( arc_get [( @ v i )] mine )
                ( run 1 )
                = j + j 1
            }
        }
        ?? ( thread_spawn body ) {
            T t → { ( vec_push [Thread] fs t ) }
            F e → { ( nurl_print `spawn fail\n` ) }
        }
        = f + f 1
    }
    : ~ i r 0
    ~ < r ( vec_len [Thread] fs ) { : i joined ( thread_join ( vec_at [Thread] fs r ) ) = r + r 1 }
    ?? . desk spare { T c → { ( nurl_print ( nurl_str_int ( drain c ) ) ) ( nurl_print `\n` ) } F → {} }
    ( nurl_print ( nurl_str_int ( drain ( vec_at [( Channel i )] . desk lanes 0 ) ) ) ) ( nurl_print `\n` )

    // 4 — and out of an Arc's payload.
    : ( Arc Desk ) kept ( arc_new [Desk] ( mkdesk ) )
    ( file ( arc_get [Desk] kept ) 5 )
    ?? . ( arc_get [Desk] kept ) spare { T c → { ( nurl_print ( nurl_str_int ( drain c ) ) ) ( nurl_print `\n` ) } F → {} }
    ^ 0
}
