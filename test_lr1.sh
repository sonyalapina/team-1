#!/usr/bin/env bash
set -euo pipefail

SCRIPT="./lr1.sh"
TMPROOT="$(mktemp -d -t lr1_ci_XXXX)"
BIN="$TMPROOT/bin"
TESTROOT="$TMPROOT/tests"
mkdir -p "$BIN" "$TESTROOT"
export PATH="$BIN:$PATH"
timeout_cmd() { timeout 25s bash -c "$1"; }

cat > "$BIN/fallocate" <<'F' ; chmod +x "$BIN/fallocate"
#!/usr/bin/env bash
size_arg="$1"
file="$2"
case "$size_arg" in
  *M) bytes=$(( ${size_arg%M} * 1024 * 1024 )) ;;
  *G) bytes=$(( ${size_arg%G} * 1024 * 1024 * 1024 )) ;;
  *) bytes=0 ;;
esac
head -c "$bytes" </dev/zero >"$file" 2>/dev/null || true
F

cat > "$BIN/mkfs.ext4" <<'F' ; chmod +x "$BIN/mkfs.ext4"
#!/usr/bin/env bash
touch "$1.format_marker" 2>/dev/null || true
F

cat > "$BIN/mount" <<'F' ; chmod +x "$BIN/mount"
#!/usr/bin/env bash
target="${@: -1}"
mkdir -p "$target"
touch "$target/.mock_mounted"
F

cat > "$BIN/mountpoint" <<'F' ; chmod +x "$BIN/mountpoint"
#!/usr/bin/env bash
if [ -e "$1/.mock_mounted" ]; then exit 0; else exit 1; fi
F

cat > "$BIN/sudo" <<'F' ; chmod +x "$BIN/sudo"
#!/usr/bin/env bash
"$@"
F

cat > "$BIN/df" <<'F' ; chmod +x "$BIN/df"
#!/usr/bin/env bash
echo "Filesystem 1K-blocks Used Available Use% Mounted on"
echo "mock 1000000 800000 200000 80% /"
F

run_and_capture(){
  local input="$1"
  local outf="$2"
  printf "%b" "$input" | timeout 25s bash "$SCRIPT" >"$outf" 2>&1 || true
}

check_grep(){
  local file="$1" patt="$2"
  grep -Eiq "$patt" "$file"
}

pass=0; fail=0; total=0

make_test_env(){
  local name="$1"
  local d="$TESTROOT/$name"
  rm -rf "$d"
  mkdir -p "$d/log" "$d/backup"
  echo "$d"
}

# 1. Неверный путь
total=$((total+1))
d=$(make_test_env "t1")
out="$TMPROOT/out1.txt"
run_and_capture "/no/such/path\n" "$out"
if check_grep "$out" "does not exist|not a folder|Folder '"; then
  echo "PASS 1"
  pass=$((pass+1))
else
  echo "FAIL 1"; cat "$out"; fail=$((fail+1))
fi

# 2. Некорректные символы
total=$((total+1))
d=$(make_test_env "t2")
good="$d/log"
out="$TMPROOT/out2.txt"
run_and_capture "$good*\n$good\n" "$out"
if check_grep "$out" "does not exist|not a folder"; then
  echo "PASS 2"; pass=$((pass+1))
else
  echo "FAIL 2"; cat "$out"; fail=$((fail+1))
fi

# 3. Пустой ввод
total=$((total+1))
d=$(make_test_env "t3")
out="$TMPROOT/out3.txt"
run_and_capture "\n$d/log\n" "$out"
if check_grep "$out" "cannot be empty|The path to the folder cannot be empty"; then
  echo "PASS 3"; pass=$((pass+1))
else
  echo "FAIL 3"; cat "$out"; fail=$((fail+1))
fi

# 4. Нет прав
total=$((total+1))
d=$(make_test_env "t4")
chmod 000 "$d/log"
out="$TMPROOT/out4.txt"
run_and_capture "$d/log\n" "$out"
chmod 755 "$d/log"
if check_grep "$out" "No access rights|No access rights to the folder"; then
  echo "PASS 4"; pass=$((pass+1))
else
  echo "FAIL 4"; cat "$out"; fail=$((fail+1))
fi

# 5. Переполнение при записи
total=$((total+1))
d=$(make_test_env "t5")
for i in {1..5}; do printf "old\n" >"$d/log/f$i.log"; touch -d "2019-01-0$i" "$d/log/f$i.log"; done
head -c 1048576 </dev/urandom >"$d/log/huge.bin"
out="$TMPROOT/out5.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
if check_grep "$out" "archive:|files were successfully archived|archiving"; then
  echo "PASS 5"; pass=$((pass+1))
else
  echo "FAIL 5"; cat "$out"; fail=$((fail+1))
fi

# 6. Переполнение при сохранении
total=$((total+1))
d=$(make_test_env "t6")
for i in 1 2 3 4; do head -c 1048576 </dev/urandom >"$d/log/a$i.log"; done
head -c 6291456 </dev/urandom >"$d/log/big2.bin"
out="$TMPROOT/out6.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
if check_grep "$out" "archive:|files were successfully archived|archiving"; then
  echo "PASS 6"; pass=$((pass+1))
else
  echo "FAIL 6"; cat "$out"; fail=$((fail+1))
fi

# 7. Проверка архивации
total=$((total+1))
d=$(make_test_env "t7")
for i in 1 2 3 4 5; do printf "x$i" >"$d/log/f$i.log"; touch -d "2019-01-0$i" "$d/log/f$i.log"; done
head -c 3145728 </dev/urandom >"$d/log/pad.bin"
out="$TMPROOT/out7.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
arc="$(ls -1 "$d/backup"/backup_* 2>/dev/null | head -n1 || true)"
if [ -n "$arc" ] && tar -tf "$arc" >/dev/null 2>&1; then
  tar -tf "$arc" | grep -qx "log/f1.log" && echo "PASS 7" && pass=$((pass+1)) || (echo "FAIL 7 - wrong files"; tar -tf "$arc"; fail=$((fail+1)))
else
  echo "FAIL 7 - no archive"; cat "$out"; fail=$((fail+1))
fi

# 8. Проверка сортировки
total=$((total+1))
d=$(make_test_env "t8")
for i in 1 2 3 4 5; do printf "x$i" >"$d/log/f$i.log"; touch -d "2019-01-0$i" "$d/log/f$i.log"; done
head -c 3145728 </dev/urandom >"$d/log/pad2.bin"
out="$TMPROOT/out8.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
arc="$(ls -1 "$d/backup"/backup_* 2>/dev/null | head -n1 || true)"
if [ -n "$arc" ]; then
  first=$(tar -tf "$arc" | head -n 1)
  if echo "$first" | grep -q "f1.log"; then
    echo "PASS 8"; pass=$((pass+1))
  else
    echo "FAIL 8"; tar -tf "$arc"; fail=$((fail+1))
  fi
else
  echo "FAIL 8 - no archive"; cat "$out"; fail=$((fail+1))
fi

# 9. Проверка освобождения места
total=$((total+1))
d=$(make_test_env "t9")
for i in 1 2 3 4 5; do head -c 200000 </dev/urandom >"$d/log/f$i.log"; done
size_before=$(du -sb "$d/log" | awk '{print $1}')
out="$TMPROOT/out9.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
size_after=$(du -sb "$d/log" | awk '{print $1}')
if [ "$size_after" -lt "$size_before" ]; then
  echo "PASS 9"; pass=$((pass+1))
else
  echo "FAIL 9"; cat "$out"; fail=$((fail+1))
fi

# 10a. Пустая папка
total=$((total+1))
d=$(make_test_env "t10a")
out="$TMPROOT/out10a.txt"
run_and_capture "$d/log\nn\n10\nn\n" "$out"
if check_grep "$out" "Files not found|No suitable files found|below threshold|Внимание: Эта папка не имеет жестк|Продолжение без ограничения"; then
  echo "PASS 10a"; pass=$((pass+1))
else
  echo "FAIL 10a"; cat "$out"; fail=$((fail+1))
fi

# 10b. Запрошено больше файлов, чем есть
total=$((total+1))
d=$(make_test_env "t10b")
printf "a\n" >"$d/log/one.log"
out="$TMPROOT/out10b.txt"
run_and_capture "$d/log\nn\n1\ny\n" "$out"
if check_grep "$out" "archive:|files were successfully archived|archiving"; then
  echo "PASS 10b"; pass=$((pass+1))
else
  echo "FAIL 10b"; cat "$out"; fail=$((fail+1))
fi

echo
echo "=== RESULTS: passed=$pass failed=$fail total=$((pass+fail)) ==="
rm -rf "$TMPROOT"
exit $((fail>0))
