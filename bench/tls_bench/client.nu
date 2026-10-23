// bench/tls_bench/client.nu — NURL's packages/http-client in the TLS
// benchmark's client rows; the peer is reqwest (rust/src/bin/tls_client.rs).
// Single-threaded and sequential, like the peer, against the same server.
//
//   client <mode> <url> <secs>
//     full    a new connection per request, no session resumption
//             (http_client_set_resume F + "Connection: close")
//     resume  a new connection per request, resuming the cached session
//     ka      one pooled keep-alive connection, requests back to back
//
// Prints the key=value line tls_load / tls_client print:
//   ok err elapsed_ns bytes p50_us p99_us p999_us

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/sort.nu`
$ `../../packages/http-client/src/http_client.nu`

// One GET; the body length, or -1 on any failure.
@ __get HttpClient c s url b close → i {
    : ( Vec Header ) hs ( vec_new [Header] )
    ? close { ( vec_push [Header] hs ( header_new `Connection` `close` ) ) } {}
    ?? ( http_client_request c `GET` url hs ( vec_new [u] ) ) {
        T r → {
            ? != ( http_client_status r ) 200 { ^ - 0 1 } {}
            ^ ( vec_len [u] . r body )
        }
        F _ → { ^ - 0 1 }
    }
}

@ __kv String ln s k i v → v {
    ( string_push_str ln k )
    ( string_push_str ln `=` )
    ( string_push_int ln v )
    ( string_push_str ln ` ` )
}

// The per-mille percentile of a sorted sample.
@ __pct ( Vec i ) v i pm → i {
    : i n ( vec_len [i] v )
    ? == n 0 { ^ 0 } {}
    : ~ i k / * n pm 1000
    ? >= k n { = k - n 1 } {}
    ^ ?? ( vec_get [i] v k ) { T x → x F _ → 0 }
}

@ main → i {
    ? < ( nurl_argv_count ) 4 {
        ( nurl_eprintln `usage: client full|resume|ka <url> <secs>` )
        ^ 2
    } {}
    : s mode ( nurl_argv_get 1 )
    : s url ( nurl_argv_get 2 )
    : i secs ( nurl_str_to_int ( nurl_argv_get 3 ) )
    : b ka != 0 ( nurl_str_eq mode `ka` )

    : HttpClient c ( http_client_new )
    ( http_client_set_verify c F )
    ( http_client_set_h3 c 2 )
    ( http_client_set_decompress c F )
    ( http_client_set_body_max c 0 )
    ( http_client_set_resume c != 0 ( nurl_str_eq mode `resume` ) )

    : ( Vec i ) lat ( vec_new [i] )
    : ~ i ok 0
    : ~ i err 0
    : ~ i bytes 0
    : i t0 ( monotonic_ns )
    : i end + t0 * secs 1000000000
    : ~ i now t0
    ~ < now end {
        : i n ( __get c url ! ka )
        : i t1 ( monotonic_ns )
        ? < n 0 { = err + err 1 } {
            = ok + ok 1
            = bytes + bytes n
            ( vec_push [i] lat / - t1 now 1000 )
        }
        = now t1
    }
    ( sort_by [i] lat \ i a i b → i { ^ - a b } )

    : String ln ( string_new )
    ( __kv ln `ok` ok )
    ( __kv ln `err` err )
    ( __kv ln `elapsed_ns` - now t0 )
    ( __kv ln `bytes` bytes )
    ( __kv ln `p50_us` ( __pct lat 500 ) )
    ( __kv ln `p99_us` ( __pct lat 990 ) )
    ( __kv ln `p999_us` ( __pct lat 999 ) )
    ( string_push_str ln `\n` )
    ( nurl_print ( string_data ln ) )
    ^ 0
}
