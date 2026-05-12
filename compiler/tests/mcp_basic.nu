// mcp_basic.nu — offline shape tests for stdlib/ext/mcp.nu.
//
// No stdin reading. Builds each envelope shape, stringifies, and
// prints — the baseline pins the canonical wire format.

$ `stdlib/ext/mcp.nu`

@ dump s tag Json j → v {
  : String s ( json_stringify j )
  ( nurl_print tag )
  ( nurl_print ` ` )
  ( nurl_print ( string_data s ) )
  ( nurl_print `\n` )
  ( string_free s )
  ( json_free j )
}

@ main → i {
  // ── 1. result envelope ───────────────────────────────────────
  : Json id1 ( json_int 7 )
  : Json r1  ( json_obj_new )
  ( json_obj_set r1 `ok` ( json_bool T ) )
  ( dump `result   ` ( mcp_response_result id1 r1 ) )
  ( json_free id1 )

  // ── 2. error envelope ────────────────────────────────────────
  : Json id2 ( json_int 9 )
  ( dump `error    ` ( mcp_response_error id2 mcp_err_method_not_found `unknown` ) )
  ( json_free id2 )

  // ── 3. notification envelope ────────────────────────────────
  : Json p ( json_obj_new )
  ( json_obj_set p `n` ( json_int 1 ) )
  ( dump `notify   ` ( mcp_notification `progress` p ) )

  // ── 4. text content + tool results ───────────────────────────
  ( dump `text     ` ( mcp_text_content `hi` ) )
  ( dump `tool_ok  ` ( mcp_tool_result_text `done` ) )
  ( dump `tool_err ` ( mcp_tool_result_error `boom` ) )

  // ── 5. tool descriptor ───────────────────────────────────────
  : Json schema ( json_obj_new )
  ( json_obj_set schema `type` ( json_str_lit `object` ) )
  ( dump `tooldesc ` ( mcp_tool_descriptor `echo` `Repeat input` schema ) )

  // ── 6. tools_list_result ─────────────────────────────────────
  : Json sch1 ( json_obj_new )
  ( json_obj_set sch1 `type` ( json_str_lit `object` ) )
  : Json sch2 ( json_obj_new )
  ( json_obj_set sch2 `type` ( json_str_lit `object` ) )
  : ( Vec Json ) tools ( vec_new [Json] )
  ( vec_push [Json] tools ( mcp_tool_descriptor `echo` `e` sch1 ) )
  ( vec_push [Json] tools ( mcp_tool_descriptor `ping` `p` sch2 ) )
  ( dump `toolslist` ( mcp_tools_list_result tools ) )

  // ── 7. initialize result ─────────────────────────────────────
  ( dump `init     ` ( mcp_initialize_result `nurl-srv` `0.1.0` ) )

  // ── 8. error code constants ──────────────────────────────────
  ( nurl_print `codes ` )
  ( nurl_print ( nurl_str_int mcp_err_parse_error ) )
  ( nurl_print ` ` )
  ( nurl_print ( nurl_str_int mcp_err_invalid_request ) )
  ( nurl_print ` ` )
  ( nurl_print ( nurl_str_int mcp_err_method_not_found ) )
  ( nurl_print ` ` )
  ( nurl_print ( nurl_str_int mcp_err_invalid_params ) )
  ( nurl_print ` ` )
  ( nurl_print ( nurl_str_int mcp_err_internal_error ) )
  ( nurl_print `\n` )

  ^ 0
}
