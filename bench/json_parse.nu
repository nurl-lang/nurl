// json_parse — parse bench/data.json 20 times, print parses-OK count.
// Uses NURL's stdlib JSON parser (stdlib/ext/json.nu).
$ `stdlib/ext/json.nu`

@ main → i {
    // The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : s src ( nurl_read_file `bench/data.json` )
    : ~ i iters * 20 # i BENCH_SCALE
    : ~ i ok 0
    ~ > iters 0 {
        : !Json JsonError r ( json_parse src )
        ?? r {
            T j → { = ok + ok 1 }
            F e → {}
        }
        = iters - iters 1
    }
    ( nurl_println_int ok )
    ^ 0
}
