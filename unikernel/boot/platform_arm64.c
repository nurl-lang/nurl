/*
 * NURL unikernel — unikernel/boot/platform_arm64.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The guest's bottom edge on AArch64 (QEMU virt) — the twin of
 * platform_x86.c, and hand-synced with it the way that file is
 * hand-synced with nolibc/syscall_linux.c. The five services are the
 * same; the machinery under each one differs:
 *
 *   write        a PL011 UART at 0x0900_0000.
 *   memory       the /memory node of the device tree, never a guess,
 *                over the same boot/pagealloc.c.
 *   time         the generic timer: CNTVCT_EL0 counts, CNTFRQ_EL0
 *                states the frequency — this machine's clock is
 *                self-describing, so the x86 `tsc_khz=` handshake is
 *                an x86 quirk, not part of the contract. `wallclock=`
 *                stays: a wall clock is the host's to state.
 *   entropy      RNDR, ID-register-gated. No source is a panic,
 *                never a fallback — same absolute rule.
 *   exit         the sentinel line, then PSCI SYSTEM_OFF (HVC, then
 *                SMC for a conduit that wants it), then WFI.
 *
 * Plus the one thing x86 got from its hypervisor for free: microvm
 * announces virtio-mmio devices on the kernel command line, virt
 * announces them in the device tree. The NURL side (hal/virtio.nu)
 * parses `virtio_mmio.device=` entries, so this file reads the tree
 * and SYNTHESIZES those entries onto the command line — one format
 * for the layer above, whatever the machine spoke below.
 */

void exit(int code);          /* nolibc/misc.c */
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

/* ── the serial port ─────────────────────────────────────────────── */

#define PL011_BASE 0x09000000UL
#define PL011_DR   (*(volatile u32 *)(PL011_BASE + 0x00))
#define PL011_FR   (*(volatile u32 *)(PL011_BASE + 0x18))
#define PL011_CR   (*(volatile u32 *)(PL011_BASE + 0x30))

static void uart_init(void) {
    /* QEMU's PL011 comes up usable; setting UARTEN|TXE is stating what
     * we rely on rather than trusting the reset state. */
    PL011_CR = (1u << 0) | (1u << 8);
}

static void uart_putc(char c) {
    if (c == '\n') {
        while (PL011_FR & (1u << 5)) { }     /* TXFF */
        PL011_DR = '\r';
    }
    while (PL011_FR & (1u << 5)) { }
    PL011_DR = (u32)(unsigned char)c;
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

/* ── faults ──────────────────────────────────────────────────────
 *
 * The frame vec_common in boot_arm64.S builds, low address first. The
 * two files are read together; changing one without the other is a
 * fault report that describes the wrong registers. */
struct fault_frame {
    u64 x[31];                /* x0–x30 */
    u64 elr, spsr, esr, far;
};

static const char *vec_name(u64 v) {
    switch (v) {
    case 0:  return "sync (kernel)";
    case 1:  return "IRQ";
    case 2:  return "FIQ";
    case 3:  return "SError";
    case 4:  return "sync IN THE FAULT HANDLER";
    case 5:  return "IRQ on the fault stack";
    case 6:  return "FIQ on the fault stack";
    case 7:  return "SError on the fault stack";
    default: return "from a lower EL (nothing should run there)";
    }
}

/* ESR_EL1.EC — the exception class. The names are the manual's, so a
 * report is something someone can look up rather than a number. */
static const char *esr_class(u64 esr) {
    switch ((esr >> 26) & 0x3F) {
    case 0x00: return "unknown reason";
    case 0x07: return "FP/SIMD access trapped (CPACR misconfigured?)";
    case 0x0E: return "illegal execution state";
    case 0x15: return "SVC (no syscalls exist on this machine)";
    case 0x18: return "trapped system-register access";
    case 0x20: return "instruction abort (exec of unmapped/forbidden page)";
    case 0x21: return "instruction abort (kernel)";
    case 0x22: return "PC alignment";
    case 0x24: return "data abort";
    case 0x25: return "data abort (kernel)";
    case 0x26: return "SP alignment";
    case 0x2C: return "FP exception";
    case 0x3C: return "BRK";
    default:   return "see ESR.EC in the ARM ARM";
    }
}

void pf_exception(u64 vector, struct fault_frame *f);

void pf_exception(u64 vector, struct fault_frame *f) {
    u64 ec = (f->esr >> 26) & 0x3F;
    uart_puts("\nnurl: fault ");
    uart_puts(vec_name(vector));
    uart_puts(" — ");
    uart_puts(esr_class(f->esr));
    uart_puts("\n  esr=");
    uart_puthex(f->esr);
    uart_puts(" elr=");
    uart_puthex(f->elr);
    uart_puts(" spsr=");
    uart_puthex(f->spsr);
    if (ec == 0x20 || ec == 0x21 || ec == 0x24 || ec == 0x25) {
        uart_puts("\n  far=");
        uart_puthex(f->far);
        /* WnR is only meaningful for data aborts. */
        if (ec == 0x24 || ec == 0x25)
            uart_puts((f->esr >> 6) & 1 ? " on write" : " on read");
        else
            uart_puts(" on instruction fetch");
    }
    uart_puts("\n  x0=");  uart_puthex(f->x[0]);
    uart_puts(" x1=");     uart_puthex(f->x[1]);
    uart_puts(" x2=");     uart_puthex(f->x[2]);
    uart_puts(" x3=");     uart_puthex(f->x[3]);
    uart_puts("\n  x19="); uart_puthex(f->x[19]);
    uart_puts(" x29=");    uart_puthex(f->x[29]);
    uart_puts(" x30=");    uart_puthex(f->x[30]);
    uart_putc('\n');
    /* 126, not 127: a fault is not a panic, and the harness can tell. */
    pf_shutdown(126);
    for (;;) __asm__ __volatile__("wfi");
}

/* ── the device tree ─────────────────────────────────────────────
 *
 * In unikernel/boot/fdt.c, because the RISC-V port needs exactly the
 * same three answers from exactly the same format — and two ports
 * parsing one tree separately is where two machines start disagreeing
 * about what it says. This file keeps only what is machine-specific.
 */
#define FDT_MAX_DEVS 32
struct fdt_facts {
    unsigned long long ram_base;
    unsigned long long ram_size;
    char  cmdline[2048];
    unsigned long cmdline_len;
    int   devices;
    /* Where they are. This port answers entropy from RNDR and does not
     * need the list, but the struct is fdt.c's and a declaration that
     * drifts from it would read the wrong fields — the twin-file rule
     * this directory exists to enforce. */
    unsigned long long dev_base[FDT_MAX_DEVS];
};
int fdt_is_tree(const void *p);
int fdt_probe(const void *fdt, struct fdt_facts *out);

static struct fdt_facts facts;

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
int  pa_owns(unsigned long p, unsigned long len);

/* Defined below; declared here because `munmap` restores a range's
 * protection before returning it to the allocator. */
int mprotect(void *p, unsigned long len, int prot);
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
    /* A page goes back to the allocator MAPPED, and that is an
     * invariant rather than a courtesy.
     *
     * A coroutine's stack is allocated here and its guard page is then
     * mprotect'ed PROT_NONE — the present bit cleared in its PTE. When
     * the coroutine ends, this used to return the whole range to the
     * page allocator with that bit still clear, so the guard page went
     * back into the pool unmapped. Nothing noticed until something else
     * was handed it: nolibc's malloc carved an arena across it and the
     * first write to a block landing on that page took a #PF on a
     * not-present page, INSIDE malloc, long after the coroutine that
     * protected it had gone. Measured cost of finding that from the
     * fault alone: an afternoon. Twenty connections that send one byte
     * and hang up were enough to kill a server.
     *
     * So: restore before releasing, and only for ranges that are ours —
     * a mapping of the baked-in filesystem points into the image, and
     * rewriting page tables for it would be a write into somebody
     * else's business. `pa_free` rejects those by address; `pa_owns`
     * asks the same question first, because the order matters: a range
     * must never be on the free list while it is still unmapped. */
    if (!pa_owns((unsigned long)p, len)) return 0;
    (void)mprotect(p, len, 0x1 | 0x2);   /* PROT_READ | PROT_WRITE */
    (void)pa_free((unsigned long)p, len);
    return 0;
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

/* ── the MMU ──────────────────────────────────────────────────────
 *
 * Up in C, where a mistake can still print. Identity map, 39-bit VA,
 * 4 KiB granule: L1 covers 1 GiB per entry, L2 2 MiB, L3 4 KiB.
 *
 *   [0, 1G)    device memory, via an L2 table of 2 MiB blocks — a
 *              table and not one big block so the null guard can
 *              later split its first 2 MiB down to pages.
 *   RAM        Normal write-back cacheable, 2 MiB L2 blocks, as many
 *              L1 slots as the /memory node says the machine has.
 *
 * The MMU is not optional here even though C runs without it: the
 * exclusive-access instructions the runtime's atomics compile to are
 * only architecturally defined on cacheable memory, and mprotect —
 * the guard pages under every coroutine stack — needs pages to
 * protect. The x86 twin runs on 2 MiB pages split on demand from a
 * boot-reserved pool; this one does exactly the same, from the same
 * pool design, for the same reason (splitting must not allocate).
 */
#define PTE_VALID   (1UL << 0)
#define PTE_TABLE   (1UL << 1)   /* L1/L2: next level. L3: page entry */
#define PTE_AF      (1UL << 10)
#define PTE_SH_IS   (3UL << 8)
#define PTE_ATTR(n) ((u64)(n) << 2)
#define PTE_RO      (1UL << 7)   /* AP[2]: read-only at EL1           */
#define PTE_UXN     (1UL << 54)

#define ATTR_NORMAL 0            /* MAIR slot 0: normal WB            */
#define ATTR_DEV    1            /* MAIR slot 1: Device-nGnRE         */

#define BLK_RAM  (PTE_VALID | PTE_AF | PTE_SH_IS | PTE_ATTR(ATTR_NORMAL) | PTE_UXN)
#define BLK_DEV  (PTE_VALID | PTE_AF | PTE_ATTR(ATTR_DEV) | PTE_UXN)
#define PG_RAM   (BLK_RAM | PTE_TABLE)   /* an L3 page sets bit 1     */
#define PG_DEV   (BLK_DEV | PTE_TABLE)

#define MAX_RAM_L2 8             /* 8 GiB of RAM is the map's ceiling */

static u64 l1_table[512]  __attribute__((aligned(4096)));
static u64 l2_dev[512]    __attribute__((aligned(4096)));
static u64 l2_ram[MAX_RAM_L2][512] __attribute__((aligned(4096)));

static void mmu_init(void) {
    /* Device gigabyte: 512 × 2 MiB blocks. Execute-never, uncached. */
    for (u64 i = 0; i < 512; i++)
        l2_dev[i] = (i << 21) | BLK_DEV;
    l1_table[0] = ((u64)(unsigned long)l2_dev) | PTE_VALID | PTE_TABLE;

    /* RAM, from where the tree says it starts to where it says it
     * ends, one L2 table per gigabyte. */
    u64 ram_end = facts.ram_base + facts.ram_size;
    u64 gb_first = facts.ram_base >> 30;
    u64 gb_last  = (ram_end - 1) >> 30;
    if (gb_last - gb_first + 1 > MAX_RAM_L2)
        pf_panic("more RAM than the boot page tables cover (raise MAX_RAM_L2)");
    for (u64 g = gb_first; g <= gb_last; g++) {
        u64 *l2 = l2_ram[g - gb_first];
        for (u64 i = 0; i < 512; i++) {
            u64 pa = (g << 30) | (i << 21);
            l2[i] = pa < ram_end ? (pa | BLK_RAM) : 0;
        }
        l1_table[g] = ((u64)(unsigned long)l2) | PTE_VALID | PTE_TABLE;
    }

    /* MAIR: slot 0 normal WB (0xFF), slot 1 Device-nGnRE (0x04). */
    u64 mair = 0xFFUL | (0x04UL << 8);
    /* TCR: 39-bit VA (T0SZ=25), 4 KiB granule, WB WA cacheable walks,
     * inner shareable, TTBR1 walks off, 40-bit IPA. */
    u64 tcr = 25UL | (1UL << 8) | (1UL << 10) | (3UL << 12)
            | (0UL << 14) | (1UL << 23) | (2UL << 32);

    __asm__ __volatile__(
        "msr MAIR_EL1, %0\n\t"
        "msr TCR_EL1, %1\n\t"
        "msr TTBR0_EL1, %2\n\t"
        "isb\n\t"
        :: "r"(mair), "r"(tcr), "r"((u64)(unsigned long)l1_table));

    u64 sctlr;
    __asm__ __volatile__("mrs %0, SCTLR_EL1" : "=r"(sctlr));
    sctlr |= (1UL << 0) | (1UL << 2) | (1UL << 12);   /* M | C | I */
    __asm__ __volatile__(
        "dsb sy\n\t"
        "msr SCTLR_EL1, %0\n\t"
        "isb\n\t"
        "tlbi vmalle1\n\t"
        "dsb sy\n\t"
        "isb\n\t" :: "r"(sctlr));
}

/* ── page protection ─────────────────────────────────────────────
 * Same contract, same pool discipline as the x86 twin; the tree is
 * one level deeper. */
static u64 *l2_entry_for(u64 va) {
    u64 l1i = (va >> 30) & 511;
    if (!(l1_table[l1i] & PTE_VALID)) return 0;
    u64 *l2 = (u64 *)(unsigned long)(l1_table[l1i] & 0x0000FFFFFFFFF000UL);
    return &l2[(va >> 21) & 511];
}

static void split_2m(u64 *l2e) {
    if (*l2e & PTE_TABLE) return;                    /* already a table */
    if (pt_pool_used >= PT_POOL_TABLES)
        pf_panic("out of page tables — more coroutine stacks than the "
                 "boot-time pool was sized for");
    u64 base = *l2e & 0x0000FFFFFFE00000UL;
    u64 attrs = (*l2e & ~0x0000FFFFFFE00000UL) | PTE_TABLE;
    u64 *l3 = pt_pool + (unsigned long)pt_pool_used * 512;
    pt_pool_used++;
    for (int i = 0; i < 512; i++) l3[i] = (base + (u64)i * 4096) | attrs;
    *l2e = ((u64)(unsigned long)l3) | PTE_VALID | PTE_TABLE;
    __asm__ __volatile__("dsb ish" ::: "memory");
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
        u64 *l2e = l2_entry_for(va);
        if (!l2e || !(*l2e & PTE_VALID)) return -1;
        split_2m(l2e);
        u64 *l3 = (u64 *)(unsigned long)(*l2e & 0x0000FFFFFFFFF000UL);
        u64 *pte = &l3[(va >> 12) & 511];
        u64 frame = *pte & 0x0000FFFFFFFFF000UL;
        if (prot == 0)       *pte = frame;                    /* invalid */
        else if (prot & 0x2) *pte = frame | PG_RAM;
        else                 *pte = frame | PG_RAM | PTE_RO;
        __asm__ __volatile__(
            "dsb ishst\n\t"
            "tlbi vaae1, %0\n\t"
            "dsb ish\n\t"
            "isb\n\t" :: "r"(va >> 12) : "memory");
    }
    return 0;
}

extern unsigned char boot_stack_bottom[];

static void pf_guard_boot_stack(void) {
    (void)mprotect(boot_stack_bottom, 4096, 0);
}

/* Page zero sits in the device gigabyte; unmapping it makes a null
 * dereference the fault every caller's error handling was written
 * against, exactly as on x86. Nothing this port needs lives below
 * 4096 — the DTB is at the start of RAM, not at zero. */
static void pf_guard_null_page(void) {
    (void)mprotect((void *)0, 4096, 0);
}

/* ── time ────────────────────────────────────────────────────────── */

static u64 cnt_freq;
static u64 cnt_base;
static u64 wall_base_sec;

static inline u64 cntvct(void) {
    u64 v;
    __asm__ __volatile__("isb; mrs %0, CNTVCT_EL0" : "=r"(v));
    return v;
}

static void time_init(void) {
    __asm__ __volatile__("mrs %0, CNTFRQ_EL0" : "=r"(cnt_freq));
    /* Self-describing hardware, but firmware is what programs CNTFRQ
     * and broken firmware exists; the command line may override, the
     * same trust model as x86's tsc_khz= (the host controls the whole
     * image anyway). */
    u64 told = cmdline_u64("cntfrq");
    if (told) cnt_freq = told;
    wall_base_sec = cmdline_u64("wallclock");
    cnt_base = cntvct();
}

int clock_gettime(int clk, void *tsp) {
    u64 *ts = (u64 *)tsp;
    if (!cnt_freq)
        pf_panic("CNTFRQ_EL0 reads zero and no cntfrq= on the command "
                 "line — refusing to invent a clock");
    u64 ticks = cntvct() - cnt_base;
    u64 sec  = ticks / cnt_freq;
    u64 rem  = ticks % cnt_freq;
    ts[0] = sec;
    ts[1] = rem * 1000000000ULL / cnt_freq;
    if (clk == 0) ts[0] += wall_base_sec;
    return 0;
}

int nanosleep(const void *req, void *rem) {
    const u64 *ts = (const u64 *)req;
    (void)rem;
    if (!cnt_freq) return 0;
    u64 want_ns = ts[0] * 1000000000ULL + ts[1];
    u64 ticks = want_ns / 1000 * cnt_freq / 1000000ULL;
    u64 start = cntvct();
    while (cntvct() - start < ticks) __asm__ __volatile__("yield");
    return 0;
}

/* ── entropy ─────────────────────────────────────────────────────── */

long long getrandom(void *buf, unsigned long len, unsigned int flags) {
    unsigned char *p = (unsigned char *)buf;
    unsigned long done = 0;
    u64 isar0;
    (void)flags;

    __asm__ __volatile__("mrs %0, ID_AA64ISAR0_EL1" : "=r"(isar0));
    if (((isar0 >> 60) & 0xF) == 0)
        pf_panic("no RNDR on this vCPU and no virtio-rng — refusing to "
                 "generate keys (use -cpu max)");

    while (done < len) {
        u64 v;
        u64 ok;
        int tries = 0;
        do {
            /* RNDR — s3_3_c2_c4_0; NZCV.Z set on failure. */
            __asm__ __volatile__(
                "mrs %0, s3_3_c2_c4_0\n\t"
                "cset %1, ne\n\t" : "=r"(v), "=r"(ok) :: "cc");
        } while (!ok && ++tries < 32);
        if (!ok) pf_panic("RNDR failed repeatedly — refusing to continue");
        for (int i = 0; i < 8 && done < len; i++, done++)
            p[done] = (unsigned char)(v >> (i * 8));
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
    return p == (void *)-1 ? 0 : p;      /* the nolibc convention — see the x86 twin */
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
    /* The sentinel line is the primary protocol on every arch — see
     * the x86 twin for why. */
    uart_puts("[nurl-exit] ");
    uart_putu((unsigned long)(code & 0xff));
    uart_putc('\n');

    /* PSCI SYSTEM_OFF (0x8400_0008). QEMU's virt board implements PSCI
     * for a guest that starts at EL1 over HVC, which is the conduit
     * this port uses (boot_arm64.S drops to EL1 immediately). SMC would
     * be the other conduit, and it is not attempted: assembling it
     * needs `.arch armv8-a+sm4`-class permission the freestanding build
     * does not grant, and a machine whose PSCI is behind SMC has
     * firmware this guest is not running under.
     *
     * If PSCI is absent the call returns and the loop below parks the
     * CPU — the sentinel line above has already told the harness what
     * happened, which is why that line and not this call is the
     * protocol. */
    register u64 x0 __asm__("x0") = 0x84000008;
    __asm__ __volatile__("hvc #0" :: "r"(x0) : "memory");
    for (;;) __asm__ __volatile__("wfi");
}

void _exit(int code) { pf_shutdown(code); for (;;) { } }

/* ── entry ───────────────────────────────────────────────────────── */

extern char **environ;          /* nolibc/misc.c owns the storage */
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

void kmain(unsigned long x0);

void kmain(unsigned long x0) {
    static char *no_argv[2];

    uart_init();
    *nl_file_flags(stdout) |= PF_F_LINEBUF;

    /* The device tree: x0 if whoever started us honoured the Linux
     * convention, the start of RAM otherwise (where QEMU's virt board
     * puts it for a bare-metal ELF). Without one this port knows
     * neither its memory nor its devices, and says so. */
    const void *fdt = 0;
    if (x0 && fdt_is_tree((const void *)x0))          fdt = (const void *)x0;
    else if (fdt_is_tree((const void *)0x40000000UL)) fdt = (const void *)0x40000000UL;
    if (!fdt)
        pf_panic("no device tree in x0 or at the start of RAM — was this "
                 "image started with qemu-system-aarch64 -M virt -kernel?");
    fdt_probe(fdt, &facts);
    cmdline = facts.cmdline;

    mem_init();
    mmu_init();
    pf_guard_boot_stack();
    pf_guard_null_page();
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
        environ = envv;
        (void)no_argv;
    }

    int argc = build_argv(cmdline);
    exit(main(argc, guest_argv));
}
