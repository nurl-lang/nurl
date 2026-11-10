// nested_field_given_a_view_of_an_older_source_runs_clean: the control: a nested store of a view whose source outlives h stays accepted.
// Closed: a nested field store walks the root binding's own storage, so it keeps the view it stores in that binding (`__field_store_nested__`, the `=.` vpass row) as the one-level store does (agora #348).
// main b997834b: runs clean.
// map: §2.12 | A2 | runs-clean | - | agora #348: a nested field store of a view records the holder's dependency on the source
$ `stdlib/core/string.nu`

: V { s v }
: H { V w }

@ main → i {
    : String b ( string_from `a string that outlives h` )
    : ~ H h @ H { @ V { `a literal` } }
    = . . h w v ( string_data b )
    ( nurl_println . . h w v )
    ^ 0
}
