// A literal handed to a raw-string parameter: a text of its own.
$ `stdlib/core/string.nu`

@ width s t → i { ^ ( nurl_str_len t ) }

@ main → i { ^ + ( width `abc` ) ( width `de` ) }
