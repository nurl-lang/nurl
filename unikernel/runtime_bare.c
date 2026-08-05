/*
 * NURL runtime — unikernel/runtime_bare.c   (the freestanding twin of
 * stdlib/runtime_ffi.c)
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * WHAT THIS IS
 *
 * runtime_ffi.c is the half of the runtime that reaches outside the
 * process: threads, sockets, processes, signals, entropy, and the M:N
 * fiber runtime with its poll(2) reactor. All of it assumes an
 * operating system with preemptive threads. A unikernel has one vCPU
 * and no scheduler under it, so that file gets a twin rather than a
 * port — this one.
 *
 * The plan's line for this phase is short: "mutex = flag + yield loop,
 * cond = fiber wait queue, pthread_create → spawn fiber". This file is
 * that sentence made precise.
 *
 * ONE EXECUTION CONTEXT
 *
 * There is exactly one hardware context. Everything that looks
 * concurrent — NURL threads, NURL fibers — is a stackful coroutine
 * switched through stdlib/runtime_ctx.c, and a switch happens only at
 * an explicit point: yield, park, a blocking mutex/cond/join, or a
 * sleep. Nothing is preemptive, so:
 *
 *   - a critical section that never yields needs no lock at all, and
 *     `pthread_mutex_lock` on an uncontended mutex is one store;
 *   - the park/unpark race the M:N runtime spends a page of comments
 *     closing cannot occur here: nobody else is running to observe a
 *     half-suspended fiber;
 *   - and, the part worth having: **deadlock is decidable**. When no
 *     coroutine is runnable and no timer is pending and the waiter's
 *     predicate is still false, nothing in the machine can ever make
 *     it true. A hosted runtime can only hang there. This one prints
 *     what it was waiting for and dies (nurl__bare_deadlock).
 *
 * THE TWO SIDES OF EVERY BLOCKING CALL
 *
 * A blocking primitive is reached either from a fiber or from the main
 * context, and those need different mechanisms:
 *
 *   from a fiber — enqueue on the object's wait queue, mark PARKED and
 *     switch to the scheduler loop. Whoever satisfies the condition
 *     moves the fiber back to the run queue.
 *
 *   from main — main *is* the scheduler loop, so it cannot park inside
 *     itself. It drives the loop one step at a time and re-tests its
 *     predicate. No wakeup can be lost, because between the test and
 *     the step nothing else can run.
 *
 * Both appear in every blocking function below. That is deliberate
 * duplication of shape, not of logic: the alternative (queue main as a
 * pseudo-fiber) needs a context to switch to that does not exist until
 * main is already inside a switch.
 *
 * BOTTOM EDGE
 *
 * Same rule as unikernel/nolibc: everything here is portable C over a
 * handful of names that one platform file supplies — mmap/mprotect/
 * munmap for stacks, clock_gettime and nanosleep for time, getrandom
 * for entropy. On Linux those come from nolibc/syscall_linux.c; the
 * unikernel target replaces that file (stacks from the boot allocator,
 * time from the TSC, entropy from RDRAND) and keeps this one verbatim.
 *
 * WHAT IS DELIBERATELY ABSENT
 *
 * Sockets, DNS, the I/O reactor, processes and signals. They are not
 * stubbed: a program that needs them fails to LINK, and the nolibc
 * corpus runner prints the missing names. A stub that silently answers
 * "no bytes, no error" is how a missing driver becomes a bug report
 * from someone else six months later — the same rule nolibc/misc.c is
 * built on. Sockets arrive in phase A4, over the sans-IO stack in
 * stdlib/net/, not over a second syscall layer here.
 */

/* ── the platform bottom edge ─────────────────────────────────────
 * Declared rather than #included: this file compiles with
 * -ffreestanding and no system headers, which is the point. The
 * signatures match nolibc/syscall_linux.c, and the unikernel's
 * replacement for that file must match them too. */
typedef unsigned long nb_size_t;

void *mmap(void *addr, unsigned long len, int prot, int flags, int fd, long off);
int   munmap(void *p, unsigned long len);
int   mprotect(void *p, unsigned long len, int prot);
int   clock_gettime(int clk, void *ts);
int   nanosleep(const void *req, void *rem);
long long getrandom(void *buf, unsigned long len, unsigned int flags);
int  *__errno_location(void);

/* nolibc (and any hosted libc) supplies these. `struct nl_file` stays
 * incomplete on purpose — this file never looks inside a stream, and an
 * incomplete type is how you say that in C rather than spelling `void *`
 * and hoping the two declarations of `stderr` agree. */
struct nl_file;
void *calloc(nb_size_t n, nb_size_t sz);
void  free(void *p);
int   fprintf(struct nl_file *stream, const char *fmt, ...);
void  abort(void);
void  exit(int code);
extern struct nl_file *stderr;

/* stdlib/runtime_ctx.c — the stackful switch, shared verbatim with the
 * hosted runtime. */
typedef struct { void *sp; } nurl_ctx_t;
void nurl_ctx_init(nurl_ctx_t *ctx, void *stack, unsigned long size,
                   void (*entry)(void *), void *arg);
void nurl_ctx_switch(nurl_ctx_t *save, nurl_ctx_t *restore);
void nurl_ctx_asan_start_switch(void **fake_save, const void *bottom,
                                unsigned long size);
void nurl_ctx_asan_finish_switch(void *fake_save, const void **bottom_old,
                                 unsigned long *size_old);

/* Sanitized freestanding builds are not a thing today (ASan needs a
 * libc), but the annotation calls are no-ops when the build is not
 * sanitized, so the pairing lives here rather than being remembered
 * later — the hosted runtime learned that the hard way. */
#if defined(__has_feature)
#  if __has_feature(address_sanitizer)
#    define NURL_BARE_ASAN 1
#  endif
#endif
#if defined(__SANITIZE_ADDRESS__)
#  define NURL_BARE_ASAN 1
#endif

#define NB_PROT_READ   0x1
#define NB_PROT_WRITE  0x2
#define NB_PROT_NONE   0x0
#define NB_MAP_PRIVATE   0x02
#define NB_MAP_ANONYMOUS 0x20
#define NB_CLOCK_MONOTONIC 1

#define NB_PAGE          4096u
#define NB_STACK_BYTES   (64 * 1024)
#define NB_GUARD_BYTES   4096

/* ── §1  Coroutines ───────────────────────────────────────────────
 *
 * One structure serves both surfaces the corpus uses. A NURL *thread*
 * (std/thread.nu → pthread_create) and a NURL *fiber* (std/async.nu →
 * nurl_fiber_spawn) are the same object here, differing only in which
 * API created it — which is the whole point of a cooperative target:
 * there is no second kind of concurrency to implement. */

typedef enum {
    NB_RUNNABLE = 0,
    NB_RUNNING,
    NB_PARKED,
    NB_DONE
} NbState;

typedef struct NbCoro NbCoro;
struct NbCoro {
    nurl_ctx_t   ctx;
    void        *stack_base;      /* mmap origin: guard page + usable  */
    unsigned long stack_total;
    void        *stack_lo;        /* usable region                     */
    unsigned long stack_usable;
    void        *fake_stack;      /* ASan, parked across a switch      */
    void       (*fn)(void *);
    void        *env;
    NbState      state;
    NbCoro      *next;            /* run queue OR one wait queue       */
    NbCoro      *tnext;           /* timer list — a distinct list, so a
                                   * sleeping coroutine is never on two
                                   * lists through the same pointer    */
    long long    wake_at_ms;
    int          joinable;        /* survives DONE until joined        */
    int          finished;        /* body returned                     */
    NbCoro      *joiners;         /* coroutines blocked in join, via
                                   * ->next; a coroutine is on exactly
                                   * one such list at a time           */
    void        *pending_unlock;  /* NbMutex* released after swap-out  */
    int          last_park_result;
};

/* Defined in §8 — named here because §7's scheduler step performs the
 * parked-with-mutex handoff. A forward declaration, not an `extern`
 * buried inside a function body: the latter hides a file-scope
 * dependency in a place no reader looks. */
void nurl__bare_mutex_release(void *m);

/* Scheduler state. One global set, because there is one scheduler. */
static NbCoro   *nb_rq_head, *nb_rq_tail;
static NbCoro   *nb_timers;            /* sorted ascending by wake_at   */
static nurl_ctx_t nb_loop_ctx;         /* the main context, mid-step    */
static NbCoro   *nb_current;           /* NULL ⇒ running on main        */
static long long nb_live;              /* spawned and not yet reaped    */
static int       nb_initialized;

/* Coroutines allocated minus coroutines freed. There is no LSan in a
 * world with no libc, so the runtime keeps the one number a leak would
 * move: a program that has shut its runtime down and still shows a
 * non-zero count has stranded a 64 KB stack somewhere. sched_gate
 * asserts it returns to zero, which is what turns "detach forgot to
 * reclaim an already-finished thread" from an invisible leak into a
 * failing test. */
long long nurl__bare_live_coros;

#ifdef NURL_BARE_ASAN
static const void   *nb_loop_lo;
static unsigned long nb_loop_size;
#endif

/* ── §2  Time ─────────────────────────────────────────────────────── */

struct nb_timespec { long tv_sec; long tv_nsec; };

static long long nb_now_ms(void) {
    struct nb_timespec ts = { 0, 0 };
    clock_gettime(NB_CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000LL + (long long)ts.tv_nsec / 1000000LL;
}

static void nb_sleep_ms(long long ms) {
    if (ms <= 0) return;
    struct nb_timespec req;
    req.tv_sec  = (long)(ms / 1000);
    req.tv_nsec = (long)((ms % 1000) * 1000000L);
    nanosleep(&req, 0);
}

/* ── §3  Diagnosis ────────────────────────────────────────────────
 *
 * The one thing a cooperative runtime can say that a preemptive one
 * cannot. Reached only when the run queue is empty, no timer is armed,
 * and somebody is still waiting — a state from which no sequence of
 * events leads anywhere. Naming the primitive is most of the debugging:
 * "deadlock: mutex_lock" and "deadlock: cond_wait" are different bugs.
 */
static void nurl__bare_deadlock(const char *what) {
    fprintf(stderr,
            "nurl: deadlock in %s — no coroutine is runnable, no timer is "
            "pending, and the waited-for condition is still false\n", what);
    abort();
}

/* ── §4  Run queue and timers ─────────────────────────────────────── */

static void nb_rq_push(NbCoro *c) {
    c->next = 0;
    if (nb_rq_tail) nb_rq_tail->next = c;
    else            nb_rq_head = c;
    nb_rq_tail = c;
}

static NbCoro *nb_rq_pop(void) {
    NbCoro *c = nb_rq_head;
    if (!c) return 0;
    nb_rq_head = c->next;
    if (!nb_rq_head) nb_rq_tail = 0;
    c->next = 0;
    return c;
}

static void nb_timer_add(NbCoro *c, long long at) {
    c->wake_at_ms = at;
    NbCoro **pp = &nb_timers;
    while (*pp && (*pp)->wake_at_ms <= at) pp = &(*pp)->tnext;
    c->tnext = *pp;
    *pp = c;
}

/* Move every expired timer back to the run queue. Returns how many. */
static int nb_timers_expire(long long now) {
    int n = 0;
    while (nb_timers && nb_timers->wake_at_ms <= now) {
        NbCoro *c = nb_timers;
        nb_timers = c->tnext;
        c->tnext = 0;
        c->last_park_result = 0;      /* timeout, per the reactor ABI */
        c->state = NB_RUNNABLE;
        nb_rq_push(c);
        n++;
    }
    return n;
}

/* ── §5  Switching ────────────────────────────────────────────────── */

static void nb_swap_to_loop(NbCoro *c) {
#ifdef NURL_BARE_ASAN
    nurl_ctx_asan_start_switch(&c->fake_stack, nb_loop_lo, nb_loop_size);
#endif
    nurl_ctx_switch(&c->ctx, &nb_loop_ctx);
#ifdef NURL_BARE_ASAN
    nurl_ctx_asan_finish_switch(c->fake_stack, &nb_loop_lo, &nb_loop_size);
#endif
}

#ifdef NURL_BARE_ASAN
static void *nb_loop_fake;      /* the main context's fake stack */
#endif

static void nb_swap_to_coro(NbCoro *c) {
#ifdef NURL_BARE_ASAN
    nurl_ctx_asan_start_switch(&nb_loop_fake, c->stack_lo, c->stack_usable);
#endif
    nurl_ctx_switch(&nb_loop_ctx, &c->ctx);
#ifdef NURL_BARE_ASAN
    nurl_ctx_asan_finish_switch(nb_loop_fake, 0, 0);
#endif
}

/* Park the running coroutine. Callers have already put it on whatever
 * queue will wake it (or on none, for a join whose target wakes it). */
static void nb_park(void) {
    NbCoro *c = nb_current;
    c->state = NB_PARKED;
    nb_swap_to_loop(c);
}

/* ── §6  Coroutine lifecycle ──────────────────────────────────────── */

static void nb_entry(void *arg) {
    NbCoro *c = (NbCoro *)arg;
#ifdef NURL_BARE_ASAN
    nurl_ctx_asan_finish_switch(0, &nb_loop_lo, &nb_loop_size);
#endif
    if (c->fn) c->fn(c->env);
    c->finished = 1;
    c->state = NB_DONE;
#ifdef NURL_BARE_ASAN
    nurl_ctx_asan_start_switch(0, nb_loop_lo, nb_loop_size);
#endif
    nurl_ctx_switch(&c->ctx, &nb_loop_ctx);   /* never resumed */
    abort();                                  /* unreachable  */
}

static NbCoro *nb_coro_new(void *fn, void *env, int joinable) {
    NbCoro *c = (NbCoro *)calloc(1, sizeof(NbCoro));
    if (!c) return 0;

    unsigned long guard  = (NB_GUARD_BYTES + NB_PAGE - 1) / NB_PAGE * NB_PAGE;
    unsigned long usable = (NB_STACK_BYTES + NB_PAGE - 1) / NB_PAGE * NB_PAGE;
    unsigned long total  = guard + usable;

    void *base = mmap(0, total, NB_PROT_READ | NB_PROT_WRITE,
                      NB_MAP_PRIVATE | NB_MAP_ANONYMOUS, -1, 0);
    if (!base || base == (void *)-1) { free(c); return 0; }
    /* A guard page costs one syscall and turns the most common fiber
     * bug — stack overflow — from silent heap corruption into a fault
     * at the instruction that did it. Worth it even here, where a
     * SIGSEGV is all the diagnosis available. */
    if (mprotect(base, guard, NB_PROT_NONE) != 0) {
        munmap(base, total);
        free(c);
        return 0;
    }

    c->stack_base   = base;
    c->stack_total  = total;
    c->stack_lo     = (char *)base + guard;
    c->stack_usable = usable;
    c->fn           = (void (*)(void *))fn;
    c->env          = env;
    c->state        = NB_RUNNABLE;
    c->joinable     = joinable;
    nurl_ctx_init(&c->ctx, c->stack_lo, usable, nb_entry, c);
    nurl__bare_live_coros++;
    return c;
}

static void nb_coro_free(NbCoro *c) {
    if (!c) return;
    if (c->stack_base) munmap(c->stack_base, c->stack_total);
    free(c);
    nurl__bare_live_coros--;
}

/* The running coroutine's usable stack, or 0 on the main context.
 * Exported for unikernel/tests/sched_gate.c, which needs an address it
 * can prove is below the stack in order to show the guard page is
 * armed. Without it the "no guard page" mutation is unobservable: the
 * overflow runs off the bottom of the mapping and faults anyway, so the
 * test cannot tell a guarded stack from an unguarded one that happened
 * to have nothing below it. */
void *nurl__bare_stack_lo(void) {
    return nb_current ? nb_current->stack_lo : 0;
}

/* Wake everything blocked in join() on `c`. */
static void nb_wake_joiners(NbCoro *c) {
    NbCoro *j = c->joiners;
    c->joiners = 0;
    while (j) {
        NbCoro *n = j->next;
        j->next = 0;
        j->state = NB_RUNNABLE;
        nb_rq_push(j);
        j = n;
    }
}

/* ── §7  The scheduler step ───────────────────────────────────────
 *
 * The whole scheduler. Returns 1 if it made progress (ran a coroutine
 * or expired a timer), 0 if there is nothing left that could ever
 * happen — which is what makes deadlock detectable rather than a hang.
 *
 * Only the main context may call this: it switches through
 * nb_loop_ctx, and a coroutine calling it would overwrite the very
 * context it must return through. Everything that could block from
 * inside a coroutine parks instead. */
static int nurl__bare_step(void) {
    NbCoro *c = nb_rq_pop();
    if (!c) {
        if (!nb_timers) return 0;
        long long now = nb_now_ms();
        if (nb_timers->wake_at_ms > now) {
            /* Nothing runnable and the earliest wake-up is in the
             * future: this is the only place the machine is allowed to
             * be idle, and the only place a real sleep is correct. */
            nb_sleep_ms(nb_timers->wake_at_ms - now);
            now = nb_now_ms();
        }
        return nb_timers_expire(now) > 0;
    }

    c->state = NB_RUNNING;
    nb_current = c;
    nb_swap_to_coro(c);
    nb_current = 0;

    if (c->state == NB_DONE) {
        nb_wake_joiners(c);
        nb_live--;
        if (!c->joinable) nb_coro_free(c);
        /* joinable: the joiner frees it, so the handle stays valid */
    } else if (c->state == NB_PARKED) {
        /* The cond_wait handoff: release the caller's mutex only after
         * the switch has completed. Under one context nothing can
         * observe the gap, but doing it here keeps the shape identical
         * to the hosted runtime, where it is load-bearing — and keeps
         * the two files readable side by side. */
        void *pm = c->pending_unlock;
        c->pending_unlock = 0;
        if (pm) nurl__bare_mutex_release(pm);
    } else {
        c->state = NB_RUNNABLE;
        nb_rq_push(c);
    }
    return 1;
}

/* Drive the scheduler until `pred(arg)` holds. Main context only. */
static void nb_drive_until(int (*pred)(void *), void *arg, const char *what) {
    while (!pred(arg)) {
        if (!nurl__bare_step()) nurl__bare_deadlock(what);
    }
}

/* ── §8  Mutexes ──────────────────────────────────────────────────
 *
 * Laid out to fit inside whatever `nurl_native_sizeof("pthread_mutex_t")`
 * reported to the NURL side (cell.nu allocates that many bytes), and to
 * be VALID WHEN ZEROED, because PTHREAD_MUTEX_INITIALIZER is a zeroed
 * struct and code that uses it never calls pthread_mutex_init. Zero =
 * unlocked, empty wait queue, which is exactly the initial state. */
typedef struct NbMutex {
    int      locked;
    int      pad;
    NbCoro  *wq_head;
    NbCoro  *wq_tail;
} NbMutex;

/* The NURL side sizes its Cell from nurl_native_sizeof("pthread_mutex_t"),
 * which runtime_core.c answers from the C compiler's own <pthread.h> —
 * 40 bytes for glibc/x86_64, 48 for pthread_cond_t, 8 for pthread_t.
 * These bounds are what makes overwriting the caller's allocation
 * impossible; unikernel/tests/pthread_layout.c is the gate that checks
 * them against the real header rather than against this comment. */
_Static_assert(sizeof(NbMutex) <= 40, "NbMutex must fit a pthread_mutex_t");

static void nb_wq_push(NbCoro **head, NbCoro **tail, NbCoro *c) {
    c->next = 0;
    if (*tail) (*tail)->next = c;
    else       *head = c;
    *tail = c;
}

static NbCoro *nb_wq_pop(NbCoro **head, NbCoro **tail) {
    NbCoro *c = *head;
    if (!c) return 0;
    *head = c->next;
    if (!*head) *tail = 0;
    c->next = 0;
    return c;
}

/* Hand the mutex to the next waiter, or leave it free. Shared by
 * pthread_mutex_unlock and the parked-with-mutex handoff in §7. */
void nurl__bare_mutex_release(void *mp) {
    NbMutex *m = (NbMutex *)mp;
    if (!m) return;
    m->locked = 0;
    NbCoro *w = nb_wq_pop(&m->wq_head, &m->wq_tail);
    if (w) { w->state = NB_RUNNABLE; nb_rq_push(w); }
}

static int nb_mutex_free_pred(void *mp) { return !((NbMutex *)mp)->locked; }

int pthread_mutex_init(void *mp, void *attr) {
    (void)attr;
    NbMutex *m = (NbMutex *)mp;
    if (!m) return 22;                       /* EINVAL */
    m->locked = 0; m->pad = 0;
    m->wq_head = m->wq_tail = 0;
    return 0;
}

int pthread_mutex_lock(void *mp) {
    NbMutex *m = (NbMutex *)mp;
    if (!m) return 22;
    if (nb_current) {
        while (m->locked) {
            nb_wq_push(&m->wq_head, &m->wq_tail, nb_current);
            nb_park();
            /* Woken by a release — but re-test, because main may have
             * taken the mutex in between. */
        }
    } else {
        nb_drive_until(nb_mutex_free_pred, m, "mutex_lock");
    }
    m->locked = 1;
    return 0;
}

int pthread_mutex_trylock(void *mp) {
    NbMutex *m = (NbMutex *)mp;
    if (!m) return 22;
    if (m->locked) return 16;                /* EBUSY */
    m->locked = 1;
    return 0;
}

int pthread_mutex_unlock(void *mp) {
    if (!mp) return 22;
    nurl__bare_mutex_release(mp);
    return 0;
}

int pthread_mutex_destroy(void *mp) {
    NbMutex *m = (NbMutex *)mp;
    if (!m) return 22;
    if (m->wq_head) return 16;               /* EBUSY — waiters remain */
    m->locked = 0;
    return 0;
}

/* ── §9  Condition variables ──────────────────────────────────────
 *
 * Fiber waiters queue; the main context cannot queue (§ header), so it
 * watches a sequence number instead. Snapshot-then-drive is race-free
 * for the same reason everything else here is: between the snapshot and
 * the first scheduler step, nothing runs. */
typedef struct NbCond {
    NbCoro            *wq_head;
    NbCoro            *wq_tail;
    unsigned long long seq;          /* bumped for a waiting main only */
    int                main_waiters;
    int                pad;
} NbCond;

_Static_assert(sizeof(NbCond)  <= 48, "NbCond must fit a pthread_cond_t");
_Static_assert(sizeof(NbCoro *) <= 8, "pthread_t must hold a coroutine handle");

/* Published so unikernel/tests/pthread_layout.c can compare them with
 * the real <pthread.h> instead of with the numbers in the comment
 * above. A build that cannot include pthread.h cannot check itself —
 * which is exactly the position the unikernel target will be in, so the
 * check has to happen on the host, from the outside. */
const unsigned long nurl__bare_sizeof_mutex = sizeof(NbMutex);
const unsigned long nurl__bare_sizeof_cond  = sizeof(NbCond);
const unsigned long nurl__bare_sizeof_coro  = sizeof(NbCoro *);

int pthread_cond_init(void *cp, void *attr) {
    (void)attr;
    NbCond *c = (NbCond *)cp;
    if (!c) return 22;
    c->wq_head = c->wq_tail = 0;
    c->seq = 0;
    c->main_waiters = 0;
    c->pad = 0;
    return 0;
}

int pthread_cond_destroy(void *cp) {
    NbCond *c = (NbCond *)cp;
    if (!c) return 22;
    if (c->wq_head || c->main_waiters) return 16;   /* EBUSY */
    return 0;
}

typedef struct { NbCond *c; unsigned long long seq; } NbCondWatch;
static int nb_cond_fired(void *wp) {
    NbCondWatch *w = (NbCondWatch *)wp;
    return w->c->seq != w->seq;
}

int pthread_cond_wait(void *cp, void *mp) {
    NbCond  *c = (NbCond *)cp;
    NbMutex *m = (NbMutex *)mp;
    if (!c || !m) return 22;

    if (nb_current) {
        nb_wq_push(&c->wq_head, &c->wq_tail, nb_current);
        /* Release the mutex on the far side of the switch — see §7. */
        nb_current->pending_unlock = m;
        nb_park();
        return pthread_mutex_lock(m);
    }
    NbCondWatch w;
    w.c = c;
    w.seq = c->seq;
    c->main_waiters++;
    nurl__bare_mutex_release(m);
    nb_drive_until(nb_cond_fired, &w, "cond_wait");
    c->main_waiters--;
    return pthread_mutex_lock(m);
}

int pthread_cond_signal(void *cp) {
    NbCond *c = (NbCond *)cp;
    if (!c) return 22;
    NbCoro *w = nb_wq_pop(&c->wq_head, &c->wq_tail);
    if (w) {
        w->state = NB_RUNNABLE;
        nb_rq_push(w);
    } else if (c->main_waiters) {
        c->seq++;
    }
    return 0;
}

int pthread_cond_broadcast(void *cp) {
    NbCond *c = (NbCond *)cp;
    if (!c) return 22;
    NbCoro *w;
    while ((w = nb_wq_pop(&c->wq_head, &c->wq_tail)) != 0) {
        w->state = NB_RUNNABLE;
        nb_rq_push(w);
    }
    if (c->main_waiters) c->seq++;
    return 0;
}

/* ── §10  Threads ─────────────────────────────────────────────────
 *
 * A NURL thread is a coroutine that nobody runs until someone blocks.
 * That is the honest cooperative meaning of "spawn": the work happens,
 * in full, at the first join or blocking call. Programs whose goldens
 * depend on a particular interleaving were already non-deterministic
 * under real threads, so nothing that passes hosted can depend on it.
 *
 * pthread_t is a pointer here; runtime_core.c reports
 * sizeof(pthread_t) to the NURL side, and every platform this targets
 * has it at least pointer-sized. */

int pthread_create(void *tp, void *attr, void *start, void *arg) {
    (void)attr;
    if (!tp || !start) return 22;
    NbCoro *c = nb_coro_new(start, arg, 1);
    if (!c) return 11;                       /* EAGAIN */
    nb_live++;
    nb_rq_push(c);
    *(void **)tp = c;
    return 0;
}

static int nb_coro_finished(void *cp) { return ((NbCoro *)cp)->finished; }

static int nb_join(NbCoro *c) {
    if (!c) return 22;
    if (!c->finished) {
        if (nb_current) {
            /* Head push: POSIX leaves the order among joiners
             * unspecified, and joining one thread from two places is
             * already undefined, so a tail pointer would buy nothing. */
            nb_current->next = c->joiners;
            c->joiners = nb_current;
            nb_park();
        } else {
            nb_drive_until(nb_coro_finished, c, "thread_join");
        }
    }
    nb_coro_free(c);
    return 0;
}

int pthread_join(void *t, void **retval) {
    if (retval) *retval = 0;
    return nb_join((NbCoro *)t);
}

int nurl_pthread_join_ptr(void *tp) {
    if (!tp) return -1;
    return nb_join(*(NbCoro **)tp);
}

/* Detach: the coroutine reaps itself when its body returns. It may
 * already have finished (nothing runs it before a blocking call, but a
 * program can yield between spawn and detach), in which case it is
 * sitting DONE and joinable, waiting for exactly this. */
static void nb_detach(NbCoro *c) {
    if (!c) return;
    if (c->finished) nb_coro_free(c);
    else             c->joinable = 0;
}

int pthread_detach(void *t) { nb_detach((NbCoro *)t); return 0; }

void nurl_pthread_detach_ptr(void *tp) {
    if (tp) nb_detach(*(NbCoro **)tp);
}

void *pthread_self(void) {
    /* Main is not a coroutine and has no NbCoro. It still needs an
     * identity distinct from every real one, and distinct from NULL,
     * which callers read as "no thread". */
    return nb_current ? (void *)nb_current : (void *)(unsigned long)1;
}

int pthread_equal(void *a, void *b) { return a == b; }

void pthread_exit(void *retval) {
    (void)retval;
    NbCoro *c = nb_current;
    if (!c) exit(0);      /* POSIX: exiting the last thread ends the process */
    c->finished = 1;
    c->state = NB_DONE;
    nurl_ctx_switch(&c->ctx, &nb_loop_ctx);
    abort();                                 /* unreachable */
}

/* ── §11  The fiber API (stdlib/std/async.nu) ─────────────────────
 *
 * Same contracts as the M:N runtime in runtime_ffi.c §24, so the NURL
 * side is unchanged. What differs is only what "concurrently" means. */

void nurl_runtime_init(long long worker_count) {
    /* One vCPU: the worker count is not a tuning knob here, it is a
     * fact. Accepted and ignored rather than rejected, so the same NURL
     * program runs on both targets. */
    (void)worker_count;
    nb_initialized = 1;
}

static int nb_no_live(void *unused) { (void)unused; return nb_live <= 0; }

void nurl_runtime_run(void) {
    if (!nb_initialized) nurl_runtime_init(0);
    nb_drive_until(nb_no_live, 0, "runtime_run");
}

void nurl_runtime_shutdown(void) {
    /* Drop whatever never ran. A coroutine still queued when the
     * program says it is done is not an error, but its 64 KB stack
     * should go back.
     *
     * Joinable ones are left alone: their handle is still in a NURL
     * value somewhere and join() frees them, so reclaiming here would
     * be the double free. Coroutines parked on a mutex or condvar are
     * left too — they are reachable only from the object they wait on,
     * and walking every such object to reclaim 64 KB during teardown
     * would cost more than it returns. The hosted runtime abandons
     * both classes as well; the difference is only that this one says
     * so. */
    NbCoro *c, *keep = 0;
    while ((c = nb_rq_pop()) != 0) {
        if (c->joinable) { c->next = keep; keep = c; }
        else             nb_coro_free(c);
    }
    while (keep) { c = keep; keep = keep->next; nb_rq_push(c); }
    NbCoro *t = nb_timers;
    nb_timers = 0;
    while (t) {
        NbCoro *n = t->tnext;
        t->tnext = 0;
        if (t->joinable) nb_rq_push(t);
        else             nb_coro_free(t);
        t = n;
    }
    nb_live = 0;
    nb_initialized = 0;
}

long long nurl_fiber_spawn(void *fn, void *env) {
    if (!fn) return 0;
    if (!nb_initialized) nurl_runtime_init(0);
    NbCoro *c = nb_coro_new(fn, env, 0);
    if (!c) return 0;
    nb_live++;
    nb_rq_push(c);
    return (long long)(unsigned long)c;
}

long long nurl_fiber_spawn_joinable(void *fn, void *env) {
    if (!fn) return 0;
    if (!nb_initialized) nurl_runtime_init(0);
    NbCoro *c = nb_coro_new(fn, env, 1);
    if (!c) return 0;
    nb_live++;
    nb_rq_push(c);
    return (long long)(unsigned long)c;
}

void nurl_fiber_yield(void) {
    if (nb_current) {
        nb_current->state = NB_RUNNABLE;
        nb_swap_to_loop(nb_current);
        return;
    }
    /* From main, "yield" means the same thing it means anywhere else:
     * let something else run. The hosted runtime returns immediately
     * because other OS threads are already running; here nothing is,
     * so a step IS the yield. Nothing can rely on the no-op — the
     * hosted contract is "may return without doing anything". */
    nurl__bare_step();
}

long long nurl_fiber_current(void) { return (long long)(unsigned long)nb_current; }

long long nurl_fiber_worker_id(void) { return nb_current ? 0 : -1; }

void nurl_fiber_park_with_mutex(long long mutex_h) {
    if (!nb_current) return;             /* same as hosted: no-op off-fiber */
    nb_current->pending_unlock = (void *)(unsigned long)mutex_h;
    nb_park();
}

void nurl_fiber_unpark(long long h) {
    NbCoro *c = (NbCoro *)(unsigned long)h;
    if (!c) return;
    c->state = NB_RUNNABLE;
    nb_rq_push(c);
}

void nurl_fiber_join(long long h) {
    NbCoro *c = (NbCoro *)(unsigned long)h;
    if (!c || !c->joinable) return;
    nb_join(c);
}

/* ── §12  Sleep ───────────────────────────────────────────────────
 *
 * The reactor ABI: 1 = the fd was ready, 0 = the deadline passed,
 * -1 = not on a fiber. sleep_ms always answers 0. Only the timer half
 * exists in this file — see the header on why the fd half is a link
 * error rather than a stub. */

long long nurl_fiber_sleep_ms(long long ms) {
    if (ms <= 0) { nurl_fiber_yield(); return 0; }
    long long deadline = nb_now_ms() + ms;
    if (nb_current) {
        nb_timer_add(nb_current, deadline);
        nb_park();
        return 0;
    }
    /* Main: run whatever is runnable while the clock catches up, and
     * only actually sleep when nothing is. A busy-wait here would burn
     * the one CPU the guest has. */
    for (;;) {
        long long now = nb_now_ms();
        if (now >= deadline) return 0;
        if (!nurl__bare_step()) nb_sleep_ms(deadline - now);
    }
}

/* ── §13  Entropy ─────────────────────────────────────────────────
 *
 * The plan's rule for this one is absolute: no entropy source → panic
 * at boot, no degraded path. The hosted runtime keeps an LCG fallback
 * for ancient kernels; here the caller is a TLS handshake or a Noise
 * key on a machine nobody can log into, and a weak key that reports
 * success is precisely the hole a "later TODO" leaves behind.
 *
 * Returns 1 or does not return. */
long long nurl_rand_fill(unsigned char *buf, long long n) {
    if (!buf || n <= 0) return 0;
    unsigned long want = (unsigned long)n, got = 0;
    while (got < want) {
        long long r = getrandom(buf + got, want - got, 0);
        if (r < 0) {
            if (*__errno_location() == 4 /* EINTR */) continue;
            fprintf(stderr, "nurl: no entropy source (getrandom failed) — "
                            "refusing to generate keys\n");
            abort();
        }
        if (r == 0) {                 /* cannot happen; would spin if it did */
            fprintf(stderr, "nurl: entropy source returned no bytes\n");
            abort();
        }
        got += (unsigned long)r;
    }
    return 1;
}
