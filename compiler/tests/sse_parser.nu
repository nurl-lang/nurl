// sse_parser.nu — offline tests for the SSE parser shipped in
// stdlib/ext/http.nu. No network access; we feed synthetic chunks that
// resemble Anthropic's `text/event-stream` framing.
//
// Verifies:
//   1. sse_frame_end finds `\n\n` and returns -1 for partial buffers
//   2. sse_parse_frame extracts event/data/id fields
//   3. multi-line `data:` joins with `\n` (per W3C spec)
//   4. comment lines (`:keepalive`) are skipped
//   5. driving the loop chunk-by-chunk yields multiple events

$ `stdlib/ext/http.nu`
$ `stdlib/ext/anthropic.nu`

@ pr s line → v {
    ( nurl_print line )
    ( nurl_print `\n` )
}

@ dump_event SseEvent ev → v {
    ( nurl_print `event=` )
    ( nurl_print ( string_data . ev name ) )
    ( nurl_print ` id=` )
    ( nurl_print ( string_data . ev id ) )
    ( nurl_print ` data=<` )
    ( nurl_print ( string_data . ev data ) )
    ( nurl_print `>\n` )
}

// Pop and print every complete event currently buffered in `acc`,
// shrinking `acc` to the remaining partial frame. Inlined into `main`
// because NURL has no `~`-mutable parameter form.

@ main → i {
    // ── 1. Frame-end detection ───────────────────────────────────────
    : s s1 `event: hi\ndata: 1\n\nevent: bye\n\n`
    ( nurl_print `frame_end=` )
    ( nurl_println_int ( sse_frame_end s1 ( nurl_str_len s1 ) ) )

    : s partial `data: x\nevent: y`
    ( nurl_print `partial=` )
    ( nurl_println_int ( sse_frame_end partial ( nurl_str_len partial ) ) )

    // ── 2. Single-frame parse with all three fields ──────────────────
    : s frame1 `event: message\nid: 42\ndata: hello world`
    : SseEvent ev1 ( sse_parse_frame frame1 ( nurl_str_len frame1 ) )
    ( dump_event ev1 )
    ( sse_event_free ev1 )

    // ── 3. Multi-line data joins with \n ─────────────────────────────
    : s frame2 `event: chunk\ndata: line1\ndata: line2\ndata: line3`
    : SseEvent ev2 ( sse_parse_frame frame2 ( nurl_str_len frame2 ) )
    ( dump_event ev2 )
    ( sse_event_free ev2 )

    // ── 4. Comment lines skipped ─────────────────────────────────────
    : s frame3 `: keepalive\nevent: ping\n: another comment\ndata: ok`
    : SseEvent ev3 ( sse_parse_frame frame3 ( nurl_str_len frame3 ) )
    ( dump_event ev3 )
    ( sse_event_free ev3 )

    // ── 5. Driving the loop chunk-by-chunk over a synthetic stream ───
    // Three events with comments and a partial split mid-frame.
    : ~ String acc ( string_with_cap 256 )

    // Chunk 1: complete first frame + start of second
    ( string_push_str acc `event: a\ndata: 1\n\nevent: b\ndata` )
    : ~ b done1 F
    ~ ! done1 {
        : i fend ( sse_frame_end ( string_data acc ) ( string_len acc ) )
        ? < fend 0 {
            = done1 T
        } {
            : SseEvent ev ( sse_parse_frame ( string_data acc ) fend )
            ( dump_event ev )
            ( sse_event_free ev )
            : i total ( string_len acc )
            : i drop + fend 2
            : String rest ( string_substr acc drop - total drop )
            ( string_free acc )
            = acc rest
        }
    }

    // Chunk 2: rest of second frame + comment + partial third
    ( string_push_str acc `: 2\n\n: heartbeat\nevent: c\nid: e3\ndata: th` )
    : ~ b done2 F
    ~ ! done2 {
        : i fend ( sse_frame_end ( string_data acc ) ( string_len acc ) )
        ? < fend 0 {
            = done2 T
        } {
            : SseEvent ev ( sse_parse_frame ( string_data acc ) fend )
            ( dump_event ev )
            ( sse_event_free ev )
            : i total ( string_len acc )
            : i drop + fend 2
            : String rest ( string_substr acc drop - total drop )
            ( string_free acc )
            = acc rest
        }
    }

    // Chunk 3: tail of third frame
    ( string_push_str acc `ree\n\n` )
    : ~ b done3 F
    ~ ! done3 {
        : i fend ( sse_frame_end ( string_data acc ) ( string_len acc ) )
        ? < fend 0 {
            = done3 T
        } {
            : SseEvent ev ( sse_parse_frame ( string_data acc ) fend )
            ( dump_event ev )
            ( sse_event_free ev )
            : i total ( string_len acc )
            : i drop + fend 2
            : String rest ( string_substr acc drop - total drop )
            ( string_free acc )
            = acc rest
        }
    }

    // ── 6. Anthropic-shaped event extraction ─────────────────────────
    // text_delta event — should produce the delta text.
    : s anth1_data `event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}`
    : SseEvent ae1 ( sse_parse_frame anth1_data ( nurl_str_len anth1_data ) )
    : ?String d1 ( claude_stream_event_text_delta ae1 )
    ?? d1 {
        T s → {
            ( nurl_print `delta1=` )
            ( nurl_print ( string_data s ) )
            ( nurl_print `\n` )
            ( string_free s )
        }
        F _ → { ( pr `delta1=<none>` ) }
    }
    ( sse_event_free ae1 )

    // input_json_delta (tool-use streaming) — should NOT match text_delta.
    : s anth2_data `event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"x\":1}"}}`
    : SseEvent ae2 ( sse_parse_frame anth2_data ( nurl_str_len anth2_data ) )
    : ?String d2 ( claude_stream_event_text_delta ae2 )
    ?? d2 {
        T s → {
            ( nurl_print `delta2=` )
            ( nurl_print ( string_data s ) )
            ( nurl_print `\n` )
            ( string_free s )
        }
        F _ → { ( pr `delta2=<none>` ) }
    }
    ( sse_event_free ae2 )

    // ping event — wrong shape, must yield None cleanly.
    : s anth3_data `event: ping\ndata: {}`
    : SseEvent ae3 ( sse_parse_frame anth3_data ( nurl_str_len anth3_data ) )
    : ?String d3 ( claude_stream_event_text_delta ae3 )
    ?? d3 {
        T s → {
            ( nurl_print `delta3=` )
            ( nurl_print ( string_data s ) )
            ( nurl_print `\n` )
            ( string_free s )
        }
        F _ → { ( pr `delta3=<none>` ) }
    }
    ( sse_event_free ae3 )

    // claude_messages_stream auth path: empty key short-circuits cleanly.
    : !HttpStream ClaudeErr sr ( claude_messages_stream `` `m` `` `hi` 16 )
    ?? sr {
        T h → {
            ( pr `unexpected: live stream from empty key` )
            ( http_stream_close h )
        }
        F e → {
            : ClaudeErr ce # ClaudeErr e
            ( nurl_print `auth_stream: ` )
            ( nurl_println ( claude_err_name ce ) )
        }
    }

    ( pr `done` )
    ( string_free acc )
    ^ 0
}
