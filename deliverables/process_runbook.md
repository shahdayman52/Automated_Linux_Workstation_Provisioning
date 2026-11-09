# Process Troubleshooting Runbook

**Nexus Data Systems — Data Engineering**
**Applies to:** Headless Debian/Ubuntu workstations provisioned by `setup_workstation.sh`

This runbook explains how to inspect running processes, find a zombie process by its PID, and terminate the process responsible for it.

---

## 1. Key Terms

| Term | Definition |
|---|---|
| **Kernel** | The core of the Linux operating system. It sits between hardware and software, schedules processes on the CPU, allocates memory, and handles system calls. Every process is created, tracked and destroyed by the kernel. |
| **PID** (Process ID) | A unique number the kernel assigns to each running process. Commands such as `ps`, `top` and `kill` use the PID to identify the process to act on. Every process also has a **PPID** (Parent Process ID), the PID of the process that started it. |
| **Daemon** | A background process that runs without a controlling terminal, usually started at boot and providing a service (for example `sshd`, `cron`, `systemd-journald`). Names often end in `d`. In `ps` output, daemons show `?` in the `TTY` column. |
| **Zombie process** | A process that has finished running but still has an entry in the kernel's process table because its parent has not yet read its exit status (with `wait()`). It uses no CPU and holds no user memory, only a small entry in the kernel's process table, but it keeps its PID. A large number of zombies can use up the available PIDs. In `ps` it shows state `Z` and is labelled `<defunct>`. |

---

## 2. Inspecting Running Processes

| Goal | Command |
|---|---|
| Snapshot of all processes, all users | `ps aux` |
| Full listing including PPID | `ps -ef` |
| Live, interactive resource view | `htop` (F6 sort, F9 kill, F10 quit) |
| Find a process by name | `pgrep -a <name>` or `ps aux \| grep <name>` |
| Show the process tree (parent/child) | `ps -ef --forest` |
| Details for a single PID | `ps -o pid,ppid,stat,user,cmd -p <PID>` |

Common `STAT` codes: `R` running, `S` sleeping, `D` uninterruptible sleep, `T` stopped, `Z` zombie.

---

## 3. Locating a Zombie Process by PID

**Step 1 — List zombies with their PID and parent PID:**

```bash
ps -eo pid,ppid,stat,cmd | awk 'NR==1 || $3 ~ /^Z/'
```

- `-e` selects every process.
- `-o pid,ppid,stat,cmd` prints only the PID, parent PID, state and command.
- `awk 'NR==1 || $3 ~ /^Z/'` keeps the header line plus only rows whose state starts with `Z`.

Example output:

```
  PID  PPID STAT CMD
 4821  4790 Z+   [worker.sh] <defunct>
```

Alternative with `ps aux` (the `STAT` column is field 8; the PID is field 2):

```bash
ps aux | awk '$8 ~ /^Z/'
```

Do not use a plain `ps aux | grep Z`: it matches a `Z` anywhere on the line (user names, commands) and returns false positives.

**Step 2 — Find the parent process:**

```bash
ps -o pid,ppid,stat,user,cmd -p <PPID>
```

Use the `PPID` from Step 1 (here `4790`).

---

## 4. Terminating the Process

A zombie has already exited, so `kill -9 <zombie PID>` has no effect: there is nothing left to kill. You remove a zombie through its **parent**.

**Step 1 — Ask the parent to reap its children (gentle):**

```bash
kill -s SIGCHLD <PPID>
```

**Step 2 — Terminate the parent gracefully (SIGTERM, signal 15):**

```bash
kill -15 <PPID>
```

**Step 3 — Force-terminate if it is still running (SIGKILL, signal 9):**

```bash
kill -9 <PPID>
```

`SIGKILL` cannot be caught or ignored. The kernel stops the process immediately. When the parent dies, its zombie children are adopted by `init`/`systemd` (PID 1), which reaps them automatically.

The same `kill -15` followed by `kill -9 <PID>` sequence force-terminates any rogue process or daemon that is still running (not a zombie) and consuming resources.

> Use `sudo kill -9 <PID>` if the process belongs to another user. Never kill PID 1 or core system daemons.

**Step 4 — Verify:**

```bash
ps -eo pid,ppid,stat,cmd | awk '$3 ~ /^Z/'   # should print nothing
ps -p <PPID>                                  # should show no process
```

---

## 5. Quick Reference

```bash
ps aux                                      # snapshot of all processes
ps -eo pid,ppid,stat,cmd | awk '$3 ~ /^Z/'  # find zombies (PID + PPID)
kill -15 <PID>                              # graceful terminate (SIGTERM)
kill -9 <PID>                               # force terminate (SIGKILL)
kill -l                                     # list all signal names/numbers
```
