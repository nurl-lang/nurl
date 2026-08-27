// unikernel/demos/guardpages.nu — a page that came back from a
// coroutine has to come back MAPPED.
//
// Every coroutine stack is allocated with a guard page below it, and
// arming that guard means clearing the present bit in its PTE. Giving
// the stack back returns the whole range to the page allocator — and
// for a while it returned the guard page with that bit still clear. The
// pool then handed the page to somebody else, nolibc's malloc carved an
// arena across it, and the first write to a block that happened to land
// there took a page fault INSIDE malloc, long after the coroutine that
// protected it had ended. On a server, twenty connections that sent one
// byte and hung up were enough.
//
// So: make coroutines come and go, then allocate and WRITE the memory
// they gave back. A guard page that returned unmapped is a fault here,
// at a line that says what it was doing, instead of a fault in the
// allocator with nothing to point at.

$ `stdlib/std/async.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ churn i n → v {
    : ~ i k 0
    ~ < k n {
        ( spawn \ → v {} )
        = k + k 1
    }
    ( runtime_run )
}

// Write one byte on every page of a freshly allocated block. The write
// is the assertion: a page the allocator handed out but nobody mapped
// faults here rather than silently later.
@ touch_pages i blocks i bytes → i {
    : ~ i pages 0
    : ~ i b 0
    ~ < b blocks {
        : ( Vec u ) v ( vec_with_cap [u] bytes )
        ( vec_set_len [u] v bytes )
        : ~ i off 0
        ~ < off bytes {
            : b _w ( vec_set [u] v off # u 65 )
            = pages + pages 1
            = off + off 4096
        }
        ( vec_free [u] v )
        = b + b 1
    }
    ^ pages
}

@ main → i {
    ( runtime_init 0 )
    // Enough coroutines that their stacks and guard pages are certain
    // to be recycled by the allocations below, and few enough that the
    // demo stays a second long.
    ( churn 64 )
    : i pages ( touch_pages 64 65536 )
    ( nurl_print `coroutines came and went, then wrote pages: ` )
    ( nurl_print ( nurl_str_int pages ) )
    ( nurl_print `\n` )
    ( churn 64 )
    : i more ( touch_pages 64 65536 )
    ( nurl_print `and again after a second round: ` )
    ( nurl_print ( nurl_str_int more ) )
    ( nurl_print `\n` )
    ( nurl_print `every page the coroutines gave back was writable: ` )
    ( nurl_print ? == pages more `yes` `no` )
    ( nurl_print `\n` )
    ( runtime_shutdown )
    ^ 0
}
