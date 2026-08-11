// diag_select_arm_no_arrow.nu — a select arm with no '→' after the
// channel. The scan runs to end of input looking for one, so the
// message carries the whole arm shape rather than pointing at a token.
//
// This site was hiding behind a sibling: it shares its explainer tail
// with two other select-arm messages, and the coverage tool used to
// fingerprint on the LONGEST literal — which was that shared tail. One
// test on any of the three marked all three exercised.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) c ( chan_new [i] )
    ?? { [i] c v {} }
    ^ 0
}
