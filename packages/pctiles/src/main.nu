// packages/pctiles/src/main.nu — `pctiles build cloud.ply -o dir`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `deps/ply/src/read.nu`
$ `pctiles.nu`

@ __usage → i {
    ( nurl_print `pctiles — a point cloud as an OGC 3D Tiles tileset (level of detail, streamed)\n\n` )
    ( nurl_print `usage: pctiles build <cloud.ply> -o <dir> [options]\n\n` )
    ( nurl_print `  -o, --out <dir>     where tileset.json and the tiles go (created)\n` )
    ( nurl_print `  --up -y|+y|+z       the cloud's up axis (default -y: OpenCV, what reconstructions write)\n` )
    ( nurl_print `  --capacity <n>      points a leaf may hold (default 60000)\n` )
    ( nurl_print `  --grid <n>          a node's sampling grid, n x n x n cells (default 64)\n` )
    ( nurl_print `  --seed <n>          the sample's shuffle (default 1; the same seed, the same tiles)\n` )
    ( nurl_print `  -q, --quiet         no progress\n` )
    ( nurl_print `  --version, --help\n` )
    ^ 2
}

@ __eq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

@ main → i {
    : i argc ( nurl_argc )
    ? < argc 2 { ^ ( __usage ) } {}
    : s cmd ( nurl_argv 1 )
    ? | ( __eq cmd `--help` ) ( __eq cmd `-h` ) { : i _u ( __usage ) ^ 0 } {}
    ? ( __eq cmd `--version` ) { ( nurl_print `pctiles ` ) ( nurl_print ( pkg_version ) ) ( nurl_print `\n` ) ^ 0 } {}
    ? ( __eq cmd `build` ) {} {
        ( nurl_print `pctiles: unknown command ` ) ( nurl_print cmd ) ( nurl_print `\n` )
        ^ ( __usage )
    }
    : ~ s input ``
    : ~ s out ``
    : ~ i up PCT_UP_NEG_Y
    : ~ i cap 60000
    : ~ i grid 64
    : ~ i seed 1
    : ~ i verbose 1
    : ~ i k 2
    ~ < k argc {
        : s a ( nurl_argv k )
        : b valued | | | | | ( __eq a `-o` ) ( __eq a `--out` ) ( __eq a `--up` ) ( __eq a `--capacity` ) ( __eq a `--grid` ) ( __eq a `--seed` )
        ? & valued >= + k 1 argc {
            ( nurl_print `pctiles: ` ) ( nurl_print a ) ( nurl_print ` needs a value\n` )
            ^ 2
        } {}
        ? valued {
            : s v ( nurl_argv + k 1 )
            ? | ( __eq a `-o` ) ( __eq a `--out` ) { = out v } {}
            ? ( __eq a `--up` ) {
                ? ( __eq v `-y` ) { = up PCT_UP_NEG_Y } {
                    ? ( __eq v `+y` ) { = up PCT_UP_POS_Y } {
                        ? ( __eq v `+z` ) { = up PCT_UP_POS_Z } {
                            ( nurl_print `pctiles: --up is -y, +y or +z\n` )
                            ^ 2
                        }
                    }
                }
            } {}
            ? ( __eq a `--capacity` ) { = cap ( nurl_str_to_int v ) } {}
            ? ( __eq a `--grid` ) { = grid ( nurl_str_to_int v ) } {}
            ? ( __eq a `--seed` ) { = seed ( nurl_str_to_int v ) } {}
            = k + k 2
        } {
            ? | ( __eq a `-q` ) ( __eq a `--quiet` ) { = verbose 0 } {
                ? > ( nurl_str_len input ) 0 {
                    ( nurl_print `pctiles: one cloud at a time (` ) ( nurl_print a ) ( nurl_print `)\n` )
                    ^ 2
                } {}
                = input a
            }
            = k + k 1
        }
    }
    ? | == ( nurl_str_len input ) 0 == ( nurl_str_len out ) 0 { ^ ( __usage ) } {}
    ? | | < cap 1 < grid 2 > grid 1024 {
        ( nurl_print `pctiles: --capacity is at least 1, --grid 2..1024\n` )
        ^ 2
    } {}
    ?? ( ply_read input ) {
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 1 }
        T c → {
            ? != verbose 0 {
                ( nurl_print `cloud  ` ) ( nurl_print ( nurl_str_int . c n ) ) ( nurl_print ` points` )
                ( nurl_print ? ( ply_cloud_has_color c ) `, coloured\n` `\n` )
            } {}
            ?? ( pct_build ( slice_from_vec [f] . c xyz ) ( slice_from_vec [u] . c rgb ) up cap grid seed out verbose ) {
                F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 1 }
                T st → {
                    ( nurl_print `wrote  ` ) ( nurl_print ( nurl_str_int . st tiles ) ) ( nurl_print ` tiles, ` )
                    ( nurl_print ( nurl_str_int + . st depth 1 ) ) ( nurl_print ` levels, ` )
                    ( nurl_print ( nurl_str_int . st points ) ) ( nurl_print ` points (largest tile ` )
                    ( nurl_print ( nurl_str_int . st largest ) ) ( nurl_print `)` )
                    ? > . st dropped 0 { ( nurl_print `, ` ) ( nurl_print ( nurl_str_int . st dropped ) ) ( nurl_print ` not finite, left out` ) } {}
                    ( nurl_print ` in ` ) ( nurl_print ( nurl_str_int . st ms ) ) ( nurl_print ` ms → ` ) ( nurl_print out ) ( nurl_print `/tileset.json\n` )
                    ^ 0
                }
            }
        }
    }
}
