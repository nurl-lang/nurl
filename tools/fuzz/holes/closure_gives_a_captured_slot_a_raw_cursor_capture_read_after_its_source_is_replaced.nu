// closure_gives_a_captured_slot_a_raw_cursor_capture_read_after_its_source_is_replaced: `= dst cur` in a closure, cur a `: ~ s` cursor over src; src replaced, dst read
// Guard (agora #887): a closure leaving a captured slot a view of another capture is refused where it is made, by the walk, the engine and tools/ncore, before the run-site capture-to-capture store is reached (CodeRabbit on github#1924).
// main e659a702 (--no-borrowck): AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | AGORA-887: `= dst cur` in a closure, cur a `: ~ s` cursor over src; src replaced, dst read
$ `stdlib/core/string.nu`
@ main → i {
    : ~ String src ( string_from `a source string long enough for the heap here` )
    : ~ s cur ( string_data src )
    : ~ s dst `x`
    : ( @ v ) f \ → v { = dst cur }
    ( f )
    = src ( string_from `a replacement string long enough for the heap` )
    ( nurl_println dst )
    ^ 0
}
