// pkg_publish_argv_redact.nu — regression test for Agora #164:
// nurlpkg / stdlib/ext/http_cli.nu must never expose registry bearer tokens
// or other secret-bearing headers in curl's process argv, environment, or
// temporary files across publish, yank, unyank and revoke.
// requires: live curl

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_cli.nu`
$ `stdlib/ext/pkg_publish.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`

@ vec_byte_at ( Vec u ) v i idx → i {
    ?? ( vec_get [u] v idx ) {
        T b → { ^ & # i b 255 }
        F _ → { ^ -1 }
    }
}

@ bytes_contains_str ( Vec u ) hay s needle → b {
    : i n ( vec_len [u] hay )
    : ( Slice u ) nv ( slice_of_str needle )
    : i m ( slice_len [u] nv )
    ? <= m 0 { ^ T } {}
    ? < n m { ^ F } {}
    : ~ i i 0
    : i limit - n m
    ~ <= i limit {
        : ~ i j 0
        : ~ b ok T
        ~ & < j m ok {
            : i c1 ( vec_byte_at hay + i j )
            : i c2 ( slice_byte nv j )
            ? != c1 c2 { = ok F } {}
            = j + j 1
        }
        ? ok { ^ T } {}
        = i + i 1
    }
    ^ F
}

@ is_digits s str → b {
    : ( Slice u ) sv ( slice_of_str str )
    : i n ( slice_len [u] sv )
    ? <= n 0 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte sv k )
        ? | < c 48 > c 57 { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ test_tmpdir → String {
    : String t1 ( env_var_or `TMPDIR` `` )
    ? > ( string_len t1 ) 0 { ^ t1 } {}
    : String t2 ( env_var_or `TEMP` `` )
    ? > ( string_len t2 ) 0 { ^ t2 } {}
    : String t3 ( env_var_or `TMP` `` )
    ? > ( string_len t3 ) 0 { ^ t3 } {}
    ^ ( string_from `/tmp` )
}

// Inspect the live curl child process while the server handler holds the HTTP
// exchange open. Returns:
//   0 = found live curl process and verified token + Authorization are absent
//       from argv, environ, and temp files
//   1 = token or Authorization leaked in argv
//   2 = token leaked in environ
//   3 = token leaked in temp file
//   4 = live curl process not found
@ inspect_inflight_curl s url_marker s secret_tok → i {
    : ~ b found F
    : ~ b leaked_argv F
    : ~ b leaked_env F
    ?? ( dir_list `/proc` ) {
        T entries → {
            : i ne ( vec_len [String] entries )
            : ~ i k 0
            ~ < k ne {
                ?? ( vec_get [String] entries k ) {
                    T name → {
                        ? ( is_digits ( string_data name ) ) {
                            : String cpath ( string_from `/proc/` )
                            ( string_push_str cpath ( string_data name ) )
                            ( string_push_str cpath `/cmdline` )
                            ?? ( read_file_bytes ( string_data cpath ) ) {
                                T cmdb → {
                                    ? & ( bytes_contains_str cmdb `curl` ) ( bytes_contains_str cmdb url_marker ) {
                                        = found T
                                        ? | ( bytes_contains_str cmdb secret_tok ) ( bytes_contains_str cmdb `Authorization` ) {
                                            = leaked_argv T
                                        } {}
                                        : String epath ( string_from `/proc/` )
                                        ( string_push_str epath ( string_data name ) )
                                        ( string_push_str epath `/environ` )
                                        ?? ( read_file_bytes ( string_data epath ) ) {
                                            T envb → {
                                                ? ( bytes_contains_str envb secret_tok ) {
                                                    = leaked_env T
                                                } {}
                                            }
                                            F _ → {}
                                        }
                                    } {}
                                }
                                F _ → {}
                            }
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
        F _ → {}
    }

    // Fallback for non-procfs POSIX hosts (macOS): inspect live `ps` command lines.
    ? ! found {
        ?? ( process_run_shell `ps -Ao command` ) {
            T out → {
                : s txt ( output_stdout out )
                ? >= ( nurl_str_find txt url_marker ) 0 {
                    = found T
                    ? | >= ( nurl_str_find txt secret_tok ) 0 >= ( nurl_str_find txt `Authorization` ) 0 {
                        = leaked_argv T
                    } {}
                } {}
            }
            F _ → {}
        }
    } {}

    // Inspect temp directory for any nurlpkg-* temp file containing the token.
    : ~ b leaked_tmp F
    : String tdir ( test_tmpdir )
    ?? ( dir_list ( string_data tdir ) ) {
        T tentries → {
            : i nt ( vec_len [String] tentries )
            : ~ i tk 0
            ~ < tk nt {
                ?? ( vec_get [String] tentries tk ) {
                    T tname → {
                        ? ( string_starts_with tname `nurlpkg-` ) {
                            : String fpath ( string_from ( string_data tdir ) )
                            ( string_push_char fpath 47 )
                            ( string_push_str fpath ( string_data tname ) )
                            ?? ( read_file_bytes ( string_data fpath ) ) {
                                T tb → {
                                    ? ( bytes_contains_str tb secret_tok ) {
                                        = leaked_tmp T
                                    } {}
                                }
                                F _ → {}
                            }
                        } {}
                    }
                    F _ → {}
                }
                = tk + tk 1
            }
        }
        F _ → {}
    }

    ? leaked_argv { ^ 1 } {}
    ? leaked_env { ^ 2 } {}
    ? leaked_tmp { ^ 3 } {}
    ? ! found { ^ 4 } {}
    ^ 0
}

@ test_classifier_and_redaction → v {
    : b s1 ( httpc_is_secret_header `Authorization: Bearer tok-123` )
    : b s2 ( httpc_is_secret_header `cookie: sid=abc` )
    : b s3 ( httpc_is_secret_header `X-Api-Key: k99` )
    : b s4 ( httpc_is_secret_header `X-Nurl-Package: demo` )
    : b s5 ( httpc_is_secret_header `Content-Type: application/gzip` )
    ( nurl_print `classify=` )
    ( nurl_print ? s1 `T` `F` )
    ( nurl_print ? s2 `T` `F` )
    ( nurl_print ? s3 `T` `F` )
    ( nurl_print ? s4 `T` `F` )
    ( nurl_println ? s5 `T` `F` )

    : String red ( httpc_redact_headers `Authorization: Bearer super-secret\r\nX-Nurl-Package: demo\r\nCookie: s=1\r\n` )
    : b r_no_secret < ( nurl_str_find ( string_data red ) `super-secret` ) 0
    : b r_no_cookie < ( nurl_str_find ( string_data red ) `s=1` ) 0
    : b r_has_pkg >= ( nurl_str_find ( string_data red ) `X-Nurl-Package: demo` ) 0
    : b r_has_red >= ( nurl_str_find ( string_data red ) `Authorization: <redacted>` ) 0
    ( nurl_print `redact=` )
    ( nurl_print ? r_no_secret `T` `F` )
    ( nurl_print ? r_no_cookie `T` `F` )
    ( nurl_print ? r_has_pkg `T` `F` )
    ( nurl_println ? r_has_red `T` `F` )

    // CRLF header-injection guard in pkg_revoke / pkg_publish / pkg_yank.
    : !i PublishErr crlf_r ( pkg_revoke `http://127.0.0.1:9/` `bad-tok\r\nX-Injected: 1` )
    ?? crlf_r {
        T _ → ( nurl_println `crlf_guard=accepted(bug)` )
        F e → {
            ( nurl_print `crlf_guard=` )
            ( nurl_println ( publish_err_name e ) )
        }
    }
}

@ header_val ( Vec Header ) hs s name → String {
    ?? ( header_get hs name ) {
        T v → { ^ v }
        F → { ^ ( string_new ) }
    }
}

@ main → i {
    ( test_classifier_and_redaction )

    : s SECRET `process-list-secret-token-99887766`
    : s MARKER `127.0.0.1:18944`
    : s REG `http://127.0.0.1:18944/`

    // Binary payload with embedded NULs and high bytes to verify wire compatibility.
    : ( Vec u ) payload ( vec_new [u] )
    ( vec_push [u] payload # u 31 )
    ( vec_push [u] payload # u 139 )
    ( vec_push [u] payload # u 0 )
    ( vec_push [u] payload # u 65 )
    ( vec_push [u] payload # u 0 )
    ( vec_push [u] payload # u 255 )

    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18944 )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse {
                : s path ( string_data . req path )
                : i check_rc ( inspect_inflight_curl MARKER SECRET )
                : String auth ( header_val . req headers `Authorization` )
                : String pkg ( header_val . req headers `X-Nurl-Package` )
                : String ver ( header_val . req headers `X-Nurl-Version` )
                : b auth_ok != 0 ( nurl_str_eq ( string_data auth ) `Bearer process-list-secret-token-99887766` )

                ? != 0 ( nurl_str_eq path `/api/v1/publish` ) {
                    : i blen ( vec_len [u] . req body )
                    : ~ b body_ok == blen 6
                    ? body_ok {
                        ? | != ( vec_byte_at . req body 0 ) 31 != ( vec_byte_at . req body 1 ) 139 { = body_ok F } {}
                        ? | != ( vec_byte_at . req body 2 ) 0 != ( vec_byte_at . req body 3 ) 65 { = body_ok F } {}
                        ? | != ( vec_byte_at . req body 4 ) 0 != ( vec_byte_at . req body 5 ) 255 { = body_ok F } {}
                    } {}
                    ( nurl_print `srv_publish: inspect=` )
                    ( nurl_print_int check_rc )
                    ( nurl_print ` auth=` )
                    ( nurl_print ? auth_ok `T` `F` )
                    ( nurl_print ` pkg=` )
                    ( nurl_print ( string_data pkg ) )
                    ( nurl_print ` ver=` )
                    ( nurl_print ( string_data ver ) )
                    ( nurl_print ` body_ok=` )
                    ( nurl_println ? body_ok `T` `F` )
                    ^ ( response_text 200 `ok` )
                } {}

                ? != 0 ( nurl_str_eq path `/api/v1/yank` ) {
                    ( nurl_print `srv_yank: inspect=` )
                    ( nurl_print_int check_rc )
                    ( nurl_print ` auth=` )
                    ( nurl_print ? auth_ok `T` `F` )
                    ( nurl_print ` pkg=` )
                    ( nurl_print ( string_data pkg ) )
                    ( nurl_print ` ver=` )
                    ( nurl_println ( string_data ver ) )
                    ^ ( response_text 200 `ok` )
                } {}

                ? != 0 ( nurl_str_eq path `/api/v1/unyank` ) {
                    ( nurl_print `srv_unyank: inspect=` )
                    ( nurl_print_int check_rc )
                    ( nurl_print ` auth=` )
                    ( nurl_print ? auth_ok `T` `F` )
                    ( nurl_print ` pkg=` )
                    ( nurl_print ( string_data pkg ) )
                    ( nurl_print ` ver=` )
                    ( nurl_println ( string_data ver ) )
                    ^ ( response_text 200 `ok` )
                } {}

                ? != 0 ( nurl_str_eq path `/api/v1/revoke` ) {
                    ( nurl_print `srv_revoke: inspect=` )
                    ( nurl_print_int check_rc )
                    ( nurl_print ` auth=` )
                    ( nurl_println ? auth_ok `T` `F` )
                    ^ ( response_text 200 `ok` )
                } {}

                ^ ( response_text 404 `not found` )
            }

            : HttpServer srv ( server_new listener h )

            : ( @ v ) client \ → v {
                ( sleep_ms 100 )
                : !i PublishErr r1 ( pkg_publish REG SECRET payload `demo` `1.2.3` `[]` )
                ?? r1 {
                    T _ → ( nurl_println `cli_publish=ok` )
                    F e → { ( nurl_print `cli_publish_err=` ) ( nurl_println ( publish_err_name e ) ) }
                }
                : !i PublishErr r2 ( pkg_yank REG SECRET `demo` `1.2.3` 1 )
                ?? r2 {
                    T _ → ( nurl_println `cli_yank=ok` )
                    F e → { ( nurl_print `cli_yank_err=` ) ( nurl_println ( publish_err_name e ) ) }
                }
                : !i PublishErr r3 ( pkg_yank REG SECRET `demo` `1.2.3` 0 )
                ?? r3 {
                    T _ → ( nurl_println `cli_unyank=ok` )
                    F e → { ( nurl_print `cli_unyank_err=` ) ( nurl_println ( publish_err_name e ) ) }
                }
                : !i PublishErr r4 ( pkg_revoke REG SECRET )
                ?? r4 {
                    T _ → ( nurl_println `cli_revoke=ok` )
                    F e → { ( nurl_print `cli_revoke_err=` ) ( nurl_println ( publish_err_name e ) ) }
                }
            }

            : !Thread ThreadErr ct ( thread_spawn client )
            : ~ i served 0
            ~ < served 4 {
                : !v NetErr sr ( server_run_once srv )
                ?? sr { T _ → {} F _ → {} }
                = served + served 1
            }
            ?? ct { T t → ( thread_join t ) F _ → {} }
            ( server_stop srv )
        }
        F _ → ( nurl_println `listen_fail` )
    }

    ( nurl_println `done` )
    ^ 0
}
