// tests/writecheck.nu — drive the writer for the round-trip test.
//
//   writecheck <out.ply> <ascii 0|1>
//
// Writes a deterministic 3-axis cross plus a slab — the same shape the
// serve test shows the viewer — and prints the count `ply_finish`
// patched into the header, so the shell can compare it against what an
// independent parser reads back.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `src/ply.nu`

@ main → i {
    ? < ( nurl_argc ) 3 {
        ( nurl_print `usage: writecheck <out.ply> <ascii 0|1>\n` )
        ^ 2
    } {}
    : s out ( nurl_argv 1 )
    : i ascii ( nurl_str_to_int ( nurl_argv 2 ) )
    ?? ( ply_create out ascii `writecheck` ) {
        F e → {
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
            ^ 1
        }
        T w → {
            // a cross on the three axes, 121 points each …
            : ~ i i0 0
            ~ <= i0 120 {
                : f t / # f - i0 60 60.0
                ( ply_vertex w t 0.0 0.0 255 60 60 )
                ( ply_vertex w 0.0 t 0.0 60 255 60 )
                ( ply_vertex w 0.0 0.0 t 60 60 255 )
                = i0 + i0 1
            }
            // … and a 1200-point slab, so the render has a body
            : ~ i k 0
            ~ < k 1200 {
                : f a * # f k 0.0121
                : f x - / * 0.6 # f % k 40 40.0 0.3
                : f y + 0.25 * 0.1 # f % / k 40 8
                : ~ f fr a
                ~ >= fr 1.0 { = fr - fr 1.0 }
                : f z * 0.4 - fr 0.5
                ( ply_vertex w x y z 200 190 170 )
                = k + k 1
            }
            : i n ( ply_count w )
            ? ( ply_finish w ) {} {
                ( nurl_print `finish failed\n` )
                ^ 1
            }
            ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
            ^ 0
        }
    }
}
