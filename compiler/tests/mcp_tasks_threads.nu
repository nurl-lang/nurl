// Regression: an MCP task handle (stdlib/ext/mcp_tasks.nu, agora #124)
// is one owner of its task and is Sync: a worker thread drives a task it
// was handed while the main thread fills the store past its cap (which
// evicts that task) and sweeps it. The task outlives the store's copy;
// the worker's writes and the main thread's reads all take the store's
// lock. Returns the failure count.
//
// requires: live

$ `stdlib/ext/mcp_tasks.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ~ i fails 0
    : McpTaskStore store ( mcp_task_store_new )
    : McpTask job ( mcp_task_create store `tools/call` `long` ( json_obj_new ) -1 0 )
    ( mcp_task_set_link job 7 )
    : ( @ v ) work \ → v {
        : ~ i k 0
        ~ < k 2000 {
            ( mcp_task_set_message job `working` )
            = k + k 1
        }
        ( mcp_task_complete job ( mcp_tool_result_text `done` ) )
    }
    ?? ( thread_spawn work ) {
        T th → {
            // Every task live: each create past the cap evicts the oldest,
            // `job` first.
            : ~ i c 0
            ~ < c + ( mcp_task_store_max ) 100 {
                : McpTask _t ( mcp_task_create store `tools/call` `filler` ( json_obj_new ) 0 0 )
                : i _st ( mcp_task_status job )
                = c + c 1
            }
            : i _swept ( mcp_task_store_sweep store 99999999999999 )
            ( thread_join th )
        }
        F _ → { ( nurl_print `  FAIL spawn\n` ) = fails + fails 1 }
    }
    ?? ( mcp_task_find store ( mcp_task_id job ) ) {
        T _f → { ( nurl_print `  FAIL evicted-found\n` ) = fails + fails 1 }
        F → {}
    }
    ? != ( mcp_task_status job ) mcp_task_completed {
        ( nurl_print `  FAIL status\n` ) = fails + fails 1
    } {}
    ? != ( mcp_task_link job ) 7 {
        ( nurl_print `  FAIL link\n` ) = fails + fails 1
    } {}
    ? != ( mcp_task_store_count store ) 0 {
        ( nurl_print `  FAIL swept\n` ) = fails + fails 1
    } {}
    ? == fails 0 { ( nurl_print `mcp_tasks_threads: all checks PASS\n` ) }
    { ( nurl_print `mcp_tasks_threads: FAILURES\n` ) }
    ^ fails
}
