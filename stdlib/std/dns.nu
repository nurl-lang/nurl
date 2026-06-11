// stdlib/std/dns.nu — DNS resolution helpers (forward + reverse).
//
// Wraps runtime §18c (`getaddrinfo` / `getnameinfo`). The system
// resolver is used directly — `/etc/resolv.conf` on POSIX, the
// configured DNS servers on Windows. No third-party resolver
// dependency (c-ares et al.) is bundled.
//
// API:
//
//   ( dns_resolve      s host )           → ! ( Vec String ) NetErr
//   ( dns_resolve_port s host i port )    → ! ( Vec String ) NetErr
//   ( dns_reverse      s ip   )           → ? String
//
// Semantics:
//
//   * `dns_resolve` returns the IP literals (IPv4 and/or IPv6) the
//     system resolver knows for `host`, in the kernel's preferred
//     order, with exact duplicates filtered. A host with no A/AAAA
//     records resolves to `Err NetOther` (mirrors the way the rest
//     of the net surface signals "no such address"); an empty input
//     also yields NetOther.
//   * `dns_resolve_port` formats each address with the port already
//     attached — "ip:port" for IPv4 and "[ip]:port" for IPv6 — so the
//     output can be fed straight into `tcp_connect` / `udp_connect`
//     after a single `string_split` on ":". The format follows
//     RFC 3986 §3.2.2 for IPv6.
//   * `dns_reverse` runs `getnameinfo(NI_NAMEREQD)` — only a true
//     PTR hit returns Some; literal-only fallbacks are filtered as
//     None. Useful for access-log enrichment.
//
// All three are SYNCHRONOUS — `getaddrinfo` blocks on the resolver
// thread for tens of milliseconds at worst. For fiber-aware async
// resolution, wrap in `fiber_spawn` from `stdlib/std/async.nu`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`

// ── Runtime FFI bridge (§18c) ──────────────────────────────────────

& `c` @ nurl_dns_resolve s host → s

& `c` @ nurl_dns_resolve_port s host i port → s

& `c` @ nurl_dns_reverse s ip → s

// ── Helpers ────────────────────────────────────────────────────────

// Split a NUL-terminated newline-separated string into an owned
// Vec[String]. Empty input → empty Vec.
@ __dns_split_lines s raw → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len raw )
    ? <= n 0 { ^ out } {}
    : ~ i start 0
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get raw k ) 10 {
            ? > k start {
                : i seg_len - k start
                : String seg ( string_with_cap seg_len )
                : ~ i j start
                ~ < j k {
                    ( string_push_char seg ( nurl_str_get raw j ) )
                    = j + j 1
                }
                ( vec_push [String] out seg )
            } {}
            = start + k 1
        } {}
        = k + k 1
    }
    // Trailing run without a terminating newline (defensive — the
    // runtime always emits one, but tolerate the alternative).
    ? > k start {
        : i seg_len - k start
        : String seg ( string_with_cap seg_len )
        : ~ i j start
        ~ < j k {
            ( string_push_char seg ( nurl_str_get raw j ) )
            = j + j 1
        }
        ( vec_push [String] out seg )
    } {}
    ^ out
}

// ── Forward resolution ─────────────────────────────────────────────

@ dns_resolve s host → !( Vec String ) NetErr {
    : s raw ( nurl_dns_resolve host )
    : ( Vec String ) out ( __dns_split_lines raw )
    ( nurl_free raw )
    ? == ( vec_len [String] out ) 0 {
        : ( @ v String ) drop_str \ String s → v { ( string_free s ) }
        ( vec_free_with [String] out drop_str )
        ^ @ !( Vec String ) NetErr { F # NetErr NetOther }
    } {}
    ^ @ !( Vec String ) NetErr { T out }
}

@ dns_resolve_port s host i port → !( Vec String ) NetErr {
    : s raw ( nurl_dns_resolve_port host port )
    : ( Vec String ) out ( __dns_split_lines raw )
    ( nurl_free raw )
    ? == ( vec_len [String] out ) 0 {
        : ( @ v String ) drop_str \ String s → v { ( string_free s ) }
        ( vec_free_with [String] out drop_str )
        ^ @ !( Vec String ) NetErr { F # NetErr NetOther }
    } {}
    ^ @ !( Vec String ) NetErr { T out }
}

// ── Reverse resolution ─────────────────────────────────────────────

@ dns_reverse s ip → ?String {
    : s raw ( nurl_dns_reverse ip )
    : i n ( nurl_str_len raw )
    ? <= n 0 {
        ( nurl_free raw )
        ^ @ ?String { F }
    } {}
    : String h ( string_from raw )
    ( nurl_free raw )
    ^ @ ?String { T h }
}
