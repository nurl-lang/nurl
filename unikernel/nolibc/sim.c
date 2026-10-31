/* Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
 *
 * unikernel/nolibc/sim.c — deterministic simulation: the clock and the
 * entropy of a program built with `build_nolibc.sh --sim` (agora #260,
 * DST 2/4).
 *
 * A simulation runs the program on the cooperative runtime the
 * unikernel uses (runtime_bare.c: one OS thread, threads and fibers as
 * coroutines, cooperative mutexes and condvars, timers, a deadlock
 * report) and replaces the three places where the outside world gets
 * in — what time it is, how long a sleep takes, and what random bytes
 * are — with answers that follow from one seed. So a run is a function
 * of (program, seed): the same seed gives the same schedule, the same
 * timeouts, the same TCP sequence numbers and the same output, and a
 * failure found under a seed replays exactly.
 *
 *   NURL_SIM=<seed>      the seed (decimal; default 1). 0 keeps the run
 *                        queue FIFO; any other seed picks the next
 *                        coroutine with the PRNG (runtime_bare.c).
 *   NURL_SIM_TRACE=1     at exit, one line on stderr: the seed, how many
 *                        scheduling picks there were, a hash of their
 *                        sequence, and the virtual time that passed.
 *   NURL_SIM_LIMIT_MS=n  the virtual time a run may take (default one
 *                        hour). A program that has not finished by then
 *                        is reported and stopped: in a simulation a
 *                        hang does not look like one — the clock jumps
 *                        from timer to timer, so a run waiting for
 *                        something that never comes races through
 *                        virtual hours in wall-clock seconds.
 *
 * TIME is virtual. It starts at a fixed instant and moves only when the
 * program sleeps or the scheduler has nothing to run but a timer —
 * runtime_bare.c's idle step sleeps until the earliest timer, and here
 * that sleep is a jump. A partition's timeout or TCP's retransmission
 * timer therefore costs no wall-clock time. Each reading also moves the
 * clock on by 1 µs: a loop that spins until the clock passes a mark
 * (a busy-wait) still ends, and the readings stay strictly increasing,
 * as a monotonic clock's must; the step is deterministic like
 * everything else.
 *
 * RANDOMNESS is a xorshift64* stream seeded through splitmix64; the
 * scheduler draws from its own stream, so whether a program asks for
 * random bytes does not shift the schedule.
 *
 * This file stands in for syscall_linux.c's clock_gettime, nanosleep and
 * getrandom, which that file leaves out under NURL_SIM.
 */

typedef unsigned long long u64;

struct nl_file;
char *getenv(const char *name);
int   atexit(void (*fn)(void));
int   fprintf(struct nl_file *stream, const char *fmt, ...);
extern struct nl_file *stderr;

/* 2026-01-01T00:00:00Z: the wall clock a simulation starts at. */
#define SIM_EPOCH_S 1767225600LL

static int sim_ready;
static u64 sim_seed;
static u64 sim_now_ns = 1000000000ULL;   /* monotonic; starts at 1 s */
static u64 sim_start_ns;
static u64 sim_bytes_state;               /* getrandom's stream */
static u64 sim_sched_state;               /* the scheduler's stream */
static u64 sim_picks;
static u64 sim_choices;                   /* picks with more than one candidate */
static u64 sim_trace = 1469598103934665603ULL;   /* FNV-1a offset basis */
static u64 sim_limit_ns = 3600ULL * 1000000000ULL;

void abort(void);

static u64 sim_splitmix(u64 *x) {
    u64 z = (*x += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

static u64 sim_xorshift(u64 *s) {
    u64 x = *s;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *s = x;
    return x * 0x2545F4914F6CDD1DULL;
}

static void sim_report(void) {
    if (!getenv("NURL_SIM_TRACE")) return;
    fprintf(stderr, "nurl-sim: seed=%llu picks=%llu choices=%llu trace=%llx virtual_ms=%llu\n",
            sim_seed, sim_picks, sim_choices, sim_trace, (sim_now_ns - sim_start_ns) / 1000000ULL);
}

static void sim_init(void) {
    if (sim_ready) return;
    sim_ready = 1;
    sim_seed = 1;
    const char *s = getenv("NURL_SIM");
    if (s && *s) {
        u64 v = 0;
        for (; *s >= '0' && *s <= '9'; s++) v = v * 10 + (u64)(*s - '0');
        sim_seed = v;
    }
    const char *lim = getenv("NURL_SIM_LIMIT_MS");
    if (lim && *lim) {
        u64 v = 0;
        for (; *lim >= '0' && *lim <= '9'; lim++) v = v * 10 + (u64)(*lim - '0');
        if (v > 0) sim_limit_ns = v * 1000000ULL;
    }
    u64 mix = sim_seed;
    sim_bytes_state = sim_splitmix(&mix) | 1;
    sim_sched_state = sim_splitmix(&mix) | 1;
    sim_start_ns = sim_now_ns;
    atexit(sim_report);
}

/* ── the scheduler's side (runtime_bare.c) ───────────────────────── */

/* Which of the `n` runnable coroutines runs next: the FIFO head (0)
 * under seed 0, the stream's choice under any other. */
unsigned long nurl__sim_pick(unsigned long n) {
    sim_init();
    if (n > 1) sim_choices++;
    if (n <= 1 || sim_seed == 0) return 0;
    return (unsigned long)(sim_xorshift(&sim_sched_state) % (u64)n);
}

/* Fold one pick — the coroutine's creation number — into the trace. */
void nurl__sim_note(unsigned long long id) {
    sim_picks++;
    for (int i = 0; i < 8; i++) {
        sim_trace ^= (id >> (8 * i)) & 0xFF;
        sim_trace *= 1099511628211ULL;   /* FNV-1a prime */
    }
}

/* The clock moved: past the limit, the run is over. */
static void sim_check_limit(void) {
    if (sim_now_ns - sim_start_ns <= sim_limit_ns) return;
    fprintf(stderr, "nurl-sim: seed=%llu did not finish in %llu ms of virtual time "
                    "(NURL_SIM_LIMIT_MS) — a wait that nothing ends, or a timer "
                    "that re-arms forever; picks=%llu trace=%llx\n",
            sim_seed, sim_limit_ns / 1000000ULL, sim_picks, sim_trace);
    abort();
}

/* ── the platform edge it replaces ───────────────────────────────── */

struct sim_timespec { long tv_sec; long tv_nsec; };

/* CLOCK_REALTIME is 0 on Linux; every other clock reads as monotonic. */
int clock_gettime(int clk, void *ts) {
    sim_init();
    struct sim_timespec *t = (struct sim_timespec *)ts;
    sim_now_ns += 1000ULL;
    u64 ns = sim_now_ns;
    if (clk == 0) {
        t->tv_sec  = (long)(SIM_EPOCH_S + (long long)((ns - sim_start_ns) / 1000000000ULL));
        t->tv_nsec = (long)((ns - sim_start_ns) % 1000000000ULL);
    } else {
        t->tv_sec  = (long)(ns / 1000000000ULL);
        t->tv_nsec = (long)(ns % 1000000000ULL);
    }
    return 0;
}

/* A sleep is a jump of the clock: nothing else runs on this thread
 * meanwhile, and nothing outside it can change. */
int nanosleep(const void *req, void *rem) {
    sim_init();
    const struct sim_timespec *r = (const struct sim_timespec *)req;
    if (r && r->tv_sec >= 0 && r->tv_nsec >= 0)
        sim_now_ns += (u64)r->tv_sec * 1000000000ULL + (u64)r->tv_nsec;
    sim_check_limit();
    if (rem) {
        struct sim_timespec *o = (struct sim_timespec *)rem;
        o->tv_sec = 0;
        o->tv_nsec = 0;
    }
    return 0;
}

long long getrandom(void *buf, unsigned long len, unsigned int flags) {
    (void)flags;
    sim_init();
    unsigned char *p = (unsigned char *)buf;
    unsigned long i = 0;
    while (i < len) {
        u64 w = sim_xorshift(&sim_bytes_state);
        for (int k = 0; k < 8 && i < len; k++, i++) p[i] = (unsigned char)(w >> (8 * k));
    }
    return (long long)len;
}
