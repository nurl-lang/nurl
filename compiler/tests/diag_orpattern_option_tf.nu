// diag_orpattern_option_tf.nu — 'T | F' written as an or-pattern over an
// option. T and F are the only two arms an option has, so the
// or-pattern IS the wildcard and the message says to write '_'.
$ `stdlib/core/string.nu`

@ main → i {
    : ?i o @ ?i { T 5 }
    : i r ?? o { T | F → 1 }
    ^ r
}
