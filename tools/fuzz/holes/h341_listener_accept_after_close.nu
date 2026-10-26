// H341: `tcp_close_listener` then `tcp_accept` on the same listener read freed memory: the close released the runtime's socket record while the handle — and every copy of it — still named it.
// Closed: closing a listener stops its runtime socket (the fd is closed once no accept is in progress) and keeps the record until the handle's last owner; an accept after the close reports NetAccept.
// v0.78.0: accepted; ASan reported heap-use-after-free in nurl_tcp_accept.
$ `stdlib/std/net.nu`

@ main → i {
    ?? ( tcp_listen `127.0.0.1` 0 ) {
        T l → {
            ( tcp_close_listener l )
            ?? ( tcp_accept l ) {
                T c → { ( puts `accepted` ) }
                F e → { ( puts ( net_err_name e ) ) }
            }
        }
        F e → { ( puts `listen failed` ) }
    }
    ^ 0
}
