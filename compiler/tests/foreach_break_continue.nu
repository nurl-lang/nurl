// foreach_break_continue.nu — `break` / `continue` inside a `~ x xs` body.
//
// docs/spec.md §5.4.1 scopes both to "the innermost enclosing `~` loop body",
// and a foreach IS a `~` loop body — but only the while form published the
// labels `gen_loop_jump` reads, so every foreach rejected both with
//
//     'continue' outside a loop — there is no next iteration.
//
// The reason it was never wired up is real: a while loop can send `continue`
// straight at its check block because the induction variable is the program's
// own binding, while a foreach owns a hidden index whose bump lived in the
// body's fall-through. A `continue` branching at the check block would skip
// the bump and spin forever. The bump now has its own label — the continue
// landing pad — which both the fall-through and every `continue` reach.
//
// Pinned below: continue, break, the two together, drops on both jump paths
// (a `% Drop` value built per iteration must be released exactly once on
// every path out of the body), both nestings against a while loop (the
// innermost loop must win, and the outer one must be restored afterwards),
// and a foreach over a Vec carrier as well as a slice.
//
// Expected output:
//   odds=9
//   mixed=8
//   drops=5
//   fe-in-while=18
//   while-in-fe=24
//   vec=10
//   done

$ `stdlib/core/vec.nu`

: ~ i g_drops 0

: DH { i tag }

% Drop ( DH ) { @ drop DH h → v { = g_drops + g_drops 1 } }

@ main → i {
    : [i xs [i | 1 2 3 4 5 6]

    // continue: skip the evens.
    : ~ i odds 0
    ~ x xs { ? == % x 2 0 { continue } {} = odds + odds x }
    ( nurl_print `odds=` ) ( nurl_print ( nurl_str_int odds ) ) ( nurl_print `\n` )

    // continue and break in one body: skip 2, stop at 5 → 1 + 3 + 4.
    : ~ i mixed 0
    ~ x xs {
        ? == x 2 { continue } {}
        ? == x 5 { break } {}
        = mixed + mixed x
    }
    ( nurl_print `mixed=` ) ( nurl_print ( nurl_str_int mixed ) ) ( nurl_print `\n` )

    // A %Drop value per iteration, released on the continue path (x=3,6),
    // the break path (x=5) and the fall-through (x=1,2,4). The loop runs
    // iterations 1..5, so exactly 5 destructors fire.
    ~ x xs {
        : DH h @ DH { x }
        ? == % x 3 0 { continue } {}
        ? == x 5 { break } {}
    }
    ( nurl_print `drops=` ) ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print `\n` )

    // foreach nested in a while: the inner break leaves only the foreach.
    : ~ i s3 0
    : ~ i a 0
    ~ < a 3 {
        = a + a 1
        ~ x xs { ? > x 2 { break } {} = s3 + s3 * a x }
    }
    ( nurl_print `fe-in-while=` ) ( nurl_print ( nurl_str_int s3 ) ) ( nurl_print `\n` )

    // while nested in a foreach: the inner continue belongs to the while,
    // and the outer foreach's labels are restored for the next iteration.
    : ~ i s4 0
    ~ x xs {
        ? > x 3 { break } {}
        : ~ i b 0
        ~ < b 3 { = b + b 1 ? == b 2 { continue } {} = s4 + s4 * x b }
    }
    ( nurl_print `while-in-fe=` ) ( nurl_print ( nurl_str_int s4 ) ) ( nurl_print `\n` )

    // The Vec carrier reaches the same code path as the slice carrier.
    : ( Vec i ) nums ( vec_iota 0 8 )
    : ~ i s5 0
    ~ y nums { ? > y 4 { break } {} = s5 + s5 y }
    ( vec_free [i] nums )
    ( nurl_print `vec=` ) ( nurl_print ( nurl_str_int s5 ) ) ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
