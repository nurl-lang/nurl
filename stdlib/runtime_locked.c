/* stdlib/runtime_locked.c — the lock of a `Locked` (stdlib/std/thread.nu).
 *
 * Included, not compiled on its own: by stdlib/runtime.c after
 * runtime_ffi.c (the hosted M:N runtime) and by unikernel/runtime_bare.c
 * (the cooperative one). The includer defines, before the #include:
 *
 *   NURL_LK_MUTEX_T   its mutex type (pthread_mutex_t / NbMutex), driven
 *                     through pthread_mutex_init / _lock / _unlock / _destroy
 *   NURL_LK_COND_T    its condition variable (NurlFCond / NbCond), driven
 *                     through nurl_fcond_init / _wait_ms / _signal /
 *                     _broadcast / _destroy: a fiber that waits parks
 *   NURL_LK_HOLDER_T  the holder record type (NurlRwHolder / NbRwHolder)
 *   NURL_LK_ME()      the running holder's record: a thread's, or a
 *                     fiber's (a coroutine's) — the RwLocked one
 *
 * and, where an OS thread can sleep on a word (Linux's futex), also
 *
 *   NURL_LK_IN_FIBER()        is the caller a fiber (which must park, not
 *                             sleep its worker)?
 *   nurl__lk_futex_wait(a, v) sleep while the int at `a` is `v`
 *   nurl__lk_futex_wake(a)    wake one sleeper on `a`
 *
 * Without them every waiter goes the counted way below. And, optionally,
 *
 *   NURL_LK_SINGLE()   no other OS thread exists now (glibc's
 *                      __libc_single_threaded): the word needs no locked
 *                      instruction, as glibc's own mutex then uses none
 *
 * A Locked's value is CHECKED OUT, as A3.2 models it (formal/A3/DESIGN.md:
 * `withLock` takes the payload out of the lock block, `scopeL` gives it
 * back). The lock is a state word: free, held in place by one holder
 * (locked_with / _update / _apply / _await / _get / _set run on the value
 * where it lies), or checked out (locked_take, until locked_restore). The
 * mutex below guards only the waiting; nobody holds it while the value is
 * used. It used to be held for the whole of the caller's closure, and that
 * went wrong three ways (agora #455):
 *
 *   - a nested locked_* on the same Locked relocked a default pthread
 *     mutex from the thread that held it. POSIX leaves that undefined:
 *     glibc and Windows wait forever, and FreeBSD's default mutex is the
 *     error-checking one, so the second lock returned EDEADLK, which went
 *     unread, and the inner closure ran on the value the outer one was
 *     still using;
 *   - a fiber that parked inside the closure (a channel, a socket) kept
 *     its worker's OS mutex: another fiber on that worker asking for the
 *     Locked stopped the whole worker, the holder included (the deadlock
 *     agora #255 removed from Cond);
 *   - a parked fiber may resume on another worker, which then unlocked
 *     a mutex it never locked.
 *
 * Now a holder that asks for a Locked it holds in place panics, naming
 * the call (the model's `Step.waitPanic`: a thread that would wait for
 * itself may panic instead), and another thread or fiber waits on a
 * condition variable that parks fibers. The fast path is what a pthread
 * mutex's is: one compare-and-swap in, one exchange out.
 *
 * The state word says what the lock is (free, held in place, taken out),
 * who holds it in place (the holder record's address: it is 8-aligned, so
 * the low three bits are free for the rest), and has one bit more,
 * NURL_LK_WAIT: someone may be waiting. A release is one exchange, and the
 * old word says whether to look. Two kinds of waiter set the bit:
 *
 *   - an OS thread, where it can sleep on the word (Linux's futex), as a
 *     pthread mutex's waiter does: it sets the bit with a compare-and-swap
 *     against the held word it saw, and sleeps while the word is that. Had
 *     the holder let go in between, the swap fails and it takes the lock;
 *     had it not, the release sees the bit and wakes one sleeper. A
 *     sleeper takes the lock with the bit set (others may sleep still);
 *   - everyone else (a fiber, which must park rather than stop its worker;
 *     an awaiter; any waiter without a futex) is counted under the mutex,
 *     in `nslow` too, before it sets the bit, and waits on a condition
 *     variable that parks fibers. A release that saw the bit reads `nslow`
 *     after its exchange (both sequentially consistent: the count comes
 *     first in the single order), and when it is not zero takes the mutex,
 *     puts the bit back while any counted waiter is left, and wakes. The
 *     waiter keeps the mutex from its swap to its wait, so the wake cannot
 *     come first.
 *
 * A contended waiter spins a few tries first (NURL_LK_SPIN), taking a lock
 * that comes free with the bit kept. */

#ifndef NURL_TLS_FN
#  define NURL_TLS_FN __attribute__((noinline))
#endif

typedef __UINTPTR_TYPE__ nurl_lk_word;
_Static_assert(_Alignof(NURL_LK_HOLDER_T) >= 8, "a Locked's word keeps three bits under the holder record's address");
#define NURL_LK_FREE  ((nurl_lk_word)0)
#define NURL_LK_HELD  ((nurl_lk_word)1)   /* held in place, by the record in the high bits */
#define NURL_LK_TAKEN ((nurl_lk_word)2)   /* checked out (locked_take); no holder recorded */
#define NURL_LK_KIND  ((nurl_lk_word)3)
#define NURL_LK_WAIT  ((nurl_lk_word)4)   /* someone may be waiting: look */
#define NURL_LK_WHO   (~(nurl_lk_word)7)
#ifndef NURL_LK_SPIN
#  define NURL_LK_SPIN 20    /* tries before a contended waiter sleeps (measured: 0, 20, 200) */
#endif

typedef struct {
    nurl_lk_word      state;
    int               nslow;       /* nenter + nchange, read without `m`  */
    int               nenter;      /* counted waiters for the lock } `m`  */
    int               nchange;     /* waiting for a change         }      */
    int               pad_;
    long long         gen;         /* changes seen by waiters (under `m`) */
    NURL_LK_MUTEX_T   m;           /* the waiting's, held for a few loads */
    NURL_LK_COND_T    enter_cv;    /* the lock is free                    */
    NURL_LK_COND_T    change_cv;   /* the value changed                   */
} NurlLk;

long long nurl_lk_size(void) { return (long long)sizeof(NurlLk); }

void nurl_lk_init(void *l) {
    NurlLk *k = (NurlLk *)l;
    k->state = NURL_LK_FREE;
    k->nslow = k->nenter = k->nchange = 0;
    k->gen = 0;
    pthread_mutex_init(&k->m, 0);
    nurl_fcond_init(&k->enter_cv);
    nurl_fcond_init(&k->change_cv);
}

void nurl_lk_destroy(void *l) {
    NurlLk *k = (NurlLk *)l;
    if (!k) return;   /* locked_zero's block before its latch is set */
    nurl_fcond_destroy(&k->change_cv);
    nurl_fcond_destroy(&k->enter_cv);
    pthread_mutex_destroy(&k->m);
}

/* "nurl: <op>: <why>" without a formatter (the unikernel has none to
 * spare). */
__attribute__((noinline, cold)) static void nurl__lk_failed(const char *op, const char *why) {
    char msg[256];
    unsigned n = 0;
    const char *parts[4] = { "nurl: ", op ? op : "a Locked", ": ", why };
    for (int p = 0; p < 4; p++)
        for (const char *s = parts[p]; *s && n < sizeof msg - 1; s++) msg[n++] = *s;
    msg[n] = 0;
    nurl_panic(msg);
}
#define NURL__LK_SELF_HELD "this thread already holds the Locked (a nested locked_* call on it would wait for itself)"

static inline void nurl__lk_relax(void) {
#if defined(__x86_64__) || defined(__i386__)
    __builtin_ia32_pause();
#elif defined(__aarch64__)
    __asm__ __volatile__("yield");
#endif
}

static inline int nurl__lk_cas(NurlLk *k, nurl_lk_word *cur, nurl_lk_word to) {
    return __atomic_compare_exchange_n(&k->state, cur, to, 0, __ATOMIC_ACQ_REL, __ATOMIC_RELAXED);
}

/* The word a holder asking for the lock writes: itself, held in place;
 * or a check-out, with no holder. */
static inline nurl_lk_word nurl__lk_mine(NURL_LK_HOLDER_T *me, nurl_lk_word kind) {
    return kind == NURL_LK_HELD ? ((nurl_lk_word)me | NURL_LK_HELD) : kind;
}

/* Held in place by `me`: a wait for itself. */
static inline int nurl__lk_self(nurl_lk_word cur, NURL_LK_HOLDER_T *me) {
    return (cur & NURL_LK_KIND) == NURL_LK_HELD && (cur & NURL_LK_WHO) == (nurl_lk_word)me;
}

#if defined(NURL_LK_FUTEX)
/* The int of the state word that holds the low bits (kind, WAIT). */
static inline int *nurl__lk_low(NurlLk *k) {
    int *w = (int *)&k->state;
#  if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    w += sizeof(nurl_lk_word) / sizeof(int) - 1;
#  endif
    return w;
}
#endif

/* Contended: spin a little (a holder about to let go is cheaper to wait
 * for than a sleep and a wake), then wait.
 *
 * An OS thread, where it can, sleeps on the state word itself, as a pthread
 * mutex's waiter does: it sets WAIT against the held word it saw and
 * sleeps while the word is that, and takes the lock with WAIT set (others
 * may sleep still; a release that finds nobody is one wasted wake). It is
 * not counted. A fiber, which must park rather than stop its worker, and
 * everyone where there is no such sleep, is counted under the mutex and
 * waits on `enter_cv`. */
__attribute__((noinline)) static void nurl__lk_wait_free(NurlLk *k, nurl_lk_word to, NURL_LK_HOLDER_T *me, const char *op) {
    for (int i = 0; i < NURL_LK_SPIN; i++) {
        nurl_lk_word cur = __atomic_load_n(&k->state, __ATOMIC_RELAXED);
        /* Free: take it, keeping the waiter bit, so this holder's release
         * wakes whoever sleeps. */
        if ((cur & NURL_LK_KIND) == NURL_LK_FREE && nurl__lk_cas(k, &cur, to | (cur & NURL_LK_WAIT))) return;
        if (nurl__lk_self(cur, me)) break;
        nurl__lk_relax();
    }
#if defined(NURL_LK_FUTEX)
    if (!NURL_LK_IN_FIBER()) {
        for (;;) {
            nurl_lk_word cur = __atomic_load_n(&k->state, __ATOMIC_RELAXED);
            if ((cur & NURL_LK_KIND) == NURL_LK_FREE) {
                if (nurl__lk_cas(k, &cur, to | NURL_LK_WAIT)) return;
                continue;
            }
            if (nurl__lk_self(cur, me)) nurl__lk_failed(op, NURL__LK_SELF_HELD);
            if (!(cur & NURL_LK_WAIT) && !nurl__lk_cas(k, &cur, cur | NURL_LK_WAIT)) continue;
            nurl__lk_futex_wait(nurl__lk_low(k), (int)(unsigned)(cur | NURL_LK_WAIT));
        }
    }
#endif
    pthread_mutex_lock(&k->m);
    k->nenter++;
    __atomic_add_fetch(&k->nslow, 1, __ATOMIC_SEQ_CST);
    for (;;) {
        nurl_lk_word cur = __atomic_load_n(&k->state, __ATOMIC_SEQ_CST);
        if ((cur & NURL_LK_KIND) == NURL_LK_FREE) {
            /* Others counted, or sleepers on the word (its WAIT): keep the bit. */
            int others = k->nenter - 1 + k->nchange > 0;
            if (nurl__lk_cas(k, &cur, to | (others ? NURL_LK_WAIT : (cur & NURL_LK_WAIT)))) break;
            continue;
        }
        if (nurl__lk_self(cur, me)) {
            k->nenter--;
            __atomic_sub_fetch(&k->nslow, 1, __ATOMIC_SEQ_CST);
            pthread_mutex_unlock(&k->m);
            nurl__lk_failed(op, NURL__LK_SELF_HELD);
        }
        if (!(cur & NURL_LK_WAIT) && !nurl__lk_cas(k, &cur, cur | NURL_LK_WAIT)) continue;
        nurl_fcond_wait_ms(&k->enter_cv, &k->m, -1);
    }
    k->nenter--;
    __atomic_sub_fetch(&k->nslow, 1, __ATOMIC_SEQ_CST);
    pthread_mutex_unlock(&k->m);
}

/* Take the lock: `kind` is NURL_LK_HELD (use the value in place) or
 * NURL_LK_TAKEN (check it out). Waits while another holder has it;
 * panics when this one holds it in place. A check-out records no holder:
 * the value may go to another thread, which restores it (a second take
 * by the taker waits for that restore, as it always did). */
static inline void nurl__lk_acquire(NurlLk *k, nurl_lk_word kind, const char *op) {
    NURL_LK_HOLDER_T *me = NURL_LK_ME();
    nurl_lk_word to = nurl__lk_mine(me, kind);
    nurl_lk_word cur = NURL_LK_FREE;
#if defined(NURL_LK_SINGLE)
    /* One thread: nothing else reads or writes the word meanwhile (a fiber
     * of this thread runs only where this one parks). */
    if (NURL_LK_SINGLE()) {
        cur = __atomic_load_n(&k->state, __ATOMIC_RELAXED);
        if (__builtin_expect(cur == NURL_LK_FREE, 1)) { __atomic_store_n(&k->state, to, __ATOMIC_RELAXED); return; }
    } else
#endif
    if (__builtin_expect(__atomic_compare_exchange_n(&k->state, &cur, to, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED), 1)) return;
    {
        if (nurl__lk_self(cur, me)) nurl__lk_failed(op, NURL__LK_SELF_HELD);
        nurl__lk_wait_free(k, to, me, op);
    }
}

/* A release that saw the waiter bit: wake a sleeper on the word, and the
 * counted waiters, if any. A counted waiter counts itself (`nslow`, in the
 * single order) before it sets WAIT on the state word, and the release
 * exchanged the word before it reads the count: a release that saw the bit
 * sees the count. */
__attribute__((noinline)) static void nurl__lk_wake(NurlLk *k, long long changed) {
#if defined(NURL_LK_FUTEX)
    nurl__lk_futex_wake(nurl__lk_low(k));
#endif
    if (__atomic_load_n(&k->nslow, __ATOMIC_SEQ_CST) == 0) return;
    pthread_mutex_lock(&k->m);
    if (k->nenter + k->nchange > 0) __atomic_or_fetch(&k->state, NURL_LK_WAIT, __ATOMIC_SEQ_CST);
    if (k->nenter) nurl_fcond_signal(&k->enter_cv);
    if (changed && k->nchange) { k->gen++; nurl_fcond_broadcast(&k->change_cv); }
    pthread_mutex_unlock(&k->m);
}

/* Let it go; `changed`: the value may be different now, so the awaiters
 * look again. */
static inline void nurl__lk_release(NurlLk *k, long long changed) {
    nurl_lk_word old;
#if defined(NURL_LK_SINGLE)
    if (NURL_LK_SINGLE()) {
        old = __atomic_load_n(&k->state, __ATOMIC_RELAXED);
        __atomic_store_n(&k->state, NURL_LK_FREE, __ATOMIC_RELAXED);
    } else
#endif
    old = __atomic_exchange_n(&k->state, NURL_LK_FREE, __ATOMIC_SEQ_CST);
    if (__builtin_expect(old & NURL_LK_WAIT, 0)) nurl__lk_wake(k, changed);
}

NURL_TLS_FN void nurl_lk_enter(void *l, const char *op)  { nurl__lk_acquire((NurlLk *)l, NURL_LK_HELD, op); }
void nurl_lk_exit(void *l, long long changed)              { nurl__lk_release((NurlLk *)l, changed); }
NURL_TLS_FN void nurl_lk_take(void *l, const char *op)   { nurl__lk_acquire((NurlLk *)l, NURL_LK_TAKEN, op); }

/* The last share's drop (Locked_drop): 1 when the value is checked out
 * (locked_take, never restored), so its slot holds zero bytes nobody owns
 * and only the latch is released — running the value's drop glue there
 * ran a `% Drop` type's destructor a second time, on zeros (agora #795).
 * Asked by the last owner only: nobody else can change the word. */
long long nurl_lk_taken(void *l) {
    nurl_lk_word cur = __atomic_load_n(&((NurlLk *)l)->state, __ATOMIC_ACQUIRE);
    return (cur & NURL_LK_KIND) == NURL_LK_TAKEN;
}

/* locked_restore: 1 when the value was checked out — it is now held in
 * place by the restorer, which puts it back and calls nurl_lk_exit; 0 when
 * it was not taken (the caller panics). Any thread may restore. */
NURL_TLS_FN long long nurl_lk_restore_begin(void *l) {
    NurlLk *k = (NurlLk *)l;
    nurl_lk_word mine = nurl__lk_mine(NURL_LK_ME(), NURL_LK_HELD);
    nurl_lk_word cur = __atomic_load_n(&k->state, __ATOMIC_RELAXED);
    do {
        if ((cur & NURL_LK_KIND) != NURL_LK_TAKEN) return 0;
    } while (!nurl__lk_cas(k, &cur, mine | (cur & NURL_LK_WAIT)));
    return 1;
}

/* locked_await between two runs of its closure: let the lock go (the run
 * may have changed the value: `changed`), wait until another holder
 * changes it, and take the lock again (through nurl_lk_enter, which reads
 * the running holder afresh: the fiber may wake on another worker). */
void nurl_lk_await(void *l, long long changed, const char *op) {
    NurlLk *k = (NurlLk *)l;
    pthread_mutex_lock(&k->m);
    k->nchange++;
    __atomic_add_fetch(&k->nslow, 1, __ATOMIC_SEQ_CST);
    if (changed && k->nchange > 1) { k->gen++; nurl_fcond_broadcast(&k->change_cv); }
    long long g = k->gen;
    /* Let go, the waiter bit set: this one waits now. */
    nurl_lk_word old = __atomic_exchange_n(&k->state, NURL_LK_FREE | NURL_LK_WAIT, __ATOMIC_SEQ_CST);
#if defined(NURL_LK_FUTEX)
    if (old & NURL_LK_WAIT) nurl__lk_futex_wake(nurl__lk_low(k));
#else
    (void)old;
#endif
    if (k->nenter) nurl_fcond_signal(&k->enter_cv);
    while (k->gen == g) nurl_fcond_wait_ms(&k->change_cv, &k->m, -1);
    k->nchange--;
    __atomic_sub_fetch(&k->nslow, 1, __ATOMIC_SEQ_CST);
    pthread_mutex_unlock(&k->m);
    nurl_lk_enter(l, op);
}

/* ── A Mutex (stdlib/std/thread.nu) ───────────────────────────────────
 * A pthread mutex of the ERRORCHECK type, asked for by name. The default
 * type leaves a relock by the holder, and an unlock by a thread that does
 * not hold it, undefined (FreeBSD's default checks, glibc's does not:
 * agora #455). Checked, each is an error, and the error panics instead of
 * going on as if the lock were held or let go: the model's thread that
 * would wait for itself may panic (`Step.waitPanic`). The MSVC-target
 * shim's SRWLOCK and WASI's one thread have no such type, and keep their
 * own (a relock waits). */
int nurl_mutex_init(void *m) {
#if defined(NURL_LK_MUTEX_ERRORCHECK)
    pthread_mutexattr_t a;
    pthread_mutexattr_init(&a);
    pthread_mutexattr_settype(&a, PTHREAD_MUTEX_ERRORCHECK);
    int rc = pthread_mutex_init(m, &a);
    pthread_mutexattr_destroy(&a);
    return rc;
#else
    return pthread_mutex_init(m, 0);
#endif
}

__attribute__((noinline, cold)) static void nurl__mutex_failed(const char *op, int rc) {
#if defined(NURL_LK_MUTEX_ERRORCHECK)
    if (rc == EDEADLK) nurl__lk_failed(op, "this thread already holds the Mutex (it would wait for itself)");
    if (rc == EPERM)   nurl__lk_failed(op, "this thread does not hold the Mutex");
#endif
    (void)rc;
    nurl__lk_failed(op, "the mutex call failed");
}

void nurl_mutex_lock(void *m) {
    int rc = pthread_mutex_lock(m);
    if (__builtin_expect(rc != 0, 0)) nurl__mutex_failed("mutex_lock", rc);
}

void nurl_mutex_unlock(void *m) {
    int rc = pthread_mutex_unlock(m);
    if (__builtin_expect(rc != 0, 0)) nurl__mutex_failed("mutex_unlock", rc);
}
