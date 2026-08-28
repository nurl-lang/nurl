// claude_chat.nu — minimal Claude (Anthropic Messages API) CLI client.
//
// Reads ANTHROPIC_API_KEY from the environment, takes the prompt either
// from argv or stdin, sends a single-turn message to claude-opus-4-7
// and prints the assistant's reply plus token usage.
//
// Build + run (Linux/macOS):
//
//     ./build.sh
//     export ANTHROPIC_API_KEY=sk-ant-...
//
//     # prompt as a single argv:
//     ./nurl.sh examples/claude_chat.nu "Explain NURL in one sentence"
//
//     # prompt as multiple argv tokens (auto-joined with spaces):
//     ./examples/claude_chat hello there
//
//     # prompt piped on stdin (no argv):
//     echo "Explain NURL" | ./examples/claude_chat
//     ./examples/claude_chat < prompt.txt
//
// Errors are reported by name (ClaudeAuth, ClaudeHttpDns, …); see
// stdlib/ext/anthropic.nu for the full error contract.

$ `stdlib/ext/anthropic.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/io.nu`

@ main → i {
    : i argc ( env_args_count )

    // Build prompt: either join argv past the program name, or — when
    // there are no extra args — slurp stdin to EOF. This makes the tool
    // usable both as `claude_chat "what is NURL"` and
    // `cat question.txt | claude_chat`.
    : String prompt ( string_with_cap 64 )
    ? > argc 1 {
        : ~ i i 1
        ~ < i argc {
            ? > i 1 { ( string_push_str prompt ` ` ) } {}
            ( string_push_str prompt ( nurl_argv_get i ) )
            = i + i 1
        }
    } {
        : String stdin_text ( read_all_stdin )
        ( string_push_str prompt ( string_data stdin_text ) )
        ( string_free stdin_text )
    }

    // Reject empty prompts so we don't silently spend a token call on a
    // blank message.
    ? == ( string_len prompt ) 0 {
        ( nurl_print `usage: claude_chat <prompt>\n` )
        ( nurl_print `       echo "<prompt>" | claude_chat\n` )
        ( nurl_print `       set ANTHROPIC_API_KEY in the environment first\n` )
        ( string_free prompt )
        ^ 1
    } {}

    // Pull the API key out of the environment. We don't print it — even
    // a partial leak in logs is a risk worth refusing.
    : ?String key ( env_get `ANTHROPIC_API_KEY` )
    : s api_key ?? key {
        T s → ( string_data s )
        F → ``
    }
    ? == ( nurl_str_len api_key ) 0 {
        ( nurl_print `error: ANTHROPIC_API_KEY not set\n` )
        ?? key { T s → ( string_free s ) F → {} }
        ^ 1
    } {}

    : !Json ClaudeErr r
    ( claude_messages api_key
    `claude-opus-4-7`
    `You are a helpful, concise assistant.`
    ( string_data prompt )
    1024 )
    ( string_free prompt )
    ?? key { T s → ( string_free s ) F → {} }

    ?? r {
        T resp → {
            ( nurl_print ( claude_text resp ) )
            ( nurl_print `\n` )
            ( nurl_print `\n[model=` )
            ( nurl_print ( claude_model resp ) )
            ( nurl_print ` stop=` )
            ( nurl_print ( claude_stop_reason resp ) )
            ( nurl_print ` in=` )
            ( nurl_print ( nurl_str_int ( claude_input_tokens resp ) ) )
            ( nurl_print ` out=` )
            ( nurl_print ( nurl_str_int ( claude_output_tokens resp ) ) )
            ( nurl_print `]\n` )
            ( claude_response_free resp )
            ^ 0
        }
        F e → {
            : ClaudeErr ce # ClaudeErr e
            ( nurl_print `error: ` )
            ( nurl_println ( claude_err_name ce ) )
            ^ 1
        }
    }
    ^ 1
}
