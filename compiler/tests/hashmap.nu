// HashMap runtime test — string keys, int values

@ main → i {
    ( nurl_print `HashMap test...\n` )

    // Create
    : i m ( nurl_map_new )

    // Put
    ( nurl_map_put m `alice` 42 )
    ( nurl_map_put m `bob` 17 )
    ( nurl_map_put m `charlie` 99 )

    // Get
    ( nurl_print `alice: ` )
    ( nurl_print ( nurl_str_int ( nurl_map_get m `alice` ) ) )
    ( nurl_print `\n` )

    ( nurl_print `bob: ` )
    ( nurl_print ( nurl_str_int ( nurl_map_get m `bob` ) ) )
    ( nurl_print `\n` )

    // Size
    ( nurl_print `size: ` )
    ( nurl_print ( nurl_str_int ( nurl_map_size m ) ) )
    ( nurl_print `\n` )

    // Has
    ( nurl_print `has alice: ` )
    ( nurl_print ? != 0 ( nurl_map_has m `alice` ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `has dave: ` )
    ( nurl_print ? != 0 ( nurl_map_has m `dave` ) `yes` `no` )
    ( nurl_print `\n` )

    // Overwrite
    ( nurl_map_put m `alice` 100 )
    ( nurl_print `alice after update: ` )
    ( nurl_print ( nurl_str_int ( nurl_map_get m `alice` ) ) )
    ( nurl_print `\n` )

    // Delete
    ( nurl_map_del m `bob` )
    ( nurl_print `has bob after del: ` )
    ( nurl_print ? != 0 ( nurl_map_has m `bob` ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `size after del: ` )
    ( nurl_print ( nurl_str_int ( nurl_map_size m ) ) )
    ( nurl_print `\n` )

    // Cleanup
    ( nurl_map_free m )

    ( nurl_print `done\n` )
    ^ 0
}