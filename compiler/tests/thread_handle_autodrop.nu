// thread_handle_autodrop.nu — a Thread is released by the language.
//
// A Thread is a handle on one spawned thread: every copy (a Vec element,
// a struct field, `Thread_share`) is the same thread. The first
// thread_join / thread_detach through any copy settles it — a second
// join returns -1 and never touches the pthread_t again — and when the
// last copy goes, a thread nobody settled is detached (Rust's
// JoinHandle). So a spawn whose handle is discarded is a fire-and-forget
// thread. Before, the handle was a raw pthread_t buffer only join /
// detach freed: every discarded one leaked the buffer and left the
// thread unreaped, and a second join was a use after free.
//
// Every round must leave the live allocation count where it found it.
// requires: live

$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

& `c` @ nurl_atomic_i64_load *u p → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

// The cell every body bumps, reached through a global so the closures
// capture nothing: the live count then does not depend on when a
// detached thread gets round to finishing.
: ~ i g_cell 0

@ bump → v { : i _old ( nurl_atomic_i64_inc # *u g_cell ) }

@ ran → i { ^ ( nurl_atomic_i64_load # *u g_cell ) }

: Holder { Thread t i id }

// Spawned and dropped on the spot, three ways.
@ discarded → v {
    ( thread_spawn \ → v { ( bump ) } )
    : !Thread ThreadErr r ( thread_spawn \ → v { ( bump ) } )
    ?? ( thread_spawn \ → v { ( bump ) } ) { T t → {} F _ → {} }
}

// Kept in a Vec and joined.
@ joined → i {
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i k 0
    ~ < k 4 {
        ?? ( thread_spawn \ → v { ( bump ) } ) { T t → { ( vec_push [Thread] ts t ) } F _ → {} }
        = k + k 1
    }
    : ~ i ok 0
    = k 0
    ~ < k ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts k ) { T t → { ? == 0 ( thread_join t ) { = ok + ok 1 } {} } F _ → {} }
        = k + k 1
    }
    ^ ok
}

// Detached by hand; a second detach is a no-op.
@ detached → v {
    ?? ( thread_spawn \ → v { ( bump ) } ) { T t → { ( thread_detach t ) ( thread_detach t ) } F _ → {} }
}

// One thread, its handle in a Vec, a struct and a share: joined through
// the struct, every later join sees it settled.
@ shared → String {
    : String out ( string_new )
    ?? ( thread_spawn \ → v { ( bump ) } ) {
        T t → {
            : ( Vec Thread ) ts ( vec_new [Thread] )
            ( vec_push [Thread] ts ( Thread_share t ) )
            : Holder h @ Holder { ( Thread_share t ) 1 }
            : Thread t2 ( Thread_share t )
            ( string_push_int out ( thread_join . h t ) )
            ( string_push_str out ` ` )
            ( string_push_int out ( thread_join t2 ) )
            ( string_push_str out ` ` )
            ?? ( vec_get [Thread] ts 0 ) { T x → { ( string_push_int out ( thread_join x ) ) } F _ → {} }
            ( thread_detach t )
        }
        F _ → { ( string_push_str out `spawn failed` ) }
    }
    ^ out
}

// No thread at all: a placeholder handle.
@ none → i {
    : Thread t @ Thread { # s 0 }
    ( thread_detach t )
    ^ ( thread_join t )
}

@ round → String {
    ( discarded )
    : i j ( joined )
    ( detached )
    : String sh ( shared )
    : String out ( string_from `joined ` )
    ( string_push_int out j )
    ( string_push_str out `/4, shared joins ` )
    ( string_push_str out ( string_data sh ) )
    ( string_push_str out `, no thread ` )
    ( string_push_int out ( none ) )
    ^ out
}

// Wait for every body spawned so far; the detached ones run on their own.
@ settle i want → v {
    : ~ i spins 0
    ~ & < ( ran ) want < spins 20000 { ( sleep_ms 1 ) = spins + spins 1 }
}

@ main → i {
    = g_cell # i ( nurl_zalloc 8 )
    : String first ( round )
    ( settle 9 )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 20 {
        : String r ( round )
        ? ( string_eq r first ) {} { ( nurl_println ( string_data r ) ) }
        = k + k 1
    }
    ( settle * 21 9 )
    : i l1 ( live )
    ( nurl_println ( string_data first ) )
    ( nurl_println ( nurl_str_cat `bodies run: ` ( nurl_str_int ( ran ) ) ) )
    ( nurl_println ? == l0 l1 `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l1 l0 ) ) )
    ^ 0
}
