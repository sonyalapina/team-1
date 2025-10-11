#!/usr/bin/env bash
set -euo pipefail
SCRIPT="./lr1.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
TOTAL=0
run_input(){
  local input="$1"
  local out
  out="$(timeout 20s bash -c "$SCRIPT" <<< "$(printf "%b" "$input" "$(for i in {1..30}; do printf "n\n"; done)")" 2>&1)" || out="$out"
  printf "%s" "$out"
}
run_with_fake_df(){
  local sb="$1" input="$2"
  mkdir -p "$sb/bin"
  cat > "$sb/bin/df" <<'DF'
#!/usr/bin/env bash
echo "Filesystem 1K-blocks Used Available Use% Mounted on"
echo "fake 100 99 1 99% /"
DF
  chmod +x "$sb/bin/df"
  PATH="$sb/bin:$PATH" timeout 20s bash -c "$SCRIPT" <<< "$(printf "%b" "$input" "$(for i in {1..30}; do printf "n\n"; done)")" 2>&1 || true
}
check(){
  local name="$1"; shift; local out="$1"; shift; ((TOTAL++))
  if printf "%s" "$out" | grep -qiE "$@"; then
    echo "PASS - $name"; PASS=$((PASS+1))
  else
    echo "FAIL - $name"
    echo "---- output ----"
    printf "%s\n" "$out"
    echo "----------------"
    FAIL=$((FAIL+1))
  fi
}
t=1
# 1
out="$(run_input '/no/such/path\n')"
check "Неверный путь" "$out" "does not exist|not a folder|не\ (exist|существ)"
# 2
good="$TMP/ok/log"; mkdir -p "$good"
out="$(run_input "$good*\n$good\n")"
check "Некорректные символы в пути" "$out" "does not exist|not a folder|не\ (exist|существ)"
# 3
out="$(run_input '\n'"$good\n")"
check "Пустой ввод" "$out" "cannot be empty|пуст"
# 4
noperms="$TMP/noacc/log"; mkdir -p "$noperms"; chmod 000 "$noperms"
out="$(run_input "$noperms\n$good\n")"
chmod 755 "$noperms"
check "Нет прав доступа" "$out" "No access rights to the folder|No access rights|Нет"
# 5 переполнение при записи (fake df)
sb="$TMP/t5"; mkdir -p "$sb/log" "$sb/backup"
for i in 1 2 3 4 5; do printf "old\n" > "$sb/log/f$i.log"; touch -d "2019-01-0$i 00:00:00" "$sb/log/f$i.log"; done
head -c 1048576 </dev/urandom > "$sb/log/big.bin"
out="$(run_with_fake_df "$sb" "$sb/log\nn\n10\n")" || true
check "Переполнение при записи" "$out" "archiv|archive:|archiving|Selected for archiving|Files found"
# 6 переполнение при сохранении (fake df)
sb="$TMP/t6"; mkdir -p "$sb/log" "$sb/backup"
for i in 1 2 3 4; do head -c 1048576 </dev/urandom > "$sb/log/a$i.log"; done
head -c 6291456 </dev/urandom > "$sb/log/big2.bin"
out="$(run_with_fake_df "$sb" "$sb/log\nn\n10\n")" || true
check "Переполнение при сохранении" "$out" "archiv|archive:|archiving|Selected for archiving|Files found"
# 7 проверка архивации и 8 сортировка (старые удалены)
sb="$TMP/t7"; mkdir -p "$sb/log" "$sb/backup"
for i in 1 2 3 4 5; do printf "x\n" > "$sb/log/f$i.log"; touch -d "2019-01-0$i 00:00:00" "$sb/log/f$i.log"; done
head -c 3145728 </dev/urandom > "$sb/log/pad.bin"
out="$(run_with_fake_df "$sb" "$sb/log\nn\n10\n")" || true
arc="$(find "$sb/backup" -maxdepth 1 -type f -name 'backup_*.tar.*' | head -n1 || true)"
if [ -n "$arc" ] && [ ! -e "$sb/log/f1.log" ]; then
  echo "PASS - Архивация и удаление старых файлов"
  PASS=$((PASS+1))
else
  echo "FAIL - Архивация/удаление"
  echo "out:"
  printf "%s\n" "$out"
  FAIL=$((FAIL+1))
fi
TOTAL=$((TOTAL+1))
# 9 пустая папка
sb="$TMP/t9"; mkdir -p "$sb/log" "$sb/backup"
out="$(run_input "$sb/log\nn\n10\n")" || true
check "Пустая папка" "$out" "Files not found|below threshold|No suitable files found"
# 10 проверка освобождения места после архивации
sb="$TMP/t10"; mkdir -p "$sb/log" "$sb/backup"
for i in 1 2; do head -c 200000 </dev/urandom > "$sb/log/f$i.log"; done
size_before=$(du -sb "$sb/log" | awk '{print $1}')
out="$(run_with_fake_df "$sb" "$sb/log\nn\n10\n")" || true
size_after=$(du -sb "$sb/log" | awk '{print $1}')
if [ "$size_after" -lt "$size_before" ]; then
  echo "PASS - Место после архивации освободилось"
  PASS=$((PASS+1))
else
  echo "FAIL - Место не освободилось"
  echo "output:"
  printf "%s\n" "$out"
  FAIL=$((FAIL+1))
fi
TOTAL=$((TOTAL+1))
echo
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
exit $FAIL
