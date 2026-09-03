// Test: stdlib/ext/http.nu — GET + POST against httpbin.org.
//
// GATED: this test only runs when NURL_HTTP_TESTS=1 is set in the
// environment (run_tests.sh skips files matching `http_*` otherwise).
// Reason: requests reach the public internet, which is unreliable in
// CI, slow, and we don't want default builds to depend on it.
//
// To run manually:
//   NURL_HTTP_TESTS=1 ./build.sh
// or:
//   ./build/nurlc compiler/tests/http_basic.nu > /tmp/h.ll && \
//     clang /tmp/h.ll stdlib/runtime.o -lm $(pkg-config --libs libcurl) -o /tmp/h && /tmp/h

$ `stdlib/ext/http.nu`

@ main → i {
    // ── GET ──
    : !Response HttpErr g ( http_get `https://httpbin.org/get` )
    ?? g {
        T r → {
            ( nurl_print `get_status=` )
            ( nurl_print ( nurl_str_int ( http_status r ) ) )
            ( nurl_print `\n` )
            // Body should mention the URL — we don't pin exact bytes since
            // httpbin includes timestamps and IPs.
            : i blen ( nurl_str_len ( http_body_str r ) )
            ( nurl_print `get_body_nonempty=` )
            ( nurl_print ? > blen 0 `T` `F` )
            ( nurl_print `\n` )
            // Headers — at least one non-zero.
            ( nurl_print `get_header_count_gt0=` )
            ( nurl_print ? > ( http_header_count r ) 0 `T` `F` )
            ( nurl_print `\n` )
            ( response_free r )
        }
        F e → {
            ( nurl_print `get_err=` )
            ?? # HttpErr e {
                HttpConnect → { ( nurl_print `Connect\n` ) }
                HttpTimeout → { ( nurl_print `Timeout\n` ) }
                HttpTls → { ( nurl_print `Tls\n` ) }
                HttpDns → { ( nurl_print `Dns\n` ) }
                HttpInvalidUrl → { ( nurl_print `InvalidUrl\n` ) }
                HttpOther → { ( nurl_print `Other\n` ) }
                HttpTooLarge → { ( nurl_print `TooLarge\n` ) }
            }
        }
    }

    // ── POST with body ──
    : !Response HttpErr p ( http_post `https://httpbin.org/post` `{"hello":"nurl"}` `application/json` )
    ?? p {
        T r → {
            ( nurl_print `post_status=` )
            ( nurl_print ( nurl_str_int ( http_status r ) ) )
            ( nurl_print `\n` )
            ( response_free r )
        }
        F e → { ( nurl_print `post_err\n` ) }
    }

    // ── Invalid URL → InvalidUrl error ──
    : !Response HttpErr bad ( http_get `notaurl` )
    ?? bad {
        T r → {
            ( nurl_print `bad_unexpected_ok\n` )
            ( response_free r )
        }
        F e → {
            ( nurl_print `bad=` )
            ?? # HttpErr e {
                HttpConnect → { ( nurl_print `Connect\n` ) }
                HttpTimeout → { ( nurl_print `Timeout\n` ) }
                HttpTls → { ( nurl_print `Tls\n` ) }
                HttpDns → { ( nurl_print `Dns\n` ) }
                HttpInvalidUrl → { ( nurl_print `InvalidUrl\n` ) }
                HttpOther → { ( nurl_print `Other\n` ) }
                HttpTooLarge → { ( nurl_print `TooLarge\n` ) }
            }
        }
    }

    ( nurl_print `done\n` )
    ^ 0
}
