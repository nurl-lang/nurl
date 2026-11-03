// trait_object_owner_given_back_its_own_value_on_some_runs: agora #459 — `= o ( pass o 0 )`, `pass` handing back its `%Show` parameter on one run and a fresh one on another
// Closed: a trait-object owner given a call that may lend its own value is told it by its box at run time (mem_dyn_key), as a String by its buffer: given its own value back it keeps it; given another, the old one goes (agora #459).
// main: heap-use-after-free (base bc5f5fe0).
// map: §7.6 | A2 | runs-clean | - | agora #459: `= o ( pass o 0 )` over a `%Show` owner
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
    = o ( pass o 0 )
    ( nurl_println_int ( len o ) )
    ^ 0
}
