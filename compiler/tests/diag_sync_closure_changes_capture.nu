// diag_sync_closure_changes_capture.nu
// A server runs its handler on every worker at once, through one
// closure: a Vec the handler captured and pushes to would grow under two
// threads together. What a closure several threads run changes must
// synchronise itself — count in an Atomic, keep the list in a Locked
// (h342).

$ `stdlib/ext/http_server.nu`

@ main → i {
    ?? ( tcp_listen `127.0.0.1` 0 ) {
        T l → {
            : ( Vec i ) seen ( vec_new [i] )
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse {
                ( vec_push [i] seen 1 )
                ^ ( response_text 200 `ok` )
            }
            : HttpServer srv ( server_new l h )
        }
        F _ → {}
    }
    ^ 0
}
