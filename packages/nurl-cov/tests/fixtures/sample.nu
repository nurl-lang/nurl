// A fixture with hand-checkable coverage.
//
// `classify` is called twice, with 5 and with 0, so every count below can
// be worked out on paper — which is the point: a coverage reader has to be
// checked against numbers a person derived, not against itself.
//
//   line 14  the function is entered twice              → 2
//   line 15  both calls test it; neither is negative    → 2, taken 2 and 0
//   line 16  both reach it; one of them is zero         → 2, taken 1 and 1
//   line 17  only the call with 5 gets this far         → 1, taken 1 and 0
//   line 18  nothing is ever 10 or more                 → 0
//   lines 21-22  nothing calls this at all              → 0
//   lines 25-28  main runs once                         → 1
@ classify i n → s {
    ? < n 0 { ^ `negative` } {}
    ? == n 0 { ^ `zero` } {}
    ? < n 10 { ^ `small` } {}
    ^ `large`
}

@ unused_helper i n → i {
    ^ * n 2
}

@ main → i {
    ( nurl_println ( classify 5 ) )
    ( nurl_println ( classify 0 ) )
    ^ 0
}
