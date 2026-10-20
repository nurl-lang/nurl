// stdlib/std/rwlock.nu — a value many threads read at once and one changes.
//
// A `Locked` (stdlib/std/thread.nu) lets one thread at a time near its
// value. State that is read far more often than it is changed — a
// database page, a catalog, a routing table — wants many readers at once
// and a writer alone: a reader-writer lock. The danger is the readers'
// side. NURL's views can change what they view (`slice_put`, a container
// mutator), and two readers holding the same value at the same time would
// race the moment one of them wrote through its view. So what a read
// guard lends is FROZEN: its type is marked `% Frozen`
// (stdlib/core/marker.nu), and the compiler rejects any call that would
// change what it lends — the same check that keeps an `Arc`'s payload
// frozen (docs/MEMORY.md §6.5). Writes go through a write guard, which
// holds the lock alone.
//
//   ( rw_new [T] x )               → ( RwLocked T )   a shared handle
//   ( rw_read [T] l )              → ( RGuard T )     shared: waits for no
//                                                     writer to hold it
//   ( rw_write [T] l )             → ( WGuard T )     exclusive
//   ( rw_try_read [T] l )          → ?( RGuard T )    without waiting
//   ( rw_try_write [T] l )         → ?( WGuard T )
//   ( rguard_get [T] g )           → T    the value, lent — frozen
//   ( wguard_get [T] g )           → T    the value, lent — what is done
//                                         to its containers changes it
//   ( wguard_update [T] g f )      → v    f runs on the value IN PLACE
//                                         (`inout`: scalars too)
//   ( wguard_apply [T R] g f )     → R    …with f's result
//   ( rw_update [T] l f )          → v    rw_write + wguard_update
//   ( rw_apply [T R] l f )         → R
//   ( rw_get [T] l )               → T    a copy, under the read lock
//   ( rw_set [T] l x )             → v    replace, under the write lock
//
// A guard holds its lock until it goes — dropped at the end of its scope,
// moved out, or released by a panic (the drop journal runs its drop,
// docs/MEMORY.md §7.2) — so a lock is never left held. A view a guard
// lends lives no longer than the guard: the borrow checker ends it where
// the guard goes, which is what makes hand-over-hand locking safe — take
// the next guard, then let the previous one go. A guard is released by
// the thread that took it, so it never crosses a thread (`% NotSend`).
//
// A second read guard of a lock its holder (a thread, or a fiber) already
// reads is counted, not taken again, so a reader never queues behind a
// writer that waits for it — on every platform, whichever side its lock
// favours. Asking for a lock the holder already has for writing, or
// asking to write one it reads, would wait for itself: that panics.
// The handle itself is shared: capture it, store it, send it; every copy
// is the same lock and the same value, and the last one releases both.
//
// A thread that already holds a guard of one RwLocked and asks it for
// another waits forever when either is a write guard (as a mutex locked
// twice does): take one guard per lock per thread.

$ `stdlib/core/marker.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/core/rcbox.nu`

& `c` @ nurl_rwlock_size → i

& `c` @ nurl_rwlock_init *u l → v

& `c` @ nurl_rwlock_rdlock sync *u l → v

& `c` @ nurl_rwlock_wrlock sync *u l → v

& `c` @ nurl_rwlock_rdunlock sync *u l → v

& `c` @ nurl_rwlock_wrunlock sync *u l → v

& `c` @ nurl_rwlock_destroy *u l → v

& `c` @ nurl_rwlock_tryrdlock sync *u l → i

& `c` @ nurl_rwlock_trywrlock sync *u l → i

// The lock itself: native storage that never moves once initialised.
: RwLatchImpl { RawBlock blk }

% Drop RwLatchImpl { unsafe @ drop RwLatchImpl x → v { ( nurl_rwlock_destroy ( raw_block_ptr . x blk ) ) } }

: RwLockedImpl [A] {
    RwLatchImpl lk
    A val
}

: RwLocked [A] { ( Shared ( RwLockedImpl A ) ) ctl }

% Sync RwLocked {}

@ RwLocked_share [A] ( RwLocked A ) l → ( RwLocked A ) {
    ^ @ ( RwLocked A ) { ( shared_clone [( RwLockedImpl A )] . l ctl ) }
}

@ RwLocked_drop [A] sink ( RwLocked A ) l → v {}

// A guard holds one owner of the block (so the value outlives every guard
// of it) and the lock, released by its drop hook.
: RGuard [A] { ( Shared ( RwLockedImpl A ) ) ctl }

: WGuard [A] { ( Shared ( RwLockedImpl A ) ) ctl }

// What a read guard lends is shared with every other reader.
% Frozen RGuard {}

// A lock is released by the thread that took it.
% NotSend RGuard {}

% NotSend WGuard {}

@ __rw_lock [A] ( Shared ( RwLockedImpl A ) ) h → *u {
    ^ ( raw_block_ptr . . ( shared_ptr [( RwLockedImpl A )] h ) lk blk )
}

@ RGuard_drop [A] sink ( RGuard A ) g → v { ( nurl_rwlock_rdunlock ( __rw_lock [A] . g ctl ) ) }

@ WGuard_drop [A] sink ( WGuard A ) g → v { ( nurl_rwlock_wrunlock ( __rw_lock [A] . g ctl ) ) }

@ rw_new [A] sink A x → ( RwLocked A ) {
    : RawBlock b ( raw_block_zero ( nurl_rwlock_size ) )
    ( nurl_rwlock_init ( raw_block_ptr b ) )
    ^ @ ( RwLocked A ) { ( shared_new [( RwLockedImpl A )] @ ( RwLockedImpl A ) { @ RwLatchImpl { b } x } ) }
}

@ rw_read [A] ( RwLocked A ) l → ( RGuard A ) {
    ( nurl_rwlock_rdlock ( __rw_lock [A] . l ctl ) )
    ^ @ ( RGuard A ) { ( shared_clone [( RwLockedImpl A )] . l ctl ) }
}

@ rw_write [A] ( RwLocked A ) l → ( WGuard A ) {
    ( nurl_rwlock_wrlock ( __rw_lock [A] . l ctl ) )
    ^ @ ( WGuard A ) { ( shared_clone [( RwLockedImpl A )] . l ctl ) }
}

@ rw_try_read [A] ( RwLocked A ) l → ?( RGuard A ) {
    ? == 0 ( nurl_rwlock_tryrdlock ( __rw_lock [A] . l ctl ) ) { ^ @ ?( RGuard A ) { F } } {}
    ^ @ ?( RGuard A ) { T @ ( RGuard A ) { ( shared_clone [( RwLockedImpl A )] . l ctl ) } }
}

@ rw_try_write [A] ( RwLocked A ) l → ?( WGuard A ) {
    ? == 0 ( nurl_rwlock_trywrlock ( __rw_lock [A] . l ctl ) ) { ^ @ ?( WGuard A ) { F } } {}
    ^ @ ?( WGuard A ) { T @ ( WGuard A ) { ( shared_clone [( RwLockedImpl A )] . l ctl ) } }
}

// The value, lent for as long as the guard lives. Frozen: nothing may
// change it through this view (the compiler checks every call).
@ rguard_get [A] ( RGuard A ) g → A { ^ . ( shared_ptr [( RwLockedImpl A )] . g ctl ) val }

// The value, lent for as long as the guard lives: what is done to its
// containers (a Vec's elements, a slice of them) changes the value. A
// scalar field is changed in place with wguard_update.
@ wguard_get [A] ( WGuard A ) g → A { ^ . ( shared_ptr [( RwLockedImpl A )] . g ctl ) val }

@ wguard_update [A] ( WGuard A ) g ( @ v inout A ) f → v {
    : ~ * ( RwLockedImpl A ) p ( shared_ptr [( RwLockedImpl A )] . g ctl )
    ( f . p val )
}

@ wguard_apply [A R] ( WGuard A ) g ( @ R inout A ) f → R {
    : ~ * ( RwLockedImpl A ) p ( shared_ptr [( RwLockedImpl A )] . g ctl )
    ^ ( f . p val )
}

@ rw_update [A] ( RwLocked A ) l ( @ v inout A ) f → v {
    : ( WGuard A ) g ( rw_write [A] l )
    ( wguard_update [A] g f )
}

@ rw_apply [A R] ( RwLocked A ) l ( @ R inout A ) f → R {
    : ( WGuard A ) g ( rw_write [A] l )
    ^ ( wguard_apply [A R] g f )
}

@ rw_get [A] ( RwLocked A ) l → A {
    : ( RGuard A ) g ( rw_read [A] l )
    ^ ( mem_dup ( rguard_get [A] g ) )
}

@ rw_set [A] ( RwLocked A ) l sink A x → v {
    : ( WGuard A ) g ( rw_write [A] l )
    : ~ * ( RwLockedImpl A ) p ( shared_ptr [( RwLockedImpl A )] . g ctl )
    = . p val x
}
