{ pkgs, ... }:
let
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
            n = libc.syscall(SYS_process_madvise, pidfd, arr, len(ivs), MADV_PAGEOUT, 0)
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
  # index means a slow cold rebuild on return. Instead, when a server shows zero
  # CPU across several consecutive polls, we page its memory out to swap and
  # leave it running; reactivation is a transparent page-in on the next request.
  systemd.services.lsp-pager = {
    description = "Page idle LSP servers out to swap to reclaim RAM (keeps them alive)";
    path = [ pkgs.procps pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Per-pid state file holds "<cpu_jiffies> <consecutive_idle_polls>".
      # CPU-idle = zero growth in utime+stime (fields 14+15 of /proc/<pid>/stat)
      # since the previous poll. After IDLE_POLLS consecutive idle polls we page
      # the process out; the counter keeps climbing while it stays idle, so we
      # re-page periodically (cheap/idempotent — only newly-resident pages move).
      STATE=/run/lsp-pager
      mkdir -p "$STATE"
      IDLE_POLLS=3   # with a 10min timer → ~30min of continuous idle before paging out

      # Match server *executables*, not wrapper/proxy helpers
      # (e.g. rust-analyzer-proc-macro-srv, which RA spawns and manages itself).
      PATTERN='^(rust-analyzer|clangd|gopls|pyright|pylsp|jedi-language-server|lua-language-server|typescript-language-server|tsserver|nil|tinymist|marksman|bash-language-server|yaml-language-server|vscode-json-language|tailwindcss-language-server|ocamllsp|texlab|ty)$'

      live=" "
      for pid in $(ps -eo pid= ); do
        comm=$(cat /proc/$pid/comm 2>/dev/null) || continue
        echo "$comm" | grep -qE "$PATTERN" || continue
        live="$live$pid "

        cpu=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null) || continue
        read -r prev_cpu idle_count < "$STATE/$pid" 2>/dev/null || { prev_cpu=""; idle_count=0; }

        if [ "$cpu" = "$prev_cpu" ]; then
          idle_count=$((idle_count + 1))
        else
          idle_count=0
        fi
        echo "$cpu $idle_count" > "$STATE/$pid"

        if [ "$idle_count" -ge "$IDLE_POLLS" ]; then
          age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
          rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
          echo "paging out idle $comm pid=$pid (age=''${age}s rss=$((rss/1024))MB idle_polls=$idle_count)"
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
    description = "Periodically page out idle LSP servers";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "10min";
    };
  };
}
