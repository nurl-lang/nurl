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

#define PT_POOL_TABLES 64
static u64 *pt_pool;              /* PT_POOL_TABLES × 512 entries */
static u32  pt_pool_used;

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

    /* The page-table pool, taken before anything else and aligned the
     * way a page table must be. */
    heap_next = (unsigned char *)(((unsigned long)heap_next + 4095) & ~4095UL);
    pt_pool = (u64 *)heap_next;
    heap_next += (unsigned long)PT_POOL_TABLES * 4096;
    if (heap_next > heap_end) pf_panic("not enough memory for the page-table pool");
    for (unsigned long i = 0; i < (unsigned long)PT_POOL_TABLES * 512; i++) pt_pool[i] = 0;
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

/* ── page protection ─────────────────────────────────────────────
 *
 * The boot page tables map the low 4 GiB with 2 MiB pages, and the one
 * caller of `mprotect` — runtime_bare arming a 4 KiB guard page below
 * each coroutine stack — needs a finer grain than that. So the 2 MiB
 * page containing the range is split into 512 4 KiB pages, once, and
 * the bits then say what the caller asked for.
 *
 * The page tables for the split come from a POOL RESERVED AT BOOT, not
 * from the heap. That is the whole difference between this and the
 * version that faulted: `mprotect` is called from inside the
 * allocator's world — a coroutine's stack has just been handed out —
 * and taking a fresh page from the same bump pointer while editing the
 * mapping of the region it lives in is one interaction too many to
 * reason about. A pool sized at boot removes the question: splitting
 * allocates nothing and cannot fail for want of memory.
 *
 * 64 tables covers 128 MiB of split range, which is 1900 coroutine
 * stacks. Running out is a panic, not a silent refusal — a guard page
 * that quietly does not exist is the bug this whole mechanism is for.
 */
static u64 *pd_entry_for(u64 va) {
    u64 cr3;
    __asm__ __volatile__("mov %%cr3, %0" : "=r"(cr3));
    u64 *pml4 = (u64 *)(unsigned long)(cr3 & 0x000FFFFFFFFFF000ULL);
    if (!(pml4[(va >> 39) & 511] & 1)) return 0;
    u64 *pdpt = (u64 *)(unsigned long)(pml4[(va >> 39) & 511] & 0x000FFFFFFFFFF000ULL);
    if (!(pdpt[(va >> 30) & 511] & 1)) return 0;
    u64 *pd = (u64 *)(unsigned long)(pdpt[(va >> 30) & 511] & 0x000FFFFFFFFFF000ULL);
    return &pd[(va >> 21) & 511];
}

/* One 2 MiB mapping becomes 512 4 KiB ones over the same frames. */
static void split_2m(u64 *pde) {
    if (!(*pde & (1ULL << 7))) return;               /* already 4 KiB */
    if (pt_pool_used >= PT_POOL_TABLES)
        pf_panic("out of page tables — more coroutine stacks than the "
                 "boot-time pool was sized for");
    u64 frame = *pde & 0x000FFFFFFFE00000ULL;        /* the 2 MiB frame */
    u64 *pt = pt_pool + (unsigned long)pt_pool_used * 512;
    pt_pool_used++;
    for (int i = 0; i < 512; i++) pt[i] = (frame + (u64)i * 4096) | 0x3;
    *pde = ((u64)(unsigned long)pt) | 0x3;           /* present | writable */
}

int mprotect(void *p, unsigned long len, int prot) {
    u64 va = (u64)(unsigned long)p & ~0xFFFULL;
    u64 end = ((u64)(unsigned long)p + len + 4095) & ~0xFFFULL;

    if (!pt_pool) return -1;
    for (; va < end; va += 4096) {
        u64 *pde = pd_entry_for(va);
        if (!pde || !(*pde & 1)) return -1;
        split_2m(pde);
        u64 *pt = (u64 *)(unsigned long)(*pde & 0x000FFFFFFFFFF000ULL);
        u64 *pte = &pt[(va >> 12) & 511];
        u64 frame = *pte & 0x000FFFFFFFFFF000ULL;
        /* PROT_NONE (0) unmaps; PROT_WRITE (2) implies read. */
        if (prot == 0)       *pte = frame;                  /* not present */
        else if (prot & 0x2) *pte = frame | 0x3;
        else                 *pte = frame | 0x1;
        __asm__ __volatile__("invlpg (%0)" :: "r"((unsigned long)va) : "memory");
    }
    return 0;
}

/* ── time ────────────────────────────────────────────────────────── */

static u64 tsc_khz;            /* 0 = nobody told us */
static u64 tsc_base;
static u64 wall_base_sec;      /* CLOCK_REALTIME epoch at boot, 0 = unset */

/* ── the kernel command line ─────────────────────────────────────
 *
 * Three consumers share one string (plan B0): the boot layer reads
 * `tsc_khz=` and `wallclock=`, B5 will read `virtio_mmio.device=`, and
 * the application's argv arrives in a single `args="…"` key. Anything
 * unrecognised is consumed here and never reaches the program, because
 * QEMU appends its own entries after `-append` and handing those to a
 * program's argument parser is how a boot flag becomes a mysterious
 * command-line error.
 */
static const char *cmdline;
const char *nurl_boot_cmdline(void);

static u64 cmdline_u64(const char *key) {
    const char *p = cmdline;
    unsigned long klen = 0;
    if (!p) return 0;
    while (key[klen]) klen++;
    while (*p) {
        const char *k = p;
        unsigned long n = 0;
        while (p[n] && p[n] != ' ' && p[n] != '=') n++;
        if (n == klen && p[n] == '=') {
            unsigned long i = 0;
            for (; i < klen; i++) if (k[i] != key[i]) break;
            if (i == klen) {
                u64 v = 0;
                const char *d = p + n + 1;
                if (*d < '0' || *d > '9') return 0;
                while (*d >= '0' && *d <= '9') { v = v * 10 + (u64)(*d - '0'); d++; }
                return v;
            }
        }
        while (*p && *p != ' ') p++;
        while (*p == ' ') p++;
    }
    return 0;
}

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
    /* Last: the host says so on the command line. Not a guess — a
     * stated input, the same trust model the plan gives the wall-clock
     * epoch (the host already controls the entire image). It is what
     * makes a TCG run possible at all: no leaf reports a frequency
     * there, and refusing to invent one is right, while refusing to be
     * TOLD one would just mean the clock never works without KVM. */
    if (!tsc_khz) tsc_khz = cmdline_u64("tsc_khz");
    wall_base_sec = cmdline_u64("wallclock");
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
    ts[0] = us / 1000000;
    ts[1] = (us % 1000000) * 1000;
    /* CLOCK_REALTIME (0) is the boot epoch plus the monotonic delta.
     * Without one it stays boot-relative and says so by being obviously
     * wrong (1970), rather than by looking plausible: X.509 validity is
     * the caller that cares, and it fails closed on a 1970 clock. */
    if (clk == 0) ts[0] += wall_base_sec;
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

/* ── the command line, for NURL ──────────────────────────────────
 *
 * Device discovery happens in NURL (hal/virtio.nu parses the
 * `virtio_mmio.device=` entries), so the string has to cross the
 * boundary. Borrowed, not copied: it lives in memory the hypervisor
 * placed and nothing here writes to it.
 *
 * The Linux freestanding build has no such thing and does not define
 * this symbol — a program that reaches for the guest's command line
 * fails to LINK there rather than reading an empty string and
 * concluding there are no devices. */
const char *nurl_boot_cmdline(void) { return cmdline ? cmdline : ""; }

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

    cmdline = si->cmdline_paddr ? (const char *)(unsigned long)si->cmdline_paddr : 0;
    mem_init(si);
    time_init();
    nl_tls_init_guest();          /* before the first __thread access */

    no_argv[0] = (char *)"nurl";
    no_argv[1] = 0;
    nl_environ = &no_argv[1];     /* an empty environment, terminated */

    exit(main(1, no_argv));
}
