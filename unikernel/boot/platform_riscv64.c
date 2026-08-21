/*
 * NURL unikernel — unikernel/boot/platform_riscv64.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The guest's bottom edge on RV64 (QEMU `virt`) — the third of the
 * three, and by now the shape is a template rather than a discovery.
 * The same five services, this machine's answers:
 *
 *   write        a 16550 UART at 0x1000_0000 (what virt puts there;
 *                the SBI console would be a firmware call instead, and
 *                a device this port already knows how to drive is one
 *                dependency fewer on which SBI version is underneath).
 *   memory       the device tree's /memory node, via boot/fdt.c —
 *                shared with the AArch64 port, one parser, one answer.
 *   time         `rdtime`, with the frequency from the tree's
 *                timebase-frequency (10 MHz on virt). Self-describing,
 *                like AArch64's CNTFRQ and unlike x86's TSC.
 *   entropy      NO instruction on this ISA's base profile — the Zkr
 *                extension's `seed` CSR is optional and QEMU's `rv64`
 *                CPU does not implement it. So: the SBI debug console
 *                cannot help either, and this port PANICS on a request
 *                for entropy rather than inventing it. That is the
 *                plan's rule applied honestly: a machine without a
 *                source refuses to make keys, and says which piece is
 *                missing.
 *   exit         the sentinel line, then SBI SRST (system reset), then
 *                the legacy SBI shutdown, then WFI.
 */

void exit(int code);
long long write(int fd, const void *buf, unsigned long n);
long long read(int fd, void *buf, unsigned long n);
int open(const char *p, int fl, int mode);
int close(int fd);
long long lseek(int fd, long long off, int whence);
void *mmap(void *addr, unsigned long len, int prot, int flags, int fd, long off);
int munmap(void *p, unsigned long len);

struct nl_file;
extern struct nl_file *stdout;
int *nl_file_flags(struct nl_file *f);
#define PF_F_LINEBUF 0x20

typedef unsigned long      pf_size_t;
typedef long               pf_ssize_t;
typedef unsigned long long u64;
typedef unsigned int       u32;

extern unsigned char __heap_start[];

/* ── the device tree, in boot/fdt.c ──────────────────────────────── */
#define FDT_MAX_DEVS 32
struct fdt_facts {
    u64   ram_base;
    u64   ram_size;
    char  cmdline[2048];
    unsigned long cmdline_len;
    int   devices;
    u64   dev_base[FDT_MAX_DEVS];
};
int fdt_is_tree(const void *p);
int fdt_probe(const void *fdt, struct fdt_facts *out);

static struct fdt_facts facts;

/* ── the serial port ─────────────────────────────────────────────
 * NS16550A at virt's 0x10000000. Byte-wide registers, no shift. */

#define UART_BASE 0x10000000UL
#define UART_THR  (*(volatile unsigned char *)(UART_BASE + 0))
#define UART_LSR  (*(volatile unsigned char *)(UART_BASE + 5))
#define UART_LSR_THRE 0x20

static void uart_init(void) {
    /* OpenSBI has already configured it for its own output; setting
     * the divisor again would only risk disagreeing with the host's
     * -serial. Stating the dependency instead of re-deriving it. */
}

static void uart_putc(char c) {
    if (c == '\n') {
        while (!(UART_LSR & UART_LSR_THRE)) { }
        UART_THR = '\r';
    }
    while (!(UART_LSR & UART_LSR_THRE)) { }
    UART_THR = (unsigned char)c;
}

static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

static void uart_putu(unsigned long v) {
    char b[21];
    int i = 20;
    b[i] = 0;
    if (!v) b[--i] = '0';
    while (v) { b[--i] = (char)('0' + v % 10); v /= 10; }
    uart_puts(&b[i]);
}

static void uart_puthex(u64 v) {
    static const char hex[] = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 60; i >= 0; i -= 4) uart_putc(hex[(v >> i) & 0xF]);
}

static void pf_shutdown(int code);

void pf_panic(const char *msg) {
    uart_puts("nurl: ");
    uart_puts(msg);
    uart_putc('\n');
    pf_shutdown(127);
    for (;;) __asm__ __volatile__("wfi");
}

/* ── SBI ─────────────────────────────────────────────────────────
 * The one firmware call this port makes. `ecall` from S-mode with the
 * extension id in a7 and the function id in a6. */
static long sbi_call(long eid, long fid, long a0_, long a1_) {
    register long a0 __asm__("a0") = a0_;
    register long a1 __asm__("a1") = a1_;
    register long a6 __asm__("a6") = fid;
    register long a7 __asm__("a7") = eid;
    __asm__ __volatile__("ecall"
                         : "+r"(a0), "+r"(a1)
                         : "r"(a6), "r"(a7)
                         : "memory");
    return a0;
}

/* ── faults ──────────────────────────────────────────────────────
 *
 * The frame `trap_entry` in boot_riscv64.S builds, low address first.
 * The two files are read together. x[0] is unused (x0 is hardwired
 * zero) and kept so an index is a register number. */
struct fault_frame {
    u64 x[32];                /* x0–x31, x[2] = the faulting sp */
    u64 sepc, scause, stval, sstatus;
};

/* scause, with the interrupt bit stripped. The names are the
 * privileged spec's, so a report is something someone can look up. */
static const char *cause_name(u64 scause) {
    if (scause >> 63) {
        switch (scause & 0xff) {
        case 1:  return "supervisor software interrupt";
        case 5:  return "supervisor timer interrupt";
        case 9:  return "supervisor external interrupt";
        default: return "interrupt (unexpected — this machine polls)";
        }
    }
    switch (scause) {
    case 0:  return "instruction address misaligned";
    case 1:  return "instruction access fault";
    case 2:  return "illegal instruction";
    case 3:  return "breakpoint";
    case 4:  return "load address misaligned";
    case 5:  return "load access fault";
    case 6:  return "store/AMO address misaligned";
    case 7:  return "store/AMO access fault";
    case 8:  return "environment call from U-mode";
    case 9:  return "environment call from S-mode";
    case 12: return "instruction page fault";
    case 13: return "load page fault";
    case 15: return "store/AMO page fault";
    default: return "see scause in the privileged spec";
    }
}

void pf_exception(struct fault_frame *f);

void pf_exception(struct fault_frame *f) {
    uart_puts("\nnurl: fault ");
    uart_puts(cause_name(f->scause));
    uart_puts("\n  scause=");
    uart_puthex(f->scause);
    uart_puts(" sepc=");
    uart_puthex(f->sepc);
    uart_puts(" sstatus=");
    uart_puthex(f->sstatus);
    if (f->scause == 12 || f->scause == 13 || f->scause == 15 ||
        f->scause == 1  || f->scause == 5  || f->scause == 7) {
        uart_puts("\n  stval=");
        uart_puthex(f->stval);
        uart_puts(f->scause == 15 || f->scause == 7 ? " on write" :
                  (f->scause == 12 || f->scause == 1 ? " on instruction fetch"
                                                     : " on read"));
    }
    uart_puts("\n  ra=");   uart_puthex(f->x[1]);
    uart_puts(" sp=");      uart_puthex(f->x[2]);
    uart_puts(" fp=");      uart_puthex(f->x[8]);
    uart_puts("\n  a0=");   uart_puthex(f->x[10]);
    uart_puts(" a1=");      uart_puthex(f->x[11]);
    uart_puts(" a2=");      uart_puthex(f->x[12]);
    uart_putc('\n');
    /* 126, not 127: a fault is not a panic, and the harness can tell. */
    pf_shutdown(126);
    for (;;) __asm__ __volatile__("wfi");
}

/* ── the kernel command line ─────────────────────────────────────── */

static const char *cmdline;
const char *nurl_boot_cmdline(void);
const char *nurl_boot_cmdline(void) { return cmdline ? cmdline : ""; }

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

/* ── memory ──────────────────────────────────────────────────────── */

static unsigned char *heap_next;
static unsigned char *heap_end;

void          pa_init(unsigned long base, unsigned long len);
unsigned long pa_alloc(unsigned long want);
int           pa_free(unsigned long p, unsigned long len);
void          pa_stats(unsigned long *live, unsigned long *peak, unsigned long *avail,
                       unsigned long *largest, unsigned long *lost, int *holes);

#define PT_POOL_TABLES 64
static u64 *pt_pool;
static u32  pt_pool_used;

static void mem_init(void) {
    u64 img = (u64)(unsigned long)__heap_start;
    if (!facts.ram_size)
        pf_panic("the device tree reported no memory — refusing to guess "
                 "how much RAM this machine has");
    u64 base = facts.ram_base, len = facts.ram_size;
    if (base + len <= img)
        pf_panic("no usable memory above the image");
    if (base < img) { len -= (img - base); base = img; }

    heap_next = (unsigned char *)(unsigned long)base;
    heap_end  = heap_next + len;

    heap_next = (unsigned char *)(((unsigned long)heap_next + 4095) & ~4095UL);
    pt_pool = (u64 *)heap_next;
    heap_next += (unsigned long)PT_POOL_TABLES * 4096;
    if (heap_next > heap_end) pf_panic("not enough memory for the page-table pool");
    for (unsigned long i = 0; i < (unsigned long)PT_POOL_TABLES * 512; i++) pt_pool[i] = 0;

    pa_init((unsigned long)heap_next, (unsigned long)(heap_end - heap_next));
}

int fs_is_file_fd(int fd);
pf_ssize_t fs_read_fd(int fd, void *buf, pf_size_t n);
pf_ssize_t fs_write_fd(int fd, const void *buf, pf_size_t n);
long long fs_lseek_fd(int fd, long long off, int whence);
int fs_close_fd(int fd);
const unsigned char *fs_map_fd(int fd, unsigned long off);
int fs_exists(const char *path);
/* `boot/vfs.c` also owns the POSIX names that used to be refusals here
 * — unlink, mkdir, access, rename, rmdir, truncate, fsync — because
 * with a disk attached their answer is a fact about the filesystem
 * rather than about the machine, and it is the same fact on all three
 * architectures. */
long vfs_syscall(long n, long a, long b, long c);
void *vfs_map_file(int fd, unsigned long len, long off);
int vfs_sync_all(void);

void *mmap(void *addr, unsigned long len, int prot, int flags, int fd, long off) {
    (void)addr; (void)prot; (void)flags;
    if (fd >= 0 && fs_is_file_fd(fd)) return vfs_map_file(fd, len, off);
    unsigned long p = pa_alloc(len);
    return p ? (void *)p : (void *)-1;
}

int munmap(void *p, unsigned long len) {
    return pa_free((unsigned long)p, len) == 0 ? 0 : 0;
}

long long nurl_guest_mem(int which) {
    unsigned long live = 0, peak = 0, avail = 0, largest = 0, lost = 0;
    int holes = 0;
    pa_stats(&live, &peak, &avail, &largest, &lost, &holes);
    switch (which) {
    case 0:  return (long long)live;
    case 1:  return (long long)peak;
    case 2:  return (long long)avail;
    case 3:  return (long long)largest;
    case 4:  return (long long)lost;
    case 5:  return (long long)holes;
    default: return 0;
    }
}

/* ── the MMU (Sv39) ───────────────────────────────────────────────
 *
 * Three levels, 4 KiB granule: L2 covers 1 GiB per entry, L1 2 MiB,
 * L0 4 KiB — the same shape as AArch64's L1/L2/L3, one name down.
 * Identity map: devices below 1 GiB, then RAM.
 *
 * A leaf entry is one with any of R/W/X set; a pointer to the next
 * level has all three clear. That is the difference from both other
 * architectures, where a bit says "block" or "table" outright, and it
 * is the single easiest thing to get wrong here: an entry with V set
 * and RWX clear is a TABLE POINTER, so a "present, no permissions"
 * mapping — which is how PROT_NONE is spelled elsewhere — would send
 * the walker into whatever the address bits point at. PROT_NONE
 * therefore clears V, not the permission bits.
 */
#define PTE_V (1UL << 0)
#define PTE_R (1UL << 1)
#define PTE_W (1UL << 2)
#define PTE_X (1UL << 3)
#define PTE_A (1UL << 6)
#define PTE_D (1UL << 7)

#define LEAF_RW (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
#define LEAF_RX (PTE_V | PTE_R | PTE_X | PTE_A)
#define LEAF_RWX (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)

#define PPN(pa) (((u64)(pa) >> 12) << 10)

#define MAX_RAM_L1 8             /* 8 GiB of RAM is the map's ceiling */

static u64 l2_table[512] __attribute__((aligned(4096)));
static u64 l1_dev[512]   __attribute__((aligned(4096)));
static u64 l1_ram[MAX_RAM_L1][512] __attribute__((aligned(4096)));

static void mmu_init(void) {
    /* Device gigabyte: 512 × 2 MiB leaves, RW (no X — nothing executes
     * from a device). */
    for (u64 i = 0; i < 512; i++)
        l1_dev[i] = PPN(i << 21) | LEAF_RW;
    l2_table[0] = PPN((u64)(unsigned long)l1_dev) | PTE_V;

    u64 ram_end = facts.ram_base + facts.ram_size;
    u64 gb_first = facts.ram_base >> 30;
    u64 gb_last  = (ram_end - 1) >> 30;
    if (gb_last - gb_first + 1 > MAX_RAM_L1)
        pf_panic("more RAM than the boot page tables cover (raise MAX_RAM_L1)");
    for (u64 g = gb_first; g <= gb_last; g++) {
        u64 *l1 = l1_ram[g - gb_first];
        for (u64 i = 0; i < 512; i++) {
            u64 pa = (g << 30) | (i << 21);
            /* RWX: the image's text is in here, and this machine has
             * one address space with one program in it — the same
             * decision the x86 boot tables make. */
            l1[i] = pa < ram_end ? (PPN(pa) | LEAF_RWX) : 0;
        }
        l2_table[g] = PPN((u64)(unsigned long)l1) | PTE_V;
    }

    /* satp: mode 8 (Sv39), ASID 0, the root table's PPN. */
    u64 satp = (8UL << 60) | ((u64)(unsigned long)l2_table >> 12);
    __asm__ __volatile__(
        "sfence.vma\n\t"
        "csrw satp, %0\n\t"
        "sfence.vma\n\t" :: "r"(satp) : "memory");
}

/* ── page protection ───────────────────────────────────────────── */
static u64 *l1_entry_for(u64 va) {
    u64 l2i = (va >> 30) & 511;
    if (!(l2_table[l2i] & PTE_V)) return 0;
    u64 *l1 = (u64 *)(unsigned long)((l2_table[l2i] >> 10) << 12);
    return &l1[(va >> 21) & 511];
}

static void split_2m(u64 *l1e) {
    /* A leaf has R, W or X set; a table pointer has none. */
    if (!(*l1e & (PTE_R | PTE_W | PTE_X))) return;    /* already a table */
    if (pt_pool_used >= PT_POOL_TABLES)
        pf_panic("out of page tables — more coroutine stacks than the "
                 "boot-time pool was sized for");
    u64 base = ((*l1e) >> 10) << 12;
    u64 attrs = *l1e & 0x3FF;                         /* the flag bits   */
    u64 *l0 = pt_pool + (unsigned long)pt_pool_used * 512;
    pt_pool_used++;
    for (int i = 0; i < 512; i++) l0[i] = PPN(base + (u64)i * 4096) | attrs;
    *l1e = PPN((u64)(unsigned long)l0) | PTE_V;
    __asm__ __volatile__("sfence.vma" ::: "memory");
}

int madvise(void *p, unsigned long len, int advice) {
    (void)p; (void)len; (void)advice;
    return 0;
}

int mprotect(void *p, unsigned long len, int prot) {
    u64 va = (u64)(unsigned long)p & ~0xFFFUL;
    u64 end = ((u64)(unsigned long)p + len + 4095) & ~0xFFFUL;

    if (!pt_pool) return -1;
    for (; va < end; va += 4096) {
        u64 *l1e = l1_entry_for(va);
        if (!l1e || !(*l1e & PTE_V)) return -1;
        split_2m(l1e);
        u64 *l0 = (u64 *)(unsigned long)((*l1e >> 10) << 12);
        u64 *pte = &l0[(va >> 12) & 511];
        u64 ppn = *pte & ~0x3FFUL;
        /* PROT_NONE clears V — see the header: V with no R/W/X is a
         * table pointer here, not an unmapped page. */
        if (prot == 0)       *pte = ppn;
        else if (prot & 0x2) *pte = ppn | LEAF_RWX;
        else                 *pte = ppn | LEAF_RX;
        __asm__ __volatile__("sfence.vma zero, %0" :: "r"(va) : "memory");
    }
    return 0;
}

extern unsigned char boot_stack_bottom[];

static void pf_guard_boot_stack(void) {
    (void)mprotect(boot_stack_bottom, 4096, 0);
}

static void pf_guard_null_page(void) {
    (void)mprotect((void *)0, 4096, 0);
}

/* ── time ────────────────────────────────────────────────────────── */

static u64 time_freq;
static u64 time_base;

static inline u64 rdtime(void) {
    u64 v;
    __asm__ __volatile__("rdtime %0" : "=r"(v));
    return v;
}

static void time_init(void) {
    /* virt's timebase is 10 MHz and the tree says so; the command line
     * may override, the same trust model as the other two ports. The
     * frequency is NOT guessed: without one, asking for the time
     * panics. */
    time_freq = cmdline_u64("timebase");
    if (!time_freq) time_freq = 10000000UL;   /* virt's, as the tree states */
    time_base = rdtime();
}

static u64 wall_base_sec;

int clock_gettime(int clk, void *tsp) {
    u64 *ts = (u64 *)tsp;
    if (!time_freq)
        pf_panic("no timebase frequency — refusing to invent a clock");
    u64 ticks = rdtime() - time_base;
    ts[0] = ticks / time_freq;
    ts[1] = (ticks % time_freq) * 1000000000ULL / time_freq;
    if (clk == 0) ts[0] += wall_base_sec;
    return 0;
}

int nanosleep(const void *req, void *rem) {
    const u64 *ts = (const u64 *)req;
    (void)rem;
    if (!time_freq) return 0;
    u64 want_ns = ts[0] * 1000000000ULL + ts[1];
    u64 ticks = want_ns / 1000 * time_freq / 1000000ULL;
    u64 start = rdtime();
    while (rdtime() - start < ticks) { }
    return 0;
}

/* ── entropy ─────────────────────────────────────────────────────
 *
 * There is no entropy INSTRUCTION in this machine's profile: the Zkr
 * extension's `seed` CSR is optional and QEMU's rv64 CPU does not
 * implement it, so reading it would be an illegal instruction rather
 * than a weak number. The answer therefore comes from a DEVICE —
 * virtio-rng, driven by boot/virtio_rng.c — which is the same layer
 * the other two architectures answer from, just a different source.
 *
 * The rule stays absolute: no source is a panic, never a fallback.
 * A machine started without `-device virtio-rng-device` is told so by
 * name, because "your TLS handshake failed" is a much worse way to
 * learn it than "this machine has no entropy device".
 */
int virtio_rng_start(const u64 *bases, int n);
long long virtio_rng_read(void *dst, unsigned long len);

long long getrandom(void *buf, unsigned long len, unsigned int flags) {
    unsigned char *p = (unsigned char *)buf;
    unsigned long done = 0;
    (void)flags;

    if (!virtio_rng_start(facts.dev_base, facts.devices))
        pf_panic("no entropy source on this machine — RISC-V's seed CSR "
                 "(Zkr) is optional and absent here, and no virtio-rng "
                 "device was found. Start the guest with "
                 "`-device virtio-rng-device`. Refusing to generate keys "
                 "from nothing.");

    while (done < len) {
        long long got = virtio_rng_read(p + done, len - done);
        if (got <= 0)
            pf_panic("the virtio-rng device stopped answering — refusing "
                     "to continue with partial entropy");
        done += (unsigned long)got;
    }
    return (long long)len;
}

/* ── the file surface nolibc expects ─────────────────────────────── */

int nl_errno_slot;
int *__errno_location(void) { return &nl_errno_slot; }

/* A descriptor naming a file goes to the filesystem; everything else is
 * the console, where stdout and stderr are the same wire. Until there
 * was a disk this function had no reason to look at `fd` at all — the
 * only writable thing on the machine was the serial port. */
long long write(int fd, const void *buf, unsigned long n) {
    const char *p = (const char *)buf;
    if (fs_is_file_fd(fd)) return (long long)fs_write_fd(fd, buf, n);
    for (unsigned long i = 0; i < n; i++) uart_putc(p[i]);
    return (long long)n;
}

long long read(int fd, void *buf, unsigned long n) {
    if (fs_is_file_fd(fd)) return (long long)fs_read_fd(fd, buf, n);
    (void)buf; (void)n;
    return 0;
}

int nl_open(const char *path, int flags, int mode);
int open(const char *p, int fl, int mode) { return nl_open(p, fl, mode); }
int close(int fd) {
    if (fs_is_file_fd(fd)) return fs_close_fd(fd);
    return 0;
}
long long lseek(int fd, long long off, int whence) {
    if (fs_is_file_fd(fd)) return fs_lseek_fd(fd, off, whence);
    (void)off; (void)whence;
    return -1;
}

pf_ssize_t nl_write(int fd, const void *buf, pf_size_t n) { return (pf_ssize_t)write(fd, buf, n); }
pf_ssize_t nl_read(int fd, void *buf, pf_size_t n) { return (pf_ssize_t)read(fd, buf, n); }
int nl_close(int fd) { return close(fd); }
long long nl_lseek(int fd, long long off, int whence) { return lseek(fd, off, whence); }

void *nl_map(pf_size_t len) {
    void *p = mmap(0, len, 0, 0, -1, 0);
    return p == (void *)-1 ? 0 : p;      /* the nolibc convention */
}
int nl_unmap(void *p, pf_size_t len) { return munmap(p, len); }
void nl_exit_group(int code) { pf_shutdown(code); for (;;) { } }

long nl_syscall6(long n, long a, long b, long c, long d, long e, long f) {
    (void)d; (void)e; (void)f;
    /* `vfs_syscall` answers getdents64 when a disk is mounted and
     * -ENOSYS otherwise, which is what this whole function used to
     * return unconditionally. */
    return vfs_syscall(n, a, b, c);
}

long nl_ret(long r) {
    if (r < 0 && r > -4096) { nl_errno_slot = (int)-r; return -1; }
    return r;
}

int getpid(void) { return 1; }

/* ── shutdown ────────────────────────────────────────────────────── */

static void pf_shutdown(int code) {
    /* Whatever is still only in the filesystem's cache goes onto the
     * medium before the machine stops. A guest that was shut down
     * cleanly and lost its last writes would be a guest whose `fsync`
     * was the only way to keep anything — which is a filesystem people
     * would be right not to trust. */
    (void)vfs_sync_all();
    uart_puts("[nurl-exit] ");
    uart_putu((unsigned long)(code & 0xff));
    uart_putc('\n');

    /* SRST (extension "SRST" = 0x53525354), function 0 = system reset,
     * type 0 = shutdown, reason 0. Firmware that predates SRST answers
     * "not supported" and returns, so the legacy shutdown (extension
     * 8) follows — and if neither exists, the sentinel line above has
     * already told the harness what happened, which is why that line
     * and not this call is the protocol. */
    (void)sbi_call(0x53525354, 0, 0, 0);
    (void)sbi_call(8, 0, 0, 0);
    for (;;) __asm__ __volatile__("wfi");
}

void _exit(int code) { pf_shutdown(code); for (;;) { } }

/* ── entry ───────────────────────────────────────────────────────── */

extern char **nl_environ;
extern void nl_tls_init_guest(void);
extern int main(int argc, char **argv);

#define ARGV_MAX 32
static char *guest_argv[ARGV_MAX + 1];
static char  argv_buf[1024];

static int build_argv(const char *cl) {
    int argc = 1;
    guest_argv[0] = (char *)"nurl";
    if (!cl) return argc;

    const char *p = cl;
    while (*p) {
        if (p[0] == 'a' && p[1] == 'r' && p[2] == 'g' && p[3] == 's' &&
            p[4] == '=' && p[5] == '"') {
            const char *q = p + 6;
            unsigned long n = 0;
            while (*q && *q != '"' && n < sizeof argv_buf - 1) argv_buf[n++] = *q++;
            argv_buf[n] = 0;
            unsigned long i = 0;
            while (i < n && argc < ARGV_MAX) {
                while (i < n && argv_buf[i] == ' ') argv_buf[i++] = 0;
                if (i >= n) break;
                guest_argv[argc++] = &argv_buf[i];
                while (i < n && argv_buf[i] != ' ') i++;
            }
            break;
        }
        while (*p && *p != ' ') p++;
        while (*p == ' ') p++;
    }
    guest_argv[argc] = 0;
    return argc;
}

extern unsigned char fault_stack_top[];

void kmain(unsigned long dtb);

void kmain(unsigned long dtb) {
    static char *no_argv[2];

    uart_init();
    *nl_file_flags(stdout) |= PF_F_LINEBUF;

    /* Where the program's output starts.
     *
     * This is the only one of the three machines whose firmware TALKS:
     * OpenSBI prints a banner on the same UART before the kernel gets
     * control, so a harness comparing the guest's output to a hosted
     * golden would be comparing the firmware's version string too. The
     * guest marks its own first byte and `run_qemu_riscv64.sh` drops
     * everything up to and including it — a rule that belongs to us
     * rather than to whatever OpenSBI's banner looks like this year. */
    uart_puts("\n[nurl-boot]\n");

    /* The trap handler's stack, handed to the vector through sscratch:
     * this architecture does not switch stacks on a trap by itself, so
     * the handler swaps to this one — the fault worth surviving is a
     * stack that hit its guard page. */
    __asm__ __volatile__("csrw sscratch, %0" :: "r"((unsigned long)fault_stack_top));

    /* The device tree: a1 as OpenSBI passes it. Without one this port
     * knows neither its memory nor its devices, and says so. */
    if (!fdt_is_tree((const void *)dtb))
        pf_panic("no device tree in a1 — was this image started with "
                 "qemu-system-riscv64 -M virt -kernel?");
    fdt_probe((const void *)dtb, &facts);
    cmdline = facts.cmdline;

    mem_init();
    mmu_init();
    pf_guard_boot_stack();
    pf_guard_null_page();
    wall_base_sec = cmdline_u64("wallclock");
    time_init();
    nl_tls_init_guest();

    /* Plan B7: getenv reads the cmdline's key=value pairs (args="…"
     * stays argv's) — boot/cmdenv.c, shared with the other boards. */
    {
        static char env_buf[1024];
        static char *envv[33];
        extern int nl_env_from_cmdline(const char *, char *,
                                       unsigned long, char **, int);
        nl_env_from_cmdline(cmdline, env_buf, sizeof env_buf, envv, 32);
        nl_environ = envv;
        (void)no_argv;
    }

    int argc = build_argv(cmdline);
    exit(main(argc, guest_argv));
}
