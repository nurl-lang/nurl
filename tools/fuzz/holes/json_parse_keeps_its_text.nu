// json_parse_keeps_its_text: a raw-pointer parameter was summarised as keeping what it was handed — json_parse_n's text, stored in its scratch parser — so json_parse kept its text, and every temporary handed to it leaked.
// map: §6.4 | B | runs-clean | h109 | raw-pointer stdlib param summarised as keeping text; temporaries leak
$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`

@ main → i {
    ?? ( json_parse ( nurl_str_cat `{"a":` `1}` ) ) {
        T j → { ( nurl_println `parsed` ) }
        F _ → { ( nurl_println `bad` ) }
    }
    ^ 0
}
