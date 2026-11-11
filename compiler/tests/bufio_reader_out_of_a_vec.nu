// Test: a BufReader kept in a Vec is read through each way an element is reached.
//
// A reader's buffer and position sit in one rcbox its handle shares, so a
// handle read out of a container — bound, passed straight on, matched out of
// an option, or walked — is the same reader, and reading a line through it
// moves the one position: four reads, four consecutive lines.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bufio.nu`
$ `stdlib/std/fs.nu`

@ show String line → v {
    ( nurl_print `[` )
    ( nurl_print ( string_data line ) )
    ( nurl_print `]\n` )
}

@ main → i {
    : s path `bufio_reader_out_of_a_vec_fixture.txt`
    ( write_file path `alpha\nbeta\ngamma\ndelta\nomega\n` )
    : ( Vec BufReader ) rs ( vec_new [BufReader] )
    ?? ( bufreader_open path ) {
        T opened → { ( vec_push [BufReader] rs opened ) }
        F e → { ( nurl_print `open failed\n` ) }
    }
    ? == ( vec_len [BufReader] rs ) 0 { ^ 1 } {}
    : String line ( string_new )

    // bound, then read through
    : BufReader br ( vec_at [BufReader] rs 0 )
    ? ( bufreader_read_line_into br line ) { ( show line ) } {}

    // passed straight on
    ? ( bufreader_read_line_into ( vec_at [BufReader] rs 0 ) line ) { ( show line ) } {}

    // an option bound, then matched
    : ?BufReader ob ( vec_get [BufReader] rs 0 )
    ?? ob {
        T r → { ? ( bufreader_read_line_into r line ) { ( show line ) } {} }
        F → {}
    }

    // walked
    ~ r rs { ? ( bufreader_read_line_into r line ) { ( show line ) } {} }

    ( file_delete path )
    ( nurl_print `done\n` )
    ^ 0
}
