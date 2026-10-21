// unsafe_report_surface.nu
// The input of compiler/tests/unsafe_report.sh: one of everything
// `nurlc --unsafe-report` lists — an `unsafe` function, an `unsafe % Send`
// and an `unsafe % Sync` assertion, and a foreign function's `in` / `sync` /
// `nocapture` parameters — beside what it does not (the markers that only
// add checks, a foreign function with no claims, the standard library's
// own assertions). As a test it also runs: the asserted types work.

$ `stdlib/std/rc.nu`
$ `stdlib/core/cell.nu`
$ `stdlib/core/marker.nu`

: Wrapper { ( Rc i ) r }

unsafe % Send Wrapper {}

: Guarded { Cell c }

unsafe % Sync Guarded {}

% NotSend Guarded {}

% Frozen Guarded {}

: Res { s handle }

% Resource Res {}

& `c` @ atoi in s text → i32

& `c` @ memchr nocapture s buf i c i n → s

& `c` @ nurl_atomic_i64_inc sync *u p → i

& `c` @ abs i x → i32

unsafe @ parse_num s text → i {
    ^ # i ( atoi text )
}

@ main → i {
    : Wrapper w @ Wrapper { ( rc_new [i] 7 ) }
    ( puts ( nurl_str_int + ( rc_get [i] . w r ) ( parse_num `35` ) ) )
    ^ 0
}
