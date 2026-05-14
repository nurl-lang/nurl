// http_proxy.nu — offline acceptance test for stdlib/ext/http_proxy.nu.
// Covers the pure helpers — no socket, no upstream call.
//
// Coverage:
//   * proxy_default_opts        — default field values
//   * proxy_err_name            — every variant renders its tag literally
//   * __is_hop_by_hop           — RFC 7230 §6.1 set + non-matches
//   * __build_upstream_url      — slash-collision normalization +
//     query-string suffixing
//   * __build_request_headers_blob — hop-by-hop + Host + Content-Length
//     are dropped; preserve_host_header keeps Host
//   * __response_header_dropped — hop-by-hop + Content-Length +
//     Content-Encoding stripped; ordinary headers survive

$ `stdlib/ext/http_proxy.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ println_s s prefix s value → v {
    ( nurl_print prefix )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ println_b s prefix b v → v {
    ( nurl_print prefix )
    ? v { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print `\n` )
}

@ println_i s prefix i v → v {
    ( nurl_print prefix )
    ( nurl_print_int v )
}

@ make_req s method s path s query → HttpRequest {
    : HttpRequest req ( request_new )
    ( string_push_str . req method method )
    ( string_push_str . req path path )
    ( string_push_str . req query query )
    ( string_push_str . req version `HTTP/1.1` )
    ^ req
}

@ main → i {
    // ── 1. proxy_default_opts ────────────────────────────────────
    ( nurl_print `── proxy_default_opts ──\n` )
    : ProxyOpts d ( proxy_default_opts )
    ( println_i `  timeout_ms=` . d timeout_ms )
    ( println_i `  connect_timeout_ms=` . d connect_timeout_ms )
    ( println_b `  strip_hop_by_hop=` . d strip_hop_by_hop )
    ( println_b `  preserve_host_header=` . d preserve_host_header )
    ( println_b `  strip_content_encoding=` . d strip_content_encoding )
    ( println_b `  strip_content_length=` . d strip_content_length )

    // ── 2. proxy_err_name ────────────────────────────────────────
    ( nurl_print `── proxy_err_name ──\n` )
    : ProxyErr e1 # ProxyErr ProxyUpstream
    : ProxyErr e2 # ProxyErr ProxyClientWrite
    : ProxyErr e3 # ProxyErr ProxyOther
    ( println_s `  e1=` ( proxy_err_name e1 ) )
    ( println_s `  e2=` ( proxy_err_name e2 ) )
    ( println_s `  e3=` ( proxy_err_name e3 ) )

    // ── 3. __is_hop_by_hop ───────────────────────────────────────
    ( nurl_print `── __is_hop_by_hop ──\n` )
    ( println_b `  connection=` ( __is_hop_by_hop `connection` ) )
    ( println_b `  keep-alive=` ( __is_hop_by_hop `keep-alive` ) )
    ( println_b `  proxy-authenticate=` ( __is_hop_by_hop `proxy-authenticate` ) )
    ( println_b `  proxy-authorization=` ( __is_hop_by_hop `proxy-authorization` ) )
    ( println_b `  te=` ( __is_hop_by_hop `te` ) )
    ( println_b `  trailer=` ( __is_hop_by_hop `trailer` ) )
    ( println_b `  transfer-encoding=` ( __is_hop_by_hop `transfer-encoding` ) )
    ( println_b `  upgrade=` ( __is_hop_by_hop `upgrade` ) )
    ( println_b `  authorization=` ( __is_hop_by_hop `authorization` ) )
    ( println_b `  content-type=` ( __is_hop_by_hop `content-type` ) )

    // ── 4. __build_upstream_url ──────────────────────────────────
    ( nurl_print `── __build_upstream_url ──\n` )
    : HttpRequest r1 ( make_req `GET` `/v1/messages` `` )
    : String u1 ( __build_upstream_url `https://api.example.com` r1 )
    ( println_s `  no_slash_path=` ( string_data u1 ) )
    ( string_free u1 )
    ( request_free r1 )

    : HttpRequest r2 ( make_req `GET` `/v1/messages` `` )
    : String u2 ( __build_upstream_url `https://api.example.com/` r2 )
    ( println_s `  base_slash_path_slash=` ( string_data u2 ) )
    ( string_free u2 )
    ( request_free r2 )

    : HttpRequest r3 ( make_req `GET` `v1/messages` `` )
    : String u3 ( __build_upstream_url `https://api.example.com/` r3 )
    ( println_s `  base_slash_no_path_slash=` ( string_data u3 ) )
    ( string_free u3 )
    ( request_free r3 )

    : HttpRequest r4 ( make_req `GET` `/search` `q=hello&n=10` )
    : String u4 ( __build_upstream_url `https://api.example.com` r4 )
    ( println_s `  with_query=` ( string_data u4 ) )
    ( string_free u4 )
    ( request_free r4 )

    // ── 5. __build_request_headers_blob ──────────────────────────
    ( nurl_print `── __build_request_headers_blob ──\n` )
    : HttpRequest hr ( make_req `POST` `/v1/messages` `` )
    ( vec_push [Header] . hr headers ( header_new `Authorization` `Bearer xyz` ) )
    ( vec_push [Header] . hr headers ( header_new `Content-Type` `application/json` ) )
    ( vec_push [Header] . hr headers ( header_new `Connection` `keep-alive` ) )
    ( vec_push [Header] . hr headers ( header_new `Host` `client.example.com` ) )
    ( vec_push [Header] . hr headers ( header_new `Content-Length` `42` ) )
    ( vec_push [Header] . hr headers ( header_new `Transfer-Encoding` `chunked` ) )

    : ProxyOpts opts1 ( proxy_default_opts )
    : String b1 ( __build_request_headers_blob hr opts1 )
    ( nurl_print `  default_strip:\n` )
    ( nurl_print ( string_data b1 ) )
    ( nurl_print `  END\n` )
    ( println_i `  default_blob_len=` ( string_len b1 ) )
    ( string_free b1 )

    : ProxyOpts opts2 @ ProxyOpts { 60000 10000 T T T T }
    : String b2 ( __build_request_headers_blob hr opts2 )
    ( nurl_print `  preserve_host:\n` )
    ( nurl_print ( string_data b2 ) )
    ( nurl_print `  END\n` )
    ( string_free b2 )
    ( request_free hr )

    // ── 6. __response_header_dropped ─────────────────────────────
    ( nurl_print `── __response_header_dropped ──\n` )
    : ProxyOpts opts3 ( proxy_default_opts )
    ( println_b `  Connection=` ( __response_header_dropped `Connection` opts3 ) )
    ( println_b `  Keep-Alive=` ( __response_header_dropped `Keep-Alive` opts3 ) )
    ( println_b `  Transfer-Encoding=` ( __response_header_dropped `Transfer-Encoding` opts3 ) )
    ( println_b `  Content-Length=` ( __response_header_dropped `Content-Length` opts3 ) )
    ( println_b `  Content-Encoding=` ( __response_header_dropped `Content-Encoding` opts3 ) )
    ( println_b `  Set-Cookie=` ( __response_header_dropped `Set-Cookie` opts3 ) )
    ( println_b `  Content-Type=` ( __response_header_dropped `Content-Type` opts3 ) )
    ( println_b `  X-Custom=` ( __response_header_dropped `X-Custom` opts3 ) )

    ( nurl_print `done\n` )
    0
}
