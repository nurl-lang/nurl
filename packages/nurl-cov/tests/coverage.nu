// nurl-cov tests — the numbers, against numbers a person derived.
//
// The fixture in tests/fixtures/sample.nu is small enough to work out by
// hand, and its header does exactly that: which lines run, how often, and
// which way each decision went. This test builds it with the compiler's
// coverage instrumentation, runs it, reads the graphs back with the
// package's own reader, and checks every one of those claims.
//
// It also checks the two things a reader can get wrong in ways that still
// look plausible:
//
//   * a line is not the sum of its blocks — a condition and the arms it
//     guards share a line, and adding them reports twice the traffic,
//   * a function nothing calls has to survive to be reported as zero,
//     which is why the build passes --no-dce.
//
// Merging is checked by folding the same object in twice: every count has
// to double, and the found/hit totals must not move.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`
$ `src/gcov.nu`
$ `src/lines.nu`
$ `src/model.nu`
$ `src/lcov.nu`
$ `src/jsonout.nu`
$ `src/runner.nu`

: ~ i g_fail 0
: ~ i g_pass 0

@ ok s name → v {
    ( nurl_print `  PASS ` ) ( nurl_println name )
    = g_pass + g_pass 1
}

@ bad s name s detail → v {
    ( nurl_print `  FAIL ` ) ( nurl_print name ) ( nurl_print `: ` ) ( nurl_println detail )
    = g_fail + g_fail 1
}

@ eq_i s name i got i want → v {
    ? == got want { ( ok name ) ^ v } {}
    : String d ( string_with_cap 64 )
    ( string_push_str d `want ` )
    ( string_push_int d want )
    ( string_push_str d `, got ` )
    ( string_push_int d got )
    ( bad name ( string_data d ) )
    ( string_free d )
}

@ is_true s name b cond → v {
    ? cond { ( ok name ) } { ( bad name `condition did not hold` ) }
}

// Build the fixture with coverage and run it. Returns the notes path, or
// an empty string when the toolchain would not produce one — which is a
// failure, not a skip: a coverage tool that cannot measure has nothing to
// report.
@ build_fixture s work → String {
    : String driver ( runner_driver )
    : String outbin ( string_from work )
    ( string_push_str outbin `/sample` )
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `--coverage` )
    ( vec_push [s] args `--no-dce` )
    ( vec_push [s] args `-O0` )
    ( vec_push [s] args `tests/fixtures/sample.nu` )
    ( vec_push [s] args ( string_data outbin ) )
    : ~ b built F
    ?? ( process_run ( string_data driver ) args `` ) {
        T o → {
            = built ( output_success o )
            ? ! built {
                ( nurl_eprint `build failed: ` )
                ( nurl_eprintln ( output_stderr o ) )
            } {}
            ( output_free o )
        }
        F e → { ( nurl_eprint `driver: ` ) ( nurl_eprintln ( process_err_name e ) ) }
    }
    ( vec_free [s] args )
    ( string_free driver )
    ? ! built { ( string_free outbin ) ^ ( string_new ) } {}

    : ( Vec s ) none ( vec_new [s] )
    ?? ( process_run ( string_data outbin ) none `` ) {
        T o → ( output_free o )
        F _ → {}
    }
    ( vec_free [s] none )
    : String notes ( string_clone outbin )
    ( string_push_str notes `.gcno` )
    ( string_free outbin )
    ^ notes
}

// The index of the fixture's own source among the object's files. A test
// binary carries the stdlib too, so the fixture is one of many.
@ fixture_src * GcovObj o → i {
    : i n ( gcov_file_count o )
    : ~ i i 0
    ~ < i n {
        ? ( ends_with ( gcov_file_path o i ) `tests/fixtures/sample.nu` ) { ^ i } {}
        = i + i 1
    }
    ^ -1
}

@ ends_with s text s suffix → b {
    : i n ( nurl_str_len text )
    : i m ( nurl_str_len suffix )
    ? > m n { ^ F } {}
    : ~ i k 0
    ~ < k m {
        ? != ( nurl_str_at text n + - n m k ) ( nurl_str_at suffix m k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ lt_at * LineTab t i line → i {
    ^ ?? ( vec_get [i] . t count line ) { T x → x F _ → -1 }
}

@ lt_exists * LineTab t i line → b {
    ^ ?? ( vec_get [i] . t exists line ) { T x → != 0 x F _ → F }
}

// Branch rows for one line, in the order the notes numbered them.
@ br_count * LineTab t i line i idx → i {
    : i n / ( vec_len [i] . t br ) LBR_W
    : ~ i seen 0
    : ~ i k 0
    ~ < k n {
        ? == line ?? ( vec_get [i] . t br + * k LBR_W LBR_LINE ) { T x → x F _ → -1 } {
            ? == seen idx {
                ^ ?? ( vec_get [i] . t br + * k LBR_W LBR_COUNT ) { T x → x F _ → -1 }
            } {}
            = seen + seen 1
        } {}
        = k + k 1
    }
    ^ -1
}

@ check_lines * GcovObj o i src → v {
    : *LineTab t ( lines_build o src )

    // The counts the fixture's own header claims.
    ( eq_i `line 14 — classify entered twice` ( lt_at t 14 ) 2 )
    ( eq_i `line 15 — the first test, both calls` ( lt_at t 15 ) 2 )
    ( eq_i `line 16 — the second test, both calls` ( lt_at t 16 ) 2 )
    ( eq_i `line 17 — only the call with 5` ( lt_at t 17 ) 1 )
    ( eq_i `line 18 — never reached` ( lt_at t 18 ) 0 )
    ( eq_i `line 22 — inside a function nothing calls` ( lt_at t 22 ) 0 )
    ( eq_i `line 26 — main runs once` ( lt_at t 26 ) 1 )

    // A line with code that never ran still EXISTS. Reporting it as
    // "no code here" is how a coverage tool hides the gap it is for.
    ( is_true `line 18 exists even though it never ran` ( lt_exists t 18 ) )
    ( is_true `line 22 exists even though it never ran` ( lt_exists t 22 ) )
    ( is_true `line 20 is blank and has no code` ! ( lt_exists t 20 ) )

    // Decisions, in storage order: the "then" arm first.
    ( eq_i `line 15 — never negative, so the taken arm is 2` ( br_count t 15 0 ) 2 )
    ( eq_i `line 15 — and the other arm 0` ( br_count t 15 1 ) 0 )
    ( eq_i `line 16 — one of the two is zero` ( br_count t 16 0 ) 1 )
    ( eq_i `line 16 — and the other is not` ( br_count t 16 1 ) 1 )
    ( eq_i `line 17 — 5 is under ten` ( br_count t 17 0 ) 1 )
    ( eq_i `line 17 — nothing was ten or more` ( br_count t 17 1 ) 0 )

    ( linetab_free t )
}

// Adding a line's blocks together would report line 15 as 4: the test
// itself ran twice, and so did the two ways out of it. It ran twice.
@ check_not_the_sum * GcovObj o i src → v {
    : *LineTab t ( lines_build o src )
    : ~ i blocks 0
    : ~ i blocksum 0
    : i first ( gcov_fn_bl_first o 0 )
    : i nfn ( gcov_fn_count o )
    : ~ i fi 0
    ~ < fi nfn {
        : i f0 ( gcov_fn_bl_first o fi )
        : i fe ( gcov_fn_bl_end o fi )
        : ~ i row f0
        ~ < row fe {
            ? & == src ( gcov_bl_src o row ) == 15 ( gcov_bl_line o row ) {
                = blocks + blocks 1
                = blocksum + blocksum ( gcov_block_count o fi ( gcov_bl_block o row ) )
            } {}
            = row + row GBL_W
        }
        = fi + fi 1
    }
    ( is_true `line 15 really is several blocks` > blocks 1 )
    ( is_true `and their sum is NOT the line count` != blocksum ( lt_at t 15 ) )
    ( eq_i `the line count stays 2` ( lt_at t 15 ) 2 )
    ( linetab_free t )
}

@ check_functions * Cov c i idx → v {
    : i n ( cov_fn_rows c idx )
    : ~ i classify -1
    : ~ i unused -1
    : ~ i mainfn -1
    : ~ i k 0
    ~ < k n {
        : s nm ( cov_fn_name c idx k )
        ? != 0 ( nurl_str_eq nm `classify` ) { = classify ( cov_fn_called c idx k ) } {}
        ? != 0 ( nurl_str_eq nm `unused_helper` ) { = unused ( cov_fn_called c idx k ) } {}
        ? != 0 ( nurl_str_eq nm `main` ) { = mainfn ( cov_fn_called c idx k ) } {}
        = k + k 1
    }
    ( eq_i `classify was called twice` classify 2 )
    ( eq_i `main was called once` mainfn 1 )
    // Without --no-dce this one is not merely zero, it is ABSENT: the
    // compiler removes it, and the report never mentions the gap.
    ( eq_i `unused_helper is present, and was called zero times` unused 0 )
}

@ model_file_idx * Cov c → i {
    : i n ( cov_file_count c )
    : ~ i i 0
    ~ < i n {
        ? ( ends_with ( cov_file_path c i ) `tests/fixtures/sample.nu` ) { ^ i } {}
        = i + i 1
    }
    ^ -1
}

@ check_merge s notes s data → v {
    : *Cov one ( cov_new )
    : *Cov two ( cov_new )
    ?? ( gcov_read notes data ) {
        T o → { ( cov_add_object one o ) ( gcov_free o ) }
        F _ → {}
    }
    ?? ( gcov_read notes data ) {
        T o → { ( cov_add_object two o ) ( gcov_free o ) }
        F _ → {}
    }
    ?? ( gcov_read notes data ) {
        T o → { ( cov_add_object two o ) ( gcov_free o ) }
        F _ → {}
    }
    : i i1 ( model_file_idx one )
    : i i2 ( model_file_idx two )
    ( is_true `the fixture is in both models` & >= i1 0 >= i2 0 )
    ? & >= i1 0 >= i2 0 {
        ( eq_i `one object: line 14 ran twice` ( cov_line_count one i1 14 ) 2 )
        ( eq_i `two objects: line 14 ran four times` ( cov_line_count two i2 14 ) 4 )
        : CovStat s1 ( cov_file_stat one i1 )
        : CovStat s2 ( cov_file_stat two i2 )
        ( eq_i `merging adds traffic, not lines` . s2 lines_found . s1 lines_found )
        ( eq_i `and does not change what was hit` . s2 lines_hit . s1 lines_hit )
        ( eq_i `nor the branch total` . s2 branches_found . s1 branches_found )
        ( check_functions one i1 )
    } {}
    ( cov_free one )
    ( cov_free two )
}

@ check_formats s notes s data → v {
    : *Cov c ( cov_new )
    ?? ( gcov_read notes data ) {
        T o → { ( cov_add_object c o ) ( gcov_free o ) }
        F _ → {}
    }
    : String info ( lcov_render c )
    ( is_true `LCOV names the fixture` ( string_contains info `tests/fixtures/sample.nu` ) )
    ( is_true `LCOV carries a function record` ( string_contains info `FNDA:2,classify` ) )
    ( is_true `LCOV carries the uncovered line` ( string_contains info `DA:18,0` ) )
    ( is_true `LCOV carries a branch record` ( string_contains info `BRDA:15,0,0,2` ) )
    ( is_true `LCOV closes its section` ( string_contains info `end_of_record` ) )
    ( string_free info )

    : String js ( json_render c )
    ( is_true `JSON reports one object` ( string_contains js `"objects":1` ) )
    ( is_true `JSON carries totals` ( string_contains js `"lines_found"` ) )
    ( is_true `JSON keys lines by number` ( string_contains js `"18":0` ) )
    ( string_free js )
    ( cov_free c )
}

@ check_missing_data s notes → v {
    // No .gcda at all: the program was built and never run. Every count is
    // zero, and that is an answer, not an error.
    ?? ( gcov_read notes `/nonexistent/never-ran.gcda` ) {
        T o → {
            : i src ( fixture_src o )
            ( is_true `the notes alone still name the source` >= src 0 )
            ? >= src 0 {
                : *LineTab t ( lines_build o src )
                ( eq_i `a program that never ran covers nothing` ( lt_at t 14 ) 0 )
                ( is_true `but the line is still known to exist` ( lt_exists t 14 ) )
                ( linetab_free t )
            } {}
            ( gcov_free o )
        }
        F _ → ( bad `notes without data` `the reader refused to read them` )
    }
}

@ check_rejects_junk s work → v {
    : String junk ( string_from work )
    ( string_push_str junk `/not-a-graph.gcno` )
    ?? ( write_file ( string_data junk ) `this is not a coverage graph at all` ) {
        T _ → {}
        F _ → {}
    }
    ?? ( gcov_read ( string_data junk ) `/nonexistent.gcda` ) {
        T o → { ( bad `a junk file` `was accepted as a coverage graph` ) ( gcov_free o ) }
        F _ → ( ok `a junk file is rejected, not misread` )
    }
    ( string_free junk )
}

// ── Hand-built graphs, for the inputs a fuzzer finds ──────────────
//
// A coverage reader is handed files it did not write. A flipped byte in a
// notes file is not a theoretical worry: one of them named line 1970155382
// here, and because the per-line tables are indexed BY line number, the
// reader sized a table from an untrusted word and hung. These build the
// smallest graphs that exercise those paths.

@ put_u32 ( Vec u ) v i x → v {
    ( vec_push [u] v # u & x 255 )
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & >> x 16 255 )
    ( vec_push [u] v # u & >> x 24 255 )
}

// The four magic bytes, the version "408*" and a build stamp. Both files
// spell the magic reversed, which is how a reader tells the endianness.
@ put_header ( Vec u ) v s magic i stamp → v {
    : ~ i k 0
    ~ < k 4 { ( vec_push [u] v # u ( nurl_str_at magic 4 k ) ) = k + k 1 }
    ( vec_push [u] v # u 42 )
    ( vec_push [u] v # u 56 )
    ( vec_push [u] v # u 48 )
    ( vec_push [u] v # u 52 )
    ( put_u32 v stamp )
}

// One word of NUL-padded name, the way the format stores a string.
@ put_name1 ( Vec u ) v i ch → v {
    ( put_u32 v 1 )
    ( vec_push [u] v # u ch )
    ( vec_push [u] v # u 0 )
    ( vec_push [u] v # u 0 )
    ( vec_push [u] v # u 0 )
}

// A notes file with one function, three blocks, and one line number that
// `line` decides. Everything else is the smallest thing the format allows.
@ build_notes i stamp i lcs i line → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( put_header v `oncg` stamp )
    ( put_u32 v 0x01000000 )
    ( put_u32 v 8 )
    ( put_u32 v 0 )  // ident
    ( put_u32 v lcs )
    ( put_u32 v 7 )  // cfg checksum
    ( put_name1 v 102 )  // name "f"
    ( put_name1 v 97 )  // file "a"
    ( put_u32 v 1 )  // start line
    ( put_u32 v 0x01410000 )
    ( put_u32 v 3 )
    ( put_u32 v 0 )
    ( put_u32 v 0 )
    ( put_u32 v 0 )
    ( put_u32 v 0x01450000 )
    ( put_u32 v 7 )
    ( put_u32 v 2 )  // block 2
    ( put_u32 v 0 )  // a file name follows
    ( put_name1 v 97 )  // "a"
    ( put_u32 v line )
    ( put_u32 v 0 )
    ( put_u32 v 0 )  // end of the record
    ^ v
}

// A data file for that function, with whatever line checksum `lcs` says.
@ build_data i stamp i lcs → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( put_header v `adcg` stamp )
    ( put_u32 v 0x01000000 )
    ( put_u32 v 3 )
    ( put_u32 v 0 )  // ident
    ( put_u32 v lcs )
    ( put_u32 v 7 )
    ^ v
}

// Overwrite one 32-bit word in a graph that has already been built, so a
// test can name the exact field it is corrupting.
@ poke_u32 ( Vec u ) v i off i x → v {
    ( vec_set [u] v off # u & x 255 )
    ( vec_set [u] v + off 1 # u & >> x 8 255 )
    ( vec_set [u] v + off 2 # u & >> x 16 255 )
    ( vec_set [u] v + off 3 # u & >> x 24 255 )
}

@ dump_bytes s path ( Vec u ) v → v {
    ?? ( write_file_bytes path v ) { T _ → {} F _ → {} }
    ( vec_free [u] v )
}

// Reading must end in an answer or a named error, never in a crash and
// never in a table sized from a number the file made up.
@ expect_err s name s notes s data GcovErr want → v {
    ?? ( gcov_read notes data ) {
        T o → { ( bad name `the file was accepted` ) ( gcov_free o ) }
        F e → ? == # i e # i want { ( ok name ) } {
            ( bad name ( gcov_err_name e ) )
        }
    }
}

@ check_malformed s work → v {
    : String n1 ( string_from work )
    ( string_push_str n1 `/m1.gcno` )
    : String d1 ( string_from work )
    ( string_push_str d1 `/m1.gcda` )

    // A line number no source file has. Before this was rejected, the
    // reader grew a dense per-line table towards two billion entries.
    ( dump_bytes ( string_data n1 ) ( build_notes 4660 1 1970155382 ) )
    ( dump_bytes ( string_data d1 ) ( build_data 4660 1 ) )
    ( expect_err `an impossible line number is refused, not allocated`
    ( string_data n1 ) ( string_data d1 ) GcovBadLine )

    // The same graph with a line a file really could have must be read.
    ( dump_bytes ( string_data n1 ) ( build_notes 4660 1 7 ) )
    ( dump_bytes ( string_data d1 ) ( build_data 4660 1 ) )
    ?? ( gcov_read ( string_data n1 ) ( string_data d1 ) ) {
        T o → {
            ( eq_i `the same graph with a real line number is read` ( gcov_fn_count o ) 1 )
            ( gcov_free o )
        }
        F e → ( bad `the same graph with a real line number is read` ( gcov_err_name e ) )
    }

    // The file stamp says the pair came from one build; the per-function
    // checksums say this function did. A notes file corrupted after the
    // fact keeps the first and loses the second, and every counter after
    // it would land on the wrong arcs.
    ( dump_bytes ( string_data n1 ) ( build_notes 4660 1 7 ) )
    ( dump_bytes ( string_data d1 ) ( build_data 4660 99 ) )
    ( expect_err `a function whose checksums disagree is refused`
    ( string_data n1 ) ( string_data d1 ) GcovChecksumMismatch )

    // A block the function does not have. An arc pointing outside the
    // block table leaves the walk that solves the flow unable to mark
    // where it has been, and it loops: this was a hang, not a wrong
    // number, which is the worse of the two.
    : ( Vec u ) badblk ( build_notes 4660 1 7 )
    ( poke_u32 badblk 80 9 )  // the LINES record's block number
    ( dump_bytes ( string_data n1 ) badblk )
    ( dump_bytes ( string_data d1 ) ( build_data 4660 1 ) )
    ( expect_err `a block the function does not have is refused`
    ( string_data n1 ) ( string_data d1 ) GcovBadBlock )

    // A whole different build.
    ( dump_bytes ( string_data n1 ) ( build_notes 4660 1 7 ) )
    ( dump_bytes ( string_data d1 ) ( build_data 1234 1 ) )
    ( expect_err `a .gcda from another build is refused`
    ( string_data n1 ) ( string_data d1 ) GcovStampMismatch )

    // Cut short at every interesting offset: nothing may crash, and
    // nothing may be read as if it were whole.
    : ( Vec u ) whole ( build_notes 4660 1 7 )
    : i n ( vec_len [u] whole )
    : ~ i survived 0
    : ~ i tried 0
    : ~ i cut 0
    ~ < cut n {
        : ( Vec u ) part ( vec_new [u] )
        : ~ i k 0
        ~ < k cut {
            ?? ( vec_get [u] whole k ) { T x → ( vec_push [u] part x ) F _ → {} }
            = k + k 1
        }
        ( dump_bytes ( string_data n1 ) part )
        = tried + tried 1
        ?? ( gcov_read ( string_data n1 ) `/nonexistent.gcda` ) {
            T o → ( gcov_free o )
            F _ → {}
        }
        = survived + survived 1
        = cut + cut 1
    }
    ( vec_free [u] whole )
    ( eq_i `every truncation of a notes file is handled` survived tried )

    ( string_free n1 )
    ( string_free d1 )
}

@ main → i {
    : String work ?? ( fs_tempdir `` `nurl-cov-test-` ) {
        T d → d
        F _ → ( string_from `.` )
    }
    : String notes ( build_fixture ( string_data work ) )
    ? == 0 ( string_len notes ) {
        ( nurl_eprintln `could not build the fixture with coverage instrumentation` )
        ( string_free notes )
        ( string_free work )
        ^ 1
    } {}
    : String data ( runner_data_path ( string_data notes ) )

    ?? ( gcov_read ( string_data notes ) ( string_data data ) ) {
        T o → {
            : i src ( fixture_src o )
            ( is_true `the object names the fixture source` >= src 0 )
            ? >= src 0 {
                ( check_lines o src )
                ( check_not_the_sum o src )
            } {}
            ( gcov_free o )
        }
        F e → ( bad `reading the object` ( gcov_err_name e ) )
    }
    ( check_merge ( string_data notes ) ( string_data data ) )
    ( check_formats ( string_data notes ) ( string_data data ) )
    ( check_missing_data ( string_data notes ) )
    ( check_rejects_junk ( string_data work ) )
    ( check_malformed ( string_data work ) )

    ( nurl_print `nurl-cov: PASS ` )
    ( nurl_print ( nurl_str_int g_pass ) )
    ( nurl_print ` FAIL ` )
    ( nurl_println ( nurl_str_int g_fail ) )

    ?? ( dir_remove_all ( string_data work ) ) { T _ → {} F _ → {} }
    ( string_free notes )
    ( string_free data )
    ( string_free work )
    ^ ? > g_fail 0 1 0
}
