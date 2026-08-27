/*
 * NURL nolibc — unikernel/tests/pthread_layout.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * runtime_bare.c's mutex and condvar are written INTO memory the NURL
 * side allocated: std/thread.nu asks cell.nu for
 * nurl_native_sizeof("pthread_mutex_t") bytes, and runtime_core.c
 * answers that from the C compiler's own <pthread.h>. If the bare
 * structures were ever to outgrow that allocation, the overflow would
 * land in the next heap block — silent, and nowhere near the code that
 * caused it.
 *
 * runtime_bare.c cannot check this itself: it compiles freestanding,
 * with no <pthread.h> to compare against, and its own _Static_asserts
 * can only test the numbers a comment claims. So it publishes its three
 * sizes and this hosted gate compares them with the real header — the
 * same "ask the platform, don't enumerate it" rule that fixed the
 * sockaddr_un layout for the BSDs.
 */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

extern const unsigned long nurl__bare_sizeof_mutex;
extern const unsigned long nurl__bare_sizeof_cond;
extern const unsigned long nurl__bare_sizeof_coro;

/* Same reason as sched_gate.c: runtime_bare frees an owned closure
 * environment through the NURL allocator, and this gate links the bare
 * runtime without runtime_core.c. Nothing here spawns an owned fiber,
 * so the definition exists to satisfy the link and aborts if that ever
 * stops being true. */
void nurl_free(char *p);
void nurl_free(char *p) {
    (void)p;
    fprintf(stderr, "pthread_layout: nurl_free reached — this gate links "
                    "no allocator\n");
    abort();
}

int main(void) {
    int bad = 0;
    struct { const char *name; unsigned long have, avail; } row[] = {
        { "mutex",    nurl__bare_sizeof_mutex, sizeof(pthread_mutex_t) },
        { "cond",     nurl__bare_sizeof_cond,  sizeof(pthread_cond_t)  },
        { "pthread_t",nurl__bare_sizeof_coro,  sizeof(pthread_t)       },
    };
    for (unsigned i = 0; i < sizeof row / sizeof row[0]; i++) {
        if (row[i].have > row[i].avail) {
            printf("  %s: bare needs %lu bytes, the NURL side allocates %lu\n",
                   row[i].name, row[i].have, row[i].avail);
            bad = 1;
        }
    }
    if (bad) return 1;
    printf("layout ok (mutex %lu/%lu, cond %lu/%lu, pthread_t %lu/%lu)\n",
           row[0].have, row[0].avail, row[1].have, row[1].avail,
           row[2].have, row[2].avail);
    return 0;
}
