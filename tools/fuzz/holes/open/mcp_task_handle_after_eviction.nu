// OPEN in 0.78.0 — an MCP task handle read after the store evicted its task.
// `mcp_task_create` / `_find` / `_nth` hand out a task as an opaque `s` handle: the address of the McpTask inside its rcbox. Nothing keeps the task alive for the handle's holder. At the cap of 2048 tasks `mcp_task_create` evicts the oldest live task when none is terminal, and `mcp_task_store_sweep` (run by every tasks/* lookup) removes the expired ones.
// Unsound because a handle kept across either then points at freed memory: `mcp_task_status first` reads the evicted McpTask. AddressSanitizer: heap-use-after-free. Closing it is a handle that owns a share of the task's rcbox (agora #124; docs/MEMORY.md §6.2).
$ `stdlib/ext/mcp_tasks.nu`

@ main → i {
    : McpTaskStore st ( mcp_task_store_new )
    : s first ( mcp_task_create st `tools/call` `x` ( json_obj_new ) -1 0 )
    : ~ i k 0
    ~ < k 2048 { : s _t ( mcp_task_create st `tools/call` `x` ( json_obj_new ) -1 0 ) = k + k 1 }
    ^ ( mcp_task_status first )
}
