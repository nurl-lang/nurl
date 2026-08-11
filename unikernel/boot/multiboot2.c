/*
 * NURL unikernel — unikernel/boot/multiboot2.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The Multiboot2 handover, converted into the PVH one.
 *
 * `boot/boot.S` has two entry points because a hypervisor and a PC
 * firmware find a kernel in two different ways. Everything below the
 * entry has one: `kmain` takes an `hvm_start_info`, `mem_init` walks
 * an `hvm_memmap_entry` array, and the command line is a string at a
 * physical address. Rather than teach all of that a second shape, this
 * file reads what GRUB left in memory and writes the shape the guest
 * already speaks — the same move the AArch64 port makes when it
 * synthesizes x86 `virtio_mmio=` cmdline entries out of a device tree,
 * so that `hal/virtio.nu` sees one format on every board.
 *
 * The conversion is nearly free because the two memory-map records
 * agree field for field (base, length, type, reserved) and agree on
 * E820's numbering, where 1 means usable RAM. What differs is the
 * container: Multiboot2 is a stream of variable-length tags, PVH is a
 * struct with a pointer to a flat array. So this file walks the tags
 * once and copies out the three things that matter.
 *
 * NOTHING HERE PRINTS. It runs before `uart_init`, before the IDT,
 * before the console — the first C on the machine. A failure is
 * therefore recorded as a sentence and handed to `kmain`, which
 * panics with it once there is somewhere for the words to go. A
 * version of this that called `pf_panic` directly would report every
 * failure as a silent hang, which is the one failure mode this whole
 * directory exists to avoid.
 */

#include "mb2.h"

typedef unsigned long long u64;
typedef unsigned int       u32;
typedef unsigned short     u16;
typedef unsigned char      u8;

/* ── the tags this reads ────────────────────────────────────────── */

#define MB2_TAG_END          0
#define MB2_TAG_CMDLINE      1
#define MB2_TAG_MMAP         6
#define MB2_TAG_FRAMEBUFFER  8
#define MB2_TAG_ACPI_OLD     14
#define MB2_TAG_ACPI_NEW     15

struct mb2_tag {
    u32 type;
    u32 size;
};

struct mb2_tag_mmap {
    u32 type;
    u32 size;
    u32 entry_size;
    u32 entry_version;
    /* entries follow, `entry_size` bytes each */
};

struct mb2_mmap_entry {
    u64 base_addr;
    u64 length;
    u32 type;              /* E820 numbering: 1 = available */
    u32 reserved;
};

struct mb2_tag_framebuffer {
    u32 type;
    u32 size;
    u64 addr;
    u32 pitch;
    u32 width;
    u32 height;
    u8  bpp;
    u8  fb_type;           /* 0 indexed, 1 RGB, 2 EGA text */
    u16 reserved;
};

/* ── what the rest of the guest speaks ──────────────────────────── */

#define HVM_START_MAGIC 0x336ec578

struct hvm_start_info {
    u32 magic;
    u32 version;
    u32 flags;
    u32 nr_modules;
    u64 modlist_paddr;
    u64 cmdline_paddr;
    u64 rsdp_paddr;
    u64 memmap_paddr;
    u32 memmap_entries;
    u32 reserved;
};

struct hvm_memmap_entry {
    u64 addr;
    u64 size;
    u32 type;
    u32 reserved;
};

/* ── the converted handover, in .bss ────────────────────────────── */

/* A PC reports a handful of E820 regions; 64 is room for a machine
 * with an unusually chopped-up map and still under 2 KiB. Overflow is
 * reported rather than truncated: a memory map missing its last entry
 * is a guest that quietly does not know about some of its own RAM. */
#define MB2_MAX_MMAP 64

static struct hvm_start_info   mb2_si;
static struct hvm_memmap_entry mb2_map[MB2_MAX_MMAP];

/* The framebuffer, published for the console to pick up in `kmain`.
 * Kept here rather than acted on here for the same reason as the
 * failure string: this runs before there is a console to initialise. */
static struct mb2_fb mb2_fb_info;
static int           mb2_have_fb;
static int           mb2_is_mb2;
static const char   *mb2_why;

int mb2_booted(void) { return mb2_is_mb2; }
const char *mb2_failure(void) { return mb2_why; }
const struct mb2_fb *mb2_framebuffer(void) {
    return mb2_have_fb ? &mb2_fb_info : 0;
}

/* The MBI is a stream of tags: a header of two u32s, then tags each
 * padded up to an 8-byte boundary, ending with a type-0 tag. */
unsigned long mb2_to_start_info(unsigned long mbi_paddr) {
    mb2_is_mb2 = 1;

    if (!mbi_paddr || (mbi_paddr & 7)) {
        mb2_why = "multiboot2 boot with no information structure "
                  "(the bootloader passed a null or misaligned pointer)";
        return 0;
    }

    const u8 *base  = (const u8 *)mbi_paddr;
    u32       total = *(const u32 *)base;
    if (total < 8) {
        mb2_why = "multiboot2 information structure is too short to "
                  "contain even its own header";
        return 0;
    }

    mb2_si.magic   = HVM_START_MAGIC;
    mb2_si.version = 1;

    u32 n = 0;
    int truncated = 0;

    for (u32 off = 8; off + sizeof(struct mb2_tag) <= total; ) {
        const struct mb2_tag *t = (const struct mb2_tag *)(base + off);
        if (t->type == MB2_TAG_END) break;
        if (t->size < sizeof(struct mb2_tag) || off + t->size > total) {
            mb2_why = "multiboot2 tag runs past the end of the "
                      "information structure — refusing to read it";
            return 0;
        }

        switch (t->type) {
        case MB2_TAG_CMDLINE:
            /* The string is in the tag itself and stays there: the MBI
             * lives in low memory, which `mem_init` never hands out,
             * so pointing at it is safe for the life of the guest. */
            mb2_si.cmdline_paddr = (u64)(unsigned long)(base + off + 8);
            break;

        case MB2_TAG_MMAP: {
            const struct mb2_tag_mmap *m = (const struct mb2_tag_mmap *)t;
            /* `entry_size` is read from the tag rather than assumed to
             * be sizeof(): the spec reserves the right to grow the
             * record, and a hard-coded stride would then read every
             * entry after the first from the middle of its
             * predecessor. The fields this copies are the ones the
             * spec pins at the front. */
            if (m->entry_size < sizeof(struct mb2_mmap_entry)) {
                mb2_why = "multiboot2 memory map declares an entry size "
                          "smaller than one entry";
                return 0;
            }
            for (u32 e = 16; e + m->entry_size <= t->size; e += m->entry_size) {
                const struct mb2_mmap_entry *me =
                    (const struct mb2_mmap_entry *)((const u8 *)t + e);
                if (n >= MB2_MAX_MMAP) { truncated = 1; break; }
                mb2_map[n].addr     = me->base_addr;
                mb2_map[n].size     = me->length;
                mb2_map[n].type     = me->type;
                mb2_map[n].reserved = 0;
                n++;
            }
            break;
        }

        case MB2_TAG_FRAMEBUFFER: {
            const struct mb2_tag_framebuffer *f =
                (const struct mb2_tag_framebuffer *)t;
            if (t->size >= sizeof(*f)) {
                mb2_fb_info.addr    = f->addr;
                mb2_fb_info.pitch   = f->pitch;
                mb2_fb_info.width   = f->width;
                mb2_fb_info.height  = f->height;
                mb2_fb_info.bpp     = f->bpp;
                mb2_fb_info.fb_type = f->fb_type;
                mb2_have_fb = 1;
            }
            break;
        }

        case MB2_TAG_ACPI_OLD:
        case MB2_TAG_ACPI_NEW:
            /* The RSDP is copied INTO the MBI by the bootloader, so
             * this address is the tag's own payload, not the firmware
             * table. Nothing in the guest reads it yet; it is carried
             * because losing it here is losing it for good. */
            mb2_si.rsdp_paddr = (u64)(unsigned long)((const u8 *)t + 8);
            break;

        default:
            break;
        }

        off += (t->size + 7) & ~7u;
    }

    if (truncated) {
        mb2_why = "this machine reports more memory regions than the "
                  "boot code has room for — refusing to run on a map "
                  "it only partly read";
        return 0;
    }
    if (!n) {
        mb2_why = "the bootloader supplied no memory map — refusing to "
                  "guess how much RAM this machine has";
        return 0;
    }

    mb2_si.memmap_paddr   = (u64)(unsigned long)mb2_map;
    mb2_si.memmap_entries = n;
    return (unsigned long)&mb2_si;
}
