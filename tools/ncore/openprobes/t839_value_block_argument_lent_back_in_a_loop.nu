// map: §2.10 | A2 | rejected | - | agora #839: `= b ( id { : String t ( mk k ) t } )` in a loop
$ `stdlib/core/string.nu`

@ mk i k → String { ^ ( string_from `a heap string long enough to be on the heap for sure` ) }

@ id String x → String { ^ x }

@ main → i {
    : ~ String b ( string_from `start` )
    : ~ i k 0
    ~ < k 3 {
        = b ( id { : String t ( mk k ) t } )
        = k + k 1
    }
    ( nurl_println ( string_data b ) )
    ^ 0
}
