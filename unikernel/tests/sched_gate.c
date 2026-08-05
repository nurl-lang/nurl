/*
 * NURL nolibc — unikernel/tests/sched_gate.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The cooperative scheduler in unikernel/runtime_bare.c, exercised
 * directly rather than through NURL.
 *
 * The corpus run (unikernel/run_nolibc_tests.sh) already proves the
 * scheduler runs real NURL programs to their goldens, and that is the
 * stronger end-to-end evidence. What it cannot show is the part that
 * has no NURL spelling:
 *
 *   - ORDER. "async_chan printed the right total" holds whether or not
 *     a mutex handed off to the waiter that had been queued longest.
 *     Here every wake-up appends a letter to one trace string, so the
 *     schedule itself is the value being compared.
 *   - DEADLOCK. The one thing this runtime can say that the hosted one
 *     cannot: with a single execution context, "nothing is runnable and
 *     nothing is timed" is a proof, not a symptom. Each `deadlock-*`
 *     scenario is a program that a preemptive runtime would hang on
 *     forever; the gate asserts it dies, with a message, in bounded
 *     time. A detector nobody has watched fire is a comment.
 *   - THE GUARD PAGE. A coroutine stack overflow must fault at the
 *     instruction that did it, not corrupt the neighbouring stack and
 *     surface somewhere else an hour later.
 *
 * Scenario selected by argv[1]; the runner script drives all of them
 * and checks each exit status.
 */
#include "../nolibc/nolibc.h"

/* ── the surface under test (unikernel/runtime_bare.c) ──────────── */
int  pthread_mutex_init(void *m, void *attr);
int  pthread_mutex_lock(void *m);
int  pthread_mutex_trylock(void *m);
int  pthread_mutex_unlock(void *m);
int  pthread_mutex_destroy(void *m);
int  pthread_cond_init(void *c, void *attr);
int  pthread_cond_wait(void *c, void *m);
int  pthread_cond_signal(void *c);
int  pthread_cond_broadcast(void *c);
int  pthread_cond_destroy(void *c);
int  pthread_create(void *t, void *attr, void *start, void *arg);
int  nurl_pthread_join_ptr(void *t);
void nurl_pthread_detach_ptr(void *t);

long long nurl_fiber_spawn(void *fn, void *env);
long long nurl_fiber_spawn_joinable(void *fn, void *env);
void      nurl_fiber_join(long long h);
void      nurl_fiber_yield(void);
long long nurl_fiber_current(void);
long long nurl_fiber_worker_id(void);
void      nurl_fiber_park_with_mutex(long long m);
void      nurl_fiber_unpark(long long h);
long long nurl_fiber_sleep_ms(long long ms);
void      nurl_runtime_init(long long workers);
void      nurl_runtime_run(void);
void      nurl_runtime_shutdown(void);
long long nurl_rand_fill(unsigned char *buf, long long n);
extern long long nurl__bare_live_coros;
void     *nurl__bare_stack_lo(void);

/* Storage the NURL side would get from cell.nu — sized the way
 * nurl_native_sizeof reports it, so this file uses the mutex exactly as
 * a NURL program does. pthread_layout.c is the gate on those numbers. */
typedef struct { long long slot[5]; } mutex_store;   /* 40 bytes */
typedef struct { long long slot[6]; } cond_store;    /* 48 bytes */

static int failures;
static int checks;

static void ck(int ok, const char *what) {
    checks++;
    if (!ok) { failures++; printf("  FAIL %s\n", what); }
}

static void ck_str(const char *got, const char *want, const char *what) {
    checks++;
    if (strcmp(got, want) != 0) {
        failures++;
        printf("  FAIL %s: got \"%s\" want \"%s\"\n", what, got, want);
    }
}

/* ── the trace ────────────────────────────────────────────────────
 * Every interesting event appends one character. The whole point is
 * that the ORDER is asserted, so a scheduler that produces the right
 * totals by the wrong schedule still fails. */
static char trace[64];
static int  trace_n;
static void mark(char c) { if (trace_n < 63) trace[trace_n++] = c; trace[trace_n] = 0; }
static void trace_reset(void) { trace_n = 0; trace[0] = 0; }

/* ── 1. mutex: contention parks, release hands off in FIFO order ── */

static mutex_store m1;
static void holder(void *env) {
    (void)env;
    pthread_mutex_lock(&m1);
    mark('H');
    nurl_fiber_yield();              /* still holding it */
    mark('h');
    pthread_mutex_unlock(&m1);
}
static void waiter_a(void *env) { (void)env; pthread_mutex_lock(&m1); mark('A'); pthread_mutex_unlock(&m1); }
static void waiter_b(void *env) { (void)env; pthread_mutex_lock(&m1); mark('B'); pthread_mutex_unlock(&m1); }

static void test_mutex(void) {
    pthread_mutex_init(&m1, 0);
    trace_reset();
    nurl_fiber_spawn(holder, 0);
    nurl_fiber_spawn(waiter_a, 0);
    nurl_fiber_spawn(waiter_b, 0);
    nurl_runtime_run();
    /* H then the yield lets A and B run and block; h releases to A
     * (queued first), A's release to B. A FIFO wait queue is not an
     * accident of the implementation — LIFO starves under load, so it
     * is asserted. */
    ck_str(trace, "HhAB", "mutex FIFO handoff");

    ck(pthread_mutex_trylock(&m1) == 0, "trylock on free mutex");
    ck(pthread_mutex_trylock(&m1) != 0, "trylock on held mutex refuses");
    pthread_mutex_unlock(&m1);
    pthread_mutex_destroy(&m1);
}

/* ── 1b. mutual exclusion under the one interleaving that breaks it ──
 *
 * Releasing a mutex moves ONE waiter to the run queue; it does not hand
 * the mutex to it. Between that move and the waiter actually running,
 * anyone else may take the lock — so the waiter has to re-test, in a
 * loop, rather than assume the lock it was woken for is still free.
 *
 * The trace tests above cannot see the difference: in all of them the
 * woken waiter is the next thing to run. This one deliberately steals
 * the mutex back before the waiter is scheduled, and counts holders. It
 * exists because turning that `while` into an `if` escaped the first
 * mutation run — the code was right and the test was blind. */
static mutex_store m4;
static int cs_depth, cs_violation;
static void enter_cs(void) { if (cs_depth != 0) cs_violation = 1; cs_depth++; }
static void leave_cs(void) { cs_depth--; }

static void cs_taker(void *env) {
    (void)env;
    pthread_mutex_lock(&m4);
    enter_cs();
    mark('F');
    leave_cs();
    pthread_mutex_unlock(&m4);
}

static void test_mutex_exclusion(void) {
    pthread_mutex_init(&m4, 0);
    trace_reset();
    cs_depth = cs_violation = 0;

    pthread_mutex_lock(&m4);
    enter_cs();
    nurl_fiber_spawn(cs_taker, 0);
    nurl_fiber_yield();                  /* F runs and blocks on m4 */
    ck_str(trace, "", "the waiter is blocked, not through");

    leave_cs();
    pthread_mutex_unlock(&m4);           /* F becomes runnable … */
    pthread_mutex_lock(&m4);             /* … but main takes the lock first */
    enter_cs();
    nurl_fiber_yield();                  /* now F runs */
    ck(!cs_violation, "a woken waiter re-tests instead of assuming the lock");
    ck_str(trace, "", "and stays out while main holds it");

    leave_cs();
    pthread_mutex_unlock(&m4);
    nurl_runtime_run();
    ck_str(trace, "F", "and gets in once main is done");
    ck(!cs_violation, "no two holders at any point");
    pthread_mutex_destroy(&m4);
}

/* ── 2. condvar: main waits, a coroutine signals ───────────────── */

static mutex_store m2;
static cond_store  c2;
static int         ready2;

static void signaller(void *env) {
    (void)env;
    pthread_mutex_lock(&m2);
    ready2 = 1;
    mark('S');
    pthread_cond_signal(&c2);
    pthread_mutex_unlock(&m2);
}

static void test_cond_main_waits(void) {
    pthread_mutex_init(&m2, 0);
    pthread_cond_init(&c2, 0);
    trace_reset();
    ready2 = 0;
    pthread_mutex_lock(&m2);
    nurl_fiber_spawn(signaller, 0);
    while (!ready2) pthread_cond_wait(&c2, &m2);
    mark('W');
    pthread_mutex_unlock(&m2);
    ck_str(trace, "SW", "main blocks in cond_wait until a coroutine signals");
    nurl_runtime_run();
    pthread_cond_destroy(&c2);
    pthread_mutex_destroy(&m2);
}

/* ── 3. condvar: signal wakes one, broadcast wakes all ──────────── */

static mutex_store m3;
static cond_store  c3;
static int         gen3;

static void sleeper3(void *env) {
    long id = (long)env;
    pthread_mutex_lock(&m3);
    int seen = gen3;
    while (gen3 == seen) pthread_cond_wait(&c3, &m3);
    mark((char)('0' + id));
    pthread_mutex_unlock(&m3);
}

static void test_cond_signal_vs_broadcast(void) {
    pthread_mutex_init(&m3, 0);
    pthread_cond_init(&c3, 0);
    trace_reset();
    gen3 = 0;
    for (long i = 1; i <= 3; i++) nurl_fiber_spawn(sleeper3, (void *)i);
    nurl_fiber_yield();              /* let all three reach the wait */
    nurl_fiber_yield();

    pthread_mutex_lock(&m3);
    gen3++;
    pthread_cond_signal(&c3);
    pthread_mutex_unlock(&m3);
    /* Pump to quiescence rather than "until something happened": the
     * first version stopped as soon as ONE waiter had marked, so a
     * signal that woke all three passed it. Once nothing is runnable
     * the extra yields are no-ops, so what this asserts is that the
     * other two are still waiting. */
    for (int i = 0; i < 8; i++) nurl_fiber_yield();
    ck_str(trace, "1", "signal wakes exactly one waiter, the oldest");

    pthread_mutex_lock(&m3);
    gen3++;
    pthread_cond_broadcast(&c3);
    pthread_mutex_unlock(&m3);
    nurl_runtime_run();
    ck_str(trace, "123", "broadcast wakes the rest, in queue order");
    pthread_cond_destroy(&c3);
    pthread_mutex_destroy(&m3);
}

/* ── 4. threads: create/join from main and from a coroutine ─────── */

static int thread_ran;
static void *thread_body(void *env) { (void)env; thread_ran++; mark('T'); return 0; }

static void joiner(void *env) {
    (void)env;
    void *t = 0;
    pthread_create(&t, 0, (void *)thread_body, 0);
    mark('j');
    nurl_pthread_join_ptr(&t);       /* blocks INSIDE a coroutine */
    mark('J');
}

static void test_threads(void) {
    trace_reset();
    thread_ran = 0;
    void *t = 0;
    ck(pthread_create(&t, 0, (void *)thread_body, 0) == 0, "pthread_create");
    ck(nurl_pthread_join_ptr(&t) == 0, "pthread_join from main");
    ck(thread_ran == 1, "thread body ran exactly once");
    ck_str(trace, "T", "join from main runs the body");

    trace_reset();
    nurl_fiber_spawn(joiner, 0);
    nurl_runtime_run();
    ck_str(trace, "jTJ", "a coroutine can block in join and be resumed");

    /* Detach, in both orders. The interesting one is detaching a thread
     * that has ALREADY finished: it is sitting DONE and joinable,
     * waiting for a join that is never coming, and detach is the only
     * thing left that can reclaim it. Nothing observes that directly —
     * the live-coroutine count at the end of main does. */
    trace_reset();
    thread_ran = 0;
    void *d1 = 0, *d2 = 0;
    pthread_create(&d1, 0, (void *)thread_body, 0);
    nurl_pthread_detach_ptr(&d1);        /* detach before it ever runs */
    pthread_create(&d2, 0, (void *)thread_body, 0);
    nurl_runtime_run();                  /* run both to completion */
    nurl_pthread_detach_ptr(&d2);        /* detach after it finished */
    ck(thread_ran == 2, "both detached threads ran");
    ck_str(trace, "TT", "detached threads still run");
}

/* ── 5. sleep: the timer queue orders wake-ups by deadline ──────── */

static void napper(void *env) {
    long id = (long)env;
    nurl_fiber_sleep_ms(id * 20);
    mark((char)('a' + id - 1));
}

static void test_sleep_order(void) {
    trace_reset();
    /* Spawned longest-first, so ordering by spawn order would give
     * "cba" and only a real deadline queue gives "abc". */
    nurl_fiber_spawn(napper, (void *)3);
    nurl_fiber_spawn(napper, (void *)1);
    nurl_fiber_spawn(napper, (void *)2);
    nurl_runtime_run();
    ck_str(trace, "abc", "timers fire in deadline order, not spawn order");
}

/* ── 6. park/unpark, the async.nu primitive pair ────────────────── */

static long long parked_h;
static void parker(void *env) {
    (void)env;
    parked_h = nurl_fiber_current();
    mark('p');
    nurl_fiber_park_with_mutex(0);   /* no mutex to release */
    mark('u');
}

static void test_park_unpark(void) {
    trace_reset();
    parked_h = 0;
    nurl_fiber_spawn(parker, 0);
    nurl_fiber_yield();
    ck(parked_h != 0, "fiber_current inside a coroutine is non-zero");
    ck(nurl_fiber_worker_id() == -1, "worker_id off a coroutine is -1");
    ck_str(trace, "p", "parked coroutine stays parked with nobody to run it");
    nurl_fiber_unpark(parked_h);
    nurl_runtime_run();
    ck_str(trace, "pu", "unpark resumes it");
}

/* ── 7. entropy ─────────────────────────────────────────────────── */

static void test_entropy(void) {
    unsigned char a[32], b[32];
    for (int i = 0; i < 32; i++) { a[i] = 0; b[i] = 0; }
    ck(nurl_rand_fill(a, 32) == 1, "rand_fill succeeds");
    ck(nurl_rand_fill(b, 32) == 1, "rand_fill succeeds twice");
    ck(memcmp(a, b, 32) != 0, "two fills differ");
    int zeros = 0;
    for (int i = 0; i < 32; i++) if (a[i] == 0) zeros++;
    /* A stub that fills nothing passes "two fills differ" only by
     * accident; 32 zero bytes from a real CSPRNG has probability
     * 2^-256. */
    ck(zeros < 32, "rand_fill wrote something");
}

/* ── the deadlock scenarios ─────────────────────────────────────── */

static mutex_store dm;
static cond_store  dc;

static void blocked_forever(void *env) {
    (void)env;
    pthread_mutex_lock(&dm);
    pthread_cond_wait(&dc, &dm);     /* nobody ever signals */
    pthread_mutex_unlock(&dm);
}

int main(int argc, char **argv) {
    const char *scenario = (argc > 1) ? argv[1] : "ok";

    if (strcmp(scenario, "deadlock-mutex") == 0) {
        /* Self-deadlock on a non-recursive mutex, with no coroutine
         * alive to ever release it. */
        pthread_mutex_init(&dm, 0);
        pthread_mutex_lock(&dm);
        pthread_mutex_lock(&dm);
        printf("unreachable\n");
        return 1;
    }
    if (strcmp(scenario, "deadlock-cond") == 0) {
        pthread_mutex_init(&dm, 0);
        pthread_cond_init(&dc, 0);
        pthread_mutex_lock(&dm);
        pthread_cond_wait(&dc, &dm);
        printf("unreachable\n");
        return 1;
    }
    if (strcmp(scenario, "deadlock-join") == 0) {
        /* The interesting one: something IS runnable when main blocks,
         * so the detector must fire only after that coroutine has run
         * and parked itself. */
        pthread_mutex_init(&dm, 0);
        pthread_cond_init(&dc, 0);
        void *t = 0;
        pthread_create(&t, 0, (void *)blocked_forever, 0);
        nurl_pthread_join_ptr(&t);
        printf("unreachable\n");
        return 1;
    }
    if (strcmp(scenario, "deadlock-run") == 0) {
        pthread_mutex_init(&dm, 0);
        pthread_cond_init(&dc, 0);
        nurl_fiber_spawn(blocked_forever, 0);
        nurl_runtime_run();
        printf("unreachable\n");
        return 1;
    }
    if (strcmp(scenario, "guard-write") == 0) {
        /* One byte below the usable stack. Under an armed guard page
         * this faults; with the mprotect removed it is ordinary
         * read-write memory inside our own mapping and the write
         * succeeds — which is exactly why "stack-overflow" alone could
         * not tell the two apart: an unguarded overflow still runs off
         * the bottom of the mapping eventually and faults there. */
        extern void poke_below_stack(void *env);
        nurl_fiber_spawn(poke_below_stack, 0);
        nurl_runtime_run();
        printf("wrote below the stack with no fault\n");
        return 1;
    }
    if (strcmp(scenario, "entropy-fault") == 0) {
        /* An unmapped destination makes getrandom fail with EFAULT —
         * the only portable way to see what this runtime does when its
         * entropy source says no. It must die: the plan's rule for a
         * machine nobody can log into is that there is no degraded
         * path. Sampling can never reach this branch, so it is reached
         * on purpose. */
        nurl_rand_fill((unsigned char *)8, 32);
        printf("entropy failure was tolerated\n");
        return 1;
    }
    if (strcmp(scenario, "stack-overflow") == 0) {
        /* Must fault on the guard page rather than scribble on the
         * neighbouring mapping. Run under a SIGSEGV expectation. */
        extern int eat_stack(int depth);
        nurl_fiber_spawn((void *)eat_stack, (void *)(long)100000);
        nurl_runtime_run();
        printf("unreachable\n");
        return 1;
    }

    nurl_runtime_init(1);
    test_mutex();
    test_mutex_exclusion();
    test_cond_main_waits();
    test_cond_signal_vs_broadcast();
    test_threads();
    test_sleep_order();
    test_park_unpark();
    test_entropy();
    nurl_runtime_shutdown();

    /* The leak check for a world with no leak checker. Every coroutine
     * these tests created has been joined, detached or run to
     * completion, so every 64 KB stack must be back. */
    ck(nurl__bare_live_coros == 0, "no coroutine outlived the tests");
    if (nurl__bare_live_coros != 0)
        printf("       %lld coroutine(s) still allocated\n", nurl__bare_live_coros);

    if (failures) { printf("sched_gate: %d of %d checks FAILED\n", failures, checks); return 1; }
    printf("sched_gate: %d checks ok\n", checks);
    return 0;
}

/* Recursion that actually consumes stack. Two things have to be true or
 * this test passes while proving nothing:
 *
 *   - the frame must be live (`volatile`, or the array is elided);
 *   - the call must NOT be in tail position. The first version ended
 *     with `if (depth > 0) eat_stack(depth - 1);`, and clang turned
 *     that sibling call into a jump — 100 000 "recursions" in one
 *     frame, no growth, no fault, and a guard-page test that reported
 *     success without ever touching the guard page. Using the result
 *     after the call is what keeps the frame alive across it. */
void poke_below_stack(void *env) {
    (void)env;
    volatile char *lo = (volatile char *)nurl__bare_stack_lo();
    lo[-1] = 42;
}

int eat_stack(int depth) {
    volatile char pad[512];
    pad[0]   = (char)depth;
    pad[511] = (char)depth;
    int deeper = (depth > 0) ? eat_stack(depth - 1) : 0;
    return deeper + pad[0] + pad[511];
}
