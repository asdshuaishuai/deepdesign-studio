// LD_PRELOAD shim: 把 WebKit 编译期硬编码的 /usr 路径重定向到用户目录
// （本机 /usr 只读且无 root，无法放置 WebKitNetworkProcess 等 helper）
// 通过环境变量 TAURI_DEPS 指定前缀，如 ~/.local/opt/tauri-deps
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <spawn.h>

static const char *PREFIXES[] = {
    "/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1",
    "/usr/bin/xdg-dbus-proxy",
    "/usr/bin/bwrap",
    NULL,
};

// 返回重写后的路径（静态缓冲区），或 NULL 表示无需重写
static const char *remap(const char *path)
{
    static __thread char buf[4096];
    const char *deps = getenv("TAURI_DEPS");
    if (!deps || !path || path[0] != '/')
        return NULL;
    for (int i = 0; PREFIXES[i]; i++) {
        size_t n = strlen(PREFIXES[i]);
        if (strncmp(path, PREFIXES[i], n) == 0 &&
            (path[n] == '\0' || path[n] == '/')) {
            snprintf(buf, sizeof buf, "%s/usr/%s", deps, path + 5); // 跳过 "/usr/"
            if (getenv("REDIRECT_DEBUG"))
                fprintf(stderr, "[redirect] %s -> %s\n", path, buf);
            return buf;
        }
    }
    if (getenv("REDIRECT_DEBUG") && path[0] == '/')
        fprintf(stderr, "[redirect-nomatch] %s\n", path);
    return NULL;
}

typedef int (*execve_fn)(const char *, char *const[], char *const[]);

int execve(const char *path, char *const argv[], char *const envp[])
{
    static execve_fn real;
    if (!real)
        real = (execve_fn)dlsym(RTLD_NEXT, "execve");
    const char *p = remap(path);
    return real(p ? p : path, argv, envp);
}

int execv(const char *path, char *const argv[])
{
    static execve_fn real;
    if (!real)
        real = (execve_fn)dlsym(RTLD_NEXT, "execve");
    const char *p = remap(path);
    return real(p ? p : path, argv, __environ);
}

int execvp(const char *file, char *const argv[])
{
    // 绝对/相对路径直接走 execve 重写；纯文件名交回原实现（由 PATH 解析）
    if (file && file[0] == '/') {
        char *const env_default[] = {NULL};
        extern char **environ;
        (void)env_default;
        return execve(file, argv, environ);
    }
    static int (*real)(const char *, char *const[]);
    if (!real)
        real = (int (*)(const char *, char *const[]))dlsym(RTLD_NEXT, "execvp");
    return real(file, argv);
}

int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *fa,
                const posix_spawnattr_t *attr,
                char *const argv[], char *const envp[])
{
    static int (*real)(pid_t *, const char *,
                       const posix_spawn_file_actions_t *,
                       const posix_spawnattr_t *, char *const[], char *const[]);
    if (!real)
        real = (int (*)(pid_t *, const char *,
                        const posix_spawn_file_actions_t *,
                        const posix_spawnattr_t *, char *const[], char *const[]))dlsym(RTLD_NEXT, "posix_spawn");
    const char *p = remap(path);
    return real(pid, p ? p : path, fa, attr, argv, envp);
}

__attribute__((constructor))
static void redirect_init(void)
{
    if (getenv("REDIRECT_DEBUG")) {
        FILE *f = fopen("/tmp/redirect-loaded", "a");
        if (f) { fprintf(f, "loaded pid=%d\n", getpid()); fclose(f); }
    }
}

int execvpe(const char *file, char *const argv[], char *const envp[])
{
    static execve_fn real;
    if (!real)
        real = (execve_fn)dlsym(RTLD_NEXT, "execvpe");
    const char *p = remap(file);
    return real(p ? p : file, argv, envp);
}
