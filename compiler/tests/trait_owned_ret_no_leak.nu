// trait_owned_ret_no_leak.nu
// Regression: a trait method that returns an OWNED string (`s` from
// nurl_str_cat), whose result is passed straight to another call rather than
// bound to a local, must have that temporary auto-freed — exactly as a plain
// function's owned-string result already is. The impl-method dispatch path used
// to skip publishing the callee's `__ret_owned` marker, so the temp leaked.
//
// Proven deterministically WITHOUT a sanitizer via nurl_free_count(): each of
// the 100 iterations produces one owned-string temp (nurl_str_cat mallocs
// directly, so it is NOT visible to nurl_alloc_count — the free count is the
// signal), and the temp must be freed after the call it is passed to. So the
// free count grows by exactly 100 across the loop. Before the fix the impl-
// method dispatch never marked the result owned, the temp was never freed, and
// the delta was 0.
$ `stdlib/core/string.nu`

& `libc` @ nurl_free_count → i

%Name [T] { @ label T self → s }

: Dog { i id }

% Name Dog { @ label Dog d → s { ^ ( nurl_str_cat `dog-` `rex` ) } }

@ sink_s s x → i { ^ 0 }  // consumes the owned-string temp, does nothing else

@ main → i {
    : Dog d @ Dog { 1 }
    : i f0 ( nurl_free_count )
    : ~ i i 0
    ~ < i 100 {
        ( sink_s ( label d ) )  // label → owned s; must be freed after the call
        = i + i 1
    }
    : i freed - ( nurl_free_count ) f0
    ( nurl_print ? == freed 100 `no leak\n` `LEAK\n` )
    ^ ? == freed 100 0 1
}
