// diag_sync_arc_cell.nu
// The Sync half, and the one place the two questions come apart. A
// `Cell` is a raw byte buffer with unsynchronised reads and writes:
// MOVING one to a worker is fine (see send_sync_markers_ok.nu, which
// does exactly that), SHARING one is a data race on its bytes. Only
// `Arc` asks the harder question, so only `( Arc Cell )` is rejected.

$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/cell.nu`

@ main → i {
    : Cell c ( cell_zero 64 )
    : ( Arc Cell ) a ( arc_new [Cell] c )
    : ( @ v ) work \ → v { : Cell g ( arc_get [Cell] a ) }
    : !Thread ThreadErr r ( thread_spawn work )
    ^ 0
}
