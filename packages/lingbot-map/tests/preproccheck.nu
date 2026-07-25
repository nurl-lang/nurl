// preproccheck.nu — run pp_load over the fixture frames and print the
// resulting tensor's shape and a checksum-free full dump of a stride of
// its values, in the format tests/preproc_oracle.py emits from the
// reference `load_and_preprocess_images` pipeline.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `src/preproc.nu`

: i SIZE 518
: i PATCH 14

// Every 997th element — a prime stride, so the sample walks all three
// planes and both axes rather than landing on one row forever. A wrong
// crop offset or a transposed plane shows up immediately; a full dump
// would be 800k numbers per frame.
: i STRIDE 997

@ dump_one s path → v {
    : !*Frame String r ( pp_load path SIZE PATCH )
    ?? r {
        F e → {
            ( nurl_print `ERR ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
        }
        T fr → {
            : i w ( pp_width fr )
            : i h ( pp_height fr )
            : i n * 3 * w h
            ( nurl_print `frame ` ) ( nurl_print path )
            ( nurl_print ` ` ) ( nurl_print ( nurl_str_int w ) )
            ( nurl_print `x` ) ( nurl_print ( nurl_str_int h ) )
            : *f d ( pp_data fr )
            : ~ i j 0
            ~ < j n {
                ( nurl_print ` ` )
                ( nurl_print ( nurl_str_float . d j ) )
                = j + j STRIDE
            }
            ( nurl_print `\n` )
            ( pp_free fr )
        }
    }
}

@ main → i {
    : i argc ( nurl_argc )
    ? < argc 2 { ( nurl_print `usage: preproccheck <frame> [frame...]\n` ) ^ 2 } {}
    : ~ i a 1
    ~ < a argc { ( dump_one ( nurl_argv a ) ) = a + a 1 }
    ^ 0
}
