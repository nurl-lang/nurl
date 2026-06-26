// stdlib/ext/smtp.nu — SMTP client (RFC 5321 / 5322), B17.
//
// A submission client: dial a mail server, optionally upgrade the
// plaintext connection to TLS with STARTTLS (RFC 3207), authenticate
// (AUTH PLAIN / AUTH LOGIN, RFC 4954), and submit a message. Built on
// net.nu's polymorphic TcpConn for read/write, with the pure-NURL TLS
// stack underneath: `tcp_connect_tls` for implicit TLS and
// `tcp_starttls` to upgrade an already-open fd in place (no OpenSSL).
// A minimal MIME builder (`mime_build`)
// produces a well-formed text/plain message; `smtp_dotstuff` applies
// the transparency rules (RFC 5321 §4.5.2) the DATA phase requires.
//
//   ( smtp_connect       s host i port )                → ! SmtpClient SmtpErr
//   ( smtp_connect_tls   s host i port b verify )       → ! SmtpClient SmtpErr  (implicit TLS, :465)
//   ( smtp_ehlo          SmtpClient c s domain )        → ! v SmtpErr
//   ( smtp_has_cap       SmtpClient c s name )          → b   (after EHLO)
//   ( smtp_starttls      SmtpClient c s host b verify ) → ! v SmtpErr  (re-EHLOs)
//   ( smtp_auth_plain    SmtpClient c s user s pass )   → ! v SmtpErr
//   ( smtp_auth_login    SmtpClient c s user s pass )   → ! v SmtpErr
//   ( smtp_mail_from     SmtpClient c s addr )          → ! v SmtpErr
//   ( smtp_rcpt_to       SmtpClient c s addr )          → ! v SmtpErr
//   ( smtp_data          SmtpClient c s message )       → ! v SmtpErr  (dot-stuffs + terminates)
//   ( smtp_quit          SmtpClient c )                 → v   (QUIT + close)
//   ( smtp_close         SmtpClient c )                 → v   (close without QUIT)
//
//   ( mime_build  s from s to s subject s body s date ) → String
//   ( smtp_dotstuff s body )                            → String
//   ( smtp_date_now )                                   → String  (RFC 2822, UTC)
//
// `verify` T checks the server certificate chain + hostname against the
// system trust store; F still encrypts but skips verification (a test
// server's `--insecure`). Leave it T over any untrusted network.
//
// Win32/WASI without OpenSSL: STARTTLS / implicit-TLS report SmtpTls.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`  // TcpConn, tcp_read_chunk / tcp_write_str / tcp_close_conn
$ `stdlib/std/encode.nu`  // b64_encode / b64_encode_vec
$ `stdlib/std/time.nu`  // smtp_date_now

// runtime.c §18 exports the client-connect primitives. nurl_tcp_close /
// nurl_tcp_err_kind are nurlc builtins; the two connect calls and the
// STARTTLS upgrade need `& `libc`` extern declarations.
& `libc` @ nurl_tcp_connect s host i port → i

: | SmtpErr {
    SmtpConnect  // TCP connect failed
    SmtpTls  // TLS handshake / STARTTLS upgrade failed
    SmtpProtocol  // unexpected reply code
    SmtpAuth  // authentication rejected
    SmtpWrite
    SmtpRead
    SmtpClosed
    SmtpTimeout
    SmtpNoStartTls  // STARTTLS requested but the server did not advertise it
}

@ smtp_err_name SmtpErr e → s {
    ^ ?? e {
        SmtpConnect → `SmtpConnect`
        SmtpTls → `SmtpTls`
        SmtpProtocol → `SmtpProtocol`
        SmtpAuth → `SmtpAuth`
        SmtpWrite → `SmtpWrite`
        SmtpRead → `SmtpRead`
        SmtpClosed → `SmtpClosed`
        SmtpTimeout → `SmtpTimeout`
        SmtpNoStartTls → `SmtpNoStartTls`
    }
}

// `rxbuf` holds bytes pulled off the socket past a reply boundary;
// `last_reply` is the full text of the most recent (possibly
// multiline) reply — EHLO capability checks read it via smtp_has_cap.
: SmtpClient {
    TcpConn conn
    ( Vec u ) rxbuf
    String last_reply
}

@ __smtp_of_net NetErr e → SmtpErr {
    ^ ?? e {
        NetClosed → # SmtpErr SmtpClosed
        NetRead → # SmtpErr SmtpRead
        NetWrite → # SmtpErr SmtpWrite
        NetTimeout → # SmtpErr SmtpTimeout
        NetTlsCtxInit → # SmtpErr SmtpTls
        NetTlsCertLoad → # SmtpErr SmtpTls
        NetTlsKeyLoad → # SmtpErr SmtpTls
        NetTlsHandshake → # SmtpErr SmtpTls
        NetBind → # SmtpErr SmtpProtocol
        NetAddrInUse → # SmtpErr SmtpConnect
        NetAccept → # SmtpErr SmtpProtocol
        NetOther → # SmtpErr SmtpProtocol
    }
}

// Bounds-checked byte read: out-of-range → -1.
@ __smtp_vget ( Vec u ) v i k → i {
    ^ ?? ( vec_get [u] v k ) { T b → # i b F _ → -1 }
}

// ── reply parsing (pure — tested directly) ───────────────────────────

// Scan `buf` for the end of one complete reply. A reply is a run of
// CRLF lines; it ends at the first line whose 4th byte is NOT '-' (the
// continuation marker), per RFC 5321 §4.2.1. Returns the byte index
// just past the terminating LF, or -1 if no complete reply is buffered.
@ __smtp_reply_scan ( Vec u ) buf → i {
    : i n ( vec_len [u] buf )
    : ~ i ls 0
    : ~ i k 0
    : ~ i result -1
    : ~ i scanning 1
    ~ & == scanning 1 < k n {
        ? == ( __smtp_vget buf k ) 10 {
            // line spans [ls, k]; "code SP/-" check on byte ls+3 (45 = '-')
            ? | <= - k ls 3 != ( __smtp_vget buf + ls 3 ) 45 {
                = result + k 1
                = scanning 0
            } {
                = ls + k 1
            }
        } {}
        = k + k 1
    }
    ^ result
}

// Parse the 3-digit status code at the front of a reply. -1 if the
// first three bytes are not digits.
@ __smtp_reply_code ( Vec u ) buf → i {
    ? < ( vec_len [u] buf ) 3 { ^ -1 } {}
    : i d0 ( __smtp_vget buf 0 )
    : i d1 ( __smtp_vget buf 1 )
    : i d2 ( __smtp_vget buf 2 )
    ? | | ( __smtp_notdigit d0 ) ( __smtp_notdigit d1 ) ( __smtp_notdigit d2 ) { ^ -1 } {}
    ^ + + * 100 - d0 48 * 10 - d1 48 - d2 48
}

@ __smtp_notdigit i c → b {
    ^ | < c 48 > c 57
}

// ── low-level send / receive ─────────────────────────────────────────

// Send `text` followed by CRLF (the SMTP command terminator).
@ __smtp_write_crlf SmtpClient c s text → !v SmtpErr {
    : String line ( string_with_cap + ( nurl_str_len text ) 2 )
    ( string_push_str line text )
    ( string_push_char line 13 )
    ( string_push_char line 10 )
    : !v NetErr w ( tcp_write_str . c conn ( string_data line ) )
    ( string_free line )
    ^ ?? w {
        T _ → @ !v SmtpErr { T 0 }
        F er → @ !v SmtpErr { F ( __smtp_of_net er ) }
    }
}

// Read one complete reply into last_reply; return its status code.
@ __smtp_read_reply SmtpClient c → !i SmtpErr {
    : ~ i spin 0
    ~ < spin 1000000 {
        : i end ( __smtp_reply_scan . c rxbuf )
        ? >= end 0 {
            : i code ( __smtp_reply_code . c rxbuf )
            ( string_clear . c last_reply )
            : ~ i k 0
            ~ < k end { ( string_push_char . c last_reply ( __smtp_vget . c rxbuf k ) ) = k + k 1 }
            : i n ( vec_len [u] . c rxbuf )
            : i rem - n end
            = k 0
            ~ < k rem {
                ?? ( vec_get [u] . c rxbuf + end k ) { T b → { ( vec_set [u] . c rxbuf k b ) } F _ → {} }
                = k + k 1
            }
            ( vec_set_len [u] . c rxbuf rem )
            ^ @ !i SmtpErr { T code }
        } {}
        : !( Vec u ) NetErr rd ( tcp_read_chunk . c conn 4096 )
        ?? rd {
            T chunk → {
                : i cn ( vec_len [u] chunk )
                : ~ i j 0
                ~ < j cn { ( vec_push [u] . c rxbuf # u ( __smtp_vget chunk j ) ) = j + j 1 }
                ( vec_free [u] chunk )
            }
            F er → { ^ @ !i SmtpErr { F ( __smtp_of_net er ) } }
        }
        = spin + spin 1
    }
    ^ @ !i SmtpErr { F # SmtpErr SmtpProtocol }
}

// Send a command, read its reply, return the status code.
@ __smtp_cmd SmtpClient c s text → !i SmtpErr {
    : !v SmtpErr w ( __smtp_write_crlf c text )
    ?? w { T _ → {} F er → { ^ @ !i SmtpErr { F er } } }
    ^ ( __smtp_read_reply c )
}

// Send `text`, require the reply code to equal `want`, else `onfail`.
@ __smtp_expect SmtpClient c s text i want SmtpErr onfail → !v SmtpErr {
    : !i SmtpErr r ( __smtp_cmd c text )
    ^ ?? r {
        T code → ?== code want { @ !v SmtpErr { T 0 } } { @ !v SmtpErr { F onfail } }
        F er → @ !v SmtpErr { F er }
    }
}

// ── connection lifecycle ─────────────────────────────────────────────

@ smtp_close SmtpClient c → v {
    ( tcp_close_conn . c conn )
    ( vec_free [u] . c rxbuf )
    ( string_free . c last_reply )
}

// Wrap a connected (plain or TLS) TcpConn into an SmtpClient and read
// the server's 220 greeting.
@ __smtp_greet TcpConn conn → !SmtpClient SmtpErr {
    : SmtpClient c @ SmtpClient { conn ( vec_new [u] ) ( string_with_cap 128 ) }
    : !i SmtpErr g ( __smtp_read_reply c )
    ^ ?? g {
        T code → ?== code 220 { @ !SmtpClient SmtpErr { T c } } { ( smtp_close c ) @ !SmtpClient SmtpErr { F # SmtpErr SmtpProtocol } }
        F er → { ( smtp_close c ) @ !SmtpClient SmtpErr { F er } }
    }
}

@ smtp_connect s host i port → !SmtpClient SmtpErr {
    : i craw ( nurl_tcp_connect host port )
    ? == craw 0 { ^ @ !SmtpClient SmtpErr { F # SmtpErr SmtpConnect } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !SmtpClient SmtpErr { F # SmtpErr SmtpConnect }
    } {}
    ^ ( __smtp_greet @ TcpConn { # s craw 0 0 } )
}

@ smtp_connect_tls s host i port b verify → !SmtpClient SmtpErr {
    ?? ( tcp_connect_tls host port host ? verify 1 0 ) {
        F _ → ^ @ !SmtpClient SmtpErr { F # SmtpErr SmtpConnect }
        T conn → ^ ( __smtp_greet conn )
    }
}

@ smtp_ehlo SmtpClient c s domain → !v SmtpErr {
    : String line ( string_with_cap 64 )
    ( string_push_str line `EHLO ` )
    ( string_push_str line domain )
    : !v SmtpErr r ( __smtp_expect c ( string_data line ) 250 # SmtpErr SmtpProtocol )
    ( string_free line )
    ^ r
}

// Substring test against the most recent EHLO reply (capability names
// are upper-case: "STARTTLS", "AUTH", "PIPELINING", …).
@ smtp_has_cap SmtpClient c s name → b {
    ^ ( string_contains . c last_reply name )
}

// EHLO must already have run (so smtp_has_cap is populated). Sends
// STARTTLS, upgrades the live fd to TLS, and re-issues EHLO (RFC 3207
// §4.2 requires discarding the pre-TLS capability list).
@ smtp_starttls SmtpClient c s host b verify → !v SmtpErr {
    ? ( smtp_has_cap c `STARTTLS` ) {} { ^ @ !v SmtpErr { F # SmtpErr SmtpNoStartTls } }
    : !v SmtpErr r ( __smtp_expect c `STARTTLS` 220 # SmtpErr SmtpProtocol )
    ?? r { T _ → {} F er → { ^ @ !v SmtpErr { F er } } }
    ?? ( tcp_starttls . c conn host verify ) {
        F _ → ^ @ !v SmtpErr { F # SmtpErr SmtpTls }
        T _ → {}
    }
    ^ ( smtp_ehlo c host )
}

// ── authentication ───────────────────────────────────────────────────

// base64( "\0" user "\0" pass ) — the AUTH PLAIN initial response
// (RFC 4954 §4). Built over a Vec[u] so the NUL separators survive.
@ __smtp_auth_plain_token s user s pass → String {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 0 )
    : i un ( nurl_str_len user )
    : ~ i k 0
    ~ < k un { ( vec_push [u] b # u ( nurl_str_get user k ) ) = k + k 1 }
    ( vec_push [u] b # u 0 )
    : i pn ( nurl_str_len pass )
    = k 0
    ~ < k pn { ( vec_push [u] b # u ( nurl_str_get pass k ) ) = k + k 1 }
    : String tok ( b64_encode_vec b )
    ( vec_free [u] b )
    ^ tok
}

@ smtp_auth_plain SmtpClient c s user s pass → !v SmtpErr {
    : String tok ( __smtp_auth_plain_token user pass )
    : String line ( string_with_cap + ( string_len tok ) 12 )
    ( string_push_str line `AUTH PLAIN ` )
    ( string_push_str line ( string_data tok ) )
    : !v SmtpErr r ( __smtp_expect c ( string_data line ) 235 # SmtpErr SmtpAuth )
    ( string_free line )
    ( string_free tok )
    ^ r
}

@ smtp_auth_login SmtpClient c s user s pass → !v SmtpErr {
    : !v SmtpErr r0 ( __smtp_expect c `AUTH LOGIN` 334 # SmtpErr SmtpAuth )
    ?? r0 { T _ → {} F er → { ^ @ !v SmtpErr { F er } } }
    : String ub ( b64_encode user )
    : !v SmtpErr r1 ( __smtp_expect c ( string_data ub ) 334 # SmtpErr SmtpAuth )
    ( string_free ub )
    ?? r1 { T _ → {} F er → { ^ @ !v SmtpErr { F er } } }
    : String pb ( b64_encode pass )
    : !v SmtpErr r2 ( __smtp_expect c ( string_data pb ) 235 # SmtpErr SmtpAuth )
    ( string_free pb )
    ^ r2
}

// ── envelope + DATA ──────────────────────────────────────────────────

@ smtp_mail_from SmtpClient c s addr → !v SmtpErr {
    : String line ( string_with_cap + ( nurl_str_len addr ) 16 )
    ( string_push_str line `MAIL FROM:<` )
    ( string_push_str line addr )
    ( string_push_char line 62 )  // '>'
    : !v SmtpErr r ( __smtp_expect c ( string_data line ) 250 # SmtpErr SmtpProtocol )
    ( string_free line )
    ^ r
}

@ smtp_rcpt_to SmtpClient c s addr → !v SmtpErr {
    : String line ( string_with_cap + ( nurl_str_len addr ) 16 )
    ( string_push_str line `RCPT TO:<` )
    ( string_push_str line addr )
    ( string_push_char line 62 )
    : !i SmtpErr r ( __smtp_cmd c ( string_data line ) )
    ( string_free line )
    ^ ?? r {
        T code → ?| == code 250 == code 251 { @ !v SmtpErr { T 0 } } { @ !v SmtpErr { F # SmtpErr SmtpProtocol } }
        F er → @ !v SmtpErr { F er }
    }
}

// DATA phase: send the command (expect 354), then the message with
// CRLF line endings, leading-dot stuffing, and the terminating
// "<CRLF>.<CRLF>" (expect 250).
@ smtp_data SmtpClient c s message → !v SmtpErr {
    : !v SmtpErr r1 ( __smtp_expect c `DATA` 354 # SmtpErr SmtpProtocol )
    ?? r1 { T _ → {} F er → { ^ @ !v SmtpErr { F er } } }
    : String ds ( smtp_dotstuff message )
    : i dn ( string_len ds )
    ? | == dn 0 != ( string_get ds - dn 1 ) 10 { ( string_push_char ds 13 ) ( string_push_char ds 10 ) } {}
    ( string_push_char ds 46 )  // '.'
    ( string_push_char ds 13 ) ( string_push_char ds 10 )
    : !v NetErr w ( tcp_write_str . c conn ( string_data ds ) )
    ( string_free ds )
    ?? w { T _ → {} F er → { ^ @ !v SmtpErr { F ( __smtp_of_net er ) } } }
    : !i SmtpErr r2 ( __smtp_read_reply c )
    ^ ?? r2 {
        T code → ?== code 250 { @ !v SmtpErr { T 0 } } { @ !v SmtpErr { F # SmtpErr SmtpProtocol } }
        F er → @ !v SmtpErr { F er }
    }
}

@ smtp_quit SmtpClient c → v {
    : !v SmtpErr w ( __smtp_write_crlf c `QUIT` )
    ?? w {
        T _ → { : !i SmtpErr _r ( __smtp_read_reply c ) ?? _r { T _ → {} F _ → {} } }
        F _ → {}
    }
    ( smtp_close c )
}

// ── message helpers (pure) ───────────────────────────────────────────

@ __smtp_crlf String m → v { ( string_push_char m 13 ) ( string_push_char m 10 ) }

@ __smtp_hdr String m s key s val → v {
    ( string_push_str m key ) ( string_push_str m val ) ( __smtp_crlf m )
}

// Build a minimal RFC 5322 text/plain message (headers + body). The
// body may use bare LF or CRLF; pass the result straight to smtp_data,
// which normalises line endings and applies dot-stuffing.
@ mime_build s from s to s subject s body s date → String {
    : String m ( string_with_cap + ( nurl_str_len body ) 256 )
    ( __smtp_hdr m `From: ` from )
    ( __smtp_hdr m `To: ` to )
    ( __smtp_hdr m `Subject: ` subject )
    ( __smtp_hdr m `Date: ` date )
    ( string_push_str m `MIME-Version: 1.0` ) ( __smtp_crlf m )
    ( string_push_str m `Content-Type: text/plain; charset=utf-8` ) ( __smtp_crlf m )
    ( string_push_str m `Content-Transfer-Encoding: 8bit` ) ( __smtp_crlf m )
    ( __smtp_crlf m )  // blank line separates headers from body
    ( string_push_str m body )
    ^ m
}

// SMTP transparency (RFC 5321 §4.5.2): normalise every line break to
// CRLF and double a '.' that begins a line. Returns a fresh String.
@ smtp_dotstuff s body → String {
    : i n ( nurl_str_len body )
    : String out ( string_with_cap + n 16 )
    : ~ i k 0
    : ~ i atbol 1
    ~ < k n {
        : i ch ( nurl_str_get body k )
        ? == ch 13 {
            ? & < + k 1 n == ( nurl_str_get body + k 1 ) 10 { = k + k 1 } {}
            ( string_push_char out 13 ) ( string_push_char out 10 )
            = atbol 1
        } {
            ? == ch 10 {
                ( string_push_char out 13 ) ( string_push_char out 10 )
                = atbol 1
            } {
                ? & == atbol 1 == ch 46 { ( string_push_char out 46 ) } {}
                ( string_push_char out ch )
                = atbol 0
            } }
        = k + k 1
    }
    ^ out
}

// RFC 2822 Date for "now" in UTC: "Mon, 02 Jan 2006 15:04:05 +0000".
@ smtp_date_now → String {
    ^ ( time_format ( time_now ) `%a, %d %b %Y %H:%M:%S +0000` )
}
