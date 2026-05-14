// anthropic_basic.nu — offline tests for stdlib/ext/anthropic.nu.
//
// No network access — only the early-exit paths and pure helpers.
// Exercises:
//   * empty api_key      → ClaudeErr::ClaudeAuth (no network call)
//   * claude_err_name    — every variant renders its tag literally

$ `stdlib/ext/anthropic.nu`

@ main → i {
    // ── 1. Empty api_key short-circuits to ClaudeAuth ────────────
    : !Json ClaudeErr r
    ( claude_messages `` `claude-opus-4-7` `` `hi` 64 )
    ?? r {
        T j → {
            ( nurl_print_str `unexpected: live response with empty api_key` )
            ( claude_response_free j )
        }
        F e → {
            : ClaudeErr ce # ClaudeErr e
            ( nurl_print `auth: ` )
            ( nurl_print_str ( claude_err_name ce ) )
        }
    }

    // ── 2. claude_err_name renders every variant ─────────────────
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeAuth ) )
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeHttpConnect ) )
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeHttpTimeout ) )
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeHttpTls ) )
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeHttpDns ) )
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeHttpInvalidUrl ) )
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeHttpOther ) )
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeJson ) )
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeApi ) )
    ( nurl_print_str ( claude_err_name # ClaudeErr ClaudeShape ) )

    ^ 0
}
