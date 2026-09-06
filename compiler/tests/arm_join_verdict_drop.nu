// arm_join_verdict_drop.nu — an arm whose VALUE is a pointer or an
// aggregate cannot free its `% Drop` values and owned struct fields at
// its fall-through (mem_arm_drop_safe: the value may be backed by one of
// them), and they used to leak whether or not anything consumed the
// value. The common shape is an arm whose tail is an assignment to an
// outer binding — `= out …` publishes the assigned type, so the arm is
// value-typed — with a Drop payload bound by the pattern:
//
//     ?? ( sqlite_open path ) {
//         F _ → {}
//         T db → { ( string_free out ) = out ( names db ) }
//     }
//
// The connection was never closed (every anomaly service handler
// leaked one per request under LSan). Now such an arm leaves through a
// private exit block, and once every arm is parsed the join decides:
// nothing consumes the value (no phi — the arms disagree, or the `?`/`??`
// heads a statement that is not its block's tail) → the exit block runs
// the parked drops; the value is consumed → a bare `br`, the value may
// alias (leak, never a use-after-free).
//
// A `?`/`??` that is the TAIL of its block cannot decide alone — its
// value is the block's value, and only the block's consumer knows
// whether that is used. It hands the exit records up (`__pend_exits__`);
// an enclosing arm inherits them into its own join, and the construct
// that knows the verdict drains them: a loop or bare block body (void:
// drop), a function or closure body (the fall-off value: dropped iff
// the body returns nothing), a block in expression position (consumed:
// bare branch). Cases 5–9 below cover each consumer.
//
// Drops are counted through a global so a drop that runs too early
// (before the consumer reads) or not at all shows in the numbers; the
// DH struct also frees real heap, so the LSan-pinned run sees a missed
// drop as a leak. Run with LSAN_DETECT_LEAKS=1: must be leak-clean.

$ `stdlib/core/string.nu`

: ~ i g_drops 0

: DH { * u buf i id }

% Drop ( DH ) { @ drop DH h → v { = g_drops + g_drops 1 ( nurl_free # s . h buf ) } }

@ open i id → !DH String {
    ? < id 0 { ^ @ !DH String { F ( string_from `negative` ) } } {}
    ^ @ !DH String { T @ DH { # *u ( malloc 16 ) id } }
}

@ label DH h → String {
    : String s ( string_from `dh-` )
    ( string_push_str s ( nurl_str_int . h id ) )
    ^ s
}

// 1. `??`: void arm beside an assignment-tailed arm — no phi, the
//    payload is dropped in the exit block, after the assignment read it.
@ mismatch → String {
    : ~ String out ( string_new )
    ?? ( open 1 ) {
        F _ → {}
        T db → {
            ( string_free out )
            = out ( label db )
        }
    }
    ^ out
}

// 2. `??`: both arms assign a String — a phi WOULD type-check, but the
//    match heads a statement that is not the block's tail, so nothing
//    consumes it and the payload is still dropped.
@ agree i id → String {
    : ~ String out ( string_new )
    ?? ( open id ) {
        F e → {
            ( string_free out )
            = out e
        }
        T db → {
            ( string_free out )
            = out ( label db )
        }
    }
    ( string_push_str out `!` )
    ^ out
}

// 3. `?`: an arm-local Drop binding in a conditional whose tail is an
//    assignment — gen_cond's twin of case 1.
@ cond b flag → String {
    : ~ String out ( string_new )
    ? flag {
        : DH h @ DH { # *u ( malloc 16 ) 30 }
        ( string_free out )
        = out ( label h )
    } {}
    ^ out
}

// 4. The value IS consumed (`:` binding of the match) — the arm-local
//    handle must survive the arm: the pointer it hands out is read by
//    the consumer. Freed by hand afterwards so the pinned run stays
//    leak-clean (the compiler leaves it, by the leak-not-UAF rule).
@ consumed → i {
    : i before g_drops
    : *u p ?? ( open 4 ) {
        T db → { : *u q . db buf = . db buf q q }
        F _ → # *u ( malloc 16 ) }
    : i after g_drops
    ( nurl_free # s p )
    ^ - after before
}

// 5. Hand-up through an arm: the `??` is the tail of a `?` arm body, so
//    the `??` cannot judge — the `?` inherits its exit and, being a
//    non-tail statement itself, drops. The anomaly service's handler
//    shape (`? see_all {} { ?? ( db_open … ) { T db → { = owner … } } }`).
@ nested b flag → String {
    : ~ String out ( string_new )
    ? flag {} {
        ?? ( open 5 ) {
            T db → {
                ( string_free out )
                = out ( label db )
            }
            F _ → {}
        }
    }
    ^ out
}

// 6. Two levels of hand-up: `??` tail of a `?` arm that is the tail of a
//    `?` arm; the outermost `?` heads a non-tail statement and drops.
@ nested2 b flag → String {
    : ~ String out ( string_new )
    ? flag {} {
        ? F {} {
            ?? ( open 6 ) {
                T db → {
                    ( string_free out )
                    = out ( label db )
                }
                F _ → {}
            }
        }
    }
    ^ out
}

// 7. Tail of a loop body: the body is void, so the loop drains and drops
//    on every iteration — three rounds, three drops.
@ looped → String {
    : ~ String out ( string_new )
    : ~ i k 0
    ~ < k 3 {
        = k + k 1
        ?? ( open k ) {
            T db → {
                ( string_free out )
                = out ( label db )
            }
            F _ → {}
        }
    }
    ^ out
}

// 8. Tail of a void function body: the fall-off value is unused, drop.
@ fn_tail_void → v {
    : ~ String out ( string_new )
    ?? ( open 8 ) {
        T db → {
            ( string_free out )
            = out ( label db )
        }
        F _ → {}
    }
    ( string_free out )
}

// 9. Tail of a closure body (void): the arm's value is a pointer into
//    the payload, nobody reads it, so the payload is dropped — INSIDE the
//    closure, whose IR owns the exit block.
@ closure_tail → i {
    : ( @ v ) f \ → v {
        ?? ( open 9 ) {
            T db → {
                ( nurl_print `closure saw dh-` )
                ( nurl_print ( nurl_str_int . db id ) )
                . db buf
            }
            F _ → { # *u 0 }
        }
    }
    ( f )
    ^ g_drops
}

@ main → i {
    : String a ( mismatch )
    ( nurl_print ( string_data a ) ) ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print `\n` )
    ( string_free a )

    : String b ( agree 2 )
    ( nurl_print ( string_data b ) ) ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print `\n` )
    ( string_free b )

    : String c ( agree -1 )
    ( nurl_print ( string_data c ) ) ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print `\n` )
    ( string_free c )

    : String d ( cond T )
    ( nurl_print ( string_data d ) ) ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print `\n` )
    ( string_free d )

    ( nurl_print `consumed arm dropped ` )
    ( nurl_print ( nurl_str_int ( consumed ) ) )
    ( nurl_print ` (must be 0)\n` )

    : String e ( nested F )
    ( nurl_print ( string_data e ) ) ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print `\n` )
    ( string_free e )

    : String f ( nested2 F )
    ( nurl_print ( string_data f ) ) ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print `\n` )
    ( string_free f )

    : String g ( looped )
    ( nurl_print ( string_data g ) ) ( nurl_print ` drops=` )
    ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print `\n` )
    ( string_free g )

    ( fn_tail_void )
    ( nurl_print `fn tail drops=` )
    ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print `\n` )

    : i h ( closure_tail )
    ( nurl_print ` drops=` ) ( nurl_print ( nurl_str_int h ) ) ( nurl_print `\n` )
    ^ 0
}
