// Shebang interpreter for `cargo -Zscript` scripts. Only the cache hit lives here, since bash
// startup alone costs more than the script it fronts; everything else is nix-run-cached.sh.
// Built into ./nix-run-cached by the home-manager activation in hosts/hm-shared/config_symlinks.nix.
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

// These scripts are polled by the bar, bound to keys, and run in loops — read far more often
// than they are edited, so they are built optimised. Passed to cargo rather than written into
// every frontmatter, and not exported: a script that shells out to cargo itself must not inherit it.
#define OPT_LEVEL "2"

static void die(const char *msg) {
	fprintf(stderr, "nix-run-cached: %s\n", msg);
	exit(1);
}

// Whole file, NUL-terminated, trailing newline stripped; NULL if absent.
static char *slurp(const char *path, size_t *len) {
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return NULL;
	struct stat st;
	if (fstat(fd, &st) < 0)
		die("fstat");
	char *buf = malloc(st.st_size + 1);
	size_t n = 0;
	ssize_t r;
	while (n < (size_t)st.st_size && (r = read(fd, buf + n, st.st_size - n)) > 0)
		n += r;
	close(fd);
	if (n != (size_t)st.st_size)
		die("short read");
	if (len)
		*len = n;
	else if (n && buf[n - 1] == '\n')
		n--;
	buf[n] = 0;
	return buf;
}

static int newer(struct timespec a, struct timespec b) {
	return a.tv_sec > b.tv_sec || (a.tv_sec == b.tv_sec && a.tv_nsec > b.tv_nsec);
}

static void exec_bin(const char *bin, char **argv) {
	argv[1] = (char *)bin;
	execv(bin, argv + 1);
	perror(bin);
	exit(127);
}

int main(int argc, char **argv) {
	if (argc < 2)
		die("usage: nix-run-cached <script.rs> [args...]");
	const char *ver = getenv("DEFAULT_CARGO_NIGHTLY_VERSION");
	if (!ver || !*ver)
		die("DEFAULT_CARGO_NIGHTLY_VERSION unset — set in os/nixos/desktop/environment.nix and re-login");
	const char *home = getenv("HOME");
	if (!home)
		die("HOME unset");

	char script[4096], state[4096], key[8192], content[8192], stamp[4096];
	if (argv[1][0] == '/')
		snprintf(script, sizeof script, "%s", argv[1]);
	else {
		char cwd[4096];
		if (!getcwd(cwd, sizeof cwd))
			die("getcwd");
		snprintf(script, sizeof script, "%s/%s", cwd, argv[1]);
	}
	snprintf(state, sizeof state, "%s/.cargo/target", home);

	// A key, not a canonical name: two spellings of one script get two entries, each correct
	// on its own because freshness is an mtime compare.
	int n = snprintf(key, sizeof key, "%s/.bin-%s-o" OPT_LEVEL "-", state, ver);
	for (const char *c = script; *c && n < (int)sizeof key - 1; c++)
		key[n++] = *c == '/' ? '%' : *c;
	key[n] = 0;

	// Once a day, detached and double-forked so the exec'd script never inherits a zombie.
	snprintf(stamp, sizeof stamp, "%s/.next-sweep", state);
	char *next = slurp(stamp, NULL);
	time_t now = time(NULL);
	if (!next || now >= atoll(next)) {
		FILE *f = fopen(stamp, "w");
		if (!f)
			die("cannot write sweep stamp");
		fprintf(f, "%lld\n", (long long)now + 86400);
		fclose(f);
		pid_t p = fork();
		if (p == 0) {
			setsid();
			if (fork() == 0) {
				int null = open("/dev/null", O_RDWR);
				dup2(null, 0), dup2(null, 1), dup2(null, 2);
				char sh[4096];
				snprintf(sh, sizeof sh, "%s.sh", argv[0]);
				execl(sh, sh, "--sweep", (char *)NULL);
			}
			_exit(0);
		}
		waitpid(p, NULL, 0);
	}
	free(next);

	struct stat sst, bst;
	if (stat(script, &sst) < 0) {
		perror(script);
		return 1;
	}
	char *bin = slurp(key, NULL);
	if (bin && stat(bin, &bst) == 0 && !access(bin, X_OK) && !newer(sst.st_mtim, bst.st_mtim)) {
		utimensat(AT_FDCWD, key, NULL, 0); // access record for the sweep
		exec_bin(bin, argv);
	}

	// Content-addressed second chance: fish config runs scripts from /nix/store/<hash>-source,
	// a new path on every switch, and cargo keys its build dir by path — so without this every
	// switch recompiles every script from scratch.
	size_t len;
	char *src = slurp(script, &len);
	if (!src) {
		perror(script);
		return 1;
	}
	uint64_t h = 0xcbf29ce484222325ull;
	for (size_t i = 0; i < len; i++)
		h = (h ^ (unsigned char)src[i]) * 0x100000001b3ull;
	snprintf(content, sizeof content, "%s/.content/%s-o" OPT_LEVEL "-%016llx", state, ver, (unsigned long long)h);
	if (!access(content, X_OK)) {
		utimensat(AT_FDCWD, content, NULL, 0); // makes it newer than the script, so the key below holds
		FILE *f = fopen(key, "w");
		if (!f)
			die("cannot write cache entry");
		fprintf(f, "%s\n", content);
		fclose(f);
		exec_bin(content, argv);
	}

	char sh[4096];
	snprintf(sh, sizeof sh, "%s.sh", argv[0]);
	char **args = malloc((argc + 5) * sizeof *args);
	args[0] = sh, args[1] = OPT_LEVEL, args[2] = key, args[3] = content, args[4] = script;
	memcpy(args + 5, argv + 2, (argc - 2) * sizeof *args);
	args[argc + 3] = NULL;
	execv(sh, args);
	perror(sh);
	return 127;
}
