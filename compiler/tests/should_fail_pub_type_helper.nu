// should_fail_pub_type_helper.nu — helper module consumed by the
// pub-type negative tests + the positive pub_type_visibility test.
// The first `pub` flips this file into grammar v2.0+ strict mode, so
// any unmarked top-level decl becomes private to this file.

pub : PubPoint {
    i x
    i y
}

: PrivPoint {
    i x
    i y
}

pub : | PubColor {
    Red
    Green
    Blue
}

: | PrivColor {
    Black
    White
}

pub : i PUB_CONST 7
: i PRIV_CONST 13
