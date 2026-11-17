// closure_gives_a_captured_slot_another_capture_on_one_arm_read_after_the_first_source_is_replaced: `? c { = dst other } {}` in a closure, dst viewing x; x replaced, dst read
// Guard (agora #887): a closure leaving a captured slot a view of another capture is refused where it is made, by the walk, the engine and tools/ncore, before the run-site capture-to-capture store is reached (CodeRabbit on github#1924).
// main e659a702 (--no-borrowck): AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | AGORA-887: `? c { = dst other } {}` in a closure, dst viewing x; x replaced, dst read
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String x ( string_from `the first viewed string long enough for heap` )
    : ~ String y ( string_from `the second viewed string long enough for hp` )
    : ~ s dst ( string_data x )
    : ~ s other ( string_data y )
    : i k ( nurl_str_len `z` )
    : ( @ v ) f \ → v { ? == k 2 { = dst other } {} }
    ( f )
    = x ( string_from `a replacement string long enough for the heap` )
    ( nurl_println dst )
    ^ 0
}
