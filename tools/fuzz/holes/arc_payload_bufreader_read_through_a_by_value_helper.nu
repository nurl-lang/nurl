// arc_payload_bufreader_read_through_a_by_value_helper: a function handed, by value, the BufReader of an Arc's payload reads a line through it, on eight threads holding a clone of the Arc. A BufReader's copies share one buffer and one position, refilled in place with no lock.
// Guard of agora #639's rule, the Arc side of shared_closure_reads_lines_through_one_bufreader: a BufReader keeps its state in a counted block only its own code reaches and refills in place, and says no `% Sync` (__libh_rc_backed). It is one unsynchronised state: an Arc whose payload reaches it does not cross to another thread, and a by-value BufReader parameter is no self-synchronising handle, so the read is a change of the frozen payload it was read out of.
// main: refused. A first cut of #639 took every handle not held in an rcbox: heap-buffer-overflow in the refill.
// map: ThruOK.noShare | A3 | rejected | - | a function handed the BufReader of `( arc_get a )` by value reads a line through it: one buffer its API refills in place, no lock (agora #639)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/core/string.nu`

: App { ( Channel i ) jobs BufReader r i n }

@ mkapp → App { ^ @ App { ( chan_new [i] ) ( bufreader_stdin ) 1 } }

@ next BufReader r → i {
    ?? ( bufreader_read_line r ) { T l → { ^ ( string_len l ) } F → {} }
    ^ 0
}

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        : i got ( next . ( arc_get [App] mine ) r )
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec ( Thread ) ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v { ( reader mine 3000 ) }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F _ → {}
        }
        = t + t 1
    }
    ~ > ( vec_len [Thread] ts ) 0 { ?? ( vec_pop [Thread] ts ) { T th → { : i joined ( thread_join th ) } F → {} } }
    ^ 0
}
