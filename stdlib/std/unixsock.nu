// stdlib/std/unixsock.nu — Unix domain sockets (AF_UNIX, local IPC).
//
// The local-only sibling of std/net.nu's TCP, same API shape: a
// filesystem-path rendezvous instead of host:port. Use it for
// Postgres-over-socket, systemd-style services, container control
// planes, or any same-host process-to-process channel — no TCP/IP
// stack, no port, and the kernel enforces filesystem permissions on
// the socket path.
//
// Pure libc FFI (socket/bind/listen/accept/connect/socketpair over
// blocking SOCK_STREAM); no runtime bridge. POSIX only — the AF_UNIX /
// SOCK_STREAM constants resolve to -1 on Win32/WASI, and every entry
// point fails cleanly (UnixSocket) there.
//
//   ( unix_listen   s path )                 → ! UnixListener UnixErr
//   ( unix_listen_with_backlog s path i n )   → ! UnixListener UnixErr
//   ( unix_accept   UnixListener l )          → ! UnixConn UnixErr
//   ( unix_connect  s path )                  → ! UnixConn UnixErr
//   ( unix_socketpair )                       → ! UnixPair UnixErr
//   ( unix_read_chunk UnixConn c i max )      → ! ( Vec u ) UnixErr  (empty = EOF)
//   ( unix_write_all  UnixConn c ( Vec u ) )  → ! v UnixErr
//   ( unix_write_str  UnixConn c s text )     → ! v UnixErr
//   ( unix_close_conn UnixConn c )            → v
//   ( unix_close_listener UnixListener l )    → v   (close + unlink the path)
//
// UnixListener / UnixConn own a raw fd; close them (close_conn /
// close_listener). unix_listen unlinks any stale socket file at `path`
// before binding, and close_listener unlinks it on the way out.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`  // read / write / close / posix_const / errno

& `c` @ socket i32 domain i32 type i32 proto → i32

& `c` @ bind i32 fd s addr i32 len → i32

& `c` @ listen i32 fd i32 backlog → i32

& `c` @ accept i32 fd s addr s addrlen → i32

& `c` @ connect i32 fd s addr i32 len → i32

& `c` @ socketpair i32 domain i32 type i32 proto s sv → i32

& `c` @ unlink s path → i32

: | UnixErr {
    UnixSocket  // socket() failed (or AF_UNIX unsupported on this OS)
    UnixBind  // bind() failed
    UnixAddrInUse  // bind() failed with EADDRINUSE
    UnixListen  // listen() failed
    UnixAccept  // accept() failed
    UnixConnect  // connect() failed
    UnixRead  // read() failed
    UnixWrite  // write() failed
    UnixClosed  // peer closed mid-write
    UnixOther
}

: UnixListener { i fd String path }
: UnixConn { i fd }
: UnixPair { UnixConn a UnixConn b }

@ unix_err_name UnixErr e → s {
    ^ ?? e {
        UnixSocket → `UnixSocket`
        UnixBind → `UnixBind`
        UnixAddrInUse → `UnixAddrInUse`
        UnixListen → `UnixListen`
        UnixAccept → `UnixAccept`
        UnixConnect → `UnixConnect`
        UnixRead → `UnixRead`
        UnixWrite → `UnixWrite`
        UnixClosed → `UnixClosed`
        UnixOther → `UnixOther`
    }
}

// ── sockaddr_un ─────────────────────────────────────────────────────

// Build a `struct sockaddr_un` on the heap with family = AF_UNIX and the
// NUL-terminated `path` copied in. Caller frees. A path longer than the
// platform's sun_path is truncated (bind then fails cleanly).
//
// The layout is NOT the same everywhere and the difference is silent:
// Linux/musl have a 2-byte sun_family at offset 0, BSD and macOS have a
// 1-byte sun_len there and sun_family at offset 1. The Linux encoding
// written on a BSD puts AF_UNIX into sun_len and leaves sun_family at
// AF_UNSPEC, so every bind and connect fails — which is what FreeBSD CI
// showed the first time this module's live section ran. So ask the
// platform for the offsets (posix_const reads them out of the real
// header via offsetof) rather than hardcoding one family's answer.
@ __un_path_cap s path → i {
    : i pmax ( posix_const `SOCKADDR_UN_PATH_MAX` )
    : i lim - pmax 1
    : i pathlen ( nurl_str_len path )
    ^ ? > pathlen lim lim pathlen
}

@ __un_addr s path → s {
    : i af ( posix_const `AF_UNIX` )
    : i foff ( posix_const `SOCKADDR_UN_FAMILY_OFF` )
    : i fsize ( posix_const `SOCKADDR_UN_FAMILY_SIZE` )
    : i poff ( posix_const `SOCKADDR_UN_PATH_OFF` )
    : i pmax ( posix_const `SOCKADDR_UN_PATH_MAX` )
    : i cap ( __un_path_cap path )
    : s addr ( nurl_zalloc + poff + pmax 2 )
    : *u ap # *u addr
    // sun_family, little-endian across however many bytes it occupies.
    : ~ i b 0
    ~ < b fsize {
        = . ap + foff b # u & >> af * 8 b 255
        = b + b 1
    }
    // Where sun_family sits at offset 1 the byte before it is sun_len.
    // BSD kernels overwrite it from the socklen argument, but a correct
    // value costs one store and makes the struct valid on its own terms.
    ? > foff 0 { = . ap 0 # u & 255 + poff + cap 1 } {}
    : ~ i k 0
    ~ < k cap { = . ap + poff k # u ( nurl_str_get path k ) = k + k 1 }
    ^ addr
}

// socklen for a path: offsetof(sun_path) + path + NUL.
@ __un_socklen s path → i {
    ^ + + ( posix_const `SOCKADDR_UN_PATH_OFF` ) ( __un_path_cap path ) 1
}

// errno → UnixErr, with `dflt` for anything unmapped.
@ __un_errno UnixErr dflt → UnixErr {
    ? == ( nurl_errno_get ) ( posix_const `EADDRINUSE` ) { ^ # UnixErr UnixAddrInUse } {}
    ^ dflt
}

// ── listener ────────────────────────────────────────────────────────

@ unix_listen_with_backlog s path i backlog → !UnixListener UnixErr {
    : i32 fd ( socket # i32 ( posix_const `AF_UNIX` ) # i32 ( posix_const `SOCK_STREAM` ) # i32 0 )
    ? < # i fd 0 { ^ @ !UnixListener UnixErr { F UnixSocket } } {}
    // clear any stale socket file (ignore result)
    : i32 _u ( unlink path )
    : s addr ( __un_addr path )
    : i32 br ( bind fd addr # i32 ( __un_socklen path ) )
    ( nurl_free addr )
    ? < # i br 0 {
        : i _c ( close # i fd )
        ^ @ !UnixListener UnixErr { F ( __un_errno # UnixErr UnixBind ) }
    } {}
    : i32 lr ( listen fd # i32 backlog )
    ? < # i lr 0 {
        : i _c ( close # i fd )
        ^ @ !UnixListener UnixErr { F UnixListen }
    } {}
    ^ @ !UnixListener UnixErr { T @ UnixListener { # i fd ( string_from path ) } }
}

@ unix_listen s path → !UnixListener UnixErr {
    ^ ( unix_listen_with_backlog path 128 )
}

@ unix_accept UnixListener l → !UnixConn UnixErr {
    : i32 cfd ( accept # i32 . l fd # s 0 # s 0 )
    ? < # i cfd 0 { ^ @ !UnixConn UnixErr { F UnixAccept } } {}
    ^ @ !UnixConn UnixErr { T @ UnixConn { # i cfd } }
}

@ unix_close_listener UnixListener l → v {
    : i _c ( close . l fd )
    : i32 _u ( unlink ( string_data . l path ) )
    ( string_free . l path )
}

// ── connect / socketpair ────────────────────────────────────────────

@ unix_connect s path → !UnixConn UnixErr {
    : i32 fd ( socket # i32 ( posix_const `AF_UNIX` ) # i32 ( posix_const `SOCK_STREAM` ) # i32 0 )
    ? < # i fd 0 { ^ @ !UnixConn UnixErr { F UnixSocket } } {}
    : s addr ( __un_addr path )
    : i32 cr ( connect fd addr # i32 ( __un_socklen path ) )
    ( nurl_free addr )
    ? < # i cr 0 {
        : i _c ( close # i fd )
        ^ @ !UnixConn UnixErr { F UnixConnect }
    } {}
    ^ @ !UnixConn UnixErr { T @ UnixConn { # i fd } }
}

@ unix_socketpair → !UnixPair UnixErr {
    : s sv ( nurl_zalloc 8 )
    : i32 r ( socketpair # i32 ( posix_const `AF_UNIX` ) # i32 ( posix_const `SOCK_STREAM` ) # i32 0 sv )
    ? < # i r 0 {
        ( nurl_free sv )
        ^ @ !UnixPair UnixErr { F UnixSocket }
    } {}
    : *i32 sp # *i32 sv
    : i fd0 # i . sp 0
    : i fd1 # i . sp 1
    ( nurl_free sv )
    ^ @ !UnixPair UnixErr { T @ UnixPair { @ UnixConn { fd0 } @ UnixConn { fd1 } } }
}

// ── read / write ────────────────────────────────────────────────────

@ unix_read_chunk UnixConn c i max → !( Vec u ) UnixErr {
    ? <= max 0 { ^ @ !( Vec u ) UnixErr { T ( vec_new [u] ) } } {}
    : ( Vec u ) buf ( vec_with_cap [u] max )
    : *u dst ( vec_data [u] buf )
    : i n ( read . c fd dst max )
    ? < n 0 {
        ( vec_free [u] buf )
        ^ @ !( Vec u ) UnixErr { F UnixRead }
    } {}
    : b _ok ( vec_set_len [u] buf n )
    ^ @ !( Vec u ) UnixErr { T buf }  // empty Vec ⇒ EOF
}

@ unix_write_all UnixConn c ( Vec u ) bytes → !v UnixErr {
    : i total ( vec_len [u] bytes )
    : *u data ( vec_data [u] bytes )
    : ~ i off 0
    ~ < off total {
        : i n ( write . c fd # *u + # i data off - total off )
        ? < n 0 { ^ @ !v UnixErr { F UnixWrite } } {}
        ? == n 0 { ^ @ !v UnixErr { F UnixClosed } } {}
        = off + off n
    }
    ^ @ !v UnixErr { T 0 }
}

@ unix_write_str UnixConn c s text → !v UnixErr {
    : i len ( nurl_str_len text )
    : ~ i off 0
    : *u data # *u text
    ~ < off len {
        : i n ( write . c fd # *u + # i data off - len off )
        ? < n 0 { ^ @ !v UnixErr { F UnixWrite } } {}
        ? == n 0 { ^ @ !v UnixErr { F UnixClosed } } {}
        = off + off n
    }
    ^ @ !v UnixErr { T 0 }
}

@ unix_close_conn UnixConn c → v {
    : i _c ( close . c fd )
}
