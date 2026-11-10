// inout_holder_repointed_to_a_join_hidden_behind_a_comment: the helper's
// right-hand side is `@ W { ? F `x` . w v }` with `//` comments holding
// backticks around it. A text scan took it for a literal of literals and
// credited the repoint: a use-after-free (formal's review of #1709). The
// check now lexes the right-hand side: still refused.
// map: §3.3d | A2 | rejected | - | a helper whose repoint hides a join reading its holder behind a comment holding a backtick: the literal check reads the lexer's tokens, not the text (agora #386).
$ `stdlib/core/string.nu`

: W { s v }

@ reset inout W w → i { = w @ W {  //`
        ? F `x` . w v  //`
    } ^ 0 }

@ main → i { : String b ( string_from `heap string long enough to go on the heap xxxxxxxx` ) : ~ W w @ W { ( string_data b ) } ( reset w ) ( string_free b ) ( nurl_println . w v ) ^ 0 }
