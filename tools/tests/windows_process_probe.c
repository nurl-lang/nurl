/* Exercise the actual shared Windows launch encoder and process APIs. */
#define NURL_PROCESS_COMMANDLINE_TEST 1
#include "../../stdlib/runtime.c"

static void check(int condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(91); }
}
static void encoder_controls(void) {
    const char *args[] = {"", "source %PATH% & !literal!.nu", "two words", "x^y", "a=b"};
    NurlProcLaunch launch = {0};
    check(nurl__proc_build_launch("C:\\tool & %PATH% !dir!\\nurl.CmD", args, 5,
          "C:\\Windows\\System32\\cmd.exe", &launch), "batch encoder failed");
    check(strstr(launch.command.data, "/D /E:ON /V:OFF /S /C") != NULL, "cmd modes");
    check(strstr(launch.command.data, "%%cd:~,%PATH%%cd:~,%") != NULL, "percent expansion guard");
    check(strstr(launch.command.data, "\"source %%cd:~,%PATH%%cd:~,% & !literal!.nu\"") != NULL, "batch argument quoting");
    nurl__proc_launch_free(&launch);
    const char *unsafe[] = {"quote\"&exit", "line\nbreak", "line\rbreak"};
    for (int i = 0; i < 3; ++i) {
        check(!nurl__proc_build_launch("safe.bat", &unsafe[i], 1, "cmd.exe", &launch), "unsafe batch argument accepted");
        nurl__proc_launch_free(&launch);
    }
    check(nurl__proc_build_launch("C:\\native %PATH% & !safe!.exe", unsafe, 3,
          "cmd.exe", &launch), "native encoder rejected arguments");
    check(!launch.application, "native executable uses shell");
    nurl__proc_launch_free(&launch);
    puts("Windows process encoder controls: ok");
}
int main(int argc, char **argv) {
#if defined(_WIN32)
    /* Preserve captured bytes; the outer probe must not translate a child's
     * CRLF a second time when testing the raw process result buffers. */
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
    /* Controlled linker used to test publication's file-type boundary. */
    if (argc > 1 && !strcmp(argv[1], "cc") && getenv("NURL_PROCESS_LINK_CONTROL")) {
        const char *output = NULL;
        for (int i = 2; i + 1 < argc; ++i)
            if (!strcmp(argv[i], "-o")) output = argv[i + 1];
        check(output && strlen(output) >= 4, "controlled linker output missing");
        const char *mode = getenv("NURL_PROCESS_LINK_CONTROL");
        char *pdb = strdup(output);
        check(pdb != NULL, "controlled linker allocation failed");
        memcpy(pdb + strlen(pdb) - 4, ".pdb", 5);
        if (!strcmp(mode, "output-directory")) {
            check(CreateDirectoryA(output, NULL), "cannot create controlled output directory");
        } else {
            check(!strcmp(mode, "pdb-directory") || !strcmp(mode, "regular-files"),
                  "unknown controlled linker mode");
            check(CopyFileA(argv[0], output, TRUE), "cannot copy controlled executable");
            if (!strcmp(mode, "pdb-directory")) {
                check(CreateDirectoryA(pdb, NULL), "cannot create controlled PDB directory");
            } else {
                FILE *symbols = fopen(pdb, "wb");
                check(symbols != NULL, "cannot create controlled PDB file");
                check(fwrite("controlled-pdb", 1, 14, symbols) == 14, "cannot write controlled PDB");
                check(fclose(symbols) == 0, "cannot close controlled PDB");
            }
        }
        free(pdb);
        return 0;
    }
#endif
    /* A copied probe stands in for nurlpkg solely to observe the driver's
     * upgrade argv without performing a network request or installation. */
    if (argc >= 2 && !strcmp(argv[1], "self-update")) {
        for (int i = 1; i < argc; ++i) printf("%zu:%s\n", strlen(argv[i]), argv[i]);
        return 0;
    }
    if (argc < 2 || !strcmp(argv[1], "controls")) { encoder_controls(); return 0; }
    if (!strcmp(argv[1], "echo")) {
        for (int i = 2; i < argc; ++i) printf("%zu:%s\n", strlen(argv[i]), argv[i]);
        return 0;
    }
    if (!strcmp(argv[1], "copy")) {
        char buffer[4096];
        size_t count;
        while ((count = fread(buffer, 1, sizeof(buffer), stdin)) != 0)
            if (fwrite(buffer, 1, count, stdout) != count) return 93;
        return ferror(stdin) ? 94 : 0;
    }
#if defined(_WIN32)
    if (argc == 3 && !strcmp(argv[1], "shell")) {
        long long raw = nurl_proc_run_shell(argv[2]);
        NurlProcResult *r = (NurlProcResult *)(uintptr_t)raw;
        check(r != NULL, "shell result missing");
        int code = r->err_kind ? 80 + (int)r->err_kind : (int)r->exit_code;
        if (r->stdout_len) fwrite(r->stdout_buf, 1, (size_t)r->stdout_len, stdout);
        if (r->stderr_len) fwrite(r->stderr_buf, 1, (size_t)r->stderr_len, stderr);
        nurl_proc_free(raw);
        return code;
    }
    if (argc >= 3 && !strcmp(argv[1], "run")) {
        long long raw = nurl_proc_run(argv[2], (const char *)(argv + 3), argc - 3, "");
        NurlProcResult *r = (NurlProcResult *)(uintptr_t)raw;
        check(r != NULL, "process result missing");
        int code = r->err_kind ? 80 + (int)r->err_kind : (int)r->exit_code;
        if (r->stdout_len) fwrite(r->stdout_buf, 1, (size_t)r->stdout_len, stdout);
        if (r->stderr_len) fwrite(r->stderr_buf, 1, (size_t)r->stderr_len, stderr);
        nurl_proc_free(raw);
        return code;
    }
    if (argc >= 3 && !strcmp(argv[1], "spawn")) {
        long long raw = nurl_proc_spawn(argv[2], (const char *)(argv + 3), argc - 3);
        check(raw && !nurl_proc_spawn_err_kind(raw), "spawn failed");
        nurl_proc_spawn_close_stdin(raw);
        while (!nurl_proc_spawn_eof(raw)) {
            const char *line = nurl_proc_spawn_read_line(raw, 5000);
            if (line && nurl_proc_spawn_read_line_len(raw)) puts(line);
            check(!nurl_proc_spawn_last_io_err(raw), "spawn read failed");
        }
        int code = (int)nurl_proc_spawn_wait(raw);
        nurl_proc_spawn_free(raw);
        return code;
    }
#endif
    fprintf(stderr, "unsupported mode\n");
    return 92;
}
