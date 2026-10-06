// sync_handles_autodrop.nu — Mutex, Cond, Semaphore and Channel are
// released by the language, not by the program.
//
// Each is a handle on one reference-counted object: every copy — a thread
// closure's capture, a struct field, a Vec element, `X_share` — is the
// same lock (the same channel), and the last owner to go destroys it. No
// shape below calls mutex_free / cond_free / sem_free / chan_free, and
// every round must leave the live allocation count where it found it.
// Before, each of these leaked unless freed by hand, and a copy freed
// early left the others holding a destroyed pthread object.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: ~ i g_total 0

: ~ i g_finished 0

: ~ i g_active 0

: ~ i g_peak 0

// A struct holding shares of a lock and a channel.
: Worker { Mutex lock ( Channel String ) out i id }

@ join_all ( Vec Thread ) ts → v {
    : ~ i k 0
    ~ < k ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts k ) {
            T t → { ( thread_join t ) }
            F → {}
        }
        = k + k 1
    }
}

// Four threads add under one lock: the lock travels in their closures.
@ locked_sum → i {
    : Mutex m ( mutex_new )
    : ~ i sum 0
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : ( @ v ) body \ → v {
            : ~ i k 0
            ~ < k 100 { ( mutex_lock m ) = g_total + g_total 1 ( mutex_unlock m ) = k + k 1 }
        }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F e → {}
        }
        = t + t 1
    }
    ( join_all ts )
    ^ g_total
}

// A producer thread hands values over a channel it captured; a Cond
// signals that it is done.
@ produce_consume → i {
    : ( Channel i ) ch ( chan_new [i] )
    : Mutex m ( mutex_new )
    : Cond done ( cond_new )
    = g_finished 0
    : ( @ v ) body \ → v {
        : ~ i k 1
        ~ <= k 10 { ( chan_send [i] ch k ) = k + k 1 }
        ( chan_close [i] ch )
        ( mutex_lock m ) = g_finished 1 ( cond_signal done ) ( mutex_unlock m )
    }
    : ~ i got 0
    ?? ( thread_spawn body ) {
        T th → {
            : ~ b more T
            ~ more {
                ?? ( chan_recv [i] ch ) {
                    T v → { = got + got v }
                    F → { = more F }
                }
            }
            ( mutex_lock m )
            ~ == g_finished 0 { ( cond_wait done m ) }
            ( mutex_unlock m )
            ( thread_join th )
        }
        F e → {}
    }
    ^ got
}

// Shares in structs and a Vec; messages still queued when the last owner
// goes are released with the channel.
@ shared_owners → i {
    : Mutex m ( mutex_new )
    : ( Channel String ) ch ( chan_new [String] )
    : ( Vec Worker ) ws ( vec_new [Worker] )
    : ~ i k 0
    ~ < k 3 {
        ( vec_push [Worker] ws @ Worker { ( Mutex_share m ) ( Channel_share [String] ch ) k } )
        = k + k 1
    }
    = k 0
    ~ < k ( vec_len [Worker] ws ) {
        ?? ( vec_get [Worker] ws k ) {
            T w → {
                ( mutex_lock . w lock )
                ( chan_send [String] . w out ( string_from ( nurl_str_int . w id ) ) )
                ( mutex_unlock . w lock )
            }
            F → {}
        }
        = k + k 1
    }
    : ~ i n ( chan_len [String] ch )
    // One message read back; two stay queued.
    ?? ( chan_try_recv [String] ch ) {
        T s → { = n + n ( string_len s ) }
        F → {}
    }
    ^ n
}

// A counting semaphore captured by workers.
@ gated → i {
    : Semaphore gate ( sem_new 2 )
    : Mutex m ( mutex_new )
    = g_peak 0
    = g_active 0
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 3 {
        : ( @ v ) body \ → v {
            ( sem_acquire gate )
            ( mutex_lock m ) = g_active + g_active 1 ? > g_active g_peak { = g_peak g_active } {} ( mutex_unlock m )
            ( mutex_lock m ) = g_active - g_active 1 ( mutex_unlock m )
            ( sem_release gate )
        }
        ?? ( thread_spawn body ) {
            T th → { ( vec_push [Thread] ts th ) }
            F e → {}
        }
        = t + t 1
    }
    ( join_all ts )
    ^ ? <= g_peak 2 ( sem_avail gate ) -1
}

@ round → v {
    = g_total 0
    : i a ( locked_sum )
    : i b ( produce_consume )
    : i c ( shared_owners )
    : i d ( gated )
    ? == g_total 400 {} { ( nurl_println `lost an update` ) }
    ? & & == a 400 == b 55 & == c 4 == d 2 {} { ( nurl_println ( nurl_str_cat `wrong ` ( nurl_str_int c ) ) ) }
}

@ main → i {
    ( round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 20 { ( round ) = k + k 1 }
    : i l1 ( live )
    ( nurl_println `locked 400, channel 55, shares 4, gate 2` )
    ( nurl_println ? == l0 l1 `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l1 l0 ) ) )
    ^ 0
}
