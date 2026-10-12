// stdlib/std/dos.nu — concurrent + per-IP connection caps
//
// API:
//
//   ( dos_state_new          i max_concurrent i max_per_ip ) → DosState
//   ( dos_state_try_acquire  DosState g s ip )               → i  0/1
//   ( dos_state_release      DosState g s ip )               → v
//   ( dos_state_active       DosState g )                    → i
//   ( dos_state_free         DosState g )                    → v  (early release)
//
// A `DosState` is a handle: every copy — each worker's — is the same
// counters, behind one mutex, and the last copy releases them. Nothing is
// freed by hand.
//
// `try_acquire` returns 1 on success (caller proceeds), 0 on
// cap-rejection. Pair every try_acquire=1 with exactly one release on
// the same IP, regardless of how the connection terminated. Empty
// ip (`\`\``) disables per-IP tracking for that call — the global cap
// still applies.
//
// IP-table semantics — verbatim translation of the C §23 policy:
//
//   * Linear-search table, max 256 distinct active IPs. Lookup is
//     O(N); realistic workloads keep N small and accept(2) dwarfs the
//     scan cost.
//   * No eviction other than refcount-to-zero. When count drops to 0
//     on release we drop the entry (last-element-swap-then-pop, O(1)).
//   * Over-cap unknown IPs fall through to "global cap only" — a real
//     attack hits the global cap long before flooding the IP table.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`

: DosImpl {
    i max_concurrent  // 0 = unlimited
    i max_per_ip  // 0 = unlimited
    i active
    ( Vec String ) ips  // the IPs with a connection open…
    ( Vec i ) counts  // …and how many each has
    Mutex mu  // guards everything above
}

: DosState { ( Arc DosImpl ) a }

@ DosState_share DosState g → DosState { ^ @ DosState { ( arc_clone [DosImpl] . g a ) } }

@ DosState_drop sink DosState g → v {}

@ __dos DosState g → *DosImpl { ^ ( arc_ptr [DosImpl] . g a ) }

// Find the IP entry index, or -1 if absent. Caller MUST hold the lock.
@ __dos_find_ip * DosImpl d s ip → i {
    : i n ( vec_len [String] . d ips )
    : ~ i k 0
    ~ < k n {
        ? == 1 ( nurl_str_eq ( string_data ( vec_at [String] . d ips k ) ) ip ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// ── Public API ────────────────────────────────────────────────────

@ dos_state_new i max_concurrent i max_per_ip → DosState {
    ^ @ DosState { ( arc_new [DosImpl] @ DosImpl {
            max_concurrent max_per_ip 0 ( vec_new [String] ) ( vec_new [i] ) ( mutex_new )
        } ) }
}

@ dos_state_try_acquire DosState g s ip → i {
    : *DosImpl d ( __dos g )
    ( mutex_lock . d mu )
    : i max_conc . d max_concurrent
    ? && > max_conc 0 >= . d active max_conc {
        ( mutex_unlock . d mu )
        ^ 0
    } {}
    : i max_per_ip . d max_per_ip
    : b have_ip && > max_per_ip 0 && != # i ip 0 != ( nurl_str_len ip ) 0
    ? have_ip {
        : i idx ( __dos_find_ip d ip )
        ? >= idx 0 {
            : *i counts ( vec_data [i] . d counts )
            ? >= . counts idx max_per_ip {
                ( mutex_unlock . d mu )
                ^ 0
            } {}
            = . counts idx + . counts idx 1
        } {
            ? < ( vec_len [String] . d ips ) 256 {
                ( vec_push [String] . d ips ( string_from ip ) )
                ( vec_push [i] . d counts 1 )
            } {}
        }
    } {}
    = . d active + . d active 1
    ( mutex_unlock . d mu )
    ^ 1
}

@ dos_state_release DosState g s ip → v {
    : *DosImpl d ( __dos g )
    ( mutex_lock . d mu )
    ? > . d active 0 { = . d active - . d active 1 } {}
    : b have_ip && != # i ip 0 != ( nurl_str_len ip ) 0
    ? have_ip {
        : i idx ( __dos_find_ip d ip )
        ? >= idx 0 {
            : *i counts ( vec_data [i] . d counts )
            ? > . counts idx 0 { = . counts idx - . counts idx 1 } {}
            ? == . counts idx 0 {
                // last-element-swap-then-pop
                : i last - ( vec_len [i] . d counts ) 1
                : b _s ( vec_swap [String] . d ips idx last )
                : b _c ( vec_swap [i] . d counts idx last )
                : ?String _ip ( vec_pop [String] . d ips )
                : ?i _n ( vec_pop [i] . d counts )
            } {}
        } {}
    } {}
    ( mutex_unlock . d mu )
}

@ dos_state_active DosState g → i {
    : *DosImpl d ( __dos g )
    ( mutex_lock . d mu )
    : i c . d active
    ( mutex_unlock . d mu )
    ^ c
}

// Let go of `g` now rather than at the end of its owner's scope.
@ dos_state_free sink DosState g → v {}
