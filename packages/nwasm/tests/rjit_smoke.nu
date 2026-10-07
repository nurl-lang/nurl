// rjit_smoke — tier 8 (src/rjit.nu) compiles a hand-built record stream:
// fn(i64 a, i64 b) → i64 { return a + b }. Nothing runs: this pins the
// analysis and the encoder end to end without an Interp, so a compile
// failure shows up here before it hides behind a silent fall-back to the
// template tier. Exit status 1 on failure, 0 on success.
$ `../src/rjit.nu`

@ main → i {
    // slots: 0 a, 1 b, 2 the pool's zero, 3 the stack
    : ( Vec i ) code ( vec_new [i] )
    ( vec_push [i] code 0 ) ( vec_push [i] code 3 ) ( vec_push [i] code 0 ) ( vec_push [i] code 1 ) ( vec_push [i] code 0 ) ( vec_push [i] code 0 )  // i64.add s3 = s0 + s1
    ( vec_push [i] code 55 ) ( vec_push [i] code 3 ) ( vec_push [i] code 1 ) ( vec_push [i] code 0 ) ( vec_push [i] code 0 ) ( vec_push [i] code 0 )  // RET s3, 1
    : ( Vec i ) aux ( vec_new [i] )
    : ( Vec i ) kv ( vec_new [i] )
    ( vec_push [i] kv 0 )
    : ( Vec i ) lt ( vec_new [i] )
    ( vec_push [i] lt 1 ) ( vec_push [i] lt 1 )
    : ( Vec i ) rsig ( vec_new [i] )
    ( vec_push [i] rsig -1 ) ( vec_push [i] rsig -1 )
    : Rj c ( rj_new code aux kv lt 2 2 4 2 1 3 )
    : b ok ( rj_compile c rsig 0 0 0 0 0 0 )
    ? ! ok {
        ( nurl_print `rjit_smoke: compile failed, reason ` ) ( nurl_println_int ( rj_get c ( rjs_fail ) ) )
        ^ 1
    } {}
    // both params and the sum in registers: no frame traffic beyond the
    // result write — the body is under 80 bytes before the stubs
    ? < ( vec_at [i] . c lab 2 ) 80 {} {
        ( nurl_print `rjit_smoke: body grew to ` ) ( nurl_println_int ( vec_at [i] . c lab 2 ) )
        ^ 1
    }
    ^ 0
}
