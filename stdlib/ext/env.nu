// stdlib/ext/env.nu — process environment + argv + cwd
//
// CLI tooling primitives. Each owned String must be freed by the caller
// (auto-drop runs at scope exit, vec_free_with for env_args_list).
//
//   ( env_args_count )       → i              like argc
//   ( env_arg i )            → String         argv[i]; empty when out of range
//   ( env_args_list )        → ( Vec String ) all argv copied into owned Strings
//   ( env_get name )         → ? String       None when unset
//   ( env_var_or name def )  → String         convenience: get-or-default
//   ( env_set name value )   → ! v IoErr      Other on failure
//   ( env_unset name )       → ! v IoErr
//   ( env_cwd )              → ! String IoErr current working directory
//   ( env_chdir path )       → ! v IoErr      change cwd
//   ( env_exit code )        → v              terminate process

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`

@ env_args_count → i {
  ^ ( nurl_argv_count )
}

@ env_arg i idx → String {
  : s raw ( nurl_argv_get idx )
  : String out ( string_from raw )
  ^ out
}

@ env_args_list → ( Vec String ) {
  : ( Vec String ) out ( vec_new [String] )
  : i n ( nurl_argv_count )
  : ~ i i 0
  ~ < i n {
    : s raw ( nurl_argv_get i )
    ( vec_push [String] out ( string_from raw ) )
    = i + i 1
  }
  ^ out
}

@ env_get s name → ? String {
  : s raw ( nurl_env_get name )
  : i p # i raw
  ? == p 0 { ^ @ ? String { F # String 0 } } {}
  : String out ( string_from raw )
  ( nurl_free raw )
  ^ @ ? String { T out }
}

@ env_var_or s name s default → String {
  : ? String got ( env_get name )
  ^ ?? got {
    T s → s
    F → ( string_from default )
  }
}

@ env_set s name s value → ! v IoErr {
  : i rc ( nurl_env_set name value )
  ? == rc 0 { ^ @ ! v IoErr { T 0 } } {}
  ^ @ ! v IoErr { F @ IoErr { Other } }
}

@ env_unset s name → ! v IoErr {
  : i rc ( nurl_env_unset name )
  ? == rc 0 { ^ @ ! v IoErr { T 0 } } {}
  ^ @ ! v IoErr { F @ IoErr { Other } }
}

@ env_cwd → ! String IoErr {
  : s raw ( nurl_cwd )
  : i p # i raw
  ? == p 0 {
    ^ @ ! String IoErr { F @ IoErr { Other } }
  } {}
  : String out ( string_from raw )
  ( nurl_free raw )
  ^ @ ! String IoErr { T out }
}

@ env_chdir s path → ! v IoErr {
  : i rc ( nurl_chdir path )
  ? == rc 0 { ^ @ ! v IoErr { T 0 } } {}
  : i k ( nurl_errno_kind )
  ? == k 0 { ^ @ ! v IoErr { F @ IoErr { NotFound } } } {}
  ? == k 1 { ^ @ ! v IoErr { F @ IoErr { PermissionDenied } } } {}
  ^ @ ! v IoErr { F @ IoErr { Other } }
}

@ env_exit i code → v {
  ( nurl_exit code )
}
