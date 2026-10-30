// mcp_task_handle_after_eviction: an MCP task handle kept past its task read freed memory: `mcp_task_create` / `_find` / `_nth` (stdlib/ext/mcp_tasks.nu) handed out a task as an opaque `s`, the address of the McpTask inside its rcbox, and nothing kept the task alive for the handle's holder. At the cap of 2048 tasks `mcp_task_create` evicts the oldest live task when none is terminal, and `mcp_task_store_sweep` drops the expired ones, so `mcp_task_status first` read the evicted task.
// Closed: the handle is an `McpTask`, one owner of the task's rcbox beside the store's list; an evicted or swept task lives until its last handle goes, still readable and changeable, no longer found by id.
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §6.4 | B | runs-clean | h343 | mcp_task_create handed out a task as a bare address; eviction at the cap (or a TTL sweep) freed the task a kept handle still named, and mcp_task_status read freed memory: the handle is one owner of the task's rcbox
$ `stdlib/ext/mcp_tasks.nu`

@ main → i {
    : McpTaskStore st ( mcp_task_store_new )
    : McpTask first ( mcp_task_create st `tools/call` `x` ( json_obj_new ) -1 0 )
    : ~ i k 0
    ~ < k 2048 { : McpTask _t ( mcp_task_create st `tools/call` `x` ( json_obj_new ) -1 0 ) = k + k 1 }
    ( mcp_task_complete first ( json_obj_new ) )
    ^ - ( mcp_task_status first ) mcp_task_completed
}
