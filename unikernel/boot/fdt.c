/*
 * NURL unikernel — unikernel/boot/fdt.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The device tree, for the machines that have one.
 *
 * x86's microvm announces its memory in a PVH handover block and its
 * virtio-mmio devices on the kernel command line. Every other machine
 * this target runs on — QEMU's `virt` board on AArch64 and on RISC-V —
 * announces both in a flattened device tree instead. That is one
 * format to parse and two ports that would otherwise parse it twice,
 * which is why this file exists: the AArch64 port wrote it, the
 * RISC-V port would have copied it, and a copy is where two machines
 * start disagreeing about what the same tree says.
 *
 * What the layers above need from a tree is exactly three answers:
 *
 *   - where RAM is and how much of it there is (/memory reg);
 *   - the command line the host set (/chosen/bootargs);
 *   - every virtio-mmio device, IN THE X86 SPELLING. `hal/virtio.nu`
 *     reads `virtio_mmio.device=size@base:irq` entries because that is
 *     what microvm hands the x86 guest, so this walker SYNTHESIZES the
 *     same entries from the tree. One format above the boot layer,
 *     whatever the machine spoke below it.
 *
 * A minimal walker, not a library: the flattened format is four token
 * types and big-endian integers, and nothing here needs more than the
 * three answers above. An unknown token stops the walk rather than
 * being interpreted — noise read as a device list is a guest driving
 * something that is not there.
 */

typedef unsigned long long u64;
typedef unsigned int       u32;

#define FDT_MAGIC       0xd00dfeed
#define FDT_BEGIN_NODE  1
#define FDT_END_NODE    2
#define FDT_PROP        3
#define FDT_NOP         4
#define FDT_END         9

/* What a walk answers. `cmdline` is the string the boot code hands to
 * `nurl_boot_cmdline`: bootargs first, then the synthesized device
 * entries, so a program's `args="…"` is found before them and QEMU's
 * device list never reaches an argument parser. */
struct fdt_facts {
    u64   ram_base;
    u64   ram_size;
    char  cmdline[2048];
    unsigned long cmdline_len;
    int   devices;            /* how many virtio-mmio nodes were seen */
};

static u32 fdt_be32(const unsigned char *p) {
    return ((u32)p[0] << 24) | ((u32)p[1] << 16) | ((u32)p[2] << 8) | (u32)p[3];
}
static u64 fdt_be64(const unsigned char *p) {
    return ((u64)fdt_be32(p) << 32) | fdt_be32(p + 4);
}

static int fdt_str_eq(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}
static int fdt_str_prefix(const char *s, const char *pre) {
    while (*pre && *s == *pre) { s++; pre++; }
    return *pre == 0;
}

static void cl_puts(struct fdt_facts *f, const char *s) {
    while (*s && f->cmdline_len < sizeof f->cmdline - 1)
        f->cmdline[f->cmdline_len++] = *s++;
    f->cmdline[f->cmdline_len] = 0;
}
static void cl_puthex(struct fdt_facts *f, u64 v) {
    static const char hex[] = "0123456789abcdef";
    char b[17];
    int i = 16;
    b[i] = 0;
    if (!v) b[--i] = '0';
    while (v) { b[--i] = hex[v & 0xF]; v >>= 4; }
    cl_puts(f, "0x");
    cl_puts(f, &b[i]);
}
static void cl_putu(struct fdt_facts *f, u64 v) {
    char b[21];
    int i = 20;
    b[i] = 0;
    if (!v) b[--i] = '0';
    while (v) { b[--i] = (char)('0' + v % 10); v /= 10; }
    cl_puts(f, &b[i]);
}

/* 1 when `p` points at a flattened device tree. */
int fdt_is_tree(const void *p) {
    return p && fdt_be32((const unsigned char *)p) == FDT_MAGIC;
}

/* Walk the tree and fill `out`. Returns 0 when `fdt` is not a tree.
 *
 * A node is classified by its NAME at whatever depth it appears —
 * AArch64's virt puts its devices at the root, RISC-V's virt puts them
 * under /soc — and judged at its END, because `reg`, `interrupts` and
 * the name arrive in whatever order the tree was written in.
 */
int fdt_probe(const void *fdt_p, struct fdt_facts *out) {
    const unsigned char *fdt = (const unsigned char *)fdt_p;
    if (!fdt_is_tree(fdt)) return 0;

    u32 off_struct  = fdt_be32(fdt + 8);
    u32 off_strings = fdt_be32(fdt + 12);
    const unsigned char *p = fdt + off_struct;
    const char *strings = (const char *)fdt + off_strings;
    const char *bootargs = 0;

    out->ram_base = out->ram_size = 0;
    out->cmdline_len = 0;
    out->cmdline[0] = 0;
    out->devices = 0;

    /* Per-depth state. The tree's SHAPE is the machine's business:
     * AArch64's virt puts its devices at the root, RISC-V's virt puts
     * them under /soc, and a walker that hard-codes a depth finds
     * nothing on the machine it was not written for — which is exactly
     * what "0 devices" on the RISC-V board turned out to mean. So a
     * node is classified by its NAME at whatever depth it appears, and
     * the address/size cells are tracked per level because a bus node
     * may state its own.
     *
     * 16 levels is far past anything these trees use; deeper than that
     * stops the walk rather than indexing off the end. */
#define FDT_MAX_DEPTH 16
    struct {
        u32 addr_cells, size_cells;
        int is_virtio, is_memory, is_chosen;
        u64 reg_base, reg_size, irq;
    } lvl[FDT_MAX_DEPTH];
    int depth = 0;

    lvl[0].addr_cells = 2; lvl[0].size_cells = 2;
    lvl[0].is_virtio = lvl[0].is_memory = lvl[0].is_chosen = 0;

    /* The device entries are accumulated here and joined onto the
     * bootargs at the end, so a program's `args="…"` is found before
     * the hypervisor's device list. */
    struct fdt_facts devs;
    devs.cmdline_len = 0;
    devs.cmdline[0] = 0;

    for (;;) {
        u32 tok = fdt_be32(p); p += 4;
        if (tok == FDT_END) break;
        if (tok == FDT_NOP) continue;
        if (tok == FDT_BEGIN_NODE) {
            const char *name = (const char *)p;
            unsigned long n = 0;
            while (name[n]) n++;
            p += (n + 1 + 3) & ~3UL;
            depth++;
            if (depth >= FDT_MAX_DEPTH) break;
            /* Cells are inherited until this node states its own. */
            lvl[depth].addr_cells = lvl[depth - 1].addr_cells;
            lvl[depth].size_cells = lvl[depth - 1].size_cells;
            lvl[depth].is_virtio = fdt_str_prefix(name, "virtio_mmio@");
            lvl[depth].is_memory = fdt_str_prefix(name, "memory@") ||
                                   fdt_str_eq(name, "memory");
            lvl[depth].is_chosen = fdt_str_eq(name, "chosen");
            lvl[depth].reg_base = lvl[depth].reg_size = lvl[depth].irq = 0;
            continue;
        }
        if (tok == FDT_END_NODE) {
            if (depth > 0 && depth < FDT_MAX_DEPTH) {
                if (lvl[depth].is_virtio && lvl[depth].reg_size) {
                    /* The x86 spelling: size@base:irq. The IRQ is the
                     * controller's number plus the SPI base (32) — what
                     * Linux would print — though the polling driver
                     * above never uses it. */
                    cl_puts(&devs, " virtio_mmio.device=");
                    cl_puthex(&devs, lvl[depth].reg_size);
                    cl_puts(&devs, "@");
                    cl_puthex(&devs, lvl[depth].reg_base);
                    cl_puts(&devs, ":");
                    cl_putu(&devs, lvl[depth].irq + 32);
                    out->devices++;
                }
                if (lvl[depth].is_memory && lvl[depth].reg_size && !out->ram_size) {
                    out->ram_base = lvl[depth].reg_base;
                    out->ram_size = lvl[depth].reg_size;
                }
            }
            depth--;
            if (depth < 0) break;
            continue;
        }
        if (tok == FDT_PROP) {
            u32 len  = fdt_be32(p);
            u32 noff = fdt_be32(p + 4);
            const unsigned char *val = p + 8;
            const char *pname = strings + noff;
            p += 8 + ((len + 3) & ~3UL);
            if (depth < 0 || depth >= FDT_MAX_DEPTH) continue;

            if (fdt_str_eq(pname, "#address-cells")) lvl[depth].addr_cells = fdt_be32(val);
            if (fdt_str_eq(pname, "#size-cells"))    lvl[depth].size_cells = fdt_be32(val);
            /* Only /chosen carries the command line. Reading a
             * `bootargs` from anywhere would take some device's
             * property as the kernel's arguments. */
            if (lvl[depth].is_chosen && fdt_str_eq(pname, "bootargs"))
                bootargs = (const char *)val;

            u32 ac = lvl[depth - (depth > 0)].addr_cells;
            u32 sc = lvl[depth - (depth > 0)].size_cells;
            if (fdt_str_eq(pname, "reg") && len >= (ac + sc) * 4) {
                lvl[depth].reg_base = ac == 2 ? fdt_be64(val) : fdt_be32(val);
                lvl[depth].reg_size = sc == 2 ? fdt_be64(val + ac * 4)
                                              : fdt_be32(val + ac * 4);
            }
            if (fdt_str_eq(pname, "interrupts") && len >= 4) {
                /* <irq> on RISC-V's PLIC, <type irq flags> on ARM's
                 * GIC. The second cell is the number in the three-cell
                 * form; in the one-cell form the first IS the number. */
                lvl[depth].irq = len >= 12 ? fdt_be32(val + 4) : fdt_be32(val);
            }
            continue;
        }
        /* Lost: stop rather than read noise as devices. */
        break;
    }

    /* bootargs FIRST, then the devices: a program's `args="…"` must be
     * found before the hypervisor's device list, and a parser that
     * scans forward stops at the first match. */
    if (bootargs) cl_puts(out, bootargs);
    for (unsigned long i = 0; i < devs.cmdline_len; i++) {
        if (out->cmdline_len >= sizeof out->cmdline - 1) break;
        out->cmdline[out->cmdline_len++] = devs.cmdline[i];
    }
    out->cmdline[out->cmdline_len] = 0;
    return 1;
}
