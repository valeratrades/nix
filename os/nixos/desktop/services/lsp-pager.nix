{ pkgs, user, ... }:
let
  retireSeconds = toString user.default_s_inactive_to_retire;
  # Poll often enough that we notice a server waking (and reset its idle clock)
  # well before the retire threshold; the threshold itself is wall-clock, so the
  # poll rate only affects detection latency, not when retirement actually fires.
  pollSeconds = "2min";
  # Page a process's resident anon memory out to swap via
  # process_madvise(MADV_PAGEOUT) — pid-targeted, leaves the process alive and
  # fully responsive; the kernel faults pages back in on next access. Requires
  # CAP_SYS_NICE, which the service has by running as root. We page out, never
  # kill: a live editor/Claude session owns each LSP and we want reactivation to
  # be a cheap page-in, not a cold re-index.
  pageout = pkgs.writers.writePython3 "lsp-pageout" { } ''
    import ctypes
    import os
    import sys

    SYS_pidfd_open = 434
    SYS_process_madvise = 440
    MADV_PAGEOUT = 21

    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    libc.syscall.restype = ctypes.c_long


    class Iovec(ctypes.Structure):
        _fields_ = [("base", ctypes.c_void_p), ("len", ctypes.c_size_t)]


    def pageout(pid):
        libc.syscall.argtypes = [ctypes.c_long, ctypes.c_int, ctypes.c_uint]
        pidfd = libc.syscall(SYS_pidfd_open, pid, 0)
        if pidfd < 0:
            return -ctypes.get_errno()  # process gone between detection and now
        try:
            # Only writable, private, anonymous mappings hold swappable heap.
            # File-backed regions are reclaimable via the page cache, shared ones
            # aren't ours to evict, and kernel maps ([vdso]/[vvar]/[vsyscall])
            # EFAULT the whole syscall — including any of these inflated the byte
            # count (a 1MB-resident process reported ~2GB) or broke the call.
            # The genuine heap/stack/anon arenas are always rw-p; requiring 'w'
            # excludes every special region in one stroke.
            # maps fields: range perms off dev ino path.
            ivs = []
            with open(f"/proc/{pid}/maps") as f:
                for line in f:
                    p = line.split()
                    perms = p[1]
                    if "w" not in perms or "p" not in perms:
                        continue
                    if len(p) > 5 and p[5] and not p[5].startswith("["):
                        continue  # skip file-backed (has a real pathname)
                    a, b = (int(x, 16) for x in p[0].split("-"))
                    if b > a:
                        ivs.append(Iovec(a, b - a))
            if not ivs:
                return 0
            arr = (Iovec * len(ivs))(*ivs)
            libc.syscall.argtypes = [
                ctypes.c_long, ctypes.c_int, ctypes.c_void_p,
                ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong,
            ]
            # process_madvise caps one call at ~INT_MAX bytes, so a multi-GB
            # server pages partially here and finishes on the next poll (2min) —
            # both happen while it stays idle, so convergence is automatic.
            n = libc.syscall(
                SYS_process_madvise, pidfd, arr, len(ivs), MADV_PAGEOUT, 0
            )
            return n if n >= 0 else -ctypes.get_errno()
        finally:
            os.close(pidfd)


    for arg in sys.argv[1:]:
        print(arg, pageout(int(arg)))
  '';
in
{
  # LSP servers (rust-analyzer, gopls, clangd, ...) have no idle-timeout concept:
  # the protocol leaves lifecycle to the editor client, and a single idle
  # rust-analyzer holds 1-3GB resident indefinitely. Each live nvim / Claude
  # session legitimately owns one, so we must NOT kill them — losing the warm
  # index means a slow cold rebuild on return. Instead, once a server has been
  # unused by its editor for `default_s_inactive_to_retire`, we page its memory
  # out to swap and leave it running; reactivation is a transparent page-in on
  # the next request (sub-second even for a multi-GB session on NVMe).
  #
  # "Unused" = no growth in /proc/<pid>/io rchar (cumulative bytes the process
  # has read). Every LSP request arrives over the editor socket and shows up as
  # rchar; idle navigation that produces no file writes still counts as use, and
  # background log writes (wchar) don't, so rchar tracks actual capability use far
  # better than CPU jiffies — which keep ticking from GC/housekeeping and falsely
  # reset the clock (and re-page an already-resident server every poll).
  systemd.services.lsp-pager = {
    description = "Retire idle LSP servers to swap to reclaim RAM (keeps them alive)";
    path = [ pkgs.procps pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Per-pid state holds "<rchar> <idle_since_uptime>". Idle = zero growth in
      # /proc/<pid>/io rchar (cumulative bytes read) since last poll. `idle_since`
      # is the monotonic /proc/uptime second at which the current idle streak
      # began; it resets the instant rchar advances. Retirement fires when
      # now - idle_since >= RETIRE_S, so the threshold is wall-clock and
      # independent of how often this runs.
      STATE=/run/lsp-pager
      mkdir -p "$STATE"
      RETIRE_S=${retireSeconds}
      now=$(awk '{print int($1)}' /proc/uptime)

      # Match server *executables*, not wrapper/proxy helpers
      # (e.g. rust-analyzer-proc-macro-srv, which RA spawns and manages itself).
      PATTERN='^(rust-analyzer|clangd|gopls|pyright|pylsp|jedi-language-server|lua-language-server|typescript-language-server|tsserver|nil|tinymist|marksman|bash-language-server|yaml-language-server|vscode-json-language|tailwindcss-language-server|ocamllsp|texlab|ty)$'

      live=" "
      for pid in $(ps -eo pid= ); do
        comm=$(cat /proc/$pid/comm 2>/dev/null) || continue
        echo "$comm" | grep -qE "$PATTERN" || continue
        live="$live$pid "

        rchar=$(awk '/^rchar:/{print $2}' /proc/$pid/io 2>/dev/null) || continue
        [ -n "$rchar" ] || continue
        read -r prev_rchar idle_since < "$STATE/$pid" 2>/dev/null || { prev_rchar=""; idle_since="$now"; }

        # rchar advanced (or first sighting): the editor used the server — reset.
        if [ "$rchar" != "$prev_rchar" ]; then
          idle_since="$now"
        fi
        echo "$rchar $idle_since" > "$STATE/$pid"

        if [ "$((now - idle_since))" -ge "$RETIRE_S" ]; then
          rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
          echo "retiring idle $comm pid=$pid (rss=$((rss/1024))MB idle=$((now - idle_since))s)"
          ${pageout} "$pid"
        fi
      done

      # Prune state for pids that are gone or no longer LSPs. Re-glob guard: a pid
      # can exit between glob and read, so tolerate a vanished entry.
      for f in "$STATE"/*; do
        [ -e "$f" ] || continue
        pid=$(basename "$f")
        case "$live" in *" $pid "*) : ;; *) rm -f "$f" 2>/dev/null ;; esac
      done
    '';
  };

  systemd.timers.lsp-pager = {
    description = "Periodically retire idle LSP servers to swap";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = pollSeconds;
      OnUnitActiveSec = pollSeconds;
    };
  };
}
