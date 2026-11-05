/* Agora #500 experiment: how long after a loopback connect() returns in
 * the client does the kernel report the listener ready (kqueue / epoll)?
 * The main thread spins a zero-timeout poll of the listener the whole
 * time, so the readiness time is seen to within a microsecond. */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__) || defined(__FreeBSD__)
#include <sys/event.h>
#define KQ 1
#else
#include <sys/epoll.h>
#endif

static long long now_ns(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}
#define N 3000
static int port;
static _Atomic long long t_conn[N];   /* when connect() returned, in ticks */
static _Atomic long long ticks;       /* main thread's 20 us work units */
static _Atomic int done_client;
static _Atomic int hog_stop;

static void *client(void *arg) {
    (void)arg;
    for (int i = 0; i < N; i++) {
        int c = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in a; memset(&a, 0, sizeof a);
        a.sin_family = AF_INET; a.sin_port = htons(port);
        a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (connect(c, (struct sockaddr *)&a, sizeof a) != 0) { perror("connect"); exit(2); }
        atomic_store(&t_conn[i], atomic_load(&ticks));
        close(c);
        usleep(1000);
    }
    atomic_store(&done_client, 1);
    return NULL;
}
static void *hog(void *arg) { (void)arg; volatile unsigned long x = 0; while (!atomic_load(&hog_stop)) x++; return NULL; }
static int cmp(const void *a, const void *b) { long long x = *(const long long *)a, y = *(const long long *)b; return x < y ? -1 : x > y; }

int main(int argc, char **argv) {
    int hogs = argc > 1 ? atoi(argv[1]) : 0;
    int every = argc > 2 ? atoi(argv[2]) : 1;       /* poll every Nth tick */
    int sysc = argc > 3 ? atoi(argv[3]) : 0;        /* a cheap syscall every tick */
    int l = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1; setsockopt(l, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a; memset(&a, 0, sizeof a);
    a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(l, (struct sockaddr *)&a, sizeof a); listen(l, 128);
    socklen_t al = sizeof a; getsockname(l, (struct sockaddr *)&a, &al); port = ntohs(a.sin_port);
    fcntl(l, F_SETFL, fcntl(l, F_GETFL) | O_NONBLOCK);
#ifdef KQ
    int q = kqueue(); struct kevent ev; EV_SET(&ev, l, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, NULL); kevent(q, &ev, 1, NULL, 0, NULL);
#else
    int q = epoll_create1(0); struct epoll_event ev = { .events = EPOLLIN | EPOLLET, .data.fd = l }; epoll_ctl(q, EPOLL_CTL_ADD, l, &ev);
#endif
    pthread_t hs[64]; for (int i = 0; i < hogs && i < 64; i++) pthread_create(&hs[i], NULL, hog, NULL);
    pthread_t ct; pthread_create(&ct, NULL, client, NULL);
    static long long t_ready[N]; int got = 0;
    while (got < N) {
#ifdef KQ
        struct kevent out[4]; struct timespec z = {0, 0};
        int n = 0;
        if (atomic_load(&ticks) % every == 0) n = kevent(q, NULL, 0, out, 4, &z);
#else
        struct epoll_event out[4]; int n = 0;
        if (atomic_load(&ticks) % every == 0) n = epoll_wait(q, out, 4, 0);
#endif
        if (n <= 0) {
            long long t0 = now_ns(); while (now_ns() - t0 < 20000) {}
            if (sysc) (void)getppid();
            atomic_fetch_add(&ticks, 1);
            continue;
        }
        long long t = atomic_load(&ticks);
        for (;;) {
            int c = accept(l, NULL, NULL);
            if (c < 0) break;
            close(c);
            if (got < N) t_ready[got++] = t;
        }
    }
    pthread_join(ct, NULL);
    atomic_store(&hog_stop, 1);
    for (int i = 0; i < hogs && i < 64; i++) pthread_join(hs[i], NULL);
    static long long lag[N]; int early = 0; int over15 = 0, over31 = 0;
    int phase[64] = {0};
    for (int i = 0; i < N; i++) phase[atomic_load(&t_conn[i]) % (every < 64 ? every : 64)]++;
    for (int i = 0; i < N; i++) { lag[i] = t_ready[i] - atomic_load(&t_conn[i]); if (lag[i] > 0) early++; }
    qsort(lag, N, sizeof lag[0], cmp);
    for (int i = 0; i < N; i++) { if (lag[i] >= 16) over15++; if (lag[i] >= 32) over31++; }
    printf("every=%d syscall=%d ", every, sysc);
    printf("hogs=%d n=%d  readiness after connect() returned: %d/%d\n", hogs, N, early, N);
    printf("  lag in 20us main-thread ticks (ready - connect return): min %lld p50 %lld p90 %lld p99 %lld p999 %lld max %lld\n",
           lag[0], lag[N / 2], lag[N * 9 / 10], lag[N * 99 / 100], lag[N * 999 / 1000], lag[N - 1]);
    printf("  lag >= 16 ticks (one poll window): %d   lag >= 32 ticks (the test's bound): %d\n", over15, over31);
    if (every > 1) {
        printf("  connect() returned at tick %% %d:", every);
        for (int k = 0; k < every && k < 64; k++) printf(" %d", phase[k]);
        printf("\n  lag histogram (ticks, bucket 4):");
        int hist[40] = {0};
        for (int i = 0; i < N; i++) { long long b = lag[i] < 0 ? 0 : lag[i] / 4; if (b > 39) b = 39; hist[b]++; }
        for (int k = 0; k < 40; k++) if (hist[k]) printf(" [%d..%d]=%d", k * 4, k * 4 + 3, hist[k]);
        printf("\n");
    }
    return 0;
}
