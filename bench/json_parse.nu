// json_parse — parse bench/data.json 20 times, print parses-OK count.
// Uses NURL's stdlib JSON parser (stdlib/ext/json.nu).
$ `stdlib/ext/json.nu`

@ main → i {
    : s src ( nurl_read_file `bench/data.json` )
    : ~ i iters 20
    : ~ i ok 0
    ~ > iters 0 {
        : !Json JsonError r ( json_parse src )
        ?? r {
            T j → { = ok + ok 1 ( json_free j ) }
            F e → {}
        }
        = iters - iters 1
    }
    ( nurl_println_int ok )
    ^ 0
}
