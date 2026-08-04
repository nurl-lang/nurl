// http_server_stop_direct.nu — regression lock for the direct
// `server_stop`-from-another-thread shutdown path (critic.md B19).
//
// `server_run_pool`'s contract has always documented this shape:
// workers block in accept, another thread calls `server_stop s`.
// Pre-fix, that path was a heap-use-after-free: pool workers hold no
// reference on the listener, so `server_stop`'s nurl_tcp_close freed
// the struct while every worker was still polling it
// (runtime.c nurl_tcp_accept's shutting_down check; 3/3 reproducible
// under ASan). `server_run` (single-threaded) had the same race.
//
// The fix mirrors `server_run_async`'s existing contract: both run
// functions retain the listener for the spawn→join window and release
// it only after no worker can touch the handle, so a concurrent stop
// defers the struct free instead of racing it.
//
// Drives both fixed paths end to end — no soft-close
// `tcp_shutdown_listener` staging, no deferred final `server_stop`;
// just the documented one-call shutdown:
//
//   phase 1: 4-worker pool on 127.0.0.1:18801, stopper thread sleeps
//            200 ms then calls `server_stop` directly. Pool must
//            return Ok (no hang, no crash).
//   phase 2: same shape against single-threaded `server_run` on
//            127.0.0.1:18802.
//
// run_san_tests.sh asserts the ASan-clean part; the plain runner
// asserts no hang / clean exit.
// requires: live

$ `stdlib/ext/http_server.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

// One phase: listen on `port`, spawn a thread that direct-stops the
// server after 200 ms, run with `n_workers` (0 ⇒ single-threaded
// server_run), report the outcome under `label`.
@ run_stop_direct_phase i port i n_workers s label → v {
    : !TcpListener NetErr lr ( tcp_listen_with_backlog `127.0.0.1` port 16 )
    ?? lr {
        F e → {
            ( nurl_print label )
            ( nurl_print `: listen failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
        }
        T listener → {
            : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse {
                ^ ( response_text 200 `ok\n` )
            }
            : HttpServer srv ( server_new listener handler )

            : ( @ v ) stopper \ → v {
                ( sleep_ms 200 )
                // The point of the test: ONE direct call, from another
                // thread, while workers are blocked in accept.
                ( server_stop srv )
            }
            : !Thread ThreadErr st ( thread_spawn stopper )
            ?? st {
                T t → {
                    : ~ b clean F
                    ? > n_workers 1 {
                        : !v NetErr rp ( server_run_pool srv n_workers )
                        ?? rp { T _ → { = clean T } F e → {} }
                    } {
                        : !v NetErr rp ( server_run srv )
                        ?? rp { T _ → { = clean T } F e → {} }
                    }
                    ( nurl_print label )
                    ? clean
                    { ( nurl_print `: clean shutdown\n` ) }
                    { ( nurl_print `: run returned error\n` ) }
                    ( thread_join t )
                    : *u stopper_env # *u stopper 1
                    ( nurl_free # s stopper_env )
                }
                F e → {
                    ( nurl_print label )
                    ( nurl_print `: stopper spawn failed: ` )
                    ( nurl_print ( thread_err_name e ) )
                    ( nurl_print `\n` )
                    ( server_stop srv )
                }
            }
        }
    }
}

@ main → i {
    ( run_stop_direct_phase 18801 4 `pool` )
    ( run_stop_direct_phase 18802 0 `seq` )
    ^ 0
}
