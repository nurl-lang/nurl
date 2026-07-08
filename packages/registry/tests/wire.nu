// tests/wire.nu — the registry wire protocol, driven through
// router_handle with NO socket: publish → index → tarball → yank →
// search → stats → revoke, plus the auth/validation rejections.
//
// Self-asserting: prints PASS/FAIL per case, exits non-zero on any FAIL.
// State lives in a fresh temp data dir per run.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/tar.nu`
$ `src/service.nu`

: ~ i g_fails 0

@ check b cond s name → v {
    ? cond {
        ( nurl_print `PASS ` )
    } {
        = g_fails + g_fails 1
        ( nurl_print `FAIL ` )
    }
    ( nurl_print name )
    ( nurl_print `\n` )
}

// Build a request the router understands.
@ mk_req s method s path s query ( Vec Header ) headers ( Vec u ) body → HttpRequest {
    ^ @ HttpRequest {
        ( string_from method )
        ( string_from path )
        ( string_from query )
        ( string_from `HTTP/1.1` )
        headers
        body
    }
}

@ hdr s name s value → Header {
    ^ @ Header { ( string_from name ) ( string_from value ) }
}

@ no_headers → ( Vec Header ) {
    ^ ( vec_new [Header] )
}

@ auth_headers s token → ( Vec Header ) {
    : ( Vec Header ) hs ( vec_new [Header] )
    : String av ( string_from `Bearer ` )
    ( string_push_str av token )
    ( vec_push [Header] hs ( hdr `authorization` ( string_data av ) ) )
    ( string_free av )
    ^ hs
}

@ pub_headers s token s name s version s deps → ( Vec Header ) {
    : ( Vec Header ) hs ( auth_headers token )
    ( vec_push [Header] hs ( hdr `x-nurl-package` name ) )
    ( vec_push [Header] hs ( hdr `x-nurl-version` version ) )
    ? > ( nurl_str_len deps ) 0 {
        ( vec_push [Header] hs ( hdr `x-nurl-deps` deps ) )
    } {}
    ^ hs
}

// Response body as an owned String.
@ resp_body_str HttpResponse r → String {
    ^ ( bytes_to_str . r body )
}

// A tiny valid .tar.gz with a README and a manifest.
@ mk_tarball → ( Vec u ) {
    : ( Vec TarEntry ) ents ( vec_new [TarEntry] )
    ( vec_push [TarEntry] ents ( tar_entry_file `nurl.toml` ( bytes_from_str `[package]
name = "demo"
version = "0.1.0"
repository = "https://example.com/repo"
` ) ) )
    ( vec_push [TarEntry] ents ( tar_entry_file `README.md` ( bytes_from_str `# demo

Hello *there*.

![pic](docs/pic.png)
` ) ) )
    ( vec_push [TarEntry] ents ( tar_entry_file `docs/pic.png` ( bytes_from_str `not-really-a-png` ) ) )
    : !( Vec u ) TarErr tr ( tar_create ents )
    ( tar_entries_free ents )
    ?? tr {
        F _ → ^ ( vec_new [u] )
        T arc → {
            : !( Vec u ) CompressErr gr ( gzip_compress arc )
            ( vec_free [u] arc )
            ?? gr {
                F _ → ^ ( vec_new [u] )
                T gz → ^ gz
            }
        }
    }
}

@ main → i {
    // Fresh state under the platform temp dir.
    : String data ( string_from `/tmp/nurl-registry-wire-test` )
    ?? ( dir_remove_all ( string_data data ) ) { T _ → {} F _ → {} }
    ?? ( dir_create_all ( string_data data ) ) { T _ → {} F _ → {} }
    : String dbp ( string_from ( string_data data ) )
    ( string_push_str dbp `/registry.db` )
    ( reg_service_config ( string_data data ) ( string_data dbp ) `test-pepper` `` `` `` )

    // Mint a token straight through the auth+db layers.
    : String token ( reg_token_new )
    : String hash ( reg_token_hash `test-pepper` ( string_data token ) )
    : ~ i uid -1
    ?? ( reg_db_open ( string_data dbp ) ) {
        F _ → {}
        T db → {
            = uid ( reg_db_user_ensure db `tester` 1000 )
            : b _i ( reg_db_token_insert db uid ( string_data hash ) `t` 1000 )
        }
    }
    ( check >= uid 0 `token minted` )
    ( string_free hash )

    : Router r ( reg_service_router )
    : ( Vec u ) gz ( mk_tarball )
    ( check > ( vec_len [u] gz ) 0 `tarball built` )

    // ── publish ──
    {
        : HttpRequest req ( mk_req `POST` `/api/v1/publish` `` ( pub_headers ( string_data token ) `demo` `0.1.0` `[{"name":"http","req":"^0.2"}]` ) ( vec_clone [u] gz ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 200 `publish 200` )
        : String b ( resp_body_str resp )
        ( check ( string_contains b `"ok":true` ) `publish ok body` )
        ( string_free b )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── publish again → 409 ──
    {
        : HttpRequest req ( mk_req `POST` `/api/v1/publish` `` ( pub_headers ( string_data token ) `demo` `0.1.0` `` ) ( vec_clone [u] gz ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 409 `republish 409` )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── bad token → 401 ──
    {
        : HttpRequest req ( mk_req `POST` `/api/v1/publish` `` ( pub_headers `deadbeef` `demo` `0.2.0` `` ) ( vec_clone [u] gz ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 401 `bad token 401` )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── invalid name → 400 ──
    {
        : HttpRequest req ( mk_req `POST` `/api/v1/publish` `` ( pub_headers ( string_data token ) `../evil` `0.1.0` `` ) ( vec_clone [u] gz ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 400 `invalid name 400` )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── index ──
    {
        : HttpRequest req ( mk_req `GET` `/index/demo.json` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 200 `index 200` )
        : String b ( resp_body_str resp )
        ( check ( string_contains b `"version":"0.1.0"` ) `index has version` )
        ( check ( string_contains b `"yanked":false` ) `index not yanked` )
        ( check ( string_contains b `"name":"http"` ) `index has dep` )
        // checksum in the index must be the sha256 of the uploaded bytes
        : ( Vec u ) digest ( sha256_pure gz )
        : String hex ( bytes_to_hex digest )
        ( check ( string_contains b ( string_data hex ) ) `index checksum matches` )
        ( vec_free [u] digest )
        ( string_free hex )
        ( string_free b )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── index for unknown package → 404 ──
    {
        : HttpRequest req ( mk_req `GET` `/index/nosuch.json` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 404 `unknown index 404` )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── tarball round-trip ──
    {
        : HttpRequest req ( mk_req `GET` `/pkgs/demo/demo-0.1.0.tar.gz` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 200 `tarball 200` )
        : ~ b same == ( vec_len [u] . resp body ) ( vec_len [u] gz )
        ? same {
            : i n ( vec_len [u] gz )
            : ~ i k 0
            ~ & same < k n {
                : i a ?? ( vec_get [u] gz k ) { T x → # i x F → -1 }
                : i c ?? ( vec_get [u] . resp body k ) { T x → # i x F → -2 }
                ? != a c { = same F } {}
                = k + k 1
            }
        } {}
        ( check same `tarball bytes identical` )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── tarball path traversal shapes → 400 ──
    {
        : HttpRequest req ( mk_req `GET` `/pkgs/demo/other-0.1.0.tar.gz` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 400 `foreign tarball name 400` )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── search ──
    {
        : HttpRequest req ( mk_req `GET` `/api/v1/search` `q=dem` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        : String b ( resp_body_str resp )
        ( check ( string_contains b `"name":"demo"` ) `search finds demo` )
        ( string_free b )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── stats ──
    {
        : HttpRequest req ( mk_req `GET` `/api/v1/stats` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        : String b ( resp_body_str resp )
        ( check ( string_contains b `"packages":1` ) `stats packages` )
        ( check ( string_contains b `"versions":1` ) `stats versions` )
        ( string_free b )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── catalog + detail pages ──
    {
        : HttpRequest req ( mk_req `GET` `/` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        : String b ( resp_body_str resp )
        ( check ( string_contains b `/packages/demo` ) `catalog links demo` )
        ( string_free b )
        ( http_response_free resp )
        ( request_free req )
    }
    {
        : HttpRequest req ( mk_req `GET` `/packages/demo` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        : String b ( resp_body_str resp )
        ( check ( string_contains b `Hello <em>there</em>` ) `detail renders README` )
        ( check ( string_contains b `/files/demo/0.1.0/docs/pic.png` ) `README image rewritten` )
        ( check ( string_contains b `https://example.com/repo` ) `repository from manifest` )
        ( check ( string_contains b `@tester` ) `owner login shown` )
        ( string_free b )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── tarball asset ──
    {
        : HttpRequest req ( mk_req `GET` `/files/demo/0.1.0/docs/pic.png` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 200 `asset 200` )
        : String b ( resp_body_str resp )
        ( check ( string_contains b `not-really-a-png` ) `asset bytes` )
        ( string_free b )
        ( http_response_free resp )
        ( request_free req )
    }
    {
        : HttpRequest req ( mk_req `GET` `/files/demo/0.1.0/src/lib.nu` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 415 `asset non-image 415` )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── yank / unyank ──
    {
        : HttpRequest req ( mk_req `POST` `/api/v1/yank` `` ( pub_headers ( string_data token ) `demo` `0.1.0` `` ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 200 `yank 200` )
        ( http_response_free resp )
        ( request_free req )
    }
    {
        : HttpRequest req ( mk_req `GET` `/index/demo.json` `` ( no_headers ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        : String b ( resp_body_str resp )
        ( check ( string_contains b `"yanked":true` ) `index yanked` )
        ( string_free b )
        ( http_response_free resp )
        ( request_free req )
    }
    {
        : HttpRequest req ( mk_req `POST` `/api/v1/unyank` `` ( pub_headers ( string_data token ) `demo` `0.1.0` `` ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 200 `unyank 200` )
        ( http_response_free resp )
        ( request_free req )
    }

    // ── ownership: a second user cannot publish or yank `demo` ──
    {
        : String tok2 ( reg_token_new )
        : String hash2 ( reg_token_hash `test-pepper` ( string_data tok2 ) )
        ?? ( reg_db_open ( string_data dbp ) ) {
            F _ → {}
            T db → {
                : i uid2 ( reg_db_user_ensure db `intruder` 2000 )
                : b _i ( reg_db_token_insert db uid2 ( string_data hash2 ) `t` 2000 )
            }
        }
        ( string_free hash2 )
        : HttpRequest req ( mk_req `POST` `/api/v1/publish` `` ( pub_headers ( string_data tok2 ) `demo` `0.2.0` `` ) ( vec_clone [u] gz ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 403 `foreign publish 403` )
        ( http_response_free resp )
        ( request_free req )
        : HttpRequest req2 ( mk_req `POST` `/api/v1/yank` `` ( pub_headers ( string_data tok2 ) `demo` `0.1.0` `` ) ( vec_new [u] ) )
        : HttpResponse resp2 ( router_handle r req2 )
        ( check == . resp2 status 403 `foreign yank 403` )
        ( http_response_free resp2 )
        ( request_free req2 )
        ( string_free tok2 )
    }

    // ── revoke ──
    {
        : HttpRequest req ( mk_req `POST` `/api/v1/revoke` `` ( auth_headers ( string_data token ) ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 200 `revoke 200` )
        ( http_response_free resp )
        ( request_free req )
    }
    {
        : HttpRequest req ( mk_req `POST` `/api/v1/yank` `` ( pub_headers ( string_data token ) `demo` `0.1.0` `` ) ( vec_new [u] ) )
        : HttpResponse resp ( router_handle r req )
        ( check == . resp status 401 `revoked token 401` )
        ( http_response_free resp )
        ( request_free req )
    }

    ( vec_free [u] gz )
    ( router_free r )
    ( string_free token )
    ?? ( dir_remove_all ( string_data data ) ) { T _ → {} F _ → {} }
    ( string_free data )
    ( string_free dbp )

    ? > g_fails 0 {
        ( nurl_print `FAILURES: ` )
        ( nurl_print ( nurl_str_int g_fails ) )
        ( nurl_print `\n` )
        ^ 1
    } {}
    ( nurl_print `ALL PASS\n` )
    ^ 0
}
