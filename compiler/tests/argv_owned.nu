// Both argv spellings return owned copies, including missing arguments.
// Count frees across lexical scopes so this regression detects leaks even
// without a sanitizer; the env/args wrappers also exercise ownership transfer.
$ `stdlib/ext/env.nu`
$ `stdlib/std/args.nu`

& `c` @ nurl_free_count → i

@ observe s value → i { ^ ( nurl_str_len value ) }

@ exercise b left → v {
    : s program ( nurl_argv_get 0 )
    : s absent ( nurl_argv_get -1 )
    : s choice ? left ( nurl_argv_get 0 ) ( nurl_argv_get -1 )
    : s returned ( forward_arg -1 )
    ( observe ( nurl_argv_get -1 ) )
    ? left { ( observe program ) ( observe choice ) } { ( observe absent ) }
    ( observe returned )
}

@ adopt_choice b adopt → v {
    : s raw ( nurl_argv_get -1 )
    ? adopt {
        : String owned ( string_from_take raw + ( nurl_str_len raw ) 1 )
        ( string_free owned )
    } {}
}

@ adopt_forward b adopt → v {
    : s raw ( nurl_argv_get -1 )
    ? adopt {
        : String owned ( take_forward raw : raw capacity : + ( nurl_str_len raw ) 1 )
        ( string_free owned )
    } {}
}

@ main → i {
    : i before ( nurl_free_count )
    ( exercise T )
    ( exercise F )
    : i dropped - ( nurl_free_count ) before
    : i transfer_before ( nurl_free_count )
    ( adopt_choice T )
    ( adopt_choice F )
    ( adopt_forward T )
    ( adopt_forward F )
    : i transferred - ( nurl_free_count ) transfer_before
    : String missing ( env_arg -1 )
    : ( Vec String ) arguments ( env_args_list )
    : ArgParser parser ( args_new `probe` `argv ownership` )
    ( args_flag parser `flag` 102 `flag` )
    ( args_opt parser `value` 118 `TEXT` `value` )
    : b parsed ( args_parse_argv parser )
    : b wrappers & & == ( string_len missing ) 0
    == ( vec_len [String] arguments ) ( nurl_argv_count ) parsed
    ( args_free parser )
    ( vec_free_with [String] arguments \ String argument → v { ( string_free argument ) } )
    ( string_free missing )
    ( nurl_print ? == dropped 10 `argv_scopes=T\n` `argv_scopes=F\n` )
    ( nurl_print ? == transferred 6 `argv_transfer=T\n` `argv_transfer=F\n` )
    ( nurl_print ? wrappers `argv_wrappers=T\n` `argv_wrappers=F\n` )
    ^ ? & & == dropped 10 == transferred 6 wrappers 0 1
}

@ forward_arg i index → s { ^ ( nurl_argv_get index ) }

@ take_forward s raw i capacity → String { ^ ( string_from_take raw capacity ) }
