// stdlib/std/dos.nu — concurrent + per-IP connection caps
//
// Mutex + condvar primitives come from stdlib/std/thread.nu (pure-NURL
// pthread FFI); the IP table is two parallel heap-allocated arrays
// (i8* / i64) hand-managed via nurl_alloc / nurl_realloc.
//
// API (the raw-pointer-as-`i` handle shape lets HttpServer's
// `dos_state` field keep its `s` type with a `# i` cast):
//
//   ( dos_state_new          i max_concurrent i max_per_ip ) → i
//   ( dos_state_try_acquire  i state s ip )                  → i  0/1
//   ( dos_state_release      i state s ip )                  → v
//   ( dos_state_active       i state )                       → i
//   ( dos_state_free         i state )                       → v
//
// `try_acquire` returns 1 on success (caller proceeds), 0 on
// cap-rejection. Pair every try_acquire=1 with exactly one release on
// the same IP, regardless of how the connection terminated. Empty
// ip (`\`\``) disables per-IP tracking for that call — the global cap
// still applies.
//
// IP-table semantics — verbatim translation of the C §23 policy:
//
//   * Linear-search array, max 256 distinct active IPs. Lookup is
//     O(N); realistic workloads keep N small and accept(2) dwarfs the
//     scan cost.
//   * No eviction other than refcount-to-zero. When count drops to 0
//     on release we drop the entry (last-element-swap-then-pop, O(1)).
//   * Over-cap unknown IPs fall through to "global cap only" — a real
//     attack hits the global cap long before flooding the IP table.
//
// Layout of the heap-allocated state buffer (10 slots × 8 = 80 bytes,
// nurl_zalloc'd; slot offsets in 8-byte units for nurl_poke/peek):
//
//   slot 0: max_concurrent (i64; 0 = unlimited)
//   slot 1: max_per_ip     (i64; 0 = unlimited)
//   slot 2: active_count   (i64; mutex-guarded read+write)
//   slot 3: ip_count       (i64)
//   slot 4: ip_cap         (i64; capped at 256)
//   slot 5: ip_keys_buf    (s; malloc'd array of strdup'd char* per
//                            slot; NULL until first entry)
//   slot 6: ip_counts_buf  (s; malloc'd array of i64 counts; NULL
//                            until first entry)
//   slot 7: mutex_buf      (s; pthread_mutex_t-sized buffer)
//   slot 8: lock_init      (i64; 1 once pthread_mutex_init succeeded)
//   slot 9: reserved       (round buffer to 80 bytes — clean cache
//                            line on x86_64, no real semantic content)

$ `stdlib/core/string.nu`
$ `stdlib/core/cell.nu`
$ `stdlib/std/thread.nu`

// `strdup` is declared in nurlc's preamble (so are nurl_alloc / _zalloc /
// _realloc / _free / _memcpy / _poke / _peek / nurl_str_*) — no extra
// `&`-FFI line needed at the module level.

// ── Internal layout helpers ────────────────────────────────────────

@ __dos_lock i state → v {
    : s sp # s state
    : i li ( nurl_peek sp 8 )
    ? != li 0 {
        ( pthread_mutex_lock # *u # s ( nurl_peek sp 7 ) )
    } {}
}

@ __dos_unlock i state → v {
    : s sp # s state
    : i li ( nurl_peek sp 8 )
    ? != li 0 {
        ( pthread_mutex_unlock # *u # s ( nurl_peek sp 7 ) )
    } {}
}

// Find the IP entry index, or -1 if absent. Caller MUST hold the lock.
@ __dos_find_ip i state s ip → i {
    : s sp # s state
    : s keys_buf # s ( nurl_peek sp 5 )
    ? == # i keys_buf 0 { ^ -1 } {}
    : i ip_count ( nurl_peek sp 3 )
    : ~ i i 0
    ~ < i ip_count {
        : s key # s ( nurl_peek keys_buf i )
        ? != # i key 0 {
            ? == 1 ( nurl_str_eq key ip ) { ^ i } {}
        } {}
        = i + i 1
    }
    ^ -1
}

// Grow the parallel ip_keys + ip_counts arrays to `new_cap` slots.
// Caller MUST hold the lock and have verified new_cap > current cap.
@ __dos_ip_grow i state i new_cap → v {
    : s sp # s state
    : s old_keys # s ( nurl_peek sp 5 )
    : s old_counts # s ( nurl_peek sp 6 )
    : s new_keys ( nurl_realloc old_keys * new_cap 8 )
    : s new_counts ( nurl_realloc old_counts * new_cap 8 )
    // Zero the newly-allocated tail slots so __dos_find_ip's NULL probe
    // is reliable. nurl_realloc leaves the new bytes uninitialised.
    : i old_cap ( nurl_peek sp 4 )
    : ~ i k old_cap
    ~ < k new_cap {
        ( nurl_poke new_keys k 0 )
        ( nurl_poke new_counts k 0 )
        = k + k 1
    }
    ( nurl_poke sp 5 # i new_keys )
    ( nurl_poke sp 6 # i new_counts )
    ( nurl_poke sp 4 new_cap )
}

// ── Public API ────────────────────────────────────────────────────

@ dos_state_new i max_concurrent i max_per_ip → i {
    : s state ( nurl_zalloc 80 )
    ( nurl_poke state 0 max_concurrent )
    ( nurl_poke state 1 max_per_ip )
    : i mu_sz ( nurl_native_sizeof `pthread_mutex_t` )
    ? > mu_sz 0 {
        : s mu_buf ( nurl_zalloc mu_sz )
        : i rc ( pthread_mutex_init # *u mu_buf # *u 0 )
        ? == rc 0 {
            ( nurl_poke state 7 # i mu_buf )
            ( nurl_poke state 8 1 )
        } { ( nurl_free mu_buf ) }
    } {}
    ^ # i state
}

@ dos_state_try_acquire i state s ip → i {
    ? == state 0 { ^ 1 } {}                                // no state → permit
    : s sp # s state
    ( __dos_lock state )
    : i max_conc ( nurl_peek sp 0 )
    : i active ( nurl_peek sp 2 )
    ? && > max_conc 0 >= active max_conc {
        ( __dos_unlock state )
        ^ 0
    } {}
    : i max_per_ip ( nurl_peek sp 1 )
    : b have_ip && > max_per_ip 0 && != # i ip 0 != ( nurl_str_len ip ) 0
    ? have_ip {
        : i idx ( __dos_find_ip state ip )
        ? >= idx 0 {
            : s counts_buf # s ( nurl_peek sp 6 )
            : i count ( nurl_peek counts_buf idx )
            ? >= count max_per_ip {
                ( __dos_unlock state )
                ^ 0
            } {}
            ( nurl_poke counts_buf idx + count 1 )
        } {
            : i ip_count ( nurl_peek sp 3 )
            ? < ip_count 256 {
                : i ip_cap ( nurl_peek sp 4 )
                ? >= ip_count ip_cap {
                    : i newcap ? == ip_cap 0 16 * ip_cap 2
                    ? > newcap 256 { = newcap 256 } {}
                    ( __dos_ip_grow state newcap )
                } {}
                // Re-read after possible grow.
                : i cap2 ( nurl_peek sp 4 )
                ? < ip_count cap2 {
                    : s keys_buf # s ( nurl_peek sp 5 )
                    : s counts_buf # s ( nurl_peek sp 6 )
                    : s dup ( strdup ip )
                    ( nurl_poke keys_buf ip_count # i dup )
                    ( nurl_poke counts_buf ip_count 1 )
                    ( nurl_poke sp 3 + ip_count 1 )
                } {}
            } {}
        }
    } {}
    ( nurl_poke sp 2 + active 1 )
    ( __dos_unlock state )
    ^ 1
}

@ dos_state_release i state s ip → v {
    ? == state 0 {} {
        : s sp # s state
        ( __dos_lock state )
        : i active ( nurl_peek sp 2 )
        ? > active 0 { ( nurl_poke sp 2 - active 1 ) } {}
        : b have_ip && != # i ip 0 != ( nurl_str_len ip ) 0
        ? have_ip {
            : i idx ( __dos_find_ip state ip )
            ? >= idx 0 {
                : s counts_buf # s ( nurl_peek sp 6 )
                : i count ( nurl_peek counts_buf idx )
                ? > count 0 { ( nurl_poke counts_buf idx - count 1 ) } {}
                : i new_count ( nurl_peek counts_buf idx )
                ? == new_count 0 {
                    // last-element-swap-then-pop
                    : s keys_buf # s ( nurl_peek sp 5 )
                    : s old_key # s ( nurl_peek keys_buf idx )
                    ? != # i old_key 0 { ( nurl_free old_key ) } {}
                    : i ip_count ( nurl_peek sp 3 )
                    : i last - ip_count 1
                    ? != idx last {
                        ( nurl_poke keys_buf idx ( nurl_peek keys_buf last ) )
                        ( nurl_poke counts_buf idx ( nurl_peek counts_buf last ) )
                    } {}
                    ( nurl_poke keys_buf last 0 )
                    ( nurl_poke counts_buf last 0 )
                    ( nurl_poke sp 3 - ip_count 1 )
                } {}
            } {}
        } {}
        ( __dos_unlock state )
    }
}

@ dos_state_active i state → i {
    ? == state 0 { ^ 0 } {}
    : s sp # s state
    ( __dos_lock state )
    : i c ( nurl_peek sp 2 )
    ( __dos_unlock state )
    ^ c
}

@ dos_state_free i state → v {
    ? == state 0 {} {
        : s sp # s state
        : s keys_buf # s ( nurl_peek sp 5 )
        : s counts_buf # s ( nurl_peek sp 6 )
        ? != # i keys_buf 0 {
            : i ip_count ( nurl_peek sp 3 )
            : ~ i i 0
            ~ < i ip_count {
                : s key # s ( nurl_peek keys_buf i )
                ? != # i key 0 { ( nurl_free key ) } {}
                = i + i 1
            }
            ( nurl_free keys_buf )
        } {}
        ? != # i counts_buf 0 { ( nurl_free counts_buf ) } {}
        : i li ( nurl_peek sp 8 )
        ? != li 0 {
            : s mu_buf # s ( nurl_peek sp 7 )
            ( pthread_mutex_destroy # *u mu_buf )
            ( nurl_free mu_buf )
        } {}
        ( nurl_free sp )
    }
}
