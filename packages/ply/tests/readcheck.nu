// tests/readcheck.nu — read PLYs back for the reader's test.
//
//   readcheck <file.ply>...
//
// Prints, per file, either `<name> n=<n> col=<0|1> sum=<x+y+z over all>
// rgb=<r+g+b over all> first=<x,y,z>` or `<name> refused: <message>`, so
// the shell can compare with what an independent parser reads.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `src/read.nu`

@ main → i {
    : ~ i k 1
    ~ < k ( nurl_argc ) {
        : s path ( nurl_argv k )
        ( nurl_print path )
        ?? ( ply_read path ) {
            F e → { ( nurl_print ` refused: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) }
            T c → {
                : ( Slice f ) p ( slice_from_vec [f] . c xyz )
                : ~ f sum 0.0
                : ~ i q 0
                ~ < q ( slice_len [f] p ) { = sum + sum ( slice_at [f] p q ) = q + q 1 }
                : ( Slice u ) r ( slice_from_vec [u] . c rgb )
                : ~ i rs 0
                = q 0
                ~ < q ( slice_len [u] r ) { = rs + rs # i ( slice_at [u] r q ) = q + q 1 }
                ( nurl_print ` n=` ) ( nurl_print ( nurl_str_int . c n ) )
                ( nurl_print ` col=` ) ( nurl_print ? ( ply_cloud_has_color c ) `1` `0` )
                ( nurl_print ` sum=` ) ( nurl_print ( nurl_str_float sum ) )
                ( nurl_print ` rgb=` ) ( nurl_print ( nurl_str_int rs ) )
                ? > . c n 0 {
                    ( nurl_print ` first=` ) ( nurl_print ( nurl_str_float ( slice_at [f] p 0 ) ) )
                    ( nurl_print `,` ) ( nurl_print ( nurl_str_float ( slice_at [f] p 1 ) ) )
                    ( nurl_print `,` ) ( nurl_print ( nurl_str_float ( slice_at [f] p 2 ) ) )
                } {}
                ( nurl_print `\n` )
            }
        }
        = k + k 1
    }
    ^ 0
}
