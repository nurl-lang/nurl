// smtp_send.nu — submit a mail over STARTTLS using ext/smtp.nu.
//
// Configuration comes from the environment so no secrets live in the
// source:
//
//   SMTP_HOST   submission host         (default: localhost)
//   SMTP_PORT   submission port         (default: 587)
//   SMTP_USER   AUTH username
//   SMTP_PASS   AUTH password
//   SMTP_FROM   envelope + From: address
//   SMTP_TO     envelope + To: address
//
//   $ SMTP_HOST=smtp.example.com SMTP_USER=me@example.com \
//     SMTP_PASS=secret SMTP_FROM=me@example.com \
//     SMTP_TO=you@example.org ./smtp_send
//
// The flow is the canonical RFC 5321 submission sequence: greeting,
// EHLO, STARTTLS (upgrade + re-EHLO), AUTH PLAIN, MAIL FROM, RCPT TO,
// DATA, QUIT. Each step propagates a typed SmtpErr.

$ `stdlib/core/string.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/smtp.nu`

@ die s ctx SmtpErr e → i {
    ( nurl_print `error at ` ) ( nurl_print ctx )
    ( nurl_print `: ` ) ( nurl_print ( smtp_err_name e ) ) ( nurl_print `\n` )
    ^ 1
}

@ run s host i port s user s pass s from s to → i {
    : !SmtpClient SmtpErr cc ( smtp_connect host port )
    ^ ?? cc {
        F e → ( die `connect` e )
        T c → {
            : !v SmtpErr e1 ( smtp_ehlo c host )
            ?? e1 { T _ → {} F e → { ( smtp_close c ) ^ ( die `ehlo` e ) } }

            : !v SmtpErr e2 ( smtp_starttls c host T )
            ?? e2 { T _ → {} F e → { ( smtp_close c ) ^ ( die `starttls` e ) } }

            : !v SmtpErr e3 ( smtp_auth_plain c user pass )
            ?? e3 { T _ → {} F e → { ( smtp_close c ) ^ ( die `auth` e ) } }

            : !v SmtpErr e4 ( smtp_mail_from c from )
            ?? e4 { T _ → {} F e → { ( smtp_close c ) ^ ( die `mail from` e ) } }

            : !v SmtpErr e5 ( smtp_rcpt_to c to )
            ?? e5 { T _ → {} F e → { ( smtp_close c ) ^ ( die `rcpt to` e ) } }

            : String date ( smtp_date_now )
            : String msg ( mime_build from to `Hello from NURL` `This message was sent by the NURL smtp client.\n` ( string_data date ) )
            : !v SmtpErr e6 ( smtp_data c ( string_data msg ) )
            ( string_free msg )
            ( string_free date )
            ?? e6 { T _ → {} F e → { ( smtp_close c ) ^ ( die `data` e ) } }

            ( smtp_quit c )
            ( nurl_print `sent OK\n` )
            ^ 0
        }
    }
}

@ main → i {
    : String host ( env_var_or `SMTP_HOST` `localhost` )
    : String ports ( env_var_or `SMTP_PORT` `587` )
    : String user ( env_var_or `SMTP_USER` `` )
    : String pass ( env_var_or `SMTP_PASS` `` )
    : String from ( env_var_or `SMTP_FROM` `from@example.com` )
    : String to ( env_var_or `SMTP_TO` `to@example.org` )
    : i port ( nurl_str_to_int ( string_data ports ) )
    : i rc ( run ( string_data host ) port ( string_data user ) ( string_data pass ) ( string_data from ) ( string_data to ) )
    ( string_free host ) ( string_free ports ) ( string_free user )
    ( string_free pass ) ( string_free from ) ( string_free to )
    ^ rc
}
