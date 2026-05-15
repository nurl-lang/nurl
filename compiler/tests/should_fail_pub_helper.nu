// should_fail_pub_helper.nu — helper module consumed by
// pub_visibility.nu. The `pub` on `pub_greet` flips this file into
// grammar v2.0 strict-visibility mode, which means any unmarked
// @-function (here `__priv_greet`) becomes private to this file.
//
// On its own this module has no main so it COMPILE OK + LINK FAIL —
// the runner's snapshot captures that state.

pub @ pub_greet → v {
    ( nurl_print `hello from pub\n` )
}

@ __priv_greet → v {
    ( nurl_print `hello from priv\n` )
}

// In-file private call: still allowed because callee and caller share
// the same source file. Exercises that the visibility check fires only
// across files, not within a single module.
pub @ pub_calls_priv → v {
    ( __priv_greet )
}
