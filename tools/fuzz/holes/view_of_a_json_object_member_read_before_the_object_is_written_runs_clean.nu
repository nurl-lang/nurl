// view_of_a_json_object_member_read_before_the_object_is_written_runs_clean: agora #594 — `: s part ?? ( json_obj_get doc `k` ) { T v → ( json_str_data v ) … }`, `part` read, then `( json_obj_set doc `k` … )`
// The shape the fix must keep: a member `json_obj_get` lent is read before the object is written.
// main a013bfae9: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #594: a view of a member `json_obj_get` lent is read before `json_obj_set` replaces the member
$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`

@ main → i {
    : ~ Json doc ( json_obj_new )
    ( json_obj_set doc `k` ( json_str_lit `a string value long enough to live on the heap` ) )
    : s part ?? ( json_obj_get doc `k` ) { T v → ( json_str_data v ) F → `` }
    ( nurl_println part )
    ( json_obj_set doc `k` ( json_str_lit `another string value, also long enough for the heap` ) )
    ^ 0
}
