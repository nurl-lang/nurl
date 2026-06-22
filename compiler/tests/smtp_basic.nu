// smtp_basic.nu — ext/smtp.nu acceptance for the offline surface.
//
// The live conversation (connect/EHLO/AUTH/MAIL/RCPT/DATA) needs a
// real server, so it is exercised by examples, not here. What IS
// goldenable — and what carries the protocol's actual logic — is built
// pure: the reply scanner/parser (multiline continuation handling),
// AUTH PLAIN/LOGIN base64 tokens, dot-stuffing transparency, and the
// MIME builder. CR/LF are rendered <CR>/<LF> so the golden stays
// byte-exact and readable.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/smtp.nu`

@ pshow s label String v → v {
    ( nurl_print label ) ( nurl_print `: ` )
    : i n ( string_len v )
    : ~ i k 0
    ~ < k n {
        : i ch ( string_get v k )
        ? == ch 13 { ( nurl_print `<CR>` ) } {
            ? == ch 10 { ( nurl_print `<LF>\n` ) } {
                : String c ( string_with_cap 2 )
                ( string_push_char c ch )
                ( nurl_print ( string_data c ) )
                ( string_free c )
            } }
        = k + k 1
    }
    ( nurl_print `\n` )
    ( string_free v )
}

@ vappend_str ( Vec u ) v s txt → v {
    : i n ( nurl_str_len txt )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( nurl_str_get txt k ) ) = k + k 1 }
}

@ vappend_crlf ( Vec u ) v → v {
    ( vec_push [u] v # u 13 ) ( vec_push [u] v # u 10 )
}

@ scan_show s label ( Vec u ) buf → v {
    ( nurl_print label )
    ( nurl_print ` end=` ) ( nurl_print ( nurl_str_int ( __smtp_reply_scan buf ) ) )
    ( nurl_print ` code=` ) ( nurl_print ( nurl_str_int ( __smtp_reply_code buf ) ) )
    ( nurl_print `\n` )
}

@ main → i {
    // ── error names ──
    ( nurl_print `errs=` )
    ( nurl_print ( smtp_err_name # SmtpErr SmtpConnect ) ) ( nurl_print `,` )
    ( nurl_print ( smtp_err_name # SmtpErr SmtpTls ) ) ( nurl_print `,` )
    ( nurl_print ( smtp_err_name # SmtpErr SmtpAuth ) ) ( nurl_print `,` )
    ( nurl_print ( smtp_err_name # SmtpErr SmtpNoStartTls ) ) ( nurl_print `\n` )

    // ── AUTH PLAIN / LOGIN tokens ──
    : String ap ( __smtp_auth_plain_token `alice@example.com` `s3cret` )
    ( nurl_print `auth_plain=` ) ( nurl_print ( string_data ap ) ) ( nurl_print `\n` )
    ( string_free ap )
    : String lu ( b64_encode `alice@example.com` )
    : String lp ( b64_encode `s3cret` )
    ( nurl_print `login_user=` ) ( nurl_print ( string_data lu ) ) ( nurl_print `\n` )
    ( nurl_print `login_pass=` ) ( nurl_print ( string_data lp ) ) ( nurl_print `\n` )
    ( string_free lu ) ( string_free lp )

    // ── reply scanner ──
    : ( Vec u ) multi ( vec_new [u] )
    ( vappend_str multi `250-mail.example.com` ) ( vappend_crlf multi )
    ( vappend_str multi `250-PIPELINING` ) ( vappend_crlf multi )
    ( vappend_str multi `250-STARTTLS` ) ( vappend_crlf multi )
    ( vappend_str multi `250 AUTH PLAIN LOGIN` ) ( vappend_crlf multi )
    ( scan_show `multi` multi )
    ( vec_free [u] multi )

    : ( Vec u ) one ( vec_new [u] )
    ( vappend_str one `220 ready` ) ( vappend_crlf one )
    ( scan_show `one` one )
    ( vec_free [u] one )

    // complete reply with trailing bytes of the next one already buffered
    : ( Vec u ) trail ( vec_new [u] )
    ( vappend_str trail `354 go` ) ( vappend_crlf trail )
    ( vappend_str trail `25` )
    ( scan_show `trail` trail )
    ( vec_free [u] trail )

    // incomplete (no terminating LF yet)
    : ( Vec u ) part ( vec_new [u] )
    ( vappend_str part `220 partial` ) ( vec_push [u] part # u 13 )
    ( scan_show `part` part )
    ( vec_free [u] part )

    // ── dot-stuffing transparency ──
    : String body ( string_with_cap 64 )
    ( string_push_str body `line one` ) ( string_push_char body 10 )
    ( string_push_str body `.leading dot` ) ( string_push_char body 10 )
    ( string_push_str body `..two dots` ) ( string_push_char body 13 ) ( string_push_char body 10 )
    ( string_push_str body `last` )
    : String ds ( smtp_dotstuff ( string_data body ) )
    ( string_free body )
    ( pshow `dotstuff` ds )

    // ── MIME builder (fixed date → deterministic) ──
    : String msg ( mime_build `alice@example.com` `bob@example.org` `Hi there` `Hello,\nthis is a test.\n` `Mon, 02 Jan 2006 15:04:05 +0000` )
    ( pshow `mime` msg )
    ^ 0
}
