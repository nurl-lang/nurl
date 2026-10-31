// vec_get_payload_returned: an accessor returning the payload of a `??` over `vec_get` on a parameter's field (`?? ( vec_get . tp vals id ) { T x → x … }`) lent the caller part of its argument, but its summary did not say so: the caller's binding of the result was not tied to the argument, so truncating the argument's Vec afterwards left the binding pointing into freed elements. The direct form (the `vec_get` in the caller) was rejected; through a function it was not (grad's tape accessors, before a tape was a plain value).
// Closed: a `??` payload handed back — by `^ x` in an arm, or as the join's value — lends the parameter its matched call lent from (a field path into it included), resolved against the callee's final summary.
// main's compiler: `t` is read after `cut` freed what it points into.
// map: CallT.summary | A1 | rejected | h270 | accessor returns vec_get payload of arg without lend summary; arg truncated
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Tz { ( Vec f ) data }
: Tp { ( Vec Tz ) vals }

@ tz_empty → Tz { ^ @ Tz { ( vec_new [f] ) } }

@ getv Tp tp i id → Tz { ^ ?? ( vec_get [Tz] . tp vals id ) { T x → x F → ( tz_empty ) } }

@ cut Tp tp → v { : b _t ( vec_truncate [Tz] . tp vals 0 ) }

@ main → i {
    : Tp tp @ Tp { ( vec_new [Tz] ) }
    : ( Vec f ) d ( vec_new [f] )
    ( vec_push [f] d 1.5 )
    ( vec_push [Tz] . tp vals @ Tz { d } )
    : Tz t ( getv tp 0 )
    ( cut tp )
    ( nurl_println_int ( vec_len [f] . t data ) )
    ^ 0
}
