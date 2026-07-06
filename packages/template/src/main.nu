// template — render a template from the command line.
//
//   template -f page.html -c ctx.json          # render with a JSON context
//   template -f page.html                      # empty context
//   echo '{{ msg }}' | template -c ctx.json    # template from stdin
//   template -f page.html -c ctx.json -p views # partials dir for {% include %}
//
// The context file must contain a JSON object; {% include 'name' %}
// resolves against --partials (every *.html in the dir, named by
// basename without the extension).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/args.nu`
$ `stdlib/ext/json.nu`
$ `src/template.nu`
$ `src/loader.nu`

@ main → i {
    : ArgParser p ( args_new `template` `render a template against a JSON context` )
    ( args_flag p `help` 104 `show this help` )  // -h
    ( args_opt p `file` 102 `FILE` `template file (default: stdin)` )  // -f
    ( args_opt p `ctx` 99 `FILE` `JSON context file (default: empty object)` )  // -c
    ( args_opt p `partials` 112 `DIR` `directory of *.html partials for {% include %}` )  // -p

    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i ai 1
    ~ < ai ac {
        ( vec_push [String] argv ( env_arg ai ) )
        = ai + ai 1
    }

    : ~ i rc 0
    ? ( args_parse p argv ) {
        ? ( args_present p `help` ) {
            : String h ( args_usage p )
            ( nurl_print `template — render a template against a JSON context\n\n` )
            ( nurl_print ( string_data h ) )
            ( string_free h )
        } {
            // template source: --file or stdin
            : ~ String tsrc ( string_new )
            : ~ b have T
            ?? ( args_value p `file` ) {
                T fv → {
                    ?? ( read_file ( string_data fv ) ) {
                        T txt → { ( string_free tsrc ) = tsrc txt }
                        F _ → {
                            ( nurl_eprint `template: cannot read file: ` )
                            ( nurl_eprintln ( string_data fv ) )
                            = rc 1
                            = have F
                        }
                    }
                    ( string_free fv )
                }
                F _ → { ( string_free tsrc ) = tsrc ( read_all_stdin ) }
            }

            // context: --ctx JSON file or empty object
            : ~ Json ctx ( json_obj_new )
            ? have {
                ?? ( args_value p `ctx` ) {
                    T cv → {
                        ?? ( read_file ( string_data cv ) ) {
                            T ctxt → {
                                ?? ( json_parse ( string_data ctxt ) ) {
                                    T j → { ( json_free ctx ) = ctx j }
                                    F e → {
                                        : String em ( json_format_error e )
                                        ( nurl_eprint `template: bad JSON context: ` )
                                        ( nurl_eprintln ( string_data em ) )
                                        ( string_free em )
                                        = rc 1
                                        = have F
                                    }
                                }
                                ( string_free ctxt )
                            }
                            F _ → {
                                ( nurl_eprint `template: cannot read context: ` )
                                ( nurl_eprintln ( string_data cv ) )
                                = rc 1
                                = have F
                            }
                        }
                        ( string_free cv )
                    }
                    F _ → {}
                }
            } {}

            // partials set
            : ~ * TplSet t ( tset_new )
            ? have {
                ?? ( args_value p `partials` ) {
                    T pv → {
                        : i n ( tset_load_dir t ( string_data pv ) `.html` )
                        ? < n 0 {
                            ( nurl_eprint `template: cannot read partials dir: ` )
                            ( nurl_eprintln ( string_data pv ) )
                            = rc 1
                            = have F
                        } {}
                        ( string_free pv )
                    }
                    F _ → {}
                }
            } {}

            ? have {
                ?? ( tpl_render_with t ( string_data tsrc ) ctx ) {
                    T outp → {
                        ( nurl_print ( string_data outp ) )
                        ( string_free outp )
                    }
                    F m → {
                        ( nurl_eprint `template: ` )
                        ( nurl_eprintln ( string_data m ) )
                        ( string_free m )
                        = rc 1
                    }
                }
            } {}

            ( tset_free t )
            ( json_free ctx )
            ( string_free tsrc )
        }
    } {
        ( nurl_eprint `template: ` ) ( nurl_eprintln ( args_error p ) )
        ( nurl_eprintln `try 'template --help'` )
        = rc 2
    }

    ( args_free p )
    ( vec_free_with [String] argv \ String x → v { ( string_free x ) } )
    ^ rc
}
