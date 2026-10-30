// httpc_url_refused.nu — agora #166: stdlib/ext/http_cli.nu runs the system
// `curl`, and a URL it is handed may come from an untrusted manifest (a
// `registry = "…"`). One that is not http:// or https:// is refused before
// curl runs: a value starting with `-` would be one of curl's options, and
// curl also speaks file://, gopher://, dict://, ldap://, scp://…. The
// arguments also carry `-g`, `--proto =http,https`, `--proto-redir
// =http,https` and `--` before the URL.

$ `stdlib/core/string.nu`
$ `stdlib/ext/http_cli.nu`

@ refused s url → i {
    ?? ( httpc_get url ) {
        T r → { ( httpc_resp_free r ) ^ 0 }
        F e → { ^ ? ( __httpc_err_is_other e ) 1 0 }
    }
}

@ __httpc_err_is_other HttpcErr e → b {
    ?? e { HttpcOther → { ^ T } _ → { ^ F } }
}

@ main → i {
    ( nurl_println_int ? ( httpc_url_is_http `https://registry.example/x` ) 1 0 )
    ( nurl_println_int ? ( httpc_url_is_http `HTTP://Registry.Example/x` ) 1 0 )
    ( nurl_println_int ? ( httpc_url_is_http `http://127.0.0.1:8080/` ) 1 0 )
    ( nurl_println_int ? ( httpc_url_is_http `-o/tmp/pwned` ) 1 0 )
    ( nurl_println_int ? ( httpc_url_is_http `--next` ) 1 0 )
    ( nurl_println_int ? ( httpc_url_is_http `file:///etc/passwd` ) 1 0 )
    ( nurl_println_int ? ( httpc_url_is_http `gopher://x/` ) 1 0 )
    ( nurl_println_int ? ( httpc_url_is_http `https:/x` ) 1 0 )
    ( nurl_println_int ? ( httpc_url_is_http `http` ) 1 0 )
    ( nurl_println_int ? ( httpc_url_is_http `` ) 1 0 )
    // Refused without running curl: HttpcOther.
    ( nurl_println_int ( refused `-K/etc/passwd` ) )
    ( nurl_println_int ( refused `--next` ) )
    ( nurl_println_int ( refused `file:///etc/passwd` ) )
    ( nurl_println_int ( refused `dict://127.0.0.1:11211/stat` ) )
    ^ 0
}
