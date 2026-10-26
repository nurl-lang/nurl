// diag_sync_server_handler_capture.nu
// An HTTP server runs its handler on every worker at once. A handler
// capturing a PNCounter (one state, changed in place with no lock) would
// have them change it together; server_new keeps the closure in the
// server, a handle asserted Sync, so the capture must be Sync too.
// Count in an Atomic, or behind a Locked, instead.

$ `stdlib/ext/http_server.nu`
$ `stdlib/dist/crdt.nu`

@ main → i {
    ?? ( tcp_listen `127.0.0.1` 0 ) {
        T l → {
            : PNCounter hits ( pncounter_new )
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse {
                ( pncounter_inc hits 1 1 )
                ^ ( response_text 200 `ok` )
            }
            : HttpServer srv ( server_new l h )
        }
        F _ → {}
    }
    ^ 0
}
