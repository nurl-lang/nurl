// channel_basic.nu — Phase 5.3 Channel[A] sanity test.
//
// Deterministic by construction: producer pushes a known sequence,
// consumer recvs into a shared accumulator under a mutex, joins close
// the loop, then we observe the totals. Live thread/channel exercise
// is gated behind NURL_NET_TESTS=1 (same convention as net_loopback,
// http_server_seq, thread_basic).
//
// As of 2026-05-17 Channel is generic — every call site supplies the
// element type via `[T-arg]`. This test exercises the `[i]`
// instantiation; see channel_string.nu for a `[s]` (string element)
// exercise.

$ `stdlib/std/channel.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

: ~ i sum_consumed 0
: ~ i count_consumed 0

@ print_kv s label i value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_int value ) )
    ( nurl_print `\n` )
}

@ run_live_channel_tests → v {
    // ── Test 1: single producer → single consumer ────────────────
    : ( Channel i ) ch ( chan_new [i] )

    : ( @ v ) producer \ → v {
        : ~ i k 0
        ~ < k 100 {
            ( chan_send [i] ch + k 1 )  // sends 1..100
            = k + k 1
        }
        ( chan_close [i] ch )
    }

    : ( @ v ) consumer \ → v {
        : ~ b done F
        ~ ! done {
            : ?i opt ( chan_recv [i] ch )
            ?? opt {
                T v → {
                    = sum_consumed + sum_consumed v
                    = count_consumed + count_consumed 1
                }
                F → { = done T }
            }
        }
    }

    : !Thread ThreadErr rp ( thread_spawn producer )
    : !Thread ThreadErr rc ( thread_spawn consumer )
    ?? rp { T t → { ( thread_join t ) } F e → { ( nurl_print `prod fail\n` ) } }
    ?? rc { T t → { ( thread_join t ) } F e → { ( nurl_print `cons fail\n` ) } }

    ( print_kv `T1 sum` sum_consumed )  // 1+2+...+100 = 5050
    ( print_kv `T1 count` count_consumed )  // 100
    ( chan_free [i] ch )

    // ── Test 2: closed-channel send returns F ─────────────────────
    : ( Channel i ) ch2 ( chan_new [i] )
    ( chan_close [i] ch2 )
    : b ok ( chan_send [i] ch2 42 )
    ( nurl_print `T2 send_to_closed=` )
    ( nurl_print ? ok `T` `F` )
    ( nurl_print `\n` )
    : ?i drained ( chan_recv [i] ch2 )
    ?? drained {
        T v → { ( nurl_print `T2 recv=Some\n` ) }
        F → { ( nurl_print `T2 recv=None\n` ) }
    }
    ( chan_free [i] ch2 )

    // ── Test 3: try_recv on empty channel returns None ────────────
    : ( Channel i ) ch3 ( chan_new [i] )
    : ?i tr1 ( chan_try_recv [i] ch3 )
    ?? tr1 {
        T v → { ( nurl_print `T3 tr_empty=Some\n` ) }
        F → { ( nurl_print `T3 tr_empty=None\n` ) }
    }
    ( chan_send [i] ch3 7 )
    : ?i tr2 ( chan_try_recv [i] ch3 )
    ?? tr2 {
        T v → { ( print_kv `T3 tr_after_send` v ) }
        F → { ( nurl_print `T3 tr_after_send=None\n` ) }
    }
    ( chan_close [i] ch3 )
    ( chan_free [i] ch3 )

    // ── Test 4: 2 producers × 50 items, 1 consumer ─────────────────
    = sum_consumed 0
    = count_consumed 0
    : ( Channel i ) ch4 ( chan_new [i] )

    : ( @ v ) prod_a \ → v {
        : ~ i k 0
        ~ < k 50 {
            ( chan_send [i] ch4 + k 1 )  // 1..50
            = k + k 1
        }
    }
    : ( @ v ) prod_b \ → v {
        : ~ i k 0
        ~ < k 50 {
            ( chan_send [i] ch4 + k 51 )  // 51..100
            = k + k 1
        }
    }
    : ( @ v ) cons2 \ → v {
        : ~ b done F
        ~ ! done {
            : ?i opt ( chan_recv [i] ch4 )
            ?? opt {
                T v → {
                    = sum_consumed + sum_consumed v
                    = count_consumed + count_consumed 1
                }
                F → { = done T }
            }
        }
    }

    : !Thread ThreadErr ra ( thread_spawn prod_a )
    : !Thread ThreadErr rb ( thread_spawn prod_b )
    : !Thread ThreadErr rcons ( thread_spawn cons2 )
    ?? ra { T t → { ( thread_join t ) } F e → {} }
    ?? rb { T t → { ( thread_join t ) } F e → {} }
    ( chan_close [i] ch4 )  // both producers done → safe to close
    ?? rcons { T t → { ( thread_join t ) } F e → {} }

    ( print_kv `T4 sum` sum_consumed )  // 1+...+100 = 5050
    ( print_kv `T4 count` count_consumed )  // 100
    ( chan_free [i] ch4 )
}

@ main → i {
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → {
            ( string_free s )
            ( run_live_channel_tests )
        }
        F → { ( nurl_print `live channel tests skipped (set NURL_NET_TESTS=1 to enable)\n` ) }
    }
    ^ 0
}
