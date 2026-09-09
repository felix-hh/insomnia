# insomnia

Keep a Mac awake for a bounded window, then let it sleep again on its own.

`sudo pmset disablesleep 1` is the real way to stop a Mac sleeping, including with the
lid shut, where `caffeinate` gives up. The problem is the matching `disablesleep 0`:
forget it and the machine never sleeps again, which you find out when you pull a hot
laptop out of a closed bag. `insomnia` sets a deadline up front and re-enables sleep
when it expires, whether or not you remember.

```console
$ insomnia
sleep disabled for 1h00m, until Tue 20:08 (watchdog pid 98605)
cancel early with: insomnia off
```

## Install

```sh
git clone https://github.com/felix-hh/insomnia.git && cd insomnia && ./install.sh
```

That symlinks `insomnia` onto your PATH (into `~/.local/bin` when it can, so no `sudo`
for that part) and installs a sudoers rule scoped to two commands so it never prompts
for a password. It prints the rule and asks for your password once.
`./install.sh --uninstall` reverses both. macOS only; it is `pmset` underneath.

## Usage

A bare number is minutes. Minimum 1 minute, maximum 24 hours.

```sh
insomnia          # 60 minutes (the default)
insomnia 30       # 30 minutes
insomnia 4h       # 4 hours
insomnia 90m      # 90 minutes
insomnia .5h      # 30 minutes
insomnia off      # re-enable sleep now (also: stop, 0)
insomnia status   # is sleep disabled, and how much time is left
```

## Re-running replaces the window

There is only ever one deadline and one watchdog. Each invocation cancels the previous
one, so a window can be extended, shortened, or fixed after a typo:

```console
$ insomnia 2
sleep disabled for 2m, until Tue 18:58 (watchdog pid 83771)

$ insomnia 24h                     # longer: replaces the 2m window
sleep disabled for 24h00m, until Wed 18:56 (watchdog pid 84013)

$ insomnia 1                       # shorter: the 24h window is gone
sleep disabled for 1m, until Tue 18:57 (watchdog pid 84058)

$ insomnia status
sleep: DISABLED, 1m left (until Tue 18:57), watchdog pid 84058
```

Last one wins, deliberately. Shortening early is harmless, you just re-run it. Keeping
the longer window instead would mean a mistyped `24h` outliving the `1` you typed to
correct it, which is the exact failure this tool exists to prevent.

## How it works

`pmset -a disablesleep 1`, then a detached watchdog polls in 30s ticks against a
wall-clock deadline and runs `pmset -a disablesleep 0`. Polling a deadline rather than
sleeping once for the whole duration means a clock jump or a suspended process cannot
stretch the window.

Before disabling anything, it preflights the entire exit path: the state file has to be
writable and the re-enable command has to actually run. Any failure after that point
would leave sleep disabled with nothing to turn it back on, so it refuses up front
instead:

```console
$ insomnia 30
insomnia: cannot re-enable sleep without a password, so refusing to disable it.
```

State lives in `~/.local/state/insomnia.state` as `<watchdog-pid> <deadline-epoch>`.

## The sudoers rule

`pmset disablesleep` is root-only, so without a rule every call prompts for a password,
including the watchdog's call hours later when nobody is at the keyboard. `install.sh`
installs this to `/etc/sudoers.d/insomnia`:

```
you ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

- Two exact commands, no wildcards, so there is no argument-injection gap. Every other
  `pmset` invocation still prompts normally.
- It cannot be narrowed to "only when insomnia is the caller": sudoers matches on user,
  host, run-as target and command, never on the calling program. It does not need to be.
  Those two commands are the entire capability this tool has, which is toggling sleep.
- The rule points at `/usr/bin/pmset`, never at this script. A NOPASSWD rule on a script
  in a user-writable checkout would hand root to anything that can write that file.

If you would rather not add a sudoers rule at all, insomnia works without one from a
root shell (`sudo -i`): it calls `pmset` directly when it is already root.

## Known gaps

- **Reboot.** `disablesleep` is persistent power-management state; the watchdog is only a
  process. Reboot mid-window and sleep stays disabled with nothing left to re-enable it.
  `insomnia status` reports `DISABLED with no live watchdog`, and `insomnia off`
  recovers it in one command, but nothing does so automatically. A LaunchDaemon forcing
  `disablesleep 0` at boot would close the gap; not implemented.

  State survives reboots too, so the recorded pid may since have been reused by an
  unrelated process. Both `status` and the kill path verify a pid really is a watchdog
  (by command-line tag) before trusting or signalling it.
- **Closing the terminal is fine.** The watchdog ignores SIGHUP, verified both directly
  and against its whole process group, so it outlives the shell that started it.
- **Orphaned watchdogs.** If a run dies between spawning its watchdog and recording the
  pid, only the signature sweep (`pkill -f insomnia-watchdog`) can reach it. The
  preflight makes that window small, not zero.
- No combined units: write `90m`, not `1h30m`.
