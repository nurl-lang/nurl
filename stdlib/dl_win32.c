/* stdlib/dl_win32.c — Win32 implementations of the three POSIX dynamic-loader
 * entry points packages/gpu/src/cpu.nu binds (& `c` @ dlopen / dlsym /
 * dlclose). They live in libdl / libc on every POSIX host, so nurl.sh needs
 * nothing; Windows has no such symbols at all, and a program that merely
 * IMPORTS packages/gpu — anomaly → tensor → gpukit → gpu, none of which asks
 * for a GPU — died at link with "undefined symbol: dlopen" referenced from
 * cpu_compile / cpu_function. nurl.bat compiles this translation unit into
 * the image when the IR references them, the same way it handles
 * stdlib/cuda_stubs.c.
 *
 * These are real forwarders, not failing stubs: LoadLibraryA / GetProcAddress
 * / FreeLibrary are the exact Win32 analogues, so the mapping costs nothing
 * and stays honest. It does NOT make the CPU backend work on Windows —
 * cpu_compile generates C++ over ucontext_t / makecontext / swapcontext and
 * OpenMP and builds it into a .so with the system c++, none of which exists
 * here. That path fails earlier, at its own system() call, and returns 0 the
 * way it does for any compile failure. What this file buys is the link. */
#ifdef _WIN32
#include <windows.h>

/* POSIX RTLD_* flags have no Win32 counterpart: LoadLibraryA resolves
 * everything eagerly and its handles are process-global, so RTLD_NOW (2) and
 * RTLD_LAZY (1) are already the behaviour and RTLD_GLOBAL / RTLD_LOCAL have
 * nothing to select. Ignore the argument rather than reject unknown bits. */
void *dlopen(const char *path, int flags) {
    (void)flags;
    /* dlopen(NULL, …) means "the running program"; GetModuleHandleA(NULL) is
     * its Win32 equivalent. Do not FreeLibrary that one — see dlclose. */
    if (!path) return (void *)GetModuleHandleA(NULL);
    return (void *)LoadLibraryA(path);
}

void *dlsym(void *handle, const char *name) {
    if (!handle || !name) return 0;
    return (void *)(unsigned long long)GetProcAddress((HMODULE)handle, name);
}

int dlclose(void *handle) {
    /* dlclose returns 0 on success, FreeLibrary returns non-zero. Refuse to
     * free the pseudo-handle dlopen(NULL) hands back: GetModuleHandleA does
     * not take a reference, so freeing it would decrement a count this
     * process never incremented. */
    if (!handle || handle == (void *)GetModuleHandleA(NULL)) return 0;
    return FreeLibrary((HMODULE)handle) ? 0 : -1;
}

/* Not bound by cpu.nu today, but any caller that reaches for dlopen reaches
 * for this next. Formats the last Win32 error into a static buffer, matching
 * dlerror's contract that the caller neither frees nor holds the string. */
char *dlerror(void) {
    static char buf[256];
    DWORD e = GetLastError();
    if (e == 0) return 0;
    DWORD n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM |
                             FORMAT_MESSAGE_IGNORE_INSERTS,
                             0, e, 0, buf, (DWORD)sizeof buf - 1, 0);
    if (n == 0) {
        buf[0] = '?'; buf[1] = 0;
    } else {
        buf[n] = 0;
        while (n && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) buf[--n] = 0;
    }
    SetLastError(0);
    return buf;
}
#endif /* _WIN32 */
