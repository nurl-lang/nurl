// MVP3 string operations — trim/to_lower/to_upper/repeat/reverse/replace
$ `stdlib/core/string.nu`

@ show String s → v {
  ( nurl_print ( string_data s ) )
  ( nurl_print `\n` )
}

@ main → i {
  : String src ( string_from `Hello, World` )
  : String lo ( string_to_lower src )
  : String up ( string_to_upper src )
  ( show lo )
  ( show up )

  : String rev ( string_reverse ( string_from `abcde` ) )
  ( show rev )

  : String ab ( string_from `ab` )
  : String rep ( string_repeat ab 4 )
  ( show rep )

  : String padded ( string_from `  \t  trim me  \n ` )
  : String tstart ( string_trim_start padded )
  : String tend ( string_trim_end padded )
  : String tboth ( string_trim padded )
  ( nurl_print `[` ) ( nurl_print ( string_data tstart ) ) ( nurl_print `]\n` )
  ( nurl_print `[` ) ( nurl_print ( string_data tend ) ) ( nurl_print `]\n` )
  ( nurl_print `[` ) ( nurl_print ( string_data tboth ) ) ( nurl_print `]\n` )

  : String sentence ( string_from `the quick brown fox jumps over the lazy dog` )
  : String replaced ( string_replace sentence `the` `THE` )
  ( show replaced )

  : String noisy ( string_from `a.b.c.d` )
  : String dots ( string_replace noisy `.` `--` )
  ( show dots )

  : String same ( string_replace ( string_from `xyz` ) `` `Q` )
  ( show same )

  ( nurl_print `done\n` )
  ^ 0
}
