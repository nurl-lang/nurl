// should_fail_ts_closure_self_cycle.nu — a handler stored in a thread-shared
// handle's state that captures a handle leading back to it closes a cycle of
// counts nothing frees; thread-shared handles are not collected, so the
// store is rejected (docs/MEMORY.md §7.7). The shape of the leak found in
// packages/swarm-mcp: a swarm whose job node's handler captured the swarm.

$ `stdlib/dist/job.nu`

: SwarmLike { JobNode job i id }

@ handler ( Vec u ) p → ( Vec u ) { ^ p }

@ register JobNode node → v {
    : JobNode back ( JobNode_share node )
    ( job_register node 1 \ ( Vec u ) p → ( Vec u ) { : JobNode keep back ^ p } )
}

@ main → i {
    ^ 0
}
