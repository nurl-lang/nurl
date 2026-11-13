// map: §2.13 | A2 | rejected | - | agora #847: `: s e { : s t ( nurl_str_cat … ) : s w t  w }  ^ e`
$ `stdlib/core/string.nu`

@ f → s {
    : s e { : s t ( nurl_str_cat `a heap string long enough to be on the heap ` `for sure, and then some` ) : s w t w }
    ^ e
}

@ main → i { : s r ( f ) ( nurl_println r ) ^ 0 }
