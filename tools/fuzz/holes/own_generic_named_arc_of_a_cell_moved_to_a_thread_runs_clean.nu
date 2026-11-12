// own_generic_named_arc_of_a_cell_moved_to_a_thread_runs_clean: a program's own generic `: Arc [T] { T v i n }` holding a Cell, moved into a thread by `thread_spawn_owned`
// Closed: agora #714 (precision), only the library's Arc shares its payload; a program's own generic of that name moves its arguments like any struct.
// main ffce8adb: refused ("it reaches a 'Cell'").
// map: §6.5 | A3 | runs-clean | - | agora #714: a program's own generic named Arc moves its Cell to the thread, as any struct does
$ `stdlib/std/thread.nu`
$ `stdlib/core/cell.nu`

: Arc [T] { T v i n }

@ main → i {
    : ( Arc Cell ) a @ ( Arc Cell ) { ( cell_zero 8 ) 1 }
    : ( @ v ) body \ → v { ( nurl_println_int ( cell_size . a v ) ) }
    ?? ( thread_spawn_owned body ) { T th → { : i j ( thread_join th ) } F e → {} }
    ^ 0
}
