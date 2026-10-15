// tests/checkedcheck.nu — gk_run_checked: which bodies the subset takes,
// and what a checked kernel does on the CPU backend, out-of-range indices
// included. Prints one `ok …` / `FAIL …` line per case and a summary.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/checked.nu`

: ~ i g_fail 0

@ verdict GpuKit kit s body b want → v {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_in_f c `x` ( vec_zeroed [f] 4 ) )
    ( gk_call_out_f c `y` ( vec_zeroed [f] 4 ) )
    ( gk_call_i64 c `n` 4 )
    : b ok ( gk_run_checked kit c `t` body 4 64 )
    ? == ok want { ( nurl_print `ok   ` ) } { ( nurl_print `FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print ? want `accepts ` `rejects ` ) ( nurl_print body )
    ? ok {} { ( nurl_print `  (` ) ( nurl_print ( gk_checked_error c ) ) ( nurl_print `)` ) }
    ( nurl_print `\n` )
}

@ subset GpuKit kit → v {
    ( verdict kit `ST(y, gid, 2.0 * LD(x, gid));` T )
    ( verdict kit `double a = LD(x, gid) * 3.5e-2; if (a > 1.0) { ST(y, gid, a); }` T )
    ( verdict kit `for (long long k = 0; k < n; k++) { ST(y, k, LD(x, k) + 1.0); }` T )
    ( verdict kit `double s = __dadd_rn(LD(x, 0), .5); ST(y, gid & 3, s);` T )
    ( verdict kit `long long v = gid; v *= 2; v &= 3; ST(y, v, (double)(long long)v);` T )
    ( verdict kit `double* p = 0; *p = 1.0;` F )
    ( verdict kit `double *p;` F )
    ( verdict kit `ST(y, gid, *(&n));` F )
    ( verdict kit `long long a = n; long long b = &a;` F )
    ( verdict kit `__gk_p0[gid] = 1.0;` F )
    ( verdict kit `double q = __gk_n0;` F )
    ( verdict kit `ST(x, gid, 1.0);` F )
    ( verdict kit `ST(z, gid, 1.0);` F )
    ( verdict kit `} extern "C" void evil() {` F )
    ( verdict kit `printf("hi");` F )
    ( verdict kit `asm("nop");` F )
    ( verdict kit `#define X 1` F )
    ( verdict kit `struct S { int a; };` F )
    ( verdict kit `memcpy(0, 0, 4);` F )
    ( verdict kit `double v = n[0];` F )
    ( verdict kit `double v = blockIdx.x;` F )
    ( verdict kit `auto f = [](){};` F )
    ( verdict kit `ST(y, gid, static_cast<double>(n));` F )
    ( verdict kit `goto out; out: ;` F )
}

// Run a checked kernel for real: in-range work, an index past the end and
// a negative one (a load reads element 0, a store is dropped).
@ run GpuKit kit → v {
    : ~ ( Vec f ) xs ( vec_new [f] )
    ( vec_push [f] xs 1.5 ) ( vec_push [f] xs 2.5 ) ( vec_push [f] xs 3.5 ) ( vec_push [f] xs 4.5 )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_in_f c `x` xs )
    ( gk_call_out_f c `y` ( vec_zeroed [f] 6 ) )
    ( gk_call_i64 c `n` 4 )
    // thread 4 reads x[4] (past the end → x[0]); thread 5 stores at -1 (dropped)
    : b ok ( gk_run_checked kit c `checked_run` `if (gid < 5) ST(y, gid, 2.0 * LD(x, gid)); else ST(y, -1, 99.0);` 6 64 )
    : ( Vec f ) ys ( gk_call_take_f c `y` )
    : ~ String got ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [f] ys ) { ? > k 0 { ( string_push_char got 44 ) } {} ( string_push_float got ( vec_at [f] ys k ) ) = k + k 1 }
    : b want_ok ( nurl_str_eq ( string_data got ) `3,5,7,9,3,0` )
    ? & ok != 0 want_ok { ( nurl_print `ok   checked kernel ran: ` ) } { ( nurl_print `FAIL checked kernel ran: ` ) = g_fail + g_fail 1 }
    ( nurl_print ( string_data got ) ) ( nurl_print `\n` )
}

@ main → i {
    : GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ^ 0 }
    ( subset kit )
    ( run kit )
    ? == g_fail 0 { ( nurl_print `checked: all passed\n` ) } { ( nurl_print `checked: FAILURES\n` ) }
    ^ 0
}
