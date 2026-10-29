// drop_join_returned_ok.nu — a `% Drop` value that cannot be copied,
// handed back through a `?` / `??` join, runs its drop exactly once
// (agora #186). A join that lends a parameter on one path and makes a
// fresh value on another answers per call whether the caller owns it;
// a local the join selects moves out on that path, as `^ l` moves it; a
// closure body's join of fresh values hands them over without a copy.
$ `stdlib/core/string.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_print `drop ` ) ( nurl_println_int . d n ) } }

@ mk i n → D { ^ @ D { ( string_from `a string long enough for a heap buffer` ) n } }

// A parameter on one path, a fresh value on the other.
@ pick D d b c → D { ^ ? c d ( mk 2 ) }

@ pickm D d ? i o → D { ^ ?? o { T x → d F → ( mk 3 ) } }

@ pickf D d b c → D { ? c d ( mk 4 ) }

// A local the join selects.
@ pickl b c → D {
    : D l ( mk 5 )
    ^ ? c l ( mk 6 )
}

@ pickpl D x b c → D {
    : D l ( mk 7 )
    ^ ? c x l
}

@ pickpo ? D xo b c → ?D {
    : ?D lo @ ?D { T ( mk 8 ) }
    ^ ? c xo lo
}

@ main → i {
    : D d ( mk 1 )
    { : D r ( pick d F ) ( nurl_println `-- pick fresh` ) }
    { : D r ( pick d T ) ( nurl_println `-- pick lent` ) }
    { : D r ( pickm d @ ?i { F } ) ( nurl_println `-- match fresh` ) }
    { : D r ( pickm d @ ?i { T 0 } ) ( nurl_println `-- match lent` ) }
    { : D r ( pickf d F ) ( nurl_println `-- fall-off fresh` ) }
    { : D r ( pickf d T ) ( nurl_println `-- fall-off lent` ) }
    { : D r ( pickl T ) ( nurl_println `-- local moved` ) }
    { : D r ( pickl F ) ( nurl_println `-- local dropped` ) }
    { : D r ( pickpl d T ) ( nurl_println `-- parameter lent` ) }
    { : D r ( pickpl d F ) ( nurl_println `-- local moved` ) }
    : ?D o @ ?D { T ( mk 9 ) }
    { : ?D r ( pickpo o T ) ( nurl_println `-- option lent` ) }
    { : ?D r ( pickpo o F ) ( nurl_println `-- option moved` ) }
    : ( @ D b ) f \ b c → D { ? c ( mk 10 ) ( mk 11 ) }
    { : D r ( f T ) ( nurl_println `-- closure first` ) }
    { : D r ( f F ) ( nurl_println `-- closure second` ) }
    ( nurl_println_int + ( string_len . d s ) . d n )
    ^ 0
}
