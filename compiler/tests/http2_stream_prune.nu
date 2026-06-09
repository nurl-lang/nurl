// http2_stream_prune.nu — offline regression for __h2_prune_closed and
// the closed-stream accounting fix in stdlib/ext/http2_conn.nu.
//
// Bug: the new-stream admission check counted EVERY entry in the stream
// table, including CLOSED streams that are never removed. RFC 9113
// §5.1.2 says only "open"/"half-closed" streams count toward
// SETTINGS_MAX_CONCURRENT_STREAMS, so on a long-lived connection the
// closed records pile up until the 256 cap is hit and all further
// requests are wrongly REFUSED — and the table grows without bound (the
// memory dimension of Rapid Reset, CVE-2023-44487).
//
// Fix: __h2_prune_closed drops closed streams (freeing their buffers)
// before each admission count. This test builds a connection table by
// hand, prunes, and asserts only the active streams survive — with their
// ids/order intact. No socket: runs on every CI host.

$ `stdlib/ext/http2_conn.nu`

@ mkstream i id i st → H2Stream {
    // Give closed streams some buffer content so the prune's free path is
    // exercised (and shows up under the sanitized runner).
    : ( Vec u ) hb ( vec_new [u] )
    ( vec_push [u] hb # u 0xAB )
    ( vec_push [u] hb # u 0xCD )
    : ( Vec u ) bd ( vec_new [u] )
    ( vec_push [u] bd # u 0xEF )
    ^ @ H2Stream { id st hb F F ( vec_new [Header] ) bd F 65535 65535 }
}

// Build an H2Connection with an empty stream table and a dummy socket
// handle (prune never touches `tcp`). Mirrors h2_conn_new's field order.
@ mkconn → H2Connection {
    : TcpConn tc @ TcpConn { # s 0 }
    ^ @ H2Connection {
        tc
        4096 0 256 65535 16384 0
        4096 1 0 65535 16384 0
        ( hpack_dyn_new 4096 )
        ( hpack_dyn_new 4096 )
        ( vec_new [H2Stream] )
        ( h2_default_initial_window_size )
        ( h2_default_initial_window_size )
        0
        F
        0
    }
}

@ assert_eq s label i got i want ( Vec i ) fails → v {
    ? == got want {
        ( nurl_print `  ok   ` ) ( nurl_print label )
        ( nurl_print ` = ` ) ( nurl_print ( nurl_str_int got ) ) ( nurl_print `\n` )
    } {
        ( nurl_print `  FAIL ` ) ( nurl_print label )
        ( nurl_print ` got ` ) ( nurl_print ( nurl_str_int got ) )
        ( nurl_print ` want ` ) ( nurl_print ( nurl_str_int want ) ) ( nurl_print `\n` )
        ( vec_push [i] fails 1 )
    }
}

@ run → i {
    : ( Vec i ) fails ( vec_new [i] )

    // ── Mixed table: 1 closed, 3 open, 5 closed, 7 half-closed-remote,
    //    9 closed → after prune only 3 and 7 (active) survive, in order.
    : ~ H2Connection c ( mkconn )
    ( vec_push [H2Stream] . c streams ( mkstream 1 ( h2_state_closed ) ) )
    ( vec_push [H2Stream] . c streams ( mkstream 3 ( h2_state_open ) ) )
    ( vec_push [H2Stream] . c streams ( mkstream 5 ( h2_state_closed ) ) )
    ( vec_push [H2Stream] . c streams ( mkstream 7 ( h2_state_half_closed_remote ) ) )
    ( vec_push [H2Stream] . c streams ( mkstream 9 ( h2_state_closed ) ) )

    = c ( __h2_prune_closed c )
    ( assert_eq `mixed: active count` ( vec_len [H2Stream] . c streams ) 2 fails )

    : *H2Stream sp ( vec_data [H2Stream] . c streams )
    ? > ( vec_len [H2Stream] . c streams ) 0 {
        : H2Stream s0 . sp 0
        ( assert_eq `mixed: survivor[0] id`    . s0 id    3 fails )
        ( assert_eq `mixed: survivor[0] state` . s0 state ( h2_state_open ) fails )
    } {}
    ? > ( vec_len [H2Stream] . c streams ) 1 {
        : H2Stream s1 . sp 1
        ( assert_eq `mixed: survivor[1] id`    . s1 id    7 fails )
        ( assert_eq `mixed: survivor[1] state` . s1 state ( h2_state_half_closed_remote ) fails )
    } {}
    ( h2_conn_free c )

    // ── All-closed table → empty after prune (the Rapid Reset / cap-
    //    exhaustion case): pile up 300 closed streams, prune to zero.
    : ~ H2Connection c2 ( mkconn )
    : ~ i k 0
    ~ < k 300 {
        ( vec_push [H2Stream] . c2 streams ( mkstream + 1 * k 2 ( h2_state_closed ) ) )
        = k + k 1
    }
    = c2 ( __h2_prune_closed c2 )
    ( assert_eq `all-closed: count` ( vec_len [H2Stream] . c2 streams ) 0 fails )
    ( h2_conn_free c2 )

    // ── All-active table → unchanged.
    : ~ H2Connection c3 ( mkconn )
    ( vec_push [H2Stream] . c3 streams ( mkstream 1 ( h2_state_open ) ) )
    ( vec_push [H2Stream] . c3 streams ( mkstream 3 ( h2_state_half_closed_remote ) ) )
    = c3 ( __h2_prune_closed c3 )
    ( assert_eq `all-active: count` ( vec_len [H2Stream] . c3 streams ) 2 fails )
    ( h2_conn_free c3 )

    : i n ( vec_len [i] fails )
    ( vec_free [i] fails )
    ^ n
}

@ main → i {
    : i f ( run )
    ? == f 0 { ( nurl_print `http2_stream_prune: all checks passed\n` ) }
            { ( nurl_print `http2_stream_prune: FAILURES\n` ) }
    ^ f
}
