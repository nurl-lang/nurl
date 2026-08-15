// send_sync_markers_ok.nu
// The other half of the Send/Sync contract: everything the derivation
// must keep ACCEPTING. A checker that rejects the nine diag_send_* /
// diag_sync_* programs is worthless if it also rejects these — the
// no-false-positive property (docs/MEMORY.md §6.3) is the constraint
// that shapes the whole design, and this file is where it is pinned.
//
// Each binding below is a shape that LOOKS like the rejected ones and
// is nonetheless correct:
//
//   Arc i          an atomic refcount around a Send+Sync payload
//   Mutex          `{ Cell c }` — structurally !Sync, and the very
//                  thing that makes contents shareable; marked by hand
//   Cell           moved to a worker, not shared: Send but !Sync, and
//                  only Arc asks the harder question
//   s / ( Vec i )  NURL spells String and every opaque FFI handle
//                  `i8*`; demoting either would demote both, and
//                  read-only sharing is ordinary correct code
//   Channel i      a thread-safe queue whose ELEMENT is Send
//   Wrapper        an Rc behind an explicit `% Send` assertion — the
//                  escape hatch, which must actually open
//   [T: Send]      the bound, satisfied by derivation for `i`
// requires: live

$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/cell.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/marker.nu`

// An Rc is not Send — unless its owner says otherwise. This is NURL's
// `unsafe impl`: the assertion stops the walk at `Wrapper`, and nothing
// inside is examined again.
: Wrapper { ( Rc i ) r }

% Send Wrapper {}

@ ship [T : Send] T v → i { ^ 1 }

@ main → i {
    : Mutex lock ( mutex_new )
    : ( Arc i ) counter ( arc_new [i] 41 )
    : Cell scratch ( cell_zero 64 )
    : s label `worker`
    : ( Vec i ) nums ( vec_new [i] )
    : ( Channel i ) ch ( chan_new [i] )
    : ( Rc i ) local ( rc_new [i] 7 )
    : Wrapper w @ Wrapper { local }

    ( vec_push [i] nums 1 )

    : ( @ v ) work \ → v {
        ( mutex_lock lock )
        ( cell_write_u8 scratch 0 9 )
        : i seen ( arc_get [i] counter )
        : i n ( vec_len [i] nums )
        : b sent ( chan_send [i] ch + seen n )
        ( nurl_print label ) ( nurl_print `\n` )
        ( mutex_unlock lock )
    }

    : !Thread ThreadErr r ( thread_spawn work )
    ?? r {
        T t → { ( thread_join t ) }
        F e → { ( nurl_print `spawn failed: ` ) ( nurl_print ( thread_err_name e ) ) ( nurl_print `\n` ) }
    }

    : ?i got ( chan_try_recv [i] ch )
    ?? got {
        T v → { ( nurl_print `got=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` ) }
        F → { ( puts `got=none` ) }
    }

    ( nurl_print `bound=` ) ( nurl_print ( nurl_str_int ( ship [i] 5 ) ) ) ( nurl_print `\n` )
    ( nurl_print `wrapped=` ) ( nurl_print ( nurl_str_int ( rc_get [i] . w r ) ) ) ( nurl_print `\n` )

    ( chan_close [i] ch )
    ( chan_free [i] ch )
    ( vec_free [i] nums )
    ( rc_free [i] local )
    ( arc_free [i] counter )
    ( cell_free scratch )
    ( mutex_free lock )
    ^ 0
}
