// spawned_closure_arm_payload: a closure a fiber (or a thread) runs, capturing a `??` arm's payload — `?? ( make ) { T s → { ( spawn_owned \ → v { ( use s ) } ) } }` — only viewed it: the arm binding has no drop slot of its own to hand over, so the closure took neither the value nor a share, and the arm's end released what the fiber then read.
// Closed: every spawn runs on a copy of the env that owns what the env only viewed (nurl_closure_own_copy: a String is copied, a handle shared), in nurl_fiber_spawn*, nurl_pthread_create_owned and the signal-handler slot.
// main (before this PR): heap-use-after-free, in the fiber reading the String.
// map: §6.5 | A3 | runs-clean | h204 | fiber closure only views a match-arm payload released at arm end
$ `stdlib/core/string.nu`
$ `stdlib/std/async.nu`

@ show String s → v { ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) }

@ make i n → ?String { ^ @ ?String { T ( string_from ( nurl_str_cat `value ` ( nurl_str_int n ) ) ) } }

@ main → i {
    ( runtime_init 2 )
    : ~ i k 0
    ~ < k 4 {
        ?? ( make k ) {
            T s → { ( spawn_owned \ → v { ( show s ) } ) }
            F → {}
        }
        = k + k 1
    }
    ( runtime_run )
    ^ 0
}
