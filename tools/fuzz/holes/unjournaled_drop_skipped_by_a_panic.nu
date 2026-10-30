// unjournaled_drop_skipped_by_a_panic: a value with a typed drop is journaled for the panic path with its type's `__jdrop_` thunk, and the push was skipped when the thunk was not out yet — "skipping just means that value isn't reclaimed on panic". Two kinds were never out in time: the drop the compiler writes field by field for a struct that cannot be copied (registered the first time one is owned: a struct holding a lock guard), and a `% Drop` impl written further down the file than its first use. A panic past either left it to nobody: the guard's lock stayed held, its share leaked, and the `% Drop` never ran.
// Closed: the push goes ahead and the thunk is emitted at module end (__pending_ujdrops__); a handle binding stays journaled once, by mem_journal_push_handle.
// main (before this PR): the lock was still held after recover (a second rw_write hung) and LeakSanitizer reported the guard's block; `dropped` stayed 0.
// map: §7.2 | A2 | runs-clean | h291 | panic past a struct holding a lock guard (or a Drop impl defined later): its drop was never journaled — lock held, leak, Drop not run
$ `stdlib/core/vec.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/atomic.nu`

: Fr { i pid }
: Held { i n ( WGuard Fr ) g }

@ hold_and_panic ( RwLocked Fr ) l → i {
    : Held h @ Held { 1 ( rw_write [Fr] l ) }
    ( panic `inside` )
    ^ . h n
}

: Later { Atomic count }

@ later_and_panic Atomic c → i {
    : Later x @ Later { ( mem_dup c ) }
    ( panic `inside` )
    ^ 1
}

% Drop Later { @ drop Later x → v { ( atomic_add . x count 1 ) } }

@ main → i {
    : ( RwLocked Fr ) l ( rw_new [Fr] @ Fr { 0 } )
    : !v PanicInfo r ( recover \ → v { : i k ( hold_and_panic l ) } )
    : ( WGuard Fr ) g ( rw_write [Fr] l )
    ( nurl_println `the lock was released by the unwind` )
    : Atomic c ( atomic_new 0 )
    : !v PanicInfo r2 ( recover \ → v { : i k ( later_and_panic c ) } )
    ( nurl_print `dropped by the unwind: ` ) ( nurl_println_int ( atomic_load c ) )
    ^ 0
}
