// Test: Phase 2C slice-field auto-drop. A struct literal populated with
// a fresh owned slice — either a slice literal `[ i | ... ]` or a
// slice-returning call — should free the slice's heap buffer when the
// struct binding goes out of scope. As with the sibling string-field
// test we can't observe the free directly from NURL code; this test
// exercises the drop path under ASan-style runs and verifies the
// user-visible length + tag round-trip correctly.

: Bag {
    [i items
    i tag
}

@ build_slice → [i {
    // Bind the slice so Phase 2A can transfer ownership through the return.
    : [i xs [i | 10 20 30]
    ^ xs
}

@ main → i {
    : Bag b @ Bag { [i | 1 2 3 4] 7 }
    ( nurl_print ( nurl_str_int . . b items length ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int . b tag ) ) ( nurl_print `\n` )

    // Slice-returning-call path: build_slice's return value flows into
    // the struct literal's slice field.
    : Bag b2 @ Bag { ( build_slice ) 99 }
    ( nurl_print ( nurl_str_int . . b2 items length ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int . b2 tag ) ) ( nurl_print `\n` )

    ^ 0
}
