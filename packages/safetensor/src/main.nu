// packages/safetensor/src/main.nu — the CLI.
//
//   safetensor info <file>            tensor count, data size
//   safetensor tensors <file>         every tensor: name, dtype, shape, offset
//   safetensor verify <file>          parse + re-check every extent
//   safetensor stats <file> <name>    count/min/max/mean of one tensor
//   safetensor export <file> <name> -o out.f32     raw f32 LE
//   safetensor selftest               crafted files: every lie must be caught

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `src/safetensor.nu`
$ `src/selftest.nu`

@ __shape_str StTensor t → String {
    : String s ( string_from `[` )
    : ~ i k 0
    ~ < k . t nd {
        ? > k 0 { ( string_push_char s 32 ) } {}
        ( string_push_int s ? == k 0 . t d0 ? == k 1 . t d1 ? == k 2 . t d2 . t d3 )
        = k + k 1
    }
    ( string_push_char s 93 )
    ^ s
}

@ __cmd_tensors * St st → v {
    : ~ i k 0
    ~ < k ( st_n_tensors st ) {
        ?? ( vec_get [StTensor] . st tensors k ) {
            T t → {
                : String line ( string_from ( string_data . t name ) )
                // pad to a column, but ALWAYS leave at least one space: a name
                // longer than the column would otherwise run into the dtype
                ~ < ( string_len line ) 46 { ( string_push_char line 32 ) }
                ( string_push_char line 32 )
                ( string_push_str line ( st_dtype_name . t dtype ) )
                ( string_push_char line 32 )
                : String sh ( __shape_str t )
                ( string_push_str line ( string_data sh ) )
                ( string_free sh )
                ( string_push_char line 32 )
                ( string_push_int line . t nbytes )
                ( string_push_str line ` B @ ` )
                ( string_push_int line . t offset )
                ( nurl_print ( string_data line ) ) ( nurl_print `\n` )
                ( string_free line )
            }
            F → {}
        }
        = k + k 1
    }
}

@ __cmd_stats * St st s name → i {
    : i idx ( st_find_tensor st name )
    ? < idx 0 {
        ( nurl_eprintln `safetensor: no such tensor` )
        ^ 1
    } {}
    ?? ( st_dequant st idx ) {
        T raw → {
            : i n / ( vec_len [u] raw ) 4
            : *u p ( vec_data [u] raw )
            : ~ f mn 1.0e30
            : ~ f mx -1.0e30
            : ~ f sum 0.0
            : ~ i k 0
            ~ < k n {
                : f v # f ( bits_to_f32 ( _st_u32 p * k 4 ) )
                ? < v mn { = mn v } {}
                ? > v mx { = mx v } {}
                = sum + sum v
                = k + k 1
            }
            : String m ( string_from `n=` )
            ( string_push_int m n )
            ( string_push_str m ` min=` )
            ( string_push_float m mn )
            ( string_push_str m ` max=` )
            ( string_push_float m mx )
            ( string_push_str m ` mean=` )
            ( string_push_float m ? > n 0 / sum # f n 0.0 )
            ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
            ( string_free m )
            ( vec_free [u] raw )
            ^ 0
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
}

@ __cmd_export * St st s name s out → i {
    : i idx ( st_find_tensor st name )
    ? < idx 0 {
        ( nurl_eprintln `safetensor: no such tensor` )
        ^ 1
    } {}
    ?? ( st_dequant st idx ) {
        T raw → {
            : ~ i rc 0
            ?? ( write_file_bytes out raw ) {
                T _ → {}
                F _ → {
                    ( nurl_eprintln `safetensor: cannot write output` )
                    = rc 1
                }
            }
            ( vec_free [u] raw )
            ^ rc
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
}

@ main → i {
    : ArgParser p ( args_new `safetensor` `Read the safetensors tensor container — the parser treats every file as untrusted input.` )
    ( args_opt p `output` 111 `FILE` `for export: write the f32-LE tensor here` )
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
        ( nurl_print `\ncommands:\n  info <file> · tensors <file> · verify <file>\n  stats <file> <name> · export <file> <name> -o out.f32\n  selftest\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    ? ( args_present p `version` ) {
        ( nurl_print `safetensor 0.1.0\n` )
        ( args_free p )
        ^ 0
    } {}
    ? < ( args_positional_count p ) 1 {
        ( nurl_eprintln `usage: safetensor <info|tensors|verify|stats|export|selftest> … (safetensor --help)` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd ( string_data c ) } F → {} }

    ? ( nurl_str_eq cmd `selftest` ) {
        : i rc ( st_selftest )
        ( args_free p )
        ^ rc
    } {}

    ? < ( args_positional_count p ) 2 {
        ( nurl_eprintln `safetensor: this command needs a file argument` )
        ( args_free p )
        ^ 2
    } {}
    : ~ s path ``
    ?? ( vec_get [String] pos 1 ) { T c → { = path ( string_data c ) } F → {} }
    : ~ s name ``
    ? >= ( args_positional_count p ) 3 {
        ?? ( vec_get [String] pos 2 ) { T c → { = name ( string_data c ) } F → {} }
    } {}

    ?? ( st_open path ) {
        T st → {
            : ~ i rc 0
            ? ( nurl_str_eq cmd `info` ) {
                : String m ( string_from `safetensors — ` )
                ( string_push_int m ( st_n_tensors st ) )
                ( string_push_str m ` tensors, data ` )
                ( string_push_int m ( st_data_size st ) )
                ( string_push_str m ` B` )
                ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
                ( string_free m )
            } {}
            ? ( nurl_str_eq cmd `tensors` ) { ( __cmd_tensors st ) } {}
            ? ( nurl_str_eq cmd `verify` ) {
                : String m ( string_from `OK — ` )
                ( string_push_int m ( st_n_tensors st ) )
                ( string_push_str m ` tensors, every extent inside the file` )
                ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
                ( string_free m )
            } {}
            ? ( nurl_str_eq cmd `stats` ) { = rc ( __cmd_stats st name ) } {}
            ? ( nurl_str_eq cmd `export` ) {
                : String o ( args_value_or p `output` `out.f32` )
                = rc ( __cmd_export st name ( string_data o ) )
                ( string_free o )
            } {}
            ( st_close st )
            ( args_free p )
            ^ rc
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ( args_free p )
            ^ 1
        }
    }
}
