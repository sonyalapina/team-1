#!/usr/bin/env bash
set -euo pipefail

# Improved test harness for lr1.sh
# Now tests assert real side-effects (archive files, sizes, mounts, etc.)

SCRIPT="./lr1.sh"
TMPROOT="$(mktemp -d -t lr1_ci_XXXX)"
export TMPROOT
BIN="$TMPROOT/bin"
TESTROOT="$TMPROOT/tests"
mkdir -p "$BIN" "$TESTROOT"
export PATH="$BIN:$PATH"

# timeout wrapper
timeout_cmd() { timeout 25s bash -c "$1"; }

# --- MOCK BINARIES ---
cat > "$BIN/fallocate" <<'F' ; chmod +x "$BIN/fallocate"
#!/usr/bin/env bash
# Simple mock: create a file of requested size (supports N M/G suffix)
size="$1"; file="$2"
case "$size" in
  *M) bytes=$(( ${size%M} * 1024 * 1024 )) ;;
  *G) bytes=$(( ${size%G} * 1024 * 1024 * 1024 )) ;;
  *) bytes=0 ;;
esac
head -c $bytes </dev/urandom >"$file" 2>/dev/null || :
F

cat > "$BIN/mkfs.ext4" <<'F' ; chmod +x "$BIN/mkfs.ext4"
#!/usr/bin/env bash
# mark that we formatted the image
touch "$1.format_marker" 2>/dev/null || true
F

cat > "$BIN/mount" <<'F' ; chmod +x "$BIN/mount"
#!/usr/bin/env bash
# last arg is target
target="${@: -1}"
mkdir -p "$target"
# create a marker file to indicate mount
touch "$target/.mock_mounted"
F

cat > "$BIN/mountpoint" <<'F' ; chmod +x "$BIN/mountpoint"
#!/usr/bin/env bash
# return 0 if .mock_mounted exists
if [ -e "$1/.mock_mounted" ]; then exit 0; else exit 1; fi
F

cat > "$BIN/sudo" <<'F' ; chmod +x "$BIN/sudo"
#!/usr/bin/env bash
# trivial sudo passthrough for tests
exec "${@}"
F

# Mock df: when asked about our test dirs (contain TMPROOT), return deterministic values
cat > "$BIN/df" <<'F' ; chmod +x "$BIN/df"
#!/usr/bin/env bash
path="${1:-/}"
if [[ "$path" == *${TMPROOT##*/}* || "$path" == *ci_* ]]; then
  echo "Filesystem 1K-blocks Used Available Use% Mounted on"
  # total 1G in KB, used 800M
  echo "mock 1000000 800000 200000 80% /"
else
  /bin/df "$@"
fi
F

# --- HELPERS ---
run_and_capture(){
  local input="$1"
  local outf="$2"
  printf "%b" "$input" | timeout 20s bash "$SCRIPT" >"$outf" 2>&1 || true
}

fail() { echo "FAIL: $*"; exit 1; }

# check that an archive exists in backup and contains expected filenames (exact match)
assert_archive_contains_exact(){
  local backup_dir="$1" expected_files=(${2})
  arc="$(ls -1 "$backup_dir"/backup_* 2>/dev/null | head -n1 || true)"
  [ -n "$arc" ] || fail "Expected archive in $backup_dir but none found"
  tar -tf "$arc" >/dev/null 2>&1 || fail "Archive $arc is not a valid tar"
  # extract names and compare
  mapfile -t got < <(tar -tf "$arc" | sed 's#.*/##')
  for ef in "${expected_files[@]}"; do
    printf '%s
' "${got[@]}" | grep -xq -- "$ef" || fail "Archive $arc missing expected file $ef"
  done
}

assert_size_decreased(){
  local dir="$1" before="$2"
  after=$(du -sb "$dir" | awk '{print $1}')
  [ "$after" -lt "$before" ] || fail "Expected size of $dir to decrease (before=$before after=$after)"
}

assert_files_removed(){
  for f in "$@"; do
    [ ! -e "$f" ] || fail "Expected $f to be removed but it still exists"
  done
}

# create test environment helper
make_test_env(){
  local name="$1"
  local d="$TESTROOT/$name"
  rm -rf "$d"
  mkdir -p "$d/log" "$d/backup"
  echo "$d"
}

# --- TESTS START ---

# 1. Invalid path: program should prompt again and not crash
d=$(make_test_env t1)
out="$TMPROOT/out1.txt"
run_and_capture "/no/such/path
$d/log

10
n
" "$out"
grep -qi "does not exist" "$out" || fail "Test1: expected 'does not exist' message"

# 2. Weird characters in path: provide bad then good
d=$(make_test_env t2)
out="$TMPROOT/out2.txt"
run_and_capture "foo*bar
$d/log

10
n
" "$out"
grep -qi "does not exist|not a folder" "$out" || fail "Test2: expected invalid path message"

# 3. Empty input handling
d=$(make_test_env t3)
out="$TMPROOT/out3.txt"
run_and_capture "
$d/log

10
n
" "$out"
grep -qi "cannot be empty" "$out" || fail "Test3: expected 'cannot be empty' prompt"

# 4. No permissions
d=$(make_test_env t4)
chmod 000 "$d/log"
out="$TMPROOT/out4.txt"
run_and_capture "$d/log
$d/log

10
n
" "$out"
chmod 755 "$d/log"
grep -qi "No access rights" "$out" || fail "Test4: expected 'No access rights'"

# 5. Archiving when over threshold: ensure archive created and files removed, size decreased
d=$(make_test_env t5)
# create old small logs and a large file to push over threshold
for i in {1..5}; do printf "old
" >"$d/log/f$i.log"; touch -d "2019-01-0$i" "$d/log/f$i.log"; done
head -c 3m </dev/urandom >"$d/log/huge.bin"
size_before=$(du -sb "$d/log" | awk '{print $1}')
out="$TMPROOT/out5.txt"
# inputs: path, don't setup size limit (n), threshold 1% (very small to force archiving), agree to create image? irrelevant, but keep
run_and_capture "$d/log
n
1
y
" "$out"
# assert an archive exists and contains at least f1.log (oldest)
assert_archive_contains_exact "$d/backup" "f1.log"
# ensure at least one file removed
[ $(ls -1 "$d/log" | wc -l) -lt 6 ] || fail "Test5: expected some files removed from $d/log"
size_after=$(du -sb "$d/log" | awk '{print $1}')
[ "$size_after" -lt "$size_before" ] || fail "Test5: expected directory size to decrease"

# 6. Archiving multiple large files: ensure archive exists and is valid
d=$(make_test_env t6)
for i in 1 2 3 4; do head -c 1048576 </dev/urandom >"$d/log/a$i.log"; done
head -c 6m </dev/urandom >"$d/log/big2.bin"
out="$TMPROOT/out6.txt"
run_and_capture "$d/log
n
1
y
" "$out"
arc="$(ls -1 "$d/backup"/backup_* 2>/dev/null | head -n1 || true)"
[ -n "$arc" ] || fail "Test6: expected an archive"
tar -tf "$arc" >/dev/null 2>&1 || fail "Test6: archive invalid"

# 7. Archive contains specifically the oldest file(s)
d=$(make_test_env t7)
for i in 1 2 3 4 5; do printf "x$i" >"$d/log/f$i.log"; touch -d "2019-01-0$i" "$d/log/f$i.log"; done
head -c 3m </dev/urandom >"$d/log/pad.bin"
out="$TMPROOT/out7.txt"
run_and_capture "$d/log
n
1
y
" "$out"
# check archive contents for f1.log
assert_archive_contains_exact "$d/backup" "f1.log"

# 8. Sorting (oldest first): we'll create ordered timestamps and check first archived file is f1.log
d=$(make_test_env t8)
for i in 1 2 3 4 5; do printf "x$i" >"$d/log/f$i.log"; touch -d "2019-01-0$i" "$d/log/f$i.log"; done
head -c 3m </dev/urandom >"$d/log/pad2.bin"
out="$TMPROOT/out8.txt"
run_and_capture "$d/log
n
1
y
" "$out"
arc="$(ls -1 "$d/backup"/backup_* 2>/dev/null | head -n1 || true)"
[ -n "$arc" ] || fail "Test8: expected archive"
firsts=$(tar -tf "$arc" | sed 's#.*/##' | head -n 1)
[ "$firsts" = "f1.log" ] || fail "Test8: expected first archived file to be f1.log but got $firsts"

# 9. Size decreased assertion
d=$(make_test_env t9)
for i in 1 2 3 4 5; do head -c 200000 </dev/urandom >"$d/log/f$i.log"; done
size_before=$(du -sb "$d/log" | awk '{print $1}')
out="$TMPROOT/out9.txt"
run_and_capture "$d/log
n
1
y
" "$out"
size_after=$(du -sb "$d/log" | awk '{print $1}')
[ "$size_after" -lt "$size_before" ] || fail "Test9: expected size to decrease"

# 10a. Empty folder: no archive created, script should report below threshold or "No suitable files"
d=$(make_test_env t10)
out="$TMPROOT/out10a.txt"
run_and_capture "$d/log
n
10
n
" "$out"
# ensure no archive created
[ -z "$(ls -1 "$d/backup"/backup_* 2>/dev/null || true)" ] || fail "Test10a: expected no archive created for empty log folder"
# check output message for below threshold
grep -Ei "below threshold|No suitable files found|Files not found" "$out" >/dev/null || fail "Test10a: expected message about no files or below threshold"

# 10b. One small file should be archived when threshold is tiny
d=$(make_test_env t10b)
printf "a
" >"$d/log/one.log"
size_before=$(du -sb "$d/log" | awk '{print $1}')
out="$TMPROOT/out10b.txt"
run_and_capture "$d/log
n
1
y
" "$out"
# ensure archive created and contains one.log
assert_archive_contains_exact "$d/backup" "one.log"

# --- CLEANUP AND REPORT ---
echo "All tests passed. Cleaning up..."
rm -rf "$TMPROOT"
exit 0
