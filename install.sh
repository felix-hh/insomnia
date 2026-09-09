#!/bin/bash
# Installs insomnia: a symlink on PATH, plus a scoped sudoers rule so it never has to
# ask for a password. Safe to re-run; it overwrites both.
#
#   ./install.sh              install to ~/.local/bin (falls back to /usr/local/bin)
#   ./install.sh --uninstall  remove the symlink and the sudoers rule

set -euo pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT=$SRC_DIR/insomnia
SUDOERS_SRC=$SRC_DIR/sudoers.insomnia
SUDOERS_DST=/etc/sudoers.d/insomnia
USER_NAME=$(id -un)

# sudo needs a TTY to prompt on. When there is none (running from an IDE, an agent, a
# CI-ish context), fall back to an askpass helper if one is configured.
SUDO=(sudo)
if [[ ! -t 0 && -n ${SUDO_ASKPASS:-} ]]; then
  SUDO=(sudo -A)
fi

if [[ $(uname) != Darwin ]]; then
  echo "insomnia: macOS only - it drives pmset." >&2
  exit 1
fi

# Prefer a user-owned PATH directory, so the symlink needs no sudo at all.
pick_bindir() {
  local d
  for d in "$HOME/.local/bin" "$HOME/bin"; do
    case ":$PATH:" in *":$d:"*) [[ -d $d && -w $d ]] && { echo "$d"; return; } ;; esac
  done
  echo /usr/local/bin
}

if [[ ${1:-} == --uninstall ]]; then
  for d in "$HOME/.local/bin" "$HOME/bin" /usr/local/bin; do
    [[ -L $d/insomnia ]] && rm -f "$d/insomnia" && echo "removed $d/insomnia"
  done
  if [[ -e $SUDOERS_DST ]]; then
    "${SUDO[@]}" rm -f "$SUDOERS_DST" && echo "removed $SUDOERS_DST"
  fi
  echo "done. sleep settings themselves are untouched: check with 'pmset -g | grep SleepDisabled'"
  exit 0
fi

chmod 755 "$SCRIPT"

BINDIR=$(pick_bindir)
if [[ -w $BINDIR ]]; then
  ln -sf "$SCRIPT" "$BINDIR/insomnia"
else
  "${SUDO[@]}" ln -sf "$SCRIPT" "$BINDIR/insomnia"
fi
echo "linked $BINDIR/insomnia -> $SCRIPT"

case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "note: $BINDIR is not on your PATH; add it to your shell profile" ;;
esac

# The sudoers rule. Without it insomnia still works, but prompts for a password on
# every call - including inside the watchdog, where nobody is around to answer.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
sed "s/__USER__/$USER_NAME/" "$SUDOERS_SRC" > "$tmp"

echo
echo "Installing the sudoers rule below. It grants exactly two commands, nothing else:"
grep -v '^#' "$tmp" | sed 's/^/    /'
echo

# Validate before asking for a password: visudo -c needs no privileges, and a broken
# sudoers file must never reach /etc/sudoers.d, where it can break sudo entirely.
if ! visudo -c -f "$tmp"; then
  echo "insomnia: generated sudoers file does not parse; nothing installed" >&2
  exit 1
fi

if ! "${SUDO[@]}" install -m 440 -o root -g wheel "$tmp" "$SUDOERS_DST"; then
  echo >&2
  echo "insomnia: could not install $SUDOERS_DST (sudo declined or was cancelled)." >&2
  echo "insomnia: the symlink is in place, so the tool works; it will just ask for a" >&2
  echo "insomnia: password on every call. Re-run ./install.sh to try again." >&2
  exit 1
fi
echo "installed $SUDOERS_DST"

echo
echo "Done. Try:  insomnia 2 && insomnia status"
