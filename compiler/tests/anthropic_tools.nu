// anthropic_tools.nu — offline tests for tool-use surface in
// stdlib/ext/anthropic.nu.
//
// No network access. Verifies:
//   1. message builders produce the documented JSON shapes
//   2. tool definition shape (name, description, input_schema)
//   3. tool_choice raw-`s` parsing for "" / auto / any / none / tool:NAME
//   4. claude_has_tool_use + claude_tool_calls + accessors against a
//      synthetic response Json
//   5. claude_messages_full short-circuits to ClaudeAuth when api_key
//      is empty, with non-empty messages and tools (proves the cleanup
//      path doesn't leak — ASan would flag if it did).

$ `stdlib/ext/anthropic.nu`

@ pr s line → v {
    ( nurl_print line )
    ( nurl_print `\n` )
}

@ pr_json Json j → v {
    : String s ( json_stringify j )
    ( pr ( string_data s ) )
    ( string_free s )
}

@ main → i {
    // ── 1. Message builders ──────────────────────────────────────
    : Json m1 ( claude_msg_user_text `hello` )
    ( pr_json m1 )
    ( json_free m1 )

    : Json m2 ( claude_msg_assistant_text `hi back` )
    ( pr_json m2 )
    ( json_free m2 )

    // claude_msg_assistant_response: build a synthetic prior response
    // {content: [{type:"text", text:"ok"}]} and replay it.
    : Json fake_resp ( json_obj_new )
    : Json content_arr ( json_arr_new )
    : Json text_block ( json_obj_new )
    ( json_obj_set text_block `type` ( json_str_lit `text` ) )
    ( json_obj_set text_block `text` ( json_str_lit `ok` ) )
    ( json_arr_push content_arr text_block )
    ( json_obj_set fake_resp `content` content_arr )

    : Json m3 ( claude_msg_assistant_response fake_resp )
    ( pr_json m3 )
    ( json_free m3 )

    // claude_msg_user_blocks: pack tool_result blocks into a user turn.
    : ( Vec Json ) blocks ( vec_new [Json] )
    ( vec_push [Json] blocks ( claude_tool_result_block `toolu_a` `42` F ) )
    ( vec_push [Json] blocks ( claude_tool_result_block `toolu_b` `boom` T ) )
    : Json m4 ( claude_msg_user_blocks blocks )
    ( pr_json m4 )
    ( json_free m4 )

    // ── 2. Tool definition ───────────────────────────────────────
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    : Json city ( json_obj_new )
    ( json_obj_set city `type` ( json_str_lit `string` ) )
    ( json_obj_set props `city` city )
    ( json_obj_set schema `properties` props )

    : Json td ( claude_tool_def `get_weather` `Look up weather` schema )
    ( pr_json td )
    ( json_free td )

    // ── 3. tool_choice parsing via _claude_build_body_full ──────
    // Indirect: build request bodies with each tool_choice form and
    // stringify. Empty messages array is fine for this offline shape
    // probe. Always include one tool so tool_choice is meaningful.
    : ( Vec Json ) empty_msgs ( vec_new [Json] )
    : ( Vec Json ) one_tool ( vec_new [Json] )
    : Json schema2 ( json_obj_new )
    ( json_obj_set schema2 `type` ( json_str_lit `object` ) )
    ( vec_push [Json] one_tool ( claude_tool_def `noop` `does nothing` schema2 ) )

    // tool_choice = "" — no tool_choice field
    : Json b1 ( _claude_build_body_full `m` `` empty_msgs one_tool `` 16 )
    ( pr_json b1 )
    ( json_free b1 )

    : Json b2 ( _claude_build_body_full `m` `` empty_msgs one_tool `auto` 16 )
    ( pr_json b2 )
    ( json_free b2 )

    : Json b3 ( _claude_build_body_full `m` `` empty_msgs one_tool `any` 16 )
    ( pr_json b3 )
    ( json_free b3 )

    : Json b4 ( _claude_build_body_full `m` `` empty_msgs one_tool `none` 16 )
    ( pr_json b4 )
    ( json_free b4 )

    : Json b5 ( _claude_build_body_full `m` `` empty_msgs one_tool `tool:get_weather` 16 )
    ( pr_json b5 )
    ( json_free b5 )

    : Json b6 ( _claude_build_body_full `m` `sys` empty_msgs one_tool `auto` 32 )
    ( pr_json b6 )
    ( json_free b6 )

    // Cleanup the borrowed Vec[Json] inputs.
    : ( @ v Json ) drop_json \ Json e → v { ( json_free e ) }
    ( vec_free_with [Json] empty_msgs drop_json )
    ( vec_free_with [Json] one_tool drop_json )

    // ── 4. Tool-use response extraction ──────────────────────────
    // Build a synthetic response with stop_reason=tool_use and two
    // tool_use blocks plus one text block.
    : Json resp ( json_obj_new )
    ( json_obj_set resp `stop_reason` ( json_str_lit `tool_use` ) )

    : Json carr ( json_arr_new )

    : Json blk_text ( json_obj_new )
    ( json_obj_set blk_text `type` ( json_str_lit `text` ) )
    ( json_obj_set blk_text `text` ( json_str_lit `let me check` ) )
    ( json_arr_push carr blk_text )

    : Json blk_tu1 ( json_obj_new )
    ( json_obj_set blk_tu1 `type` ( json_str_lit `tool_use` ) )
    ( json_obj_set blk_tu1 `id` ( json_str_lit `toolu_01` ) )
    ( json_obj_set blk_tu1 `name` ( json_str_lit `get_weather` ) )
    : Json in1 ( json_obj_new )
    ( json_obj_set in1 `city` ( json_str_lit `Helsinki` ) )
    ( json_obj_set blk_tu1 `input` in1 )
    ( json_arr_push carr blk_tu1 )

    : Json blk_tu2 ( json_obj_new )
    ( json_obj_set blk_tu2 `type` ( json_str_lit `tool_use` ) )
    ( json_obj_set blk_tu2 `id` ( json_str_lit `toolu_02` ) )
    ( json_obj_set blk_tu2 `name` ( json_str_lit `get_time` ) )
    : Json in2 ( json_obj_new )
    ( json_obj_set blk_tu2 `input` in2 )
    ( json_arr_push carr blk_tu2 )

    ( json_obj_set resp `content` carr )

    // claude_has_tool_use
    ? ( claude_has_tool_use resp ) {
        ( pr `has_tool_use=T` )
    } {
        ( pr `has_tool_use=F` )
    }

    // claude_text returns the first text block.
    ( nurl_print `text=` )
    ( nurl_print ( claude_text resp ) )
    ( nurl_print `\n` )

    // claude_tool_calls — owned Vec[Json] of cloned tool_use blocks.
    : ( Vec Json ) tcs ( claude_tool_calls resp )
    ( nurl_print `tool_calls_n=` )
    ( nurl_print ( nurl_str_int ( vec_len [Json] tcs ) ) )
    ( nurl_print `\n` )

    : i tn ( vec_len [Json] tcs )
    : ~ i k 0
    ~ < k tn {
        : ?Json e ( vec_get [Json] tcs k )
        ?? e {
            T tu → {
                ( nurl_print `  id=` )
                ( nurl_print ( claude_tool_use_id tu ) )
                ( nurl_print ` name=` )
                ( nurl_print ( claude_tool_use_name tu ) )
                ( nurl_print ` input=` )
                : ?Json inp ( claude_tool_use_input tu )
                ?? inp {
                    T ij → {
                        : String is ( json_stringify ij )
                        ( nurl_print ( string_data is ) )
                        ( string_free is )
                    }
                    F → { ( nurl_print `<missing>` ) }
                }
                ( nurl_print `\n` )
            }
            F → {}
        }
        = k + k 1
    }

    // Free the Vec[Json] of clones — we own them.
    ( vec_free_with [Json] tcs drop_json )

    // Sanity check that the original response is still intact (cloning
    // worked, no double-free).
    ( nurl_print `stop_reason=` )
    ( nurl_print ( claude_stop_reason resp ) )
    ( nurl_print `\n` )
    ( json_free resp )

    // ── 4b. Cached message builders ──────────────────────────────────
    : Json mc1 ( claude_msg_user_text_cached `cache me` )
    ( pr_json mc1 )
    ( json_free mc1 )

    : Json mc2 ( claude_msg_assistant_text_cached `cached reply` )
    ( pr_json mc2 )
    ( json_free mc2 )

    // ── 4c. claude_messages_full_ex body shapes ──────────────────────
    : ( Vec Json ) ex_msgs ( vec_new [Json] )
    : ( Vec Json ) ex_tools ( vec_new [Json] )
    : Json ex_schema_a ( json_obj_new )
    ( json_obj_set ex_schema_a `type` ( json_str_lit `object` ) )
    ( vec_push [Json] ex_tools ( claude_tool_def `t1` `first` ex_schema_a ) )
    : Json ex_schema_b ( json_obj_new )
    ( json_obj_set ex_schema_b `type` ( json_str_lit `object` ) )
    ( vec_push [Json] ex_tools ( claude_tool_def `t2` `second` ex_schema_b ) )

    // cache_system only — system field becomes the array form, tools stay flat.
    : Json e1 ( _claude_build_body_full_ex
    `m` `you are claude` ex_msgs ex_tools `auto` 64
    T F 0 )
    ( pr_json e1 )
    ( json_free e1 )

    // cache_tools only — last tool gets cache_control, system stays bare string.
    : Json e2 ( _claude_build_body_full_ex
    `m` `you are claude` ex_msgs ex_tools `auto` 64
    F T 0 )
    ( pr_json e2 )
    ( json_free e2 )

    // Both caches plus extended thinking budget.
    : Json e3 ( _claude_build_body_full_ex
    `m` `you are claude` ex_msgs ex_tools `auto` 1024
    T T 4096 )
    ( pr_json e3 )
    ( json_free e3 )

    // Empty system + cache_system flag → field omitted entirely.
    : Json e4 ( _claude_build_body_full_ex
    `m` `` ex_msgs ex_tools `auto` 64
    T F 0 )
    ( pr_json e4 )
    ( json_free e4 )

    ( vec_free_with [Json] ex_msgs drop_json )
    ( vec_free_with [Json] ex_tools drop_json )

    // ── 4d. Cache token + thinking accessors ─────────────────────────
    : Json fake_usage ( json_obj_new )
    ( json_obj_set fake_usage `input_tokens` ( json_int 100 ) )
    ( json_obj_set fake_usage `output_tokens` ( json_int 50 ) )
    ( json_obj_set fake_usage `cache_creation_input_tokens` ( json_int 1234 ) )
    ( json_obj_set fake_usage `cache_read_input_tokens` ( json_int 5678 ) )
    : Json fake_resp2 ( json_obj_new )
    ( json_obj_set fake_resp2 `usage` fake_usage )

    ( nurl_print `cache_create=` )
    ( nurl_print ( nurl_str_int ( claude_cache_creation_tokens fake_resp2 ) ) )
    ( nurl_print `\n` )
    ( nurl_print `cache_read=` )
    ( nurl_print ( nurl_str_int ( claude_cache_read_tokens fake_resp2 ) ) )
    ( nurl_print `\n` )

    // Missing usage → 0.
    : Json empty_resp ( json_obj_new )
    ( nurl_print `cache_create_missing=` )
    ( nurl_print ( nurl_str_int ( claude_cache_creation_tokens empty_resp ) ) )
    ( nurl_print `\n` )

    ( json_free fake_resp2 )
    ( json_free empty_resp )

    // ── 4e. Multimodal content blocks (vision + documents) ───────────
    : Json tb ( claude_text_block `Describe this image:` )
    ( pr_json tb )
    ( json_free tb )

    : Json iurl ( claude_image_url_block `https://example.com/cat.png` )
    ( pr_json iurl )
    ( json_free iurl )

    : Json ib64 ( claude_image_b64_block `image/png` `iVBORw0KGgo=` )
    ( pr_json ib64 )
    ( json_free ib64 )

    : Json durl ( claude_document_url_block `https://example.com/paper.pdf` )
    ( pr_json durl )
    ( json_free durl )

    : Json db64 ( claude_document_b64_block `JVBERi0xLjQK` )
    ( pr_json db64 )
    ( json_free db64 )

    // Full vision turn: text + image url packaged via claude_msg_user_blocks.
    : ( Vec Json ) vblocks ( vec_new [Json] )
    ( vec_push [Json] vblocks ( claude_text_block `What is in this picture?` ) )
    ( vec_push [Json] vblocks ( claude_image_url_block `https://example.com/cat.png` ) )
    : Json vmsg ( claude_msg_user_blocks vblocks )
    ( pr_json vmsg )
    ( json_free vmsg )

    // ── 5. claude_messages_full ClaudeAuth path with non-empty inputs ─
    : ( Vec Json ) m_msgs ( vec_new [Json] )
    ( vec_push [Json] m_msgs ( claude_msg_user_text `hello` ) )
    : ( Vec Json ) m_tools ( vec_new [Json] )
    : Json schema3 ( json_obj_new )
    ( vec_push [Json] m_tools ( claude_tool_def `t` `desc` schema3 ) )

    : !Json ClaudeErr r
    ( claude_messages_full `` `m` `` m_msgs m_tools `auto` 16 )
    ?? r {
        T j → {
            ( pr `unexpected: live response with empty key` )
            ( claude_response_free j )
        }
        F e → {
            : ClaudeErr ce # ClaudeErr e
            ( nurl_print `auth_full: ` )
            ( nurl_println ( claude_err_name ce ) )
        }
    }

    ( vec_free_with [Json] m_msgs drop_json )
    ( vec_free_with [Json] m_tools drop_json )

    ^ 0
}
