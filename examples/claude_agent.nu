// claude_agent.nu — minimal tool-using Claude agent.
//
// Drives a Claude conversation that has access to two tools:
//
//   run_shell {command}  — executes a /bin/sh command, returns stdout
//   read_file {path}     — returns the contents of a UTF-8 text file
//
// The agent loop runs up to AGENT_MAX_TURNS = 8 round-trips:
//
//   1. Send messages + tools to Claude.
//   2. If stop_reason != "tool_use": print the assistant's final text
//      and stop.
//   3. Otherwise, run every tool_use block, collect the results into a
//      single user turn, and loop.
//
// Build + run (Linux/macOS):
//
//     ./build.sh
//     export ANTHROPIC_API_KEY=sk-ant-...
//     ./nurl.sh examples/claude_agent.nu "list the .nu files in stdlib/core and tell me which is largest"
//
// The model is hard-coded to claude-opus-4-7. Tweak `MODEL` below to
// switch to a smaller / faster variant.
//
// SECURITY: `run_shell` executes ARBITRARY commands the model decides
// on. Run this only inside a sandbox (Docker, a VM, a throwaway repo
// clone) when you don't fully trust your prompt. The `system_prompt`
// below asks the model to behave, but that is not a security control.

$ `stdlib/ext/anthropic.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/result.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/core/vec.nu`

// ── Tool descriptors ────────────────────────────────────────────────

// Build {type:"object", properties:{<name>:{type:"string",description:<desc>}}, required:[<name>]}.
// One required string field is enough for both tools we expose.
@ one_string_schema s field_name s field_desc → Json {
  : Json schema ( json_obj_new )
  ( json_obj_set schema `type` ( json_str_lit `object` ) )

  : Json prop ( json_obj_new )
  ( json_obj_set prop `type`        ( json_str_lit `string` ) )
  ( json_obj_set prop `description` ( json_str_lit field_desc ) )

  : Json props ( json_obj_new )
  ( json_obj_set props field_name prop )
  ( json_obj_set schema `properties` props )

  : Json req ( json_arr_new )
  ( json_arr_push req ( json_str_lit field_name ) )
  ( json_obj_set schema `required` req )

  ^ schema
}

@ build_tools → ( Vec Json ) {
  : ( Vec Json ) tools ( vec_new [Json] )

  : Json shell_schema ( one_string_schema `command` `Shell command to execute via /bin/sh -c` )
  ( vec_push [Json] tools
    ( claude_tool_def `run_shell`
                      `Run a shell command and return its stdout. Use sparingly; prefer read_file when you only need to inspect a file.`
                      shell_schema ) )

  : Json file_schema ( one_string_schema `path` `Filesystem path of the file to read` )
  ( vec_push [Json] tools
    ( claude_tool_def `read_file`
                      `Read a UTF-8 text file and return its contents.`
                      file_schema ) )

  ^ tools
}

// ── Tool dispatch ───────────────────────────────────────────────────

// Helper: pull a string field out of a tool_use's input object. Returns
// "" if the field is absent or the wrong shape — let Claude resubmit.
@ input_str Json input s field → s {
  : ? Json v ( json_obj_get input field )
  ?? v {
    T j → { ^ ( json_str_data j ) }
    F   → { ^ `` }
  }
  ^ ``
}

// Cap the tool result so a wild `find /` can't blow our context window.
// Trims to N bytes at most and appends a marker if truncated.
@ MAX_TOOL_BYTES → i { ^ 80000 }

@ truncate_for_model String src → String {
  : i n ( string_len src )
  : i lim ( MAX_TOOL_BYTES )
  ? <= n lim {
    ^ src
  } {}
  : String head ( string_substr src 0 lim )
  ( string_push_str head `\n…[truncated, ` )
  ( string_push_int head - n lim )
  ( string_push_str head ` more bytes]` )
  ( string_free src )
  ^ head
}

// Run a single tool_use block, returning (text, is_error). Both arms
// hand back an owned String so the caller can free uniformly.
@ run_tool Json tu → String {
  : s name ( claude_tool_use_name tu )
  : ? Json input_o ( claude_tool_use_input tu )

  : Json input ?? input_o {
    T j → j
    F   → @ Json { JNull }
  }

  ? != ( nurl_str_eq name `run_shell` ) 0 {
    : s cmd ( input_str input `command` )
    ? == ( nurl_str_len cmd ) 0 {
      ^ ( string_from `error: tool 'run_shell' requires non-empty 'command' field` )
    } {}
    : ! Output ProcessErr r ( process_run_shell cmd )
    ?? r {
      T out → {
        : i ec ( output_exit_code out )
        : String body ( string_with_cap 256 )
        ? != ec 0 {
          ( string_push_str body `[exit ` )
          ( string_push_int body ec )
          ( string_push_str body `]\n` )
        } {}
        ( string_push_str body ( output_stdout out ) )
        : i errlen ( output_stderr_len out )
        ? > errlen 0 {
          ( string_push_str body `\n[stderr]\n` )
          ( string_push_str body ( output_stderr out ) )
        } {}
        ( output_free out )
        ^ ( truncate_for_model body )
      }
      F e → {
        : ProcessErr pe # ProcessErr e
        : String msg ( string_from `error: process_run failed: ` )
        ( string_push_str msg ( process_err_name pe ) )
        ^ msg
      }
    }
  } {}

  ? != ( nurl_str_eq name `read_file` ) 0 {
    : s path ( input_str input `path` )
    ? == ( nurl_str_len path ) 0 {
      ^ ( string_from `error: tool 'read_file' requires non-empty 'path' field` )
    } {}
    : ! String IoErr r ( read_file path )
    ?? r {
      T contents → { ^ ( truncate_for_model contents ) }
      F e → {
        : IoErr ie # IoErr e
        : String msg ( string_from `error: read_file: ` )
        ( string_push_str msg ( io_err_msg ie ) )
        ^ msg
      }
    }
  } {}

  : String unknown ( string_from `error: unknown tool '` )
  ( string_push_str unknown name )
  ( string_push_str unknown `'` )
  ^ unknown
}

// True if name is one of our advertised tools.
@ is_known_tool s name → b {
  ? != ( nurl_str_eq name `run_shell` ) 0 { ^ T } {}
  ? != ( nurl_str_eq name `read_file` ) 0 { ^ T } {}
  ^ F
}

// ── Main loop ───────────────────────────────────────────────────────

@ AGENT_MAX_TURNS → i { ^ 8 }
@ AGENT_MAX_TOKENS → i { ^ 4096 }
@ MODEL → s { ^ `claude-opus-4-7` }
@ SYSTEM_PROMPT → s {
  ^ `You are an assistant running inside a NURL agent host. You have two tools: run_shell (for shell commands) and read_file (for file inspection). Use them to answer the user's request, then provide a final concise text reply. Avoid destructive commands (rm, mv, etc.) unless explicitly asked.`
}

@ main → i {
  // Build initial user prompt.
  : i argc ( env_args_count )
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

  ? == ( string_len prompt ) 0 {
    ( nurl_print `usage: claude_agent <prompt>\n` )
    ( nurl_print `       echo "<prompt>" | claude_agent\n` )
    ( nurl_print `       set ANTHROPIC_API_KEY in the environment first\n` )
    ( string_free prompt )
    ^ 1
  } {}

  : ? String key ( env_get `ANTHROPIC_API_KEY` )
  : s api_key ?? key {
    T s → ( string_data s )
    F   → ``
  }
  ? == ( nurl_str_len api_key ) 0 {
    ( nurl_print `error: ANTHROPIC_API_KEY not set\n` )
    ?? key { T s → ( string_free s )  F → {} }
    ( string_free prompt )
    ^ 1
  } {}

  // Build messages = [user_text(prompt)] and tools.
  : ( Vec Json ) msgs ( vec_new [Json] )
  ( vec_push [Json] msgs ( claude_msg_user_text ( string_data prompt ) ) )
  ( string_free prompt )

  : ( Vec Json ) tools ( build_tools )

  // Drop closure for the Vec[Json] cleanups at end-of-program.
  : (@ v Json) drop_json \ Json e → v { ( json_free e ) }

  // Loop.
  : ~ i turn 0
  : ~ b done F
  : ~ i exit_code 1
  : ~ i total_in 0
  : ~ i total_out 0

  ~ & ! done < turn ( AGENT_MAX_TURNS ) {
    ( nurl_eprint `[agent] turn ` )
    ( nurl_eprint ( nurl_str_int turn ) )
    ( nurl_eprint `\n` )
    ( eflush )

    : ! Json ClaudeErr r
      ( claude_messages_full api_key
                             ( MODEL )
                             ( SYSTEM_PROMPT )
                             msgs tools `auto`
                             ( AGENT_MAX_TOKENS ) )
    ?? r {
      T resp → {
        = total_in  + total_in  ( claude_input_tokens resp )
        = total_out + total_out ( claude_output_tokens resp )

        // Append the assistant turn (full content array — text +
        // tool_use blocks) to the conversation so the model sees its
        // own moves on the next call.
        ( vec_push [Json] msgs ( claude_msg_assistant_response resp ) )

        ? ( claude_has_tool_use resp ) {
          // Run every tool_use block in order, collect results.
          : ( Vec Json ) tcs ( claude_tool_calls resp )
          : ( Vec Json ) results ( vec_new [Json] )

          : i tn ( vec_len [Json] tcs )
          : ~ i k 0
          ~ < k tn {
            : ? Json e ( vec_get [Json] tcs k )
            ?? e {
              T tu → {
                : s tu_id   ( claude_tool_use_id tu )
                : s tu_name ( claude_tool_use_name tu )

                ( nurl_eprint `[agent]  tool ` )
                ( nurl_eprint tu_name )
                ( nurl_eprint ` (` )
                ( nurl_eprint tu_id )
                ( nurl_eprint `)\n` )
                ( eflush )

                : ~ b is_err F
                ? ( is_known_tool tu_name ) {} {
                  = is_err T
                }
                : String out ( run_tool tu )
                ? is_err {
                  ( vec_push [Json] results
                    ( claude_tool_result_block tu_id ( string_data out ) T ) )
                } {
                  // Heuristic: the tool itself signals errors with a
                  // string that starts with "error:". Mark them so
                  // Claude knows to retry / adjust.
                  : b looks_err ( string_starts_with out `error:` )
                  ( vec_push [Json] results
                    ( claude_tool_result_block tu_id ( string_data out ) looks_err ) )
                }
                ( string_free out )
              }
              F → {}
            }
            = k + k 1
          }
          ( vec_free_with [Json] tcs drop_json )

          // Push the user-side tool_result turn.
          ( vec_push [Json] msgs ( claude_msg_user_blocks results ) )
          ( claude_response_free resp )
        } {
          // No tool_use: print the final answer and stop.
          ( nurl_print ( claude_text resp ) )
          ( nurl_print `\n` )
          ( claude_response_free resp )
          = done T
          = exit_code 0
        }
      }
      F e → {
        : ClaudeErr ce # ClaudeErr e
        ( nurl_eprint `[agent] error: ` )
        ( nurl_eprint ( claude_err_name ce ) )
        ( nurl_eprint `\n` )
        = done T
      }
    }

    = turn + turn 1
  }

  ? & ! done >= turn ( AGENT_MAX_TURNS ) {
    ( nurl_eprint `[agent] hit AGENT_MAX_TURNS without final reply\n` )
  } {}

  ( nurl_eprint `[agent] tokens in=` )
  ( nurl_eprint ( nurl_str_int total_in ) )
  ( nurl_eprint ` out=` )
  ( nurl_eprint ( nurl_str_int total_out ) )
  ( nurl_eprint ` turns=` )
  ( nurl_eprint ( nurl_str_int turn ) )
  ( nurl_eprint `\n` )

  ( vec_free_with [Json] msgs  drop_json )
  ( vec_free_with [Json] tools drop_json )
  ?? key { T s → ( string_free s )  F → {} }

  ^ exit_code
}
