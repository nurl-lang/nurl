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
 *   write        an 8250 UART at 0x3F8, and — on a Multiboot2 boot,
 *                i.e. real hardware — the screen as well (see console.c;
 *                a laptop booted off a USB stick has no serial port
 *                for anyone to be listening on). Reads answer 0 (EOF):
 *                there is no console input, and pretending otherwise
 *                would hang a reader forever instead of ending its
 *                loop.
 *   memory       a bump allocator over the RAM the hypervisor reported.
 *                The upper bound is READ, never assumed — a guessed
 *                limit is a guest that corrupts itself on a machine
 *                with less RAM than the guess.
 *   time         the TSC, with its frequency from whichever of four
 *                sources can supply one: the hypervisor, the core
 *                crystal, the command line, the CPU's nameplate, or —
 *                on iron, where none of those exists — measured
 *                against the PIT. If nothing can supply one, asking
 *                for the time PANICS rather than returning a made-up
 *                number; the plan's rule for entropy, applied to the
 *                clock for the same reason.
 *   entropy      RDRAND, CPUID-gated. No source is a panic, never a
 *                fallback: this is where a "later TODO" becomes a
 *                weak key nobody notices.
 *   exit         a sentinel line on the serial port (the protocol both
 *                hypervisors can carry), then isa-debug-exit as a
 *                QEMU-side cross-check, then triple fault.
 */

#include "console.h"
#include "mb2.h"

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

/* The two things this file needs from nolibc's stdio: the stream and
 * the flag that makes a console behave like one. Declared rather than
 * included, the way the rest of this file declares what it uses. */
struct nl_file;
extern struct nl_file *stdout;
int *nl_file_flags(struct nl_file *f);
#define PF_F_LINEBUF 0x20

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

/* Wait for the transmit holding register to empty, but not for ever.
 *
 * Under a hypervisor there is always a UART and it is always ready. On
 * real hardware there may be no UART at all, and an absent port on a
 * PC bus usually reads back 0xFF — which has bit 5 set, so the loop
 * exits and the write goes nowhere, which is correct. "Usually" is the
 * problem: a machine whose chipset answers 0x00 instead would hang
 * here, in the console, before printing the thing that would have said
 * why. A bound turns that from a dead machine into a slow one. */
#define UART_SPIN 100000

static void uart_putc_raw(char c) {
    unsigned n = UART_SPIN;
    while (n-- && !(inb(COM1 + 5) & 0x20)) { }
    outb(COM1, (unsigned char)c);
}

/* Everything the guest prints goes through here: `write`, the panic
 * path and the fault report alike. Both sinks get every byte, because
 * which of them a human is actually looking at is a property of the
 * machine — a hypervisor holds the serial line, a laptop booted off a
 * USB stick has only the screen — and the guest cannot tell. */
static void pf_putc(char c) {
    /* Line feeds become CRLF: a serial terminal does not do it for us,
     * and the goldens this boot is checked against are line-oriented.
     * The screen wants no such thing — console_putc reads '\n' as "next
     * line, first column" — so the carriage return is the serial
     * port's alone. */
    if (c == '\n') uart_putc_raw('\r');
    uart_putc_raw(c);
    console_putc(c);
}

static void uart_puts(const char *s) { while (*s) pf_putc(*s++); }

static void uart_putu(unsigned long v) {
    char b[24];
    int n = 0;
    if (!v) { pf_putc('0'); return; }
    while (v) { b[n++] = (char)('0' + (v % 10)); v /= 10; }
    while (n) pf_putc(b[--n]);
}

static void uart_puthex(u64 v) {
    static const char digits[] = "0123456789abcdef";
    char b[16];
    int n = 0;
    uart_puts("0x");
    if (!v) { pf_putc('0'); return; }
    while (v) { b[n++] = digits[v & 15]; v >>= 4; }
    while (n) pf_putc(b[--n]);
}

/* ── panic ───────────────────────────────────────────────────────── */

static void pf_shutdown(int code);

void pf_panic(const char *msg) {
    uart_puts("nurl: ");
    uart_puts(msg);
    pf_putc('\n');
    pf_shutdown(127);
    for (;;) __asm__ __volatile__("cli; hlt");
}

/* ── faults ──────────────────────────────────────────────────────
 *
 * A machine with no IDT answers every exception the same way: the CPU
 * cannot deliver it, cannot deliver the double fault either, and shuts
 * down. From outside that is indistinguishable from a clean exit —
 * QEMU quits, the exit sentinel is simply absent — so the first thing
 * anyone knows about a null dereference is that the output stopped.
 * Every fault below is a bug in something above; the machine's job is
 * to say which one, where, and stop.
 *
 * IST1 for #DF and #PF, because the fault this most needs to survive is
 * a stack that hit its guard page: delivering that on the same stack
 * faults again, and the second fault is the last thing that happens.
 */

/* The register file `isr_common` in boot.S pushes, low address first.
 * The two files are read together; changing one without the other is a
 * fault report that describes the wrong registers. */
struct fault_frame {
    u64 r15, r14, r13, r12, r11, r10, r9, r8;
    u64 rbp, rdi, rsi, rdx, rcx, rbx, rax;
    u64 vector, errcode;
    u64 rip, cs, rflags, rsp, ss;
};

struct idt_entry {
    unsigned short off_lo;
    unsigned short sel;
    unsigned char  ist;
    unsigned char  type_attr;
    unsigned short off_mid;
    u32            off_hi;
    u32            zero;
} __attribute__((packed));

extern char isr_stubs[];              /* boot.S: 256 stubs, 16 bytes each */
extern char fault_stack_top[];
extern unsigned char tss64[];
extern u64 gdt64[];

static struct idt_entry idt[256];

/* The names are the ones every manual and every search result uses.
 * "vector 14" is a number; "#PF" is a thing someone can look up. */
static const char *fault_name(u64 v) {
    switch (v) {
    case 0:  return "#DE divide error";
    case 1:  return "#DB debug";
    case 2:  return "NMI";
    case 3:  return "#BP breakpoint";
    case 4:  return "#OF overflow";
    case 5:  return "#BR bound range";
    case 6:  return "#UD invalid opcode";
    case 7:  return "#NM device not available";
    case 8:  return "#DF double fault";
    case 10: return "#TS invalid TSS";
    case 11: return "#NP segment not present";
    case 12: return "#SS stack fault";
    case 13: return "#GP general protection";
    case 14: return "#PF page fault";
    case 16: return "#MF x87 exception";
    case 17: return "#AC alignment check";
    case 18: return "#MC machine check";
    case 19: return "#XM SIMD exception";
    default: return "unexpected interrupt";
    }
}

/* Called from isr_common with the frame it built and CR2 as read at
 * entry — reading CR2 here would be too late if anything in between
 * faulted, and nothing in between may. */
void pf_exception(struct fault_frame *f, u64 cr2);

void pf_exception(struct fault_frame *f, u64 cr2) {
    uart_puts("\nnurl: fault ");
    uart_puts(fault_name(f->vector));
    uart_puts(" vector=");
    uart_putu((unsigned long)f->vector);
    uart_puts(" err=");
    uart_puthex(f->errcode);
    uart_puts("\n  rip=");
    uart_puthex(f->rip);
    uart_puts(" rsp=");
    uart_puthex(f->rsp);
    uart_puts(" rflags=");
    uart_puthex(f->rflags);
    if (f->vector == 14) {
        uart_puts("\n  cr2=");
        uart_puthex(cr2);
        /* The error code's bits are the difference between "wrote to a
         * page that is not there" and "read one that is" — the first
         * question anyone asks, answered without a manual. */
        uart_puts(f->errcode & 1 ? " (protection)" : " (not present)");
        uart_puts(f->errcode & 2 ? " on write" : " on read");
        if (f->errcode & 16) uart_puts(" on instruction fetch");
    }
    uart_puts("\n  rax="); uart_puthex(f->rax);
    uart_puts(" rbx=");    uart_puthex(f->rbx);
    uart_puts(" rcx=");    uart_puthex(f->rcx);
    uart_puts(" rdx=");    uart_puthex(f->rdx);
    uart_puts("\n  rsi="); uart_puthex(f->rsi);
    uart_puts(" rdi=");    uart_puthex(f->rdi);
    uart_puts(" rbp=");    uart_puthex(f->rbp);
    pf_putc('\n');
    /* 126, not 127: a fault is not the same event as a panic, and a
     * harness that can tell them apart can say which one it saw. */
    pf_shutdown(126);
    for (;;) __asm__ __volatile__("cli; hlt");
}

static void idt_set(int n, unsigned long handler, unsigned char ist) {
    idt[n].off_lo    = (unsigned short)(handler & 0xFFFF);
    idt[n].sel       = 0x08;                    /* the 64-bit code segment */
    idt[n].ist       = ist;
    idt[n].type_attr = 0x8E;                    /* present, DPL 0, interrupt gate */
    idt[n].off_mid   = (unsigned short)((handler >> 16) & 0xFFFF);
    idt[n].off_hi    = (u32)(handler >> 32);
    idt[n].zero      = 0;
}

/* The TSS descriptor is sixteen bytes in long mode and its base is
 * split across three fields, which is why it is written here rather
 * than in the assembler's table. Type 9 = available 64-bit TSS. */
static void tss_init(void) {
    unsigned long base  = (unsigned long)tss64;
    unsigned long limit = 104 - 1;

    /* IST1, at offset 36 in the TSS: the stack #DF and #PF arrive on. */
    u64 top = (u64)(unsigned long)fault_stack_top;
    for (int i = 0; i < 104; i++) tss64[i] = 0;
    tss64[36] = (unsigned char)(top      & 0xFF);
    tss64[37] = (unsigned char)((top >> 8)  & 0xFF);
    tss64[38] = (unsigned char)((top >> 16) & 0xFF);
    tss64[39] = (unsigned char)((top >> 24) & 0xFF);
    tss64[40] = (unsigned char)((top >> 32) & 0xFF);
    tss64[41] = (unsigned char)((top >> 40) & 0xFF);
    tss64[42] = (unsigned char)((top >> 48) & 0xFF);
    tss64[43] = (unsigned char)((top >> 56) & 0xFF);
    /* No I/O permission bitmap: the limit says where it would start and
     * it starts past the end, which is how a TSS says "none". */
    tss64[102] = (unsigned char)(104 & 0xFF);
    tss64[103] = (unsigned char)((104 >> 8) & 0xFF);

    gdt64[3] = (u64)(limit & 0xFFFF)
             | ((u64)(base & 0xFFFFFF) << 16)
             | ((u64)0x9 << 40)                 /* type: available 64-bit TSS */
             | ((u64)1 << 47)                   /* present */
             | ((u64)((limit >> 16) & 0xF) << 48)
             | ((u64)((base >> 24) & 0xFF) << 56);
    gdt64[4] = (u64)(base >> 32);

    __asm__ __volatile__("ltr %w0" :: "r"((unsigned short)0x18));
}

static void idt_init(void) {
    for (int n = 0; n < 256; n++) {
        unsigned char ist = (n == 8 || n == 14) ? 1 : 0;
        idt_set(n, (unsigned long)(isr_stubs + 16 * n), ist);
    }
    struct { unsigned short limit; unsigned long base; } __attribute__((packed))
        idtr = { (unsigned short)(sizeof idt - 1), (unsigned long)idt };
    __asm__ __volatile__("lidt %0" :: "m"(idtr));
}

/* ── memory ──────────────────────────────────────────────────────── */

static unsigned char *heap_next;
static unsigned char *heap_end;

/* unikernel/boot/pagealloc.c — the pages themselves. Portable C, tested
 * on the host, so the one thing a guest cannot debug is the one thing
 * that is not written here. */
void          pa_init(unsigned long base, unsigned long len);
unsigned long pa_alloc(unsigned long want);
int           pa_free(unsigned long p, unsigned long len);
void          pa_stats(unsigned long *live, unsigned long *peak, unsigned long *avail,
                       unsigned long *largest, unsigned long *lost, int *holes);

#define PT_POOL_TABLES 64
static u64 *pt_pool;              /* PT_POOL_TABLES × 512 entries */
static u32  pt_pool_used;

/* The largest usable region at or above the image. Anything below the
 * image is where the image is, and a second region we could stitch on
 * buys nothing until there is a real allocator to stitch it into. */
static u64 ram_total;             /* every usable region, added up */

static void mem_init(const struct hvm_start_info *si) {
    u64 best_base = 0, best_len = 0;
    u64 img = (u64)(unsigned long)__heap_start;

    if (si && si->version >= 1 && si->memmap_entries && si->memmap_paddr) {
        const struct hvm_memmap_entry *e =
            (const struct hvm_memmap_entry *)(unsigned long)si->memmap_paddr;
        for (u32 i = 0; i < si->memmap_entries; i++) {
            u64 base = e[i].addr, len = e[i].size;
            if (e[i].type != 1) continue;
            /* Counted before the "is it above the image" filter below:
             * this is the machine's RAM as the firmware described it,
             * which is the number a person compares against the sticker
             * on the memory module. What the allocator can reach is a
             * smaller and separate question. */
            ram_total += len;
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

    /* Everything past the pool is the program's, and from here on it is
     * the page allocator's to hand out and take back. */
    pa_init((unsigned long)heap_next, (unsigned long)(heap_end - heap_next));
}

/* mmap and munmap, over the page allocator in boot/pagealloc.c: the
 * region the hypervisor reported, handed out in pages and TAKEN BACK.
 * The version this replaced was a bump pointer with a munmap that
 * reported success and did nothing, which is fine for a program that
 * runs once and wrong for a server — measured, it died on the 251st
 * megabyte of allocate-and-free on a 256 MiB machine. */
/* unikernel/boot/initfs.c — the baked-in filesystem. Declared here
 * because every one of these is reached from the POSIX names below,
 * which are what NURL's FFI actually calls. */
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
    /* A file-backed mapping goes to `boot/vfs.c`: a pointer into the
     * image when the file is in the archive, freshly-filled pages when
     * it is on the disk. Anonymous mappings fall through to the page
     * allocator below. */
    if (fd >= 0 && fs_is_file_fd(fd)) return vfs_map_file(fd, len, off);
    unsigned long p = pa_alloc(len);
    return p ? (void *)p : (void *)-1;      /* MAP_FAILED — the caller checks */
}

int munmap(void *p, unsigned long len) {
    /* A mapping of the baked-in filesystem points into the image, not
     * into the heap; pa_free rejects it by address, which is exactly the
     * check that keeps the image out of the free list. */
    return pa_free((unsigned long)p, len) == 0 ? 0 : 0;
}

/* What the machine has and what it is using — the numbers a long-running
 * guest is judged by, and the reason `mem_stats` exists at all: a soak
 * test that cannot see the heap can only report "it did not crash yet".
 * Reported through the same FFI shape everything else here uses. */
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

/* An advisory call about pages this machine does not reclaim. Success
 * is the honest answer — the advice was heard and there is nothing to
 * act on — and it is what every caller of madvise already handles. */
int madvise(void *p, unsigned long len, int advice) {
    (void)p; (void)len; (void)advice;
    return 0;
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

/* The boot stack gets the same treatment a coroutine's does. It is the
 * stack every program starts on and the one `main` recurses on, and
 * until this call the page under it was ordinary .bss: a recursion that
 * ran off the end overwrote the page tables' neighbours and the program
 * kept going with someone else's variables. Now it faults, and the
 * handler says where.
 *
 * Called after mem_init, because splitting a 2 MiB mapping needs the
 * page-table pool that mem_init reserves. */
extern unsigned char boot_stack_bottom[];

static void pf_guard_boot_stack(void) {
    (void)mprotect(boot_stack_bottom, 4096, 0);
}

/* The other guard page, and the one every C programmer already expects
 * to exist. The boot tables identity-map the low 4 GiB present and
 * writable, page zero included, so a store through a null pointer in
 * this guest QUIETLY SUCCEEDED: it wrote a word into physical page zero
 * and the program carried on with a bug that would have been a segfault
 * on any hosted target. Unmapping the page turns it back into the fault
 * every caller's error handling was written against.
 *
 * Only the first page, and only if nothing we still need lives in it:
 * the hypervisor chooses where the handover block and the command line
 * go, and this guest keeps reading the command line long after boot. */
static const char *cmdline;              /* set in kmain, read for ever after */

static void pf_guard_null_page(const void *si) {
    if ((unsigned long)si < 4096) return;
    if (cmdline && (unsigned long)cmdline < 4096) return;
    (void)mprotect((void *)0, 4096, 0);
}

/* ── time ────────────────────────────────────────────────────────── */

static u64 tsc_khz;            /* 0 = nobody told us */
/* WHERE that number came from. Printed rather than kept private
 * because a clock is exactly as trustworthy as its source, and on
 * this machine there are four of them with very different
 * standing — a hypervisor stating a fact, a CPU stating a ratio, a
 * nameplate rounded to the megahertz, and a measurement. */
static const char *tsc_source = "nowhere — the clock does not work";
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

/* ── the TSC against the PIT ─────────────────────────────────────
 *
 * Channel 2 is the one of the three an operating system may use as a
 * stopwatch: channels 0 and 1 belong to the interrupt controller and
 * to DMA refresh, while channel 2 drives the PC speaker and therefore
 * has both a gate software owns (port 0x61 bit 0) and an output
 * software can read (bit 5). No interrupt, no IDT entry, no wiring —
 * arm it, watch the bit, count TSC ticks in between.
 *
 * Bit 1 of port 0x61 is the speaker itself and is left CLEAR. It is
 * one bit away from a calibration routine that beeps.
 *
 * 10 ms is the window: long enough that the few hundred cycles of
 * `inb` overhead round away, short enough not to be felt at boot.
 * Returns 0 — "still nobody knows" — if the timer never fires, which
 * is what a machine without a PIT looks like, and leaves the caller's
 * refusal to invent a frequency intact.
 */
#define PIT_HZ    1193182u
#define PIT_TICKS (PIT_HZ / 100u)      /* 10 ms */

static u64 pit_calibrate_khz(void) {
    unsigned char saved = inb(0x61);

    /* Gate on, speaker off. */
    outb(0x61, (unsigned char)((saved & ~0x02) | 0x01));
    /* Channel 2, access lobyte+hibyte, mode 0 (interrupt on terminal
     * count — OUT goes low now and high when the count runs out, which
     * is the edge this waits for), binary. */
    outb(0x43, 0xB0);
    outb(0x42, (unsigned char)(PIT_TICKS & 0xFF));
    outb(0x42, (unsigned char)(PIT_TICKS >> 8));

    /* Restart the count by taking the gate down and back up, so the
     * window begins where the TSC is read and not where the divisor
     * happened to be written. */
    outb(0x61, (unsigned char)(inb(0x61) & ~0x01));
    outb(0x61, (unsigned char)(inb(0x61) | 0x01));

    u64 t0 = rdtsc();
    /* The bound is generous — a slow machine reading a port takes
     * microseconds — and exists so that a chipset with no PIT behind
     * the ports produces an answer instead of a hang. */
    for (unsigned spins = 0; !(inb(0x61) & 0x20); spins++)
        if (spins > 20000000u) { outb(0x61, saved); return 0; }
    u64 t1 = rdtsc();

    outb(0x61, saved);

    u64 ticks = t1 - t0;                    /* over 10 ms            */
    u64 khz   = ticks / 10;                 /* ticks per millisecond */
    /* A plausibility floor, not a guess: anything under 10 MHz means
     * the gate never moved and this measured its own loop. */
    return khz > 10000 ? khz : 0;
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
        if (a) { tsc_khz = a; tsc_source = "the hypervisor (CPUID 0x40000010)"; }
    }
    if (!tsc_khz) {
        /* Leaf 0x15: core crystal frequency and the TSC/crystal ratio. */
        cpuid(0, &a, &b, &c, &d);
        if (a >= 0x15) {
            u32 den, num, crystal, unused;
            cpuid(0x15, &den, &num, &crystal, &unused);
            if (den && num && crystal)
            {
                tsc_khz = ((u64)crystal * num) / den / 1000;
                tsc_source = "the core crystal (CPUID 0x15)";
            }
        }
    }
    /* Last: the host says so on the command line. Not a guess — a
     * stated input, the same trust model the plan gives the wall-clock
     * epoch (the host already controls the entire image). It is what
     * makes a TCG run possible at all: no leaf reports a frequency
     * there, and refusing to invent one is right, while refusing to be
     * TOLD one would just mean the clock never works without KVM. */
    if (!tsc_khz) {
        tsc_khz = cmdline_u64("tsc_khz");
        if (tsc_khz) tsc_source = "the kernel command line";
    }

    /* Leaf 0x16: the processor's base frequency, in MHz. Coarser than
     * 0x15 — it is a rounded nameplate number, not a crystal ratio —
     * and on the machines that have one but not the other it is the
     * difference between a clock and a panic. Below the command line
     * on purpose: someone who states a frequency has measured it. */
    if (!tsc_khz) {
        cpuid(0, &a, &b, &c, &d);
        if (a >= 0x16) {
            u32 base_mhz, unused1, unused2, unused3;
            cpuid(0x16, &base_mhz, &unused1, &unused2, &unused3);
            base_mhz &= 0xFFFF;
            if (base_mhz) {
                tsc_khz = (u64)base_mhz * 1000;
                tsc_source = "the base frequency (CPUID 0x16)";
            }
        }
    }

    /* Last resort on real hardware: measure it against the PIT.
     *
     * Nobody tells a PC what its TSC frequency is. There is no
     * hypervisor to ask, the command line was written by whoever made
     * the USB stick, and on an AMD part neither CPUID leaf exists — so
     * a machine that boots off iron would panic the first time
     * anything asked what time it was. A PC does, however, have a
     * 1.193182 MHz oscillator that has not changed since 1981, and
     * counting TSC ticks against it is measuring rather than guessing,
     * which is the only thing this file will do with a clock.
     *
     * Multiboot2 only: a microvm has no PIT, and probing for one there
     * would spin out the bound and slow every boot down to no purpose. */
    if (!tsc_khz && mb2_booted()) {
        tsc_khz = pit_calibrate_khz();
        if (tsc_khz) tsc_source = "measurement against the PIT";
    }

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

/* ── the tickless idle ────────────────────────────────────────────
 *
 * "Fully polling" (plan B0) turned out to mean an IDLE worker
 * appliance burning a full host core: every sleep in the machine
 * funnels through nanosleep, and nanosleep spun on `pause` until the
 * TSC caught up — measured at 1002/1000 ticks of one core over an
 * idle 10 s. The fix is the smallest interrupt the design allows: the
 * local APIC timer in TSC-deadline mode, one vector (32), one ISR
 * that acknowledges and resumes, and `sti; hlt` in the one place the
 * machine waits. Devices stay POLLED — the B0 decision stands; the
 * only thing an interrupt is used for is ending a sleep, so the
 * deadlock-decidability story is untouched (a sleep always has a
 * deadline, and the detector already refuses an unbounded idle).
 *
 * sti;hlt is the load-bearing pair: sti's one-instruction shadow
 * means an interrupt cannot slip in between the two and leave hlt
 * sleeping past its own wakeup.
 */

static inline u64 rdmsr(u32 msr) {
    u32 lo, hi;
    __asm__ __volatile__("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr));
    return ((u64)hi << 32) | lo;
}

static inline void wrmsr(u32 msr, u64 v) {
    __asm__ __volatile__("wrmsr" : : "c"(msr),
                         "a"((u32)v), "d"((u32)(v >> 32)));
}

#define MSR_APIC_BASE    0x1Bu
#define MSR_X2_SVR       0x80Fu
#define MSR_X2_EOI       0x80Bu
#define MSR_X2_LVT_TIMER 0x832u
#define MSR_TSC_DEADLINE 0x6E0u
#define IDLE_VECTOR      32u

static volatile u32 *lapic_mmio;   /* xAPIC; null when x2APIC or absent */
static int lapic_x2;
static int lapic_deadline_ok;      /* CPUID says TSC-deadline exists   */
static u64 idle_hlt_count;

static void lapic_wr(u32 reg, u32 v) {
    if (lapic_x2) wrmsr(0x800u + (reg >> 4), v);
    else if (lapic_mmio) lapic_mmio[reg >> 2] = v;
}

static u32 lapic_rd(u32 reg) {
    if (lapic_x2) return (u32)rdmsr(0x800u + (reg >> 4));
    if (lapic_mmio) return lapic_mmio[reg >> 2];
    return 0;
}

void pf_irq(u64 vec);
void pf_irq(u64 vec) {
    (void)vec;                     /* only IDLE_VECTOR is ever armed */
    if (lapic_x2) wrmsr(MSR_X2_EOI, 0);
    else if (lapic_mmio) lapic_mmio[0xB0 >> 2] = 0;
}

void lapic_init(void);
void lapic_init(void) {
    u32 a, b, c, d;
    cpuid(1, &a, &b, &c, &d);
    if (!(d & (1u << 9))) return;             /* no local APIC at all */
    lapic_deadline_ok = (c >> 24) & 1;        /* TSC-deadline timer   */
    /* The legacy PICs first: on real hardware (the Multiboot2 path)
     * they power up delivering IRQs at vectors 8–15 — ON TOP of the
     * CPU exceptions — the moment IF opens. Mask everything; the only
     * interrupt this machine wants is its own timer. Harmless where
     * no PIC exists. */
    __asm__ __volatile__("outb %%al, $0xA1" : : "a"((unsigned char)0xFF));
    __asm__ __volatile__("outb %%al, $0x21" : : "a"((unsigned char)0xFF));
    u64 base = rdmsr(MSR_APIC_BASE);
    lapic_x2 = (base >> 10) & 1;
    if (!lapic_x2)
        lapic_mmio = (volatile u32 *)(base & 0xFFFFF000ULL);
    /* Software-enable via the spurious-vector register; 0xFF for the
     * spurious slot, which this machine never expects to see. */
    lapic_wr(0xF0, 0x100u | 0xFFu);
    if (lapic_deadline_ok)
        lapic_wr(0x320, (2u << 17) | IDLE_VECTOR);   /* TSC-deadline mode */
}

/* The one-shot fallback's unit: APIC-timer counts per millisecond,
 * measured against the TSC once, lazily — the TSC frequency is not
 * known until time_init, which runs after lapic_init. TCG is the
 * customer: its -cpu max has a local APIC but no TSC-deadline. */
static u32 apic_counts_per_ms;

static void lapic_calibrate(void) {
    if (apic_counts_per_ms || !tsc_khz) return;
    lapic_wr(0x3E0, 0x3);                    /* divide by 16 */
    lapic_wr(0x320, (1u << 16) | IDLE_VECTOR);   /* masked while measuring */
    lapic_wr(0x380, 0xFFFFFFFFu);
    u64 t0 = rdtsc();
    u64 span = tsc_khz * 10ULL;              /* a 10 ms window */
    while (rdtsc() - t0 < span) __asm__ __volatile__("pause");
    u32 used = 0xFFFFFFFFu - lapic_rd(0x390);
    lapic_wr(0x380, 0);                      /* stop the count */
    apic_counts_per_ms = used / 10 ? used / 10 : 1;
}

/* Exposed to NURL for the gate: a machine that claims to idle on hlt
 * should be able to show it did. */
long long nurl_idle_hlt_count(void);
long long nurl_idle_hlt_count(void) { return (long long)idle_hlt_count; }

/* Which idle the machine ended up with, for the gate's diagnostics:
 * bit 0 = TSC-deadline capable, bit 1 = xAPIC mapped, bit 2 = x2APIC. */
long long nurl_idle_mode(void);
long long nurl_idle_mode(void) {
    return (lapic_x2 ? 4 : 0) | (lapic_mmio ? 2 : 0) | (lapic_deadline_ok ? 1 : 0);
}

int nanosleep(const void *req, void *rem) {
    const u64 *ts = (const u64 *)req;
    (void)rem;
    if (!tsc_khz) return 0;
    u64 want = ts[0] * 1000000000ULL + ts[1];
    u64 start = rdtsc();
    u64 ticks = (want / 1000) * (tsc_khz / 1000 ? tsc_khz / 1000 : 1);
    u64 deadline = start + ticks;
    if (lapic_deadline_ok && (lapic_mmio || lapic_x2)) {
        while (rdtsc() < deadline) {
            wrmsr(MSR_TSC_DEADLINE, deadline);
            __asm__ __volatile__("sti; hlt; cli");
            idle_hlt_count++;
        }
        return 0;
    }
    if (lapic_mmio || lapic_x2) {
        /* No TSC-deadline (TCG): the classic one-shot, in units the
         * calibration measured. Undershoot is fine — the loop re-arms
         * for the remainder; an interrupt that fires early only costs
         * one more lap. */
        lapic_calibrate();
        if (apic_counts_per_ms) {
            u64 now;
            while ((now = rdtsc()) < deadline) {
                u64 left_ms = (deadline - now) / (tsc_khz ? tsc_khz : 1);
                u64 counts = (left_ms ? left_ms : 1) * apic_counts_per_ms;
                if (counts > 0xFFFFFFFFu) counts = 0xFFFFFFFFu;
                lapic_wr(0x320, IDLE_VECTOR);        /* one-shot, unmasked */
                lapic_wr(0x3E0, 0x3);
                lapic_wr(0x380, (u32)counts);
                __asm__ __volatile__("sti; hlt; cli");
                idle_hlt_count++;
                lapic_wr(0x380, 0);                  /* quiet between laps */
            }
            return 0;
        }
    }
    /* No usable APIC timer: the polling spin, bounded by the deadline
     * the caller asked for — the pre-idle behaviour, kept as the
     * honest fallback rather than a silent requirement. */
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

/* A descriptor naming a file goes to the filesystem; everything else is
 * the console, where stdout and stderr are the same wire. Until there
 * was a disk this function had no reason to look at `fd` at all — the
 * only writable thing on the machine was the serial port. */
int vfs_std_of(int fd);
int vfs_is_std_target(int fd);
int vfs_close_saved(int fd);

long long write(int fd, const void *buf, unsigned long n) {
    const char *p = (const char *)buf;
    if (fs_is_file_fd(fd)) return (long long)fs_write_fd(fd, buf, n);
    /* A standard descriptor may have been pointed at a file — that is
     * what `cmd > file` is, and vfs.c owns the table that says so. */
    if (fd >= 0 && fd <= 2) {
        int t = vfs_std_of(fd);
        if (t >= 0) return (long long)fs_write_fd(t, buf, n);
    }
    for (unsigned long i = 0; i < n; i++) pf_putc(p[i]);
    return (long long)n;
}

/* No console input. 0 is EOF, which every reader already handles; -1
 * with an errno would make them retry forever.
 *
 * The POSIX names are the ones NURL's FFI calls — `std/fs.nu` opens
 * with `open` and sizes with `lseek` — so they are the ones that
 * dispatch to the baked-in filesystem. Defining only the `nl_*` layer
 * left `lseek` returning -1 for every file in the image, and
 * `read_file` reported ENOENT about a file it had successfully
 * opened. */
long long read(int fd, void *buf, unsigned long n) {
    if (fs_is_file_fd(fd)) return (long long)fs_read_fd(fd, buf, n);
    if (fd >= 0 && fd <= 2) {
        int t = vfs_std_of(fd);
        if (t >= 0) return (long long)fs_read_fd(t, buf, n);
    }
    (void)buf; (void)n;
    return 0;
}

int nl_open(const char *path, int flags, int mode);
int open(const char *p, int fl, int mode) { return nl_open(p, fl, mode); }
int close(int fd) {
    if (vfs_close_saved(fd)) return 0;
    /* A descriptor standing in for a standard one stays open: the shell
     * closes it right after `dup2`, and closing it for real there would
     * make the redirect it just installed point at nothing. */
    if (vfs_is_std_target(fd)) return 0;
    if (fs_is_file_fd(fd)) return fs_close_fd(fd);
    return 0;
}
long long lseek(int fd, long long off, int whence) {
    if (fs_is_file_fd(fd)) return fs_lseek_fd(fd, off, whence);
    (void)off; (void)whence;
    return -1;
}

static void pf_shutdown(int code);

/* nolibc's stdio talks to the `nl_*` layer, not to the POSIX names —
 * that is the seam syscall_linux.c defines, so a guest that replaces
 * that file has to define it too. Same functions, one indirection up. */
pf_ssize_t nl_write(int fd, const void *buf, pf_size_t n) { return (pf_ssize_t)write(fd, buf, n); }
/* Reads come from the baked-in filesystem when the descriptor names a
 * file in it, and from the console otherwise — which has nothing to
 * say. `nl_open` lives in initfs.c: opening is entirely that file's
 * business, and there is nothing else on this machine to open. */
pf_ssize_t fs_read_fd(int fd, void *buf, pf_size_t n);
long long fs_lseek_fd(int fd, long long off, int whence);
int fs_close_fd(int fd);

pf_ssize_t nl_read(int fd, void *buf, pf_size_t n) { return (pf_ssize_t)read(fd, buf, n); }
int nl_close(int fd) { return close(fd); }
long long nl_lseek(int fd, long long off, int whence) { return lseek(fd, off, whence); }
/* ZERO on failure, not MAP_FAILED. `mmap` answers the POSIX way and
 * `nl_map` answers the way nolibc's allocator asks — `if (!p)` is the
 * check in malloc.c, and the Linux twin (syscall_linux.c) has always
 * converted. This one did not, so a guest that ran out of memory handed
 * back (void *)-1 and the first write through it faulted at
 * 0xffffffffffffffff: exhaustion turned into a wild store instead of an
 * "out of memory" line. Twins that drift is what this whole directory
 * is arranged to prevent; here it drifted. */
void *nl_map(pf_size_t len) {
    void *p = mmap(0, len, 0, 0, -1, 0);
    return p == (void *)-1 ? 0 : p;
}
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
/* nolibc/misc.c reaches for the raw syscall pair for the handful of
 * calls it does not wrap. There is no syscall instruction to make
 * here, and the answer is the same one every other file gets: the
 * operation is not available, said out loud. -ENOSYS is what a Linux
 * kernel says about a syscall it does not implement, so every caller
 * already knows this shape. */
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

/* access(2), against the filesystem this machine actually has. F_OK (0)
 * and R_OK (4) are answerable — the image either contains the file or it
 * does not — and W_OK (2) and X_OK (1) are refused, because the archive
 * lives in the text segment and nothing in it is writable or runnable.
 *
 * The version that refused everything was worse than useless: a program
 * that checks `file_exists` before reading its certificate was told the
 * certificate was not there, and went off to write a new one onto a
 * read-only filesystem. A stub that lies about the machine's own
 * contents produces exactly that shape of bug. */
int getpid(void) { return 1; }

/* ── shutdown ────────────────────────────────────────────────────── */

static void pf_shutdown(int code) {
    /* Whatever is still only in the filesystem's cache goes onto the
     * medium before the machine stops. A guest that was shut down
     * cleanly and lost its last writes would be a guest whose `fsync`
     * was the only way to keep anything — which is a filesystem people
     * would be right not to trust. */
    (void)vfs_sync_all();
    /* The primary protocol, because it is the only one both hypervisors
     * can carry: Firecracker cannot hand a guest exit code back at all,
     * so the harness parses this line. QEMU's isa-debug-exit below is a
     * cross-check, not the mechanism. */
    uart_puts("[nurl-exit] ");
    uart_putu((unsigned long)(code & 0xff));
    pf_putc('\n');

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

/* `exit`, `abort` and `environ` belong to nolibc/misc.c, which this
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

/* ── what machine is this? ───────────────────────────────────────
 *
 * A guest under a hypervisor is running on a machine somebody
 * configured and can go and look at. A guest on iron is running on a
 * machine whose properties are the whole question — is this the RAM I
 * think it is, did the clock calibrate, is anything reaching the
 * screen — and the only thing that can answer is the guest.
 *
 * So these exist for `demos/baremetal.nu` to print. They report what
 * was measured or handed over, never a default: a number that might be
 * a fallback and might be the truth is worse than no number.
 */

void pa_stats(unsigned long *live, unsigned long *peak, unsigned long *avail,
              unsigned long *largest, unsigned long *lost, int *holes);

unsigned long nurl_mem_total(void) { return (unsigned long)ram_total; }

unsigned long nurl_mem_used(void) {
    unsigned long live = 0;
    pa_stats(&live, 0, 0, 0, 0, 0);
    return live;
}

unsigned long nurl_tsc_khz(void) { return (unsigned long)tsc_khz; }

const char *nurl_clock_source(void) { return tsc_source; }

/* CPUID leaves 0x80000002..4, forty-eight bytes of brand string that
 * the part names itself with. Absent on parts older than about 2000,
 * where saying so is the honest answer. */
const char *nurl_cpu_brand(void) {
    static char brand[49];
    static int  done;
    if (done) return brand;
    done = 1;

    u32 a, b, c, d;
    cpuid(0x80000000, &a, &b, &c, &d);
    if (a < 0x80000004) {
        brand[0] = 0;
        return "unknown (no CPUID brand string)";
    }
    u32 *w = (u32 *)brand;
    for (u32 leaf = 0x80000002; leaf <= 0x80000004; leaf++) {
        cpuid(leaf, &a, &b, &c, &d);
        *w++ = a; *w++ = b; *w++ = c; *w++ = d;
    }
    brand[48] = 0;
    /* Intel pads the front with spaces, AMD does not. */
    const char *p = brand;
    while (*p == ' ') p++;
    return p;
}

const char *nurl_console_kind(void) { return console_kind_name(); }

/* ── entry ───────────────────────────────────────────────────────── */

extern char **environ;          /* nolibc/misc.c owns the storage */          /* nolibc/misc.c owns the storage */
extern void nl_tls_init_guest(void);
extern int main(int argc, char **argv);

/* `args="…"` from the command line, split on spaces into argv.
 *
 * One key, not "everything after the last flag": QEMU's
 * auto-kernel-cmdline APPENDS its virtio entries after -append, so a
 * program that took the tail of the line would receive the
 * hypervisor's device list as arguments (plan B0). The quotes are
 * required for the same reason — they say where the program's
 * arguments end. */
#define ARGV_MAX 32
static char *guest_argv[ARGV_MAX + 1];
static char  argv_buf[1024];

/* Where the value of `args=` starts and what ends it.
 *
 * Two loaders write this key and they do not agree on where the quotes
 * go. QEMU passes `-append` through untouched, so the guest sees
 * exactly what was typed: args="alpha beta". GRUB's script parser
 * consumes the quotes while tokenising and puts them back around the
 * WHOLE token when it builds the Multiboot2 command line, so the guest
 * sees "args=alpha beta" — the same information, a quote earlier.
 * Matching the literal six characters `args="` finds the first and
 * silently misses the second, which is a program that gets no
 * arguments and no explanation.
 *
 * So: find the key, then let the QUOTING decide the end. Opening quote
 * after the '=' or before the 'a', either way the value ends at the
 * next quote; unquoted, it ends at the next space, which also makes
 * `args=solo` mean what it looks like.
 *
 * The end is still an explicit terminator rather than "the rest of the
 * line", and that has not changed: QEMU's auto-kernel-cmdline APPENDS
 * its virtio entries after -append, so a program taking the tail would
 * receive the hypervisor's device list as arguments.
 */
static const char *args_value(const char *cl, const char *p, char *endc) {
    const char *v = p + 5;                 /* past "args="            */
    if (*v == '"')      { *endc = '"'; return v + 1; }
    if (p > cl && p[-1] == '"') { *endc = '"'; return v; }
    *endc = ' ';
    return v;
}

static int build_argv(const char *cl) {
    int argc = 1;
    guest_argv[0] = (char *)"nurl";
    if (!cl) return argc;

    /* Scanned character by character rather than token by token,
     * because under GRUB the key is INSIDE a quoted token that contains
     * spaces — splitting on spaces first would cut "args=alpha beta"
     * into `"args=alpha` and `beta"` and never see the key at the front
     * of anything. The boundary test is what a token scan was for: only
     * a match at the start of the line, after a space or just inside an
     * opening quote counts, so `myargs=` is not this key. */
    for (const char *p = cl; *p; p++) {
        if (p[0] != 'a' || p[1] != 'r' || p[2] != 'g' || p[3] != 's' ||
            p[4] != '=')
            continue;
        if (p != cl && p[-1] != ' ' && p[-1] != '"') continue;

        char end;
        const char *q = args_value(cl, p, &end);
        unsigned long n = 0;
        while (*q && *q != end && n < sizeof argv_buf - 1) argv_buf[n++] = *q++;
        argv_buf[n] = 0;
        /* Split in place: every run of non-spaces is one argument, and
         * the terminator goes where the space was. */
        unsigned long i = 0;
        while (i < n && argc < ARGV_MAX) {
            while (i < n && argv_buf[i] == ' ') argv_buf[i++] = 0;
            if (i >= n) break;
            guest_argv[argc++] = &argv_buf[i];
            while (i < n && argv_buf[i] != ' ') i++;
        }
        break;
    }
    guest_argv[argc] = 0;
    return argc;
}

void kmain(unsigned long start_info_paddr) {
    static char *no_argv[2];
    const struct hvm_start_info *si =
        (const struct hvm_start_info *)start_info_paddr;

    uart_init();
    /* This machine's stdout is a SERIAL CONSOLE, so it is line
     * buffered — the flag nolibc has always had and nothing ever set.
     *
     * Fully buffered was the wrong default here in the way that only
     * shows up on the programs this target is for: a server does not
     * exit, so it never flushes, so a guest that printed a startup
     * banner and then spent an hour answering requests had printed
     * NOTHING as far as anyone watching the console could tell. The
     * first thing an operator does with an appliance is read its log.
     * Guest only: the Linux -nostdlib build keeps libc's rule (a
     * redirected stdout is fully buffered), which is what its goldens
     * are written against. */
    *nl_file_flags(stdout) |= PF_F_LINEBUF;
    /* Before anything that can fault, which is everything: an IDT
     * installed after the first mistake describes nothing. */
    tss_init();
    idt_init();
    /* The idle timer's half of the IDT: vector 32 resumes instead of
     * reporting. Init after the IDT so a fault in here is a report. */
    lapic_init();

    /* The screen, and only on real hardware. It comes after the IDT
     * because it is the first code to touch an address the firmware
     * chose rather than one this image did, and a fault there should
     * be a report rather than a reboot. */
    if (mb2_booted()) {
        console_init(mb2_framebuffer());
        /* The Multiboot2 conversion runs before any of this exists, so
         * it records its complaint instead of making it. Now there is
         * somewhere for the words to go. */
        const char *why = mb2_failure();
        if (why) pf_panic(why);
    }

    if (!si || si->magic != HVM_START_MAGIC)
        pf_panic(mb2_booted()
                 ? "the multiboot2 handover did not convert — this is a "
                   "bug in boot/multiboot2.c, not in the bootloader"
                 : "not a PVH boot — no hvm_start_info at the handover "
                   "address (was this image loaded with -kernel?)");

    cmdline = si->cmdline_paddr ? (const char *)(unsigned long)si->cmdline_paddr : 0;
    mem_init(si);
    pf_guard_boot_stack();
    pf_guard_null_page(si);
    time_init();
    nl_tls_init_guest();          /* before the first __thread access */

    /* Plan B7: getenv reads the cmdline's key=value pairs (args="…"
     * stays argv's). boot/cmdenv.c owns the grammar for all three
     * platforms. */
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
