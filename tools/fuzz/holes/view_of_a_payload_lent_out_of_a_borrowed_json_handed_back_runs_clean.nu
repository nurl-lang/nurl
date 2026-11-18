// view_of_a_payload_lent_out_of_a_borrowed_json_handed_back_runs_clean: `?? t { T tj → ( json_str_data tj ) … }` with t a `json_obj_get` lend of a parameter's element, the view handed back and read after the match while the parameter lives
// AGORA-842 guard (CodeRabbit on github#1967): accepted - a payload lent out of a borrow is no part of that borrow: the view is the caller's JSON's (mcp_hardening's first_text)
// map: §2.10 | A2 | runs-clean | - | AGORA-842
$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`

@ text_of Json el → s {
    : ?Json t ( json_obj_get el `text` )
    ^ ?? t { T tj → ( json_str_data tj ) F → `(notext)` }
}

@ main → i {
    : Json el ( json_obj_new )
    ( json_obj_set el `text` ( json_str_lit `a text long enough to be on the heap for certain, surely` ) )
    : s v ( text_of el )
    ( nurl_println v )
    ^ 0
}
