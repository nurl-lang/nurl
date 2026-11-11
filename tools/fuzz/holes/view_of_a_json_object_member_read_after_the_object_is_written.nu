// view_of_a_json_object_member_read_after_the_object_is_written: agora #594 — `: s part ?? ( json_obj_get doc `k` ) { T v → ( json_str_data v ) … }`, `( json_obj_set doc `k` … )`, `part` read
// `json_obj_get` hands back a part read in place out of its argument through a `??` payload: the lend its summary missed. The write releases the member the view reads.
// main a013bfae9: compiles; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #594: a view of a member `json_obj_get` lent is read after `json_obj_set` replaced the member
$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`

@ main → i {
    : ~ Json doc ( json_obj_new )
    ( json_obj_set doc `k` ( json_str_lit `a string value long enough to live on the heap` ) )
    : s part ?? ( json_obj_get doc `k` ) { T v → ( json_str_data v ) F → `` }
    ( json_obj_set doc `k` ( json_str_lit `another string value, also long enough for the heap` ) )
    ( nurl_println part )
    ^ 0
}
