// start_global_shared_unsynchronised: safe code had no way to hold one piece of program-wide state — a global that owns something is read only from `unsafe` functions — so packages kept their state behind `mem_addr` of a mutable global and a hand-held mutex. A global set at start (`: ( Locked T ) g ( make )`) closes that gap; it must not let threads share state that does not synchronise itself.
// Closed: a global set at start holds a Locked, an Arc, a Channel, a Mutex, a Cond or a Semaphore; a ( Vec i ) — pushed through an immutable binding from two threads here — is rejected, and nothing writes the global after start.
// main's compiler: the form did not exist; the same program through a raw global raced two vec_push calls on one buffer.
// map: §6.5 | A3 | rejected | h263 | start-set Vec global pushed from two threads without synchronisation
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ make → ( Vec i ) { ^ ( vec_new [i] ) }

: ( Vec i ) g_items ( make )

@ main → i {
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 10000 { ( vec_push [i] g_items k ) = k + k 1 } }
    ?? ( thread_spawn_owned body ) {
        T t → { : ~ i k 0 ~ < k 10000 { ( vec_push [i] g_items k ) = k + k 1 } : i _j ( thread_join t ) }
        F _ → {}
    }
    ( nurl_println_int ( vec_len [i] g_items ) )
    ^ 0
}
