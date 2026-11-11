// diag_sync_handle_inout_storage.nu — a change made through a value that
// synchronises itself is that value's own only when the value is passed by
// value (docs/MEMORY.md §6.5; agora #639). An `inout` parameter is the
// holder's storage: a function that fills it writes where every thread
// running the closure reads its capture, and no lock of the Tally's covers
// the place the Tally is kept in.

$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`

: Tally { Atomic sum }

unsafe % Sync Tally {}

@ tally_reset inout Tally t → v { = t @ Tally { ( atomic_new 0 ) } }

: Board { Tally tally i n }

@ main → i {
    : ~ Board board @ Board { @ Tally { ( atomic_new 0 ) } 1 }
    : ( @ v i ) work \ i k → v { ( tally_reset . board tally ) }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    ^ 0
}
