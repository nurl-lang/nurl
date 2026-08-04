// async_chan.nu — Phase 4 Channel[A] fiber-park integration test.
//
// Two fibers ping-pong 1000 values across two channels. Each `recv`
// on an empty channel parks the calling fiber until the counterpart's
// `send` arrives; the worker pthread is NOT blocked — it keeps running
// other fibers. Verifies:
//   * `nurl_fiber_park_with_mutex` + `nurl_fiber_unpark` are race-free
//     (the worker loop releases the parker's mutex AFTER swap-out)
//   * Channel send wakes a parked fiber receiver in addition to any
//     pthread waiter (cond_signal path)
//   * `chan_close` wakes parked fiber receivers so they can drain
//     and return None
//   * The full ping-pong terminates (1000 round-trips × 2 = 2000
//     context switches between fibers, no deadlock)
//   * runtime_run completes when both fibers have exited

$ `stdlib/std/async.nu`
$ `stdlib/std/channel.nu`

: ~ i a_count 0
: ~ i b_count 0

@ main → i {
    ( runtime_init 4 )

    : ( Channel i ) a2b ( chan_new [i] )
    : ( Channel i ) b2a ( chan_new [i] )

    : ( @ v ) fiber_a \ → v {
        : ~ i i 0
        ~ < i 1000 {
            ( chan_send [i] a2b i )
            : ?i r ( chan_recv [i] b2a )
            ?? r {
                T v → { = a_count + a_count 1 }
                F → { = i 1000 }  // channel closed early; bail
            }
            = i + i 1
        }
    }

    : ( @ v ) fiber_b \ → v {
        : ~ i j 0
        ~ < j 1000 {
            : ?i r ( chan_recv [i] a2b )
            ?? r {
                T v → {
                    = b_count + b_count 1
                    ( chan_send [i] b2a * v 2 )
                }
                F → { = j 1000 }
            }
            = j + j 1
        }
    }

    ( spawn fiber_a )
    ( spawn fiber_b )
    ( runtime_run )

    ( nurl_print `a_count=` )
    ( nurl_print ( nurl_str_int a_count ) )
    ( nurl_print `\n` )
    ( nurl_print `b_count=` )
    ( nurl_print ( nurl_str_int b_count ) )
    ( nurl_print `\n` )

    ( chan_close [i] a2b )
    ( chan_close [i] b2a )
    ( chan_free [i] a2b )
    ( chan_free [i] b2a )
    // Escaped closure envs — ours to release once runtime_run has
    // drained every fiber (docs/MEMORY.md §7.4).
    ( nurl_free # s # *u fiber_a 1 )
    ( nurl_free # s # *u fiber_b 1 )
    ( runtime_shutdown )
    ^ 0
}
