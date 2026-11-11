// shared_closure_reads_lines_through_one_bufreader: a closure eight threads run reads a line through the BufReader in its captured struct. A BufReader's copies share one buffer and one position — in a counted block its API refills in place — so every thread moves and refills the one buffer with no lock.
// Guard of agora #639's rule: a standard-library handle synchronises itself where it says `% Sync`; one whose state sits in a counted block its own code writes through is one unsynchronised state (__libh_rc_backed), wherever it is held.
// main: refused. A first cut of #639 took every handle not held in an rcbox: heap-buffer-overflow in the refill.
// map: §6.5 | A3 | rejected | - | a thread-shared closure reads a line through its captured struct's BufReader: one buffer in a counted block its API refills in place, no lock (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/core/string.nu`

: App { ( Channel i ) jobs BufReader r i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( bufreader_stdin ) 1 } }

: Holder { ( @ v i ) f i tag }

@ hit ( Arc Holder ) a i n → v {
    : Holder h ( arc_get [Holder] a )
    : ( @ v i ) g . h f
    : ~ i j 0
    ~ < j n {
        ( g j )
        = j + j 1
    }
}

@ main → i {
    : App app ( mkapp )
    : ( @ v i ) work \ i k → v {
        : ?String l ( bufreader_read_line . app r )
    }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc Holder ) mine ( arc_clone [Holder] shared )
        : ( @ v ) body \ → v { ( hit mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
