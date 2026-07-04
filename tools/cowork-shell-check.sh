#!/usr/bin/env bash
# cowork-memory-sync — POSIX-shell probe
#
# Run this INSIDE a Cowork session (paste it into the chat and say
# "run this in bash"), on the machine you want to check — especially
# Windows. It reports whether Cowork's Bash tool is a POSIX-style shell
# with the commands the plugin relies on.
#
# READING THE RESULT:
#   - If the first lines print a real `uname` and timestamp and the
#     commands say OK, Cowork's shell is POSIX-style → the plugin's shell
#     usage is safe on this machine.
#   - If it errors immediately, prints nothing, or says "command not
#     found", Cowork is NOT running a POSIX shell here → report that; the
#     plugin's mkdir/rm/cp/find/grep steps won't work as written.

echo "== interpreter =="
echo "uname -s : $(uname -s 2>&1)"
echo "bash     : ${BASH_VERSION:-<not bash / unknown>}"
echo ""

echo "== commands the plugin uses =="
for c in uname date hostname mkdir rm cp ls find grep sed; do
  if command -v "$c" >/dev/null 2>&1; then echo "$c : OK"; else echo "$c : MISSING"; fi
done
echo ""

echo "== functional checks (exact patterns the skills run) =="
d="${TMPDIR:-/tmp}/cms-probe.$$"
mkdir -p "$d/sub" 2>/dev/null   && echo "mkdir -p       : OK" || echo "mkdir -p       : FAIL"
printf 'hello 2001.1234567\n' > "$d/2026-01-01-me-x.md" 2>/dev/null \
                                && echo "write (>)      : OK" || echo "write (>)      : FAIL"
cp "$d/2026-01-01-me-x.md" "$d/copy.md" 2>/dev/null \
                                && echo "cp             : OK" || echo "cp             : FAIL"
ls "$d"/*.md >/dev/null 2>&1     && echo "glob ls        : OK" || echo "glob ls        : FAIL"
grep -il '2001\.' "$d"/*.md >/dev/null 2>&1 \
                                && echo "grep -il       : OK" || echo "grep -il       : FAIL"
date +'%Y-%m-%dT%H:%M:%S%z' >/dev/null 2>&1 \
                                && echo "date +%z       : OK" || echo "date +%z       : FAIL"
rm -f "$d"/*.md 2>/dev/null && rm -rf "$d" 2>/dev/null \
                                && echo "rm -f / rm -rf : OK" || echo "rm             : FAIL"
echo ""
echo "Done. If uname/date errored or the commands are MISSING/FAIL,"
echo "Cowork's shell on this machine is NOT POSIX-style — report that."
