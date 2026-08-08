// loop_break_continue.nu — `break` / `continue` (grammar v2.4).
//
// Both terminate the block they appear in and branch: `break` to the
// loop's exit, `continue` to its condition. The cases below pin the
// four things that can go wrong — an off-by-one at the exit, a
// `continue` that skips the wrong side, an inner `break` that escapes
// the OUTER loop, and a jump that walks past a scope's cleanup.
//
// Expected output:
//   break at 5, seen=5
//   odds=5
//   nested hits=6
//   done

$ `stdlib/core/string.nu`

@ main → i {
    // break: stop at 5
    : ~ i i 0
    : ~ i seen 0
    ~ < i 10 {
        ? == i 5 { break } {}
        = seen + seen 1
        = i + i 1
    }
    ( nurl_print `break at 5, seen=` ) ( nurl_print ( nurl_str_int seen ) ) ( nurl_print `\n` )

    // continue: skip evens
    : ~ i j 0
    : ~ i odds 0
    ~ < j 10 {
        = j + j 1
        ? == 0 % - j 1 2 { continue } {}
        = odds + odds 1
    }
    ( nurl_print `odds=` ) ( nurl_print ( nurl_str_int odds ) ) ( nurl_print `\n` )

    // nested: inner break must not leave the outer
    : ~ i a 0
    : ~ i hits 0
    ~ < a 3 {
        : ~ i b 0
        ~ < b 10 { ? == b 2 { break } {} = hits + hits 1 = b + b 1 }
        = a + a 1
    }
    ( nurl_print `nested hits=` ) ( nurl_print ( nurl_str_int hits ) ) ( nurl_print `\n` )

    // a String allocated in the body, then break — must not leak
    : ~ i k 0
    ~ < k 100 {
        : String tmp ( string_from `xyz` )
        ? == k 3 { ( string_free tmp ) break } {}
        ( string_free tmp )
        = k + k 1
    }
    ( nurl_print `done\n` )
    ^ 0
}
