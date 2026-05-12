// anthropic_stream.nu — offline tests for the streaming SSE-event
// extractors in stdlib/ext/anthropic.nu.
//
// No network access. Builds synthetic SseEvent values with the exact
// JSON shapes Anthropic emits for each streaming frame, runs every
// extractor against them, and prints the outcome so the result file
// captures full-fidelity oracles.
//
// Coverage:
//   1. claude_stream_event_text_delta       — hit + miss
//   2. claude_stream_event_input_json_delta — hit + miss + multi-frame
//                                              accumulation
//   3. claude_stream_event_index             — content_block_start /
//                                              content_block_delta /
//                                              content_block_stop hit;
//                                              other-event miss
//   4. claude_stream_event_block_kind        — text + tool_use
//   5. claude_stream_event_tool_use_id       — hit + miss when content_block
//                                              isn't a tool_use
//   6. claude_stream_event_tool_use_name     — hit + miss
//   7. claude_stream_event_stop_reason       — message_delta hit
//   8. claude_stream_event_error_type        — error event hit + miss
//   9. claude_stream_event_error_message     — error event hit + miss

$ `stdlib/ext/http.nu`
$ `stdlib/ext/anthropic.nu`

@ pr s line → v {
  ( nurl_print line )
  ( nurl_print `\n` )
}

@ make_event s name s data → SseEvent {
  : String n_  ( string_from name )
  : String d_  ( string_from data )
  : String id_ ( string_new )
  ^ @ SseEvent { n_ d_ id_ }
}

@ pr_str_opt s tag ? String r → v {
  ( nurl_print tag )
  ( nurl_print `=` )
  ?? r {
    T s → {
      ( nurl_print ( string_data s ) )
      ( string_free s )
    }
    F _ → { ( nurl_print `<none>` ) }
  }
  ( nurl_print `\n` )
}

@ pr_int_opt s tag ? i r → v {
  ( nurl_print tag )
  ( nurl_print `=` )
  ?? r {
    T n → { ( nurl_print ( nurl_str_int n ) ) }
    F _ → { ( nurl_print `<none>` ) }
  }
  ( nurl_print `\n` )
}

@ main → i {
  // ── 1. text_delta ────────────────────────────────────────────────
  : SseEvent ev_text ( make_event
      `content_block_delta`
      `{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}` )
  ( pr_str_opt `text_delta_hit`  ( claude_stream_event_text_delta       ev_text ) )
  ( pr_str_opt `text_delta_ijd`  ( claude_stream_event_input_json_delta ev_text ) )
  ( pr_int_opt `text_delta_idx`  ( claude_stream_event_index            ev_text ) )
  ( sse_event_free ev_text )

  // ── 2. input_json_delta — single frame ───────────────────────────
  : SseEvent ev_ijd1 ( make_event
      `content_block_delta`
      `{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"city\":"}}` )
  ( pr_str_opt `ijd_text_delta` ( claude_stream_event_text_delta       ev_ijd1 ) )
  ( pr_str_opt `ijd_partial`    ( claude_stream_event_input_json_delta ev_ijd1 ) )
  ( pr_int_opt `ijd_index`      ( claude_stream_event_index            ev_ijd1 ) )
  ( sse_event_free ev_ijd1 )

  // ── 2b. input_json_delta — accumulate two frames into a complete JSON ─
  : SseEvent ev_ijd2 ( make_event
      `content_block_delta`
      `{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"Helsinki\"}"}}` )
  : ~ String acc ( string_with_cap 64 )
  : SseEvent ev_ijd_a ( make_event
      `content_block_delta`
      `{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"city\":"}}` )
  ?? ( claude_stream_event_input_json_delta ev_ijd_a ) {
    T s → { ( string_push_str acc ( string_data s ) ) ( string_free s ) }
    F _ → {}
  }
  ( sse_event_free ev_ijd_a )
  ?? ( claude_stream_event_input_json_delta ev_ijd2 ) {
    T s → { ( string_push_str acc ( string_data s ) ) ( string_free s ) }
    F _ → {}
  }
  ( sse_event_free ev_ijd2 )
  ( nurl_print `accumulated=` )
  ( nurl_print ( string_data acc ) )
  ( nurl_print `\n` )
  ( string_free acc )

  // ── 3. content_block_start (text) ────────────────────────────────
  : SseEvent ev_cbs_text ( make_event
      `content_block_start`
      `{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}` )
  ( pr_int_opt `cbs_text_idx`  ( claude_stream_event_index         ev_cbs_text ) )
  ( pr_str_opt `cbs_text_kind` ( claude_stream_event_block_kind    ev_cbs_text ) )
  ( pr_str_opt `cbs_text_id`   ( claude_stream_event_tool_use_id   ev_cbs_text ) )
  ( pr_str_opt `cbs_text_name` ( claude_stream_event_tool_use_name ev_cbs_text ) )
  ( sse_event_free ev_cbs_text )

  // ── 3b. content_block_start (tool_use) ───────────────────────────
  : SseEvent ev_cbs_tu ( make_event
      `content_block_start`
      `{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01ABC","name":"get_weather","input":{}}}` )
  ( pr_int_opt `cbs_tu_idx`   ( claude_stream_event_index         ev_cbs_tu ) )
  ( pr_str_opt `cbs_tu_kind`  ( claude_stream_event_block_kind    ev_cbs_tu ) )
  ( pr_str_opt `cbs_tu_id`    ( claude_stream_event_tool_use_id   ev_cbs_tu ) )
  ( pr_str_opt `cbs_tu_name`  ( claude_stream_event_tool_use_name ev_cbs_tu ) )
  ( sse_event_free ev_cbs_tu )

  // ── 4. content_block_stop ────────────────────────────────────────
  : SseEvent ev_cbe ( make_event
      `content_block_stop`
      `{"type":"content_block_stop","index":1}` )
  ( pr_int_opt `cbstop_idx`   ( claude_stream_event_index      ev_cbe ) )
  ( pr_str_opt `cbstop_kind`  ( claude_stream_event_block_kind ev_cbe ) )
  ( sse_event_free ev_cbe )

  // ── 5. message_delta — stop_reason ───────────────────────────────
  : SseEvent ev_md ( make_event
      `message_delta`
      `{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":42}}` )
  ( pr_str_opt `md_stop`      ( claude_stream_event_stop_reason ev_md ) )
  ( pr_int_opt `md_idx`       ( claude_stream_event_index       ev_md ) )
  ( pr_str_opt `md_text`      ( claude_stream_event_text_delta  ev_md ) )
  ( sse_event_free ev_md )

  // ── 5b. message_delta — end_turn ─────────────────────────────────
  : SseEvent ev_md2 ( make_event
      `message_delta`
      `{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null}}` )
  ( pr_str_opt `md2_stop`     ( claude_stream_event_stop_reason ev_md2 ) )
  ( sse_event_free ev_md2 )

  // ── 6. error event ───────────────────────────────────────────────
  : SseEvent ev_err ( make_event
      `error`
      `{"type":"error","error":{"type":"overloaded_error","message":"Servers are overloaded"}}` )
  ( pr_str_opt `err_type`     ( claude_stream_event_error_type    ev_err ) )
  ( pr_str_opt `err_message`  ( claude_stream_event_error_message ev_err ) )
  ( pr_str_opt `err_text`     ( claude_stream_event_text_delta    ev_err ) )
  ( pr_str_opt `err_stop`     ( claude_stream_event_stop_reason   ev_err ) )
  ( sse_event_free ev_err )

  // ── 7. ping (filler frame) — every extractor must yield None ─────
  : SseEvent ev_ping ( make_event
      `ping`
      `{"type":"ping"}` )
  ( pr_str_opt `ping_text`    ( claude_stream_event_text_delta       ev_ping ) )
  ( pr_str_opt `ping_ijd`     ( claude_stream_event_input_json_delta ev_ping ) )
  ( pr_int_opt `ping_idx`     ( claude_stream_event_index            ev_ping ) )
  ( pr_str_opt `ping_kind`    ( claude_stream_event_block_kind       ev_ping ) )
  ( pr_str_opt `ping_tu_id`   ( claude_stream_event_tool_use_id      ev_ping ) )
  ( pr_str_opt `ping_tu_name` ( claude_stream_event_tool_use_name    ev_ping ) )
  ( pr_str_opt `ping_stop`    ( claude_stream_event_stop_reason      ev_ping ) )
  ( pr_str_opt `ping_etype`   ( claude_stream_event_error_type       ev_ping ) )
  ( pr_str_opt `ping_emsg`    ( claude_stream_event_error_message    ev_ping ) )
  ( sse_event_free ev_ping )

  ( pr `done` )
  ^ 0
}
