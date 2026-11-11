// bufreader_kept_by_the_spawner_of_a_thread_that_reads_through_it: a thread's closure reads a line through the BufReader it captured, and the spawner reads one through the same BufReader while the thread runs. A BufReader's copies share one buffer and one position — in a counted block its API refills in place — so the two threads move and refill the one buffer with no lock.
// Guard of agora #639's rule: a share handle whose representation is raw code's is used by two threads at once only where it says `% Sync` (__thr_share_ok: __ty_sealed); its fields being Sync says nothing of what its API writes. A thread's closure moves a BufReader as it moves a Vec.
// main: accepted — the capture was not moved; the race is in the refill (not ASan-visible on an empty stdin).
// map: §6.5 | A3 | rejected | - | the spawner keeps reading through the BufReader its thread's closure captured: one buffer in a counted block its API refills in place, no lock — the capture moves (agora #639)
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : BufReader r ( bufreader_stdin )
    : ( @ v ) body \ → v {
        ?? ( bufreader_read_line r ) {
            T ln → { ( nurl_print ( string_data ln ) ) }
            F → {}
        }
    }
    ?? ( thread_spawn body ) {
        T th → {
            ?? ( bufreader_read_line r ) {
                T ln → { ( nurl_print ( string_data ln ) ) }
                F → {}
            }
            : i joined ( thread_join th )
        }
        F _ → {}
    }
    ^ 0
}
