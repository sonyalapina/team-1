#!/usr/bin/env bash
set -u

SCRIPT_PATH="./lr1.sh"
THRESHOLD="10"

Pass=0; Fail=0; Total=0
ROOT="$(mktemp -d -t lr1tests-XXXX)"
trap 'rm -rf "$ROOT"' EXIT

ok(){ echo "PASS - $1"; ((Pass++)); }
fail(){ echo "FAIL - $1"; ((Fail++)); }
mkbox(){ local n="$1"; local SB="$ROOT/$n"; mkdir -p "$SB/log" "$SB/backup"; echo "$SB"; }
bytes(){ head -c "$1" /dev/urandom > "$2"; }
size(){ du -sb "$1" 2>/dev/null | awk '{print $1}'; }
find_arc(){ find "$1" -maxdepth 1 -type f \( -name '*.tar.xz' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.zip' \) | head -n1; }

run_inputs(){ local inp="$1"; bash -c "$SCRIPT_PATH" <<< "$inp"; }

with_fake_df_run(){
  local sb="$1" inp="$2"
  mkdir -p "$sb/bin"
  cat > "$sb/bin/df" <<'DF'
#!/usr/bin/env bash
printf "Filesystem 1K-blocks Used Available Use%% Mounted on\nmock 100 1 99 1%% /\n"
DF
  chmod +x "$sb/bin/df"
  PATH="$sb/bin:$PATH" bash -c "$SCRIPT_PATH" <<< "$inp"
}

t_bad_path(){
  ((Total++))
  local SB; SB=$(mkbox t1); local L="$SB/log"
  local out; out="$(run_inputs "/no/such\n$L\nn\n$THRESHOLD\n")" || true
  echo "$out" | grep -qiE "does not exist|not a folder|не сущ" && ok "Неверный путь отклонён" || fail "Неверный путь должен падать"
}

t_bad_chars(){
  ((Total++))
  local SB; SB=$(mkbox t2); local L="$SB/log"
  local out; out="$(run_inputs "$L*\n$L\nn\n$THRESHOLD\n")" || true
  echo "$out" | grep -qiE "does not exist|not a folder|не сущ" && ok "Странный путь отклонён" || fail "Странный путь должен падать"
}

t_empty_path(){
  ((Total++))
  local SB; SB=$(mkbox t3); local L="$SB/log"
  local out; out="$(run_inputs "\n$L\nn\n$THRESHOLD\n")" || true
  echo "$out" | grep -qiE "cannot be empty|пуст" && ok "Пустой путь отклонён" || fail "Пустой путь должен отклоняться"
}

t_no_perms(){
  ((Total++))
  local SB; SB=$(mkbox t4); local L="$SB/log" L2="$SB/log2"; mkdir -p "$L2"
  chmod 000 "$L"
  local out; out="$(run_inputs "$L\n$L2\nn\n$THRESHOLD\n")" || true
  chmod 755 "$L"
  echo "$out" | grep -qiE "No access rights|Нет прав" && ok "Нет прав — корректно" || fail "Должно ругаться на права"
}

t_overflow_on_write(){
  ((Total++))
  local SB; SB=$(mkbox t5); local L="$SB/log" B="$SB/backup"
  for i in 1 2 3 4 5; do echo f>"$L/f$i.log"; touch -d "2019-01-0$i 00:00:00" "$L/f$i.log"; done
  bytes $((5*1024*1024)) "$L/big.bin"
  with_fake_df_run "$SB" "$L\nn\n$THRESHOLD\n" >/dev/null 2>&1 || true
  local T; T="$(find_arc "$B")"
  [[ -n "$T" ]] && ok "Архив есть при переполнении (запись)" || fail "Нет архива при переполнении (запись)"
}

t_overflow_on_save(){
  ((Total++))
  local SB; SB=$(mkbox t6); local L="$SB/log" B="$SB/backup"
  for i in 1 2 3 4; do bytes $((1*1024*1024)) "$L/a$i.log"; done
  bytes $((6*1024*1024)) "$L/new_save.bin"
  with_fake_df_run "$SB" "$L\nn\n$THRESHOLD\n" >/dev/null 2>&1 || true
  local T; T="$(find_arc "$B")"
  [[ -n "$T" ]] && ok "Архив есть при переполнении (сохранение)" || fail "Нет архива при переполнении (сохранение)"
}

t_archive_and_sort(){
  ((Total++))
  local SB; SB=$(mkbox t7); local L="$SB/log" B="$SB/backup"
  for i in 1 2 3 4 5; do echo x>"$L/f$i.log"; touch -d "2019-01-0$i 00:00:00" "$L/f$i.log"; done
  bytes $((3*1024*1024)) "$L/pad.bin"
  with_fake_df_run "$SB" "$L\nn\n$THRESHOLD\n" >/dev/null 2>&1 || true
  local T; T="$(find_arc "$B")"
  if [[ -n "$T" && ! -e "$L/f1.log" && ! -e "$L/f2.log" ]]; then ok "Архив есть; самые старые удалены"
  else fail "Нет архива или старые файлы не удалены"; fi
}

t_space_freed(){
  ((Total++))
  local SB; SB=$(mkbox t8); local L="$SB/log" B="$SB/backup"
  for i in {1..5}; do bytes $((2*1024*1024)) "$L/s$i.log"; touch -d "2018-01-0${i} 00:00:00" "$L/s$i.log"; done
  local before; before=$(size "$L")
  with_fake_df_run "$SB" "$L\nn\n$THRESHOLD\n" >/dev/null 2>&1 || true
  local after; after=$(size "$L")
  (( after < before )) && ok "Размер уменьшился после архивации" || fail "Размер не уменьшился"
}

t_empty_dir(){
  ((Total++))
  local SB; SB=$(mkbox t9); local L="$SB/log"
  run_inputs "$L\nn\n$THRESHOLD\n" >/dev/null 2>&1 && ok "Пустая папка — не падает" || fail "Пустая папка — упал"
}

echo "=== LR1 tests (lr1.sh) ==="
t_bad_path
t_bad_chars
t_empty_path
t_no_perms
t_overflow_on_write
t_overflow_on_save
t_archive_and_sort
t_space_freed
t_empty_dir
echo
echo "=== Results: $Pass passed, $Fail failed, $Total total ==="
[[ $Fail -eq 0 ]]
