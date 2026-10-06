// owned_params_and_arm_tails.nu — values owned through an option parameter
// or a block arm's tail are released exactly once.
//
// Before, in turn (main leaked every one of these):
//   - a `sink ?String` parameter was never dropped: the literal option type
//     has no drop of its own (bindings register under the `%__opt.<T>`
//     twin; parameters did not);
//   - returning its payload (`?? o { T v → { ^ v } … }`) was taken for a
//     lend of the parameter, so the caller did not own the result;
//   - a `??` / `?` arm written as a block ending in a literal
//     (`T x → { … @ !S E { T s } }`) yielded a borrow: only an arm that IS
//     a literal was counted as owned;
//   - opt_unwrap_or borrowed both arguments, so the caller's default leaked
//     whenever the option was present (it now consumes both);
//   - a `% Drop` impl's one-field struct never ran its drop glue (no slot).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: | E { Bad }

: P { String a i n }

: One { ( Vec i ) v }

% Drop One { @ drop One x → v {} }

@ eat sink ? String o → i { ^ 1 }

@ pick_join sink ? String o sink String d → String { ^ ?? o { T v → v F → d } }

@ pick_ret sink ? String o sink String d → String {
    ?? o { T v → { ^ v } F → {} }
    ^ d
}

@ seed i k → !i E {
    ? < k 0 { ^ @ !i E { F @ E { Bad } } } {}
    ^ @ !i E { T k }
}

@ block_arm i k → !P E {
    : !i E r ( seed k )
    : !P E out ?? r {
        T x → {
            : String s ( string_from `block` )
            @ !P E { T @ P { s x } }
        }
        F e → @ !P E { F e }
    }
    ^ out
}

@ ternary_arm b c → P {
    : P p ? c { : i d 1 @ P { ( string_from `x` ) d } } { @ P { ( string_from `y` ) 2 } }
    ^ p
}

@ some → ?String { ^ @ ?String { T ( string_from `some` ) } }

@ round → i {
    : ~ i acc 0
    = acc + acc ( eat ( some ) )
    : ?String o ( some )
    = acc + acc ( eat o )
    : String a ( pick_join ( some ) ( string_from `d` ) )
    : String b ( pick_ret ( some ) ( string_from `d` ) )
    : String c ( pick_ret @ ?String { F # String 0 } ( string_from `dflt` ) )
    = acc + acc + ( string_len a ) + ( string_len b ) ( string_len c )
    ?? ( block_arm 3 ) { T p → { = acc + acc . p n } F e → {} }
    : P t ( ternary_arm T )
    = acc + acc . t n
    : ( Vec i ) w ( opt_unwrap_or [( Vec i )] @ ?( Vec i ) { T ( vec_new [i] ) } ( vec_new [i] ) )
    = acc + acc ( vec_len [i] w )
    : One one @ One { ( vec_new [i] ) }
    ( vec_push [i] . one v 5 )
    ^ acc
}

@ main → i {
    : i first ( round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 30 { ( round ) = k + k 1 }
    : i l1 ( live )
    // 1 + 1 + 4 + 4 + 4 + 3 + 1
    ( nurl_println ( nurl_str_cat `sum ` ( nurl_str_int first ) ) )
    ( nurl_println ? == l0 l1 `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l1 l0 ) ) )
    ^ 0
}
