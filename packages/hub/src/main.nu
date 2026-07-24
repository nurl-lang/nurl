// packages/hub/src/main.nu — the `hub` CLI.
//
//   hub pull   <ref>          fetch a file or a whole repo (auto)
//   hub file   <ref>          fetch one file, print its local path
//   hub dir    <ref>          fetch a whole repo, print its directory
//   hub ls                    list what is cached
//   hub path   <ref>          print the cached path (no fetch), else exit 1
//   hub verify <handle>       re-hash every blob against its sha256
//   hub rm     <handle>       forget a model, GC unshared blobs
//
// A ref is org/repo, org/repo/path/file.gguf, org/repo@rev[/path],
// hf.co/… , or an http(s):// URL. The cache is $NURL_MODELS or
// ~/.nurl/models.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `src/hub.nu`
$ `src/hf.nu`

@ __hub_cli_err String e → i {
    ( nurl_eprintln ( string_data e ) )
    ( string_free e )
    ^ 1
}

// pull auto-dispatch: a URL or a subpath ref is a file, else a repo.
@ __hub_pull s ref → i {
    : HubRef r ( hub_ref_parse ref )
    : ~ b isfile F
    ? . r is_url { = isfile T } {}
    ? > ( string_len . r subpath ) 0 { = isfile T } {}
    ( hub_ref_free r )
    ? isfile {
        : !String String pr ( hub_file ref )
        ?? pr {
            T p → { ( nurl_print ( string_data p ) ) ( nurl_print `\n` ) ( string_free p ) ^ 0 }
            F e → { ^ ( __hub_cli_err e ) }
        }
    } {
        : !String String pr ( hub_dir ref )
        ?? pr {
            T p → { ( nurl_print ( string_data p ) ) ( nurl_print `\n` ) ( string_free p ) ^ 0 }
            F e → { ^ ( __hub_cli_err e ) }
        }
    }
}

@ main → i {
    : ArgParser p ( args_new `hub` `Fetch models from Hugging Face into one shared, verified cache (~/.nurl/models).` )
    ( args_flag p `help` 104 `show this help` )
    ( args_flag p `version` 0 `print the version` )

    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  pull <ref>   fetch a file or a whole repo (auto)\n  file <ref>   fetch one file, print its path\n  dir <ref>    fetch a whole repo, print its directory\n  ls           list cached models\n  path <ref>   print the cached path without fetching\n  verify <h>   re-hash every blob against its sha256\n  rm <handle>  forget a model, GC unshared blobs\n\nrefs: org/repo · org/repo/file.gguf · org/repo@rev[/path] · hf.co/… · https://…\ncache: $NURL_MODELS or ~/.nurl/models\n` )
        ( string_free u ) ( args_free p )
        ^ 0
    } {}
    ? ( args_present p `version` ) {
        ( nurl_print `hub 0.1.0\n` )
        ( args_free p )
        ^ 0
    } {}

    ? < ( args_positional_count p ) 1 {
        ( nurl_eprintln `usage: hub <pull|file|dir|ls|path|verify|rm> … (hub --help)` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd ( string_data c ) } F → {} }
    : ~ String a1 ( string_new )
    ? >= ( args_positional_count p ) 2 {
        ?? ( vec_get [String] pos 1 ) { T v → { ( string_free a1 ) = a1 ( string_from ( string_data v ) ) } F → {} }
    } {}

    : ~ i rc 0
    ? ( nurl_str_eq cmd `ls` ) {
        ( hub_ls )
    } {
        ? ( nurl_str_eq cmd `pull` ) {
            = rc ( __hub_pull ( string_data a1 ) )
        } {
            ? ( nurl_str_eq cmd `file` ) {
                : !String String pr ( hub_file ( string_data a1 ) )
                ?? pr { T pp → { ( nurl_print ( string_data pp ) ) ( nurl_print `\n` ) ( string_free pp ) } F e → { = rc ( __hub_cli_err e ) } }
            } {
                ? ( nurl_str_eq cmd `dir` ) {
                    : !String String pr ( hub_dir ( string_data a1 ) )
                    ?? pr { T pp → { ( nurl_print ( string_data pp ) ) ( nurl_print `\n` ) ( string_free pp ) } F e → { = rc ( __hub_cli_err e ) } }
                } {
                    ? ( nurl_str_eq cmd `path` ) {
                        ?? ( hub_path ( string_data a1 ) ) {
                            T pp → { ( nurl_print ( string_data pp ) ) ( nurl_print `\n` ) ( string_free pp ) }
                            F → { ( nurl_eprintln `hub: not cached` ) = rc 1 }
                        }
                    } {
                        ? ( nurl_str_eq cmd `verify` ) {
                            : !v String vr ( hub_verify ( string_data a1 ) )
                            ?? vr { T _ → { ( nurl_print `ok\n` ) } F e → { = rc ( __hub_cli_err e ) } }
                        } {
                            ? ( nurl_str_eq cmd `rm` ) {
                                : !v String rr ( hub_rm ( string_data a1 ) )
                                ?? rr { T _ → { ( nurl_print `removed\n` ) } F e → { = rc ( __hub_cli_err e ) } }
                            } {
                                : String m ( string_from `hub: unknown command '` )
                                ( string_push_str m cmd )
                                ( string_push_str m `' (hub --help)` )
                                ( nurl_eprintln ( string_data m ) )
                                ( string_free m )
                                = rc 2
                            } } } } } } }

    ( string_free a1 )
    ( args_free p )
    ^ rc
}
