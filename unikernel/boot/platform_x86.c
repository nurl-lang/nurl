/*
 * NURL unikernel — unikernel/boot/platform_x86.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The guest's bottom edge: the file that replaces
 * unikernel/nolibc/syscall_linux.c when there is no kernel to make a
 * syscall to. Everything above it — nolibc, runtime_core.c,
 * runtime_bare.c, the whole NURL program — is the same code the Linux
 * -nostdlib build runs, which is what makes that build worth anything
 * as a test of this one.
 *
 * Five things a program needs and a machine has to provide:
 *
 *   write        an 8250 UART at 0x3F8. Reads answer 0 (EOF): there is
 *                no console input, and pretending otherwise would hang
 *                a reader forever instead of ending its loop.
 *   memory       a bump allocator over the RAM the hypervisor reported.
 *                The upper bound is READ, never assumed — a guessed
 *                limit is a guest that corrupts itself on a machine
 *                with less RAM than the guess.
 *   time         the TSC, with its frequency from the hypervisor. If
 *                nobody says what the frequency is, asking for the
 *                time PANICS rather than returning a made-up number;
 *                the plan's rule for entropy, applied to the clock for
 *                the same reason.
 *   entropy      RDRAND, CPUID-gated. No source is a panic, never a
 *                fallback: this is where a "later TODO" becomes a
 *                weak key nobody notices.
 *   exit         a sentinel line on the serial port (the protocol both
 *                hypervisors can carry), then isa-debug-exit as a
 *                QEMU-side cross-check, then triple fault.
 */

/* Forward declarations for the POSIX-named half, which the `nl_*`
 * wrappers below reach before their definitions. */
void exit(int code);          /* nolibc/misc.c */
long long write(int fd, const void *buf, unsigned long n);
long long read(int fd, void *buf, unsigned long n);
int open(const char *p, int fl, int mode);
int close(int fd);
long long lseek(int fd, long long off, int whence);
void *mmap(void *addr, unsigned long len, int prot, int flags, int fd, long off);
int munmap(void *p, unsigned long len);

typedef unsigned long      pf_size_t;
typedef long               pf_ssize_t;
typedef unsigned long long u64;
typedef unsigned int       u32;

/* ── the PVH handover block ──────────────────────────────────────── */

#define HVM_START_MAGIC 0x336ec578

struct hvm_start_info {
    u32 magic;
    u32 version;
    u32 flags;
    u32 nr_modules;
    u64 modlist_paddr;
    u64 cmdline_paddr;
    u64 rsdp_paddr;
    u64 memmap_paddr;      /* version >= 1 */
    u32 memmap_entries;
    u32 reserved;
};

struct hvm_memmap_entry {
    u64 addr;
    u64 size;
    u32 type;              /* 1 = usable RAM */
    u32 reserved;
};

/* Provided by the linker script. */
extern unsigned char __heap_start[];

/* ── the serial port ─────────────────────────────────────────────── */

#define COM1 0x3F8

static inline void outb(unsigned short port, unsigned char v) {
    __asm__ __volatile__("outb %0, %1" :: "a"(v), "Nd"(port));
}
static inline unsigned char inb(unsigned short port) {
    unsigned char v;
    __asm__ __volatile__("inb %1, %0" : "=a"(v) : "Nd"(port));
    return v;
}
static inline void outl(unsigned short port, u32 v) {
    __asm__ __volatile__("outl %0, %1" :: "a"(v), "Nd"(port));
}

static void uart_init(void) {
    outb(COM1 + 1, 0x00);      /* interrupts off — v1 polls everything */
    outb(COM1 + 3, 0x80);      /* DLAB: the divisor is next            */
    outb(COM1 + 0, 0x01);      /* 115200 baud                          */
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x03);      /* 8N1                                  */
    outb(COM1 + 2, 0xC7);      /* FIFO on, cleared, 14-byte threshold  */
    outb(COM1 + 4, 0x03);      /* DTR | RTS                            */
}

static void uart_putc(char c) {
    /* Line feeds become CRLF: a serial terminal does not do it for us,
     * and the goldens this boot is checked against are line-oriented. */
    if (c == '\n') {
        while (!(inb(COM1 + 5) & 0x20)) { }
        outb(COM1, '\r');
    }
    while (!(inb(COM1 + 5) & 0x20)) { }
    outb(COM1, (unsigned char)c);
}

static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

static void uart_putu(unsigned long v) {
    char b[24];
    int n = 0;
    if (!v) { uart_putc('0'); return; }
    while (v) { b[n++] = (char)('0' + (v % 10)); v /= 10; }
    while (n) uart_putc(b[--n]);
}

/* ── panic ───────────────────────────────────────────────────────── */

static void pf_shutdown(int code);

void pf_panic(const char *msg) {
    uart_puts("nurl: ");
    uart_puts(msg);
    uart_putc('\n');
    pf_shutdown(127);
    for (;;) __asm__ __volatile__("cli; hlt");
}

/* ── memory ──────────────────────────────────────────────────────── */

static unsigned char *heap_next;
static unsigned char *heap_end;

/* The largest usable region at or above the image. Anything below the
 * image is where the image is, and a second region we could stitch on
 * buys nothing until there is a real allocator to stitch it into. */
static void mem_init(const struct hvm_start_info *si) {
    u64 best_base = 0, best_len = 0;
    u64 img = (u64)(unsigned long)__heap_start;

    if (si && si->version >= 1 && si->memmap_entries && si->memmap_paddr) {
        const struct hvm_memmap_entry *e =
            (const struct hvm_memmap_entry *)(unsigned long)si->memmap_paddr;
        for (u32 i = 0; i < si->memmap_entries; i++) {
            u64 base = e[i].addr, len = e[i].size;
            if (e[i].type != 1) continue;
            if (base + len <= img) continue;      /* entirely below us */
            if (base < img) { len -= (img - base); base = img; }
            if (len > best_len) { best_base = base; best_len = len; }
        }
    }
    if (!best_len)
        pf_panic("the hypervisor reported no usable memory above the image "
                 "— refusing to guess how much RAM this machine has");

    heap_next = (unsigned char *)(unsigned long)best_base;
    heap_end  = heap_next + best_len;
}

/* mmap, as much of it as a guest needs: anonymous, private, and never
 * unmapped. munmap is a no-op that reports success, which is honest
 * here — a bump allocator cannot return a hole in the middle, and the
 * one caller that unmaps (a finished coroutine's stack) is reclaimed by
 * runtime_bare's own free list rather than by the kernel. */
void *mmap(void *addr, unsigned long len, int prot, int flags, int fd, long off) {
    (void)addr; (void)prot; (void)flags; (void)fd; (void)off;
    unsigned long need = (len + 4095) & ~4095UL;
    if (!heap_next || (unsigned long)(heap_end - heap_next) < need)
        return (void *)-1;                  /* MAP_FAILED — the caller checks */
    unsigned char *p = heap_next;
    heap_next += need;
    return p;
}

int munmap(void *p, unsigned long len) { (void)p; (void)len; return 0; }

/* ── mprotect ────────────────────────────────────────────────────
 *
 * The only caller is runtime_bare's coroutine allocator, arming the
 * guard page below each 64 KiB stack. This target cannot yet do it:
 * the boot page tables map the low 4 GiB with 2 MiB pages, and a 4 KiB
 * guard needs the containing 2 MiB page split into 512 small ones
 * first. The split is written and is NOT here, because the version
 * that was faulted inside `nurl_free` — the freestanding allocator and
 * the coroutine stacks come out of one bump region, so unmapping a
 * page inside it is not the local act it is on Linux. Getting that
 * right is the memory phase (B2), which is where the guest grows a
 * real allocator instead of a bump pointer.
 *
 * Until then this REFUSES, and `nb_coro_new` turns the refusal into a
 * loud stop rather than a fiber that silently never runs. A guest
 * without fibers is a limitation; a guest whose fibers report success
 * and compute nothing is a bug report from six months later.
 */
int mprotect(void *p, unsigned long len, int prot) {
    (void)p; (void)len; (void)prot;
    return -1;
}

/* ── time ────────────────────────────────────────────────────────── */

static u64 tsc_khz;            /* 0 = nobody told us */
static u64 tsc_base;

static inline u64 rdtsc(void) {
    u32 lo, hi;
    __asm__ __volatile__("rdtsc" : "=a"(lo), "=d"(hi));
    return ((u64)hi << 32) | lo;
}

static inline void cpuid(u32 leaf, u32 *a, u32 *b, u32 *c, u32 *d) {
    __asm__ __volatile__("cpuid"
                         : "=a"(*a), "=b"(*b), "=c"(*c), "=d"(*d)
                         : "a"(leaf), "c"(0));
}

static void time_init(void) {
    u32 a, b, c, d;

    /* KVM's paravirt leaf: TSC frequency in kHz, stated outright. This
     * is the source microvm actually has — leaf 0x15 returns zeros on
     * most hosts under KVM, and there is no PIT to calibrate against
     * because microvm strips it. */
    cpuid(0x40000000, &a, &b, &c, &d);
    if (a >= 0x40000010) {
        cpuid(0x40000010, &a, &b, &c, &d);
        if (a) tsc_khz = a;
    }
    if (!tsc_khz) {
        /* Leaf 0x15: core crystal frequency and the TSC/crystal ratio. */
        cpuid(0, &a, &b, &c, &d);
        if (a >= 0x15) {
            u32 den, num, crystal, unused;
            cpuid(0x15, &den, &num, &crystal, &unused);
            if (den && num && crystal)
                tsc_khz = ((u64)crystal * num) / den / 1000;
        }
    }
    tsc_base = rdtsc();
}

/* CLOCK_MONOTONIC = 1, CLOCK_REALTIME = 0 — the two nolibc asks for.
 * Both come off the TSC; wall-clock epoch arrives with the kernel
 * command line (plan B3) and is a functionality input, not a security
 * control. */
int clock_gettime(int clk, void *tsp) {
    u64 *ts = (u64 *)tsp;
    if (!tsc_khz)
        pf_panic("no TSC frequency from the hypervisor — refusing to "
                 "invent one (a guessed clock is a wrong timeout, a wrong "
                 "RTO and a certificate that expires when it feels like it)");
    u64 ticks = rdtsc() - tsc_base;
    u64 us = ticks / (tsc_khz / 1000 ? tsc_khz / 1000 : 1);
    (void)clk;
    ts[0] = us / 1000000;
    ts[1] = (us % 1000000) * 1000;
    return 0;
}

int nanosleep(const void *req, void *rem) {
    const u64 *ts = (const u64 *)req;
    (void)rem;
    if (!tsc_khz) return 0;
    u64 want = ts[0] * 1000000000ULL + ts[1];
    u64 start = rdtsc();
    u64 ticks = (want / 1000) * (tsc_khz / 1000 ? tsc_khz / 1000 : 1);
    /* hlt would need a timer interrupt, and v1 has no IDT vectors
     * wired. Spinning is what "fully polling" costs, and it is bounded
     * by the deadline the caller asked for. */
    while (rdtsc() - start < ticks) __asm__ __volatile__("pause");
    return 0;
}

/* ── entropy ─────────────────────────────────────────────────────── */

long long getrandom(void *buf, unsigned long len, unsigned int flags) {
    u32 a, b, c, d;
    unsigned char *p = (unsigned char *)buf;
    unsigned long done = 0;
    (void)flags;

    cpuid(1, &a, &b, &c, &d);
    if (!(c & (1u << 30)))
        pf_panic("no RDRAND on this vCPU and no virtio-rng — refusing to "
                 "generate keys");

    while (done < len) {
        unsigned long long v;
        unsigned char ok;
        int tries = 0;
        do {
            __asm__ __volatile__("rdrand %0; setc %1" : "=r"(v), "=qm"(ok));
        } while (!ok && ++tries < 32);
        if (!ok) pf_panic("RDRAND failed repeatedly — refusing to continue");
        for (int i = 0; i < 8 && done < len; i++, done++)
            p[done] = (unsigned char)(v >> (i * 8));
    }
    return (long long)len;
}

/* ── the file surface nolibc expects ─────────────────────────────── */

int nl_errno_slot;
int *__errno_location(void) { return &nl_errno_slot; }

long long write(int fd, const void *buf, unsigned long n) {
    const char *p = (const char *)buf;
    (void)fd;                        /* stdout and stderr are the same wire */
    for (unsigned long i = 0; i < n; i++) uart_putc(p[i]);
    return (long long)n;
}

/* No console input. 0 is EOF, which every reader already handles; -1
 * with an errno would make them retry forever. */
long long read(int fd, void *buf, unsigned long n) {
    (void)fd; (void)buf; (void)n;
    return 0;
}

int open(const char *p, int fl, int mode) { (void)p; (void)fl; (void)mode; return -1; }
int close(int fd) { (void)fd; return 0; }
long long lseek(int fd, long long off, int whence) { (void)fd; (void)off; (void)whence; return -1; }

static void pf_shutdown(int code);

/* nolibc's stdio talks to the `nl_*` layer, not to the POSIX names —
 * that is the seam syscall_linux.c defines, so a guest that replaces
 * that file has to define it too. Same functions, one indirection up. */
pf_ssize_t nl_write(int fd, const void *buf, pf_size_t n) { return (pf_ssize_t)write(fd, buf, n); }
pf_ssize_t nl_read(int fd, void *buf, pf_size_t n) { return (pf_ssize_t)read(fd, buf, n); }
int nl_open(const char *path, int flags, int mode) { return open(path, flags, mode); }
int nl_close(int fd) { return close(fd); }
long long nl_lseek(int fd, long long off, int whence) { return lseek(fd, off, whence); }
void *nl_map(pf_size_t len) { return mmap(0, len, 0, 0, -1, 0); }
int nl_unmap(void *p, pf_size_t len) { return munmap(p, len); }
/* Straight to the machine. nolibc's `exit` flushes stdio and then
 * calls THIS — routing it back through `exit` is an infinite
 * recursion that overflows the boot stack and triple-faults, which
 * looks exactly like a clean shutdown from outside: QEMU exits 0 and
 * the sentinel line never appears. */
void nl_exit_group(int code) { pf_shutdown(code); for (;;) { } }

/* The filesystem, until B7 bakes an image in: nothing is there, and
 * every one of these already has a caller that handles the failure.
 * A stub that reports success would make that caller's error path
 * unreachable and its success path wrong. */
int unlink(const char *p) { (void)p; return -1; }

/* nolibc/misc.c reaches for the raw syscall pair for the handful of
 * calls it does not wrap. There is no syscall instruction to make
 * here, and the answer is the same one every other file gets: the
 * operation is not available, said out loud. -ENOSYS is what a Linux
 * kernel says about a syscall it does not implement, so every caller
 * already knows this shape. */
long nl_syscall6(long n, long a, long b, long c, long d, long e, long f) {
    (void)n; (void)a; (void)b; (void)c; (void)d; (void)e; (void)f;
    return -38;                                        /* -ENOSYS */
}

long nl_ret(long r) {
    if (r < 0 && r > -4096) { nl_errno_slot = (int)-r; return -1; }
    return r;
}
int mkdir(const char *p, int mode) { (void)p; (void)mode; return -1; }
int access(const char *p, int mode) { (void)p; (void)mode; return -1; }
int getpid(void) { return 1; }

/* ── shutdown ────────────────────────────────────────────────────── */

static void pf_shutdown(int code) {
    /* The primary protocol, because it is the only one both hypervisors
     * can carry: Firecracker cannot hand a guest exit code back at all,
     * so the harness parses this line. QEMU's isa-debug-exit below is a
     * cross-check, not the mechanism. */
    uart_puts("[nurl-exit] ");
    uart_putu((unsigned long)(code & 0xff));
    uart_putc('\n');

    /* isa-debug-exit: the guest's code appears as (code << 1) | 1, so 0
     * is not expressible — hence the sentinel line above being primary
     * rather than a convenience. */
    outl(0xf4, (u32)(code & 0xff));

    /* Nothing there. Triple fault: load a null IDT and take an
     * exception. Firecracker treats KVM_EXIT_SHUTDOWN as "the VM
     * stopped", which is exactly what this means. */
    struct { unsigned short limit; unsigned long base; } __attribute__((packed))
        null_idt = { 0, 0 };
    __asm__ __volatile__("lidt %0; int3" :: "m"(null_idt));
    for (;;) __asm__ __volatile__("cli; hlt");
}

/* `exit`, `abort` and `nl_environ` belong to nolibc/misc.c, which this
 * target keeps verbatim: exit runs the atexit chain and flushes stdio
 * before calling `nl_exit_group`, and abort prints its line first.
 * Defining them here would duplicate the symbols AND skip both. The
 * machine's part is nl_exit_group, above. */
void _exit(int code) { pf_shutdown(code); for (;;) { } }

/* ── entry ───────────────────────────────────────────────────────── */

extern char **nl_environ;          /* nolibc/misc.c owns the storage */
extern void nl_tls_init_guest(void);
extern int main(int argc, char **argv);

void kmain(unsigned long start_info_paddr) {
    static char *no_argv[2];
    const struct hvm_start_info *si =
        (const struct hvm_start_info *)start_info_paddr;

    uart_init();
    if (!si || si->magic != HVM_START_MAGIC)
        pf_panic("not a PVH boot — no hvm_start_info at the handover "
                 "address (was this image loaded with -kernel?)");

    mem_init(si);
    time_init();
    nl_tls_init_guest();          /* before the first __thread access */

    no_argv[0] = (char *)"nurl";
    no_argv[1] = 0;
    nl_environ = &no_argv[1];     /* an empty environment, terminated */

    exit(main(1, no_argv));
}
