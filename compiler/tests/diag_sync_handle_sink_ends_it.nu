// diag_sync_handle_sink_ends_it.nu — a value that synchronises itself
// answers for the changes made through it, not for its own end (docs/
// MEMORY.md §6.5; agora #639). A `sink` parameter takes the value over: a
// thread-shared closure that hands its captured struct's Tally to one
// ends, on whichever thread runs first, what every other thread still
// reads.

$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`

: Tally { Atomic sum }

unsafe % Sync Tally {}

@ tally_close sink Tally t → i { ^ ( atomic_load . t sum ) }

: Board { Tally tally i n }

@ main → i {
    : Board board @ Board { @ Tally { ( atomic_new 0 ) } 1 }
    : ( @ v i ) work \ i k → v { : i last ( tally_close . board tally ) }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    ^ 0
}
