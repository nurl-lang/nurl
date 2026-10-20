// sink_scalar_is_a_copy.nu — handing a number or a flag to a `sink`
// parameter copies it; the binding stays usable.
//
// A `sink` parameter takes ownership of what it is given, and the
// binding handed over is dead after the call. A scalar owns nothing, so
// there is nothing to take: `n` is still there after `( eat n )`. The
// generic case is the common one — `( locked_new [i] n )` instantiates a
// `sink T` at `i` — and it is the same value going into two fields of
// one literal (an Atomic and a Locked holding the same start).

$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/core/string.nu`

@ eat sink i x → i { ^ + x 1 }

: Start { Atomic seen ( Locked i ) grow }

@ start_at i pid → Start { ^ @ Start { ( atomic_new pid ) ( locked_new [i] pid ) } }

@ main → i {
    : i n 4
    : i a ( eat n )
    : ( Locked i ) l ( locked_new [i] n )
    : b flag T
    : ( Locked b ) lf ( locked_new [b] flag )
    ( nurl_println ( nurl_str_cat `after eat: ` ( nurl_str_int + a n ) ) )
    ( nurl_println ( nurl_str_cat `locked: ` ( nurl_str_int + n ( locked_get [i] l ) ) ) )
    ( nurl_println ? & flag ( locked_get [b] lf ) `flag kept` `flag lost` )
    : Start s ( start_at 7 )
    ( nurl_println ( nurl_str_cat `start: ` ( nurl_str_int + ( atomic_load . s seen ) ( locked_get [i] . s grow ) ) ) )
    ^ 0
}
