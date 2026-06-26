// Legit (must KEEP compiling): partial init leaves trailing fields zero,
// and integer literals narrow into sized/unsigned fields. Guards against
// the field checks over-tightening.
$ `stdlib/core/string.nu`

: A { i x i y i z }
: P { u r u g u b }

@ main → i {
    : A a @ A { 7 }
    : P p @ P { 255 128 0 }
    ( nurl_print_int + + . a x . a y . a z )
    ( nurl_print_int + + # i . p r # i . p g # i . p b )
    ^ 0
}
