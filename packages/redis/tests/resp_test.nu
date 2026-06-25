// packages/redis/tests/resp_test.nu — pure unit tests for the RESP codec.
// No server required. Build and run:
//   cd packages/redis
//   NURL_STDLIB=<repo-root> ../../build/nurlc tests/resp_test.nu > /tmp/t.ll
//   clang /tmp/t.ll <repo-root>/stdlib/runtime.o -o /tmp/resp_test && /tmp/resp_test

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/resp.nu`

: ~ i g_fail 0

@ __ok s name b cond → v {
    ? cond { ( nurl_print `ok   ` ) } { ( nurl_print `FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

// Build a ( Vec u ) byte buffer from a raw string (NUL-safe for our ASCII
// test vectors, which contain none).
@ __buf s raw → ( Vec u ) {
    : i n ( nurl_str_len raw )
    : ( Vec u ) v ( vec_new [u] )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( nurl_str_get raw k ) ) = k + k 1 }
    ^ v
}

@ __args2 s a s b → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from a ) )
    ( vec_push [String] v ( string_from b ) )
    ^ v
}

@ __free_args ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n { ?? ( vec_get [String] v k ) { T s → ( string_free s ) F _ → {} } = k + k 1 }
    ( vec_free [String] v )
}

// Compare a ( Vec u ) against an expected raw string.
@ __bytes_eq ( Vec u ) v s raw → b {
    : i n ( nurl_str_len raw )
    ? != ( vec_len [u] v ) n { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ < k n {
        ? != ?? ( vec_get [u] v k ) { T x → # i x F _ → -1 } ( nurl_str_get raw k ) { = ok F } {}
        = k + k 1
    }
    ^ ok
}

@ main → i {
    // ── encode: SET foo bar ──
    : ( Vec String ) cmd ( __args2 `GET` `foo` )
    : ( Vec u ) enc ( resp_encode cmd )
    ( __ok `encode GET foo` ( __bytes_eq enc `*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n` ) )
    ( vec_free [u] enc )
    ( __free_args cmd )

    // ── simple string +OK ──
    : ( Vec u ) b1 ( __buf `+OK\r\n` )
    : RespParse p1 ( resp_parse b1 0 )
    ( __ok `+OK status ok`   == . p1 status 0 )
    ( __ok `+OK consumed 5`  == . p1 consumed 5 )
    : i r1 ( resp_reply_root . p1 reply )
    ( __ok `+OK kind str`    == ( resp_node_kind . p1 reply r1 ) 2 )
    ( __ok `+OK text`        ( nurl_str_eq ( resp_node_str . p1 reply r1 ) `OK` ) )
    ( resp_reply_free . p1 reply ) ( vec_free [u] b1 )

    // ── error -ERR foo ──
    : ( Vec u ) b2 ( __buf `-ERR bad\r\n` )
    : RespParse p2 ( resp_parse b2 0 )
    : i r2 ( resp_reply_root . p2 reply )
    ( __ok `-ERR kind err`   == ( resp_node_kind . p2 reply r2 ) 3 )
    ( __ok `-ERR text`       ( nurl_str_eq ( resp_node_str . p2 reply r2 ) `ERR bad` ) )
    ( resp_reply_free . p2 reply ) ( vec_free [u] b2 )

    // ── integer :1000 ──
    : ( Vec u ) b3 ( __buf `:1000\r\n` )
    : RespParse p3 ( resp_parse b3 0 )
    : i r3 ( resp_reply_root . p3 reply )
    ( __ok `:1000 kind int`  == ( resp_node_kind . p3 reply r3 ) 1 )
    ( __ok `:1000 value`     == ( resp_node_int . p3 reply r3 ) 1000 )
    ( resp_reply_free . p3 reply ) ( vec_free [u] b3 )

    // ── negative integer :-5 ──
    : ( Vec u ) b3b ( __buf `:-5\r\n` )
    : RespParse p3b ( resp_parse b3b 0 )
    ( __ok `:-5 value`       == ( resp_node_int . p3b reply ( resp_reply_root . p3b reply ) ) -5 )
    ( resp_reply_free . p3b reply ) ( vec_free [u] b3b )

    // ── bulk string $5 hello ──
    : ( Vec u ) b4 ( __buf `$5\r\nhello\r\n` )
    : RespParse p4 ( resp_parse b4 0 )
    : i r4 ( resp_reply_root . p4 reply )
    ( __ok `$5 kind str`     == ( resp_node_kind . p4 reply r4 ) 2 )
    ( __ok `$5 text`         ( nurl_str_eq ( resp_node_str . p4 reply r4 ) `hello` ) )
    ( __ok `$5 consumed 11`  == . p4 consumed 11 )
    ( resp_reply_free . p4 reply ) ( vec_free [u] b4 )

    // ── nil bulk $-1 ──
    : ( Vec u ) b5 ( __buf `$-1\r\n` )
    : RespParse p5 ( resp_parse b5 0 )
    ( __ok `$-1 is nil`      ( resp_node_is_nil . p5 reply ( resp_reply_root . p5 reply ) ) )
    ( resp_reply_free . p5 reply ) ( vec_free [u] b5 )

    // ── empty bulk $0 ──
    : ( Vec u ) b5b ( __buf `$0\r\n\r\n` )
    : RespParse p5b ( resp_parse b5b 0 )
    ( __ok `$0 kind str`     == ( resp_node_kind . p5b reply ( resp_reply_root . p5b reply ) ) 2 )
    ( __ok `$0 empty text`   ( nurl_str_eq ( resp_node_str . p5b reply ( resp_reply_root . p5b reply ) ) `` ) )
    ( resp_reply_free . p5b reply ) ( vec_free [u] b5b )

    // ── array of two bulks *2 foo bar ──
    : ( Vec u ) b6 ( __buf `*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n` )
    : RespParse p6 ( resp_parse b6 0 )
    : i r6 ( resp_reply_root . p6 reply )
    ( __ok `*2 kind arr`     == ( resp_node_kind . p6 reply r6 ) 4 )
    ( __ok `*2 len 2`        == ( resp_node_arr_len . p6 reply r6 ) 2 )
    ( __ok `*2 [0] foo`      ( nurl_str_eq ( resp_node_str . p6 reply ( resp_node_arr_at . p6 reply r6 0 ) ) `foo` ) )
    ( __ok `*2 [1] bar`      ( nurl_str_eq ( resp_node_str . p6 reply ( resp_node_arr_at . p6 reply r6 1 ) ) `bar` ) )
    ( resp_reply_free . p6 reply ) ( vec_free [u] b6 )

    // ── nested array: *2 :1 *2 $1 a $1 b ──
    : ( Vec u ) b7 ( __buf `*2\r\n:1\r\n*2\r\n$1\r\na\r\n$1\r\nb\r\n` )
    : RespParse p7 ( resp_parse b7 0 )
    : i r7 ( resp_reply_root . p7 reply )
    ( __ok `nested len 2`    == ( resp_node_arr_len . p7 reply r7 ) 2 )
    : i n7a ( resp_node_arr_at . p7 reply r7 0 )
    : i n7b ( resp_node_arr_at . p7 reply r7 1 )
    ( __ok `nested [0] int`  == ( resp_node_int . p7 reply n7a ) 1 )
    ( __ok `nested [1] arr`  == ( resp_node_kind . p7 reply n7b ) 4 )
    ( __ok `nested [1][1] b` ( nurl_str_eq ( resp_node_str . p7 reply ( resp_node_arr_at . p7 reply n7b 1 ) ) `b` ) )
    ( resp_reply_free . p7 reply ) ( vec_free [u] b7 )

    // ── incomplete: bulk header without the data yet ──
    : ( Vec u ) b8 ( __buf `$5\r\nhel` )
    : RespParse p8 ( resp_parse b8 0 )
    ( __ok `incomplete bulk` == . p8 status 1 )
    ( resp_reply_free . p8 reply ) ( vec_free [u] b8 )

    // ── incomplete: array missing its second element ──
    : ( Vec u ) b9 ( __buf `*2\r\n$3\r\nfoo\r\n` )
    : RespParse p9 ( resp_parse b9 0 )
    ( __ok `incomplete arr`  == . p9 status 1 )
    ( resp_reply_free . p9 reply ) ( vec_free [u] b9 )

    ? == g_fail 0 { ( nurl_print `\nALL PASS\n` ) ^ 0 } { ( nurl_print `\nFAILED\n` ) ^ 1 }
}
