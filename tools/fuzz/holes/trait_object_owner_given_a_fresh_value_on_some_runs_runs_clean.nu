// trait_object_owner_given_a_fresh_value_on_some_runs_runs_clean: agora #459 guard — the same with `( pass o 1 )`: a fresh value, the old one released
// Guard: keys differ, so the old value goes by its flag as before.
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #459 guard: `= o ( pass o 1 )` over a `%Show` owner
$ `stdlib/core/string.nu`

% Show [T] {
    @ len T self → i
}

: V { String p i pad }

% Show V { @ len V v → i { ^ ( string_len . v p ) } }

@ mkd s t → %Show { ^ ( dyn Show @ V { ( string_from t ) 0 } ) }

@ pass %Show d i k → %Show { ? == k 0 { ^ d } {} ^ ( mkd `a fresh dyn string long enough for the heap` ) }

@ main → i {
    : ~ % Show o ( mkd `the owner dyn string long enough for the heap` )
    = o ( pass o 1 )
    ( nurl_println_int ( len o ) )
    ^ 0
}
