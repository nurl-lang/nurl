// cli/prompt.nu — interactive prompts over std/term + core/io.
//
// All prompts write to stderr (so a command's stdout stays clean for pipes)
// and read a line from stdin. `cli_password` suppresses the echo when stdin
// is a real terminal, and degrades to a plain read otherwise.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/term.nu`

// Ask a free-text question; returns the entered line (trailing newline
// stripped by read_line). Empty String on EOF.
@ cli_prompt s question → String {
    ( nurl_eprint question )
    ( eflush )
    ^ ( read_line )
}

// Yes/no confirmation. `def` is returned on a bare Enter or EOF. Only the
// first character is inspected (y/Y → true, n/N → false, else the default).
@ cli_confirm s question b def → b {
    ( nurl_eprint question )
    ? def { ( nurl_eprint ` [Y/n] ` ) } { ( nurl_eprint ` [y/N] ` ) }
    ( eflush )
    : String line ( read_line )
    : i n ( string_len line )
    ? == n 0 { ( string_free line ) ^ def } {}
    : i c ( string_get line 0 )
    ( string_free line )
    ? || == c 121 == c 89 { ^ T } {}
    ? || == c 110 == c 78 { ^ F } {}
    ^ def
}

// Read a secret. When stdin is a TTY the terminal echo is disabled for the
// duration; otherwise this is a normal (echoed) line read. No in-line
// editing (backspace) in the no-echo path — kept intentionally minimal.
@ cli_password s question → String {
    ( nurl_eprint question )
    ( eflush )
    ?? ( term_raw_enable 0 ) {
        T st → {
            : String secret ( __cli_read_secret )
            ( term_raw_disable st )
            ( nurl_eprint `\n` )
            ( eflush )
            ^ secret
        }
        F → { ^ ( read_line ) }
    }
}

@ __cli_read_secret → String {
    : String buf ( string_new )
    : ~ b going T
    ~ going {
        : ( Vec u ) b1 ( read_n_bytes 1 )
        ? == ( vec_len [u] b1 ) 0 {
            = going F
            ( vec_free [u] b1 )
        } {
            : ~ i c 0
            ?? ( vec_get [u] b1 0 ) { T x → { = c # i x } F _ → {} }
            ( vec_free [u] b1 )
            ? || == c 10 == c 13 {
                = going F
            } {
                // ignore control bytes (< 32) except printable
                ? >= c 32 { ( string_push_char buf c ) } {}
            }
        }
    }
    ^ buf
}
