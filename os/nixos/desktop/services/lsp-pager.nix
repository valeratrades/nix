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
            ivs = []
            with open(f"/proc/{pid}/maps") as f:
                for line in f:
                    p = line.split()
                    if "r" not in p[1]:
                        continue
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
  # index means a slow cold rebuild on return. Instead, once a server has burned
  # no CPU for `default_s_inactive_to_retire`, we page its memory out to swap and
  # leave it running; reactivation is a transparent page-in on the next request
  # (sub-second even for a multi-GB session on NVMe).
  systemd.services.lsp-pager = {
    description = "Retire idle LSP servers to swap to reclaim RAM (keeps them alive)";
    path = [ pkgs.procps pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Per-pid state holds "<cpu_jiffies> <idle_since_uptime>". CPU-idle = zero
      # growth in utime+stime (fields 14+15 of /proc/<pid>/stat) since last poll.
      # `idle_since` is the monotonic /proc/uptime second at which the current
      # idle streak began; it resets the instant CPU advances. Retirement fires
      # when now - idle_since >= RETIRE_S, so the threshold is wall-clock and
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

        cpu=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null) || continue
        read -r prev_cpu idle_since < "$STATE/$pid" 2>/dev/null || { prev_cpu=""; idle_since="$now"; }

        # CPU advanced (or first sighting): the server did work — reset the clock.
        if [ "$cpu" != "$prev_cpu" ]; then
          idle_since="$now"
        fi
        echo "$cpu $idle_since" > "$STATE/$pid"

        if [ "$((now - idle_since))" -ge "$RETIRE_S" ]; then
          rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
          echo "retiring idle $comm pid=$pid (rss=$((rss/1024))MB idle=$((now - idle_since))s)"
          ${pageout} "$pid"
        fi
      done

      # Prune state for pids that are gone or no longer LSPs.
      for f in "$STATE"/*; do
        [ -e "$f" ] || continue
        pid=$(basename "$f")
        case "$live" in *" $pid "*) : ;; *) rm -f "$f" ;; esac
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
