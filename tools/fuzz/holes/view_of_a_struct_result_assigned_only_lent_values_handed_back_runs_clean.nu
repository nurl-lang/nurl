// view_of_a_struct_result_assigned_only_lent_values_handed_back_runs_clean: agora #679 — a `: ~` struct binding bound to `vec_at`'s lend and assigned another on one path, handed back; its caller hands back a view of a field
// Control for agora #679: every value the binding is given is a lend or holds nothing, so the function hands over no storage of its own and its caller's view is a view of the argument.
// map: §2.8 | A2 | runs-clean | - | agora #679: a `: ~` struct binding bound to `vec_at`'s lend and assigned another on one path, handed back; its caller hands back a view of a field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) v b own → S {
    : ~ S o ( vec_at [S] v 0 )
    ? own { = o ( vec_at [S] v 0 ) } {}
    ^ o
}

@ f ( Vec S ) v b own → s {
    : S e ( pick v own )
    ^ ( string_data . e name )
}

@ main → i {
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks `a lent string long enough to live on the heap, for sure` ) )
    ( nurl_println ( f v T ) )
    ( nurl_println ( f v F ) )
    ^ 0
}
