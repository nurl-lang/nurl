// stdlib/std/signal.nu — signal-driven graceful shutdown for the
// HTTP server (and any other accept-loop).
//
// Single API:
//
//   ( signal_install_shutdown TcpListener listener ) → v
//   ( signal_clear_shutdown )                        → v
//   ( signal_trigger_shutdown )                      → v   test/dev only
//
// Memory model:
//
//   * `listener` is BORROWED. The runtime stores a single-slot
//     pointer to the `NurlTcp` struct; the OS-level signal handler
//     dereferences `h->fd` and calls `shutdown(fd, RDWR)`. The
//     struct itself is never freed by the handler — caller is
//     still responsible for `server_stop` (which frees the struct)
//     after the accept loop returns.
//   * Only one listener can be registered at a time. Repeat calls
//     overwrite the slot; pass NULL via `signal_clear_shutdown` to
//     forget the registration entirely.
//   * Idempotent across signal types — POSIX SIGINT/SIGTERM and
//     Win32 CTRL_C/CTRL_BREAK/CTRL_CLOSE all dispatch to the same
//     handler.
//
// Typical usage:
//
//     : ! TcpListener NetErr lr ( tcp_listen `0.0.0.0` 8080 1024 )
//     ?? lr {
//       T listener → {
//         ( signal_install_shutdown listener )
//         : HttpServer server ( server_new listener handler )
//         : ! v NetErr rr ( server_run server )
//         ( server_stop server )
//         ...
//       }
//       F e → ...
//     }
//
// The `server_run` returns Ok cleanly on listener close, so
// graceful-shutdown integration is one line at the top of the loop.

$ `stdlib/std/net.nu`

@ signal_install_shutdown TcpListener listener → v {
    : s raw . listener raw
    : i h # i raw
    ( nurl_signal_install_shutdown h )
}

@ signal_clear_shutdown → v {
    ( nurl_signal_install_shutdown 0 )
}

// For tests / dev: trigger the same shutdown path the OS-level
// handler would, without actually raising the signal (which on
// Windows can't be delivered programmatically and on POSIX could
// kill the test runner if the registration order is wrong).
@ signal_trigger_shutdown → v {
    ( nurl_signal_trigger_shutdown )
}
