#!/usr/bin/env bash
set -u

SRC_ORIG="./not_to_use/archiver.sh"

Pass=0; Fail=0; Total=0
ROOT="$(mktemp -d -t archtests-XXXX)"
trap 'rm -rf "$ROOT"' EXIT

ok(){ echo "PASS - $1"; ((Pass++)); }
fail(){ echo "FAIL - $1"; ((Fail++)); }
mkbox(){ local n="$1"; local SB="$ROOT/$n"; mkdir -p "$SB/log" "$SB/backup"; echo "$SB"; }
arc(){ find "$1" -maxdepth 1 -type f -name 'backup_*.tar.*' | head -n1; }

make_copy_with_vars(){
  local src="$1" out="$2" L="$3" B="$4" M="$5"
  cp "$src" "$out"
  sed -i -E "s|^SOURCE_DIR=.*|SOURCE_DIR=\"$L\"|; s|^FILES_TO_ARCHIVE=.*|FILES_TO_ARCHIVE=$M|; s|^BACKUP_DIR=.*|BACKUP_DIR=\"$B\"|" "$out"
  chmod +x "$out"
}

t_more_than_exist(){
  ((Total++))
  local SB; SB=$(mkbox a1); local L="$SB/log" B="$SB/backup" S="$SB/archiver_copy.sh"
  echo d > "$L/f1.log"; touch -d "2020-01-01 00:00:00" "$L/f1.log"
  echo d > "$L/f2.log"; touch -d "2020-01-02 00:00:00" "$L/f2.log"
  make_copy_with_vars "$SRC_ORIG" "$S" "$L" "$B" 10
  bash "$S" >/dev/null 2>&1 || { fail "Скрипт упал при M>кол-ва"; return; }
  local T; T="$(arc "$B")"
  [[ -n "$T" ]] || { fail "Архив не создан при M>кол-ва"; return; }
  local list; list="$(tar -tf "$T" | sed 's#.*/##' | sort)"
  grep -qx "f1.log" <<<"$list" && grep -qx "f2.log" <<<"$list" && ok "В архиве все файлы (M>кол-ва)" || fail "Содержимое архива неверно"
}

t_sorting_oldest_first(){
  ((Total++))
  local SB; SB=$(mkbox a2); local L="$SB/log" B="$SB/backup" S="$SB/archiver_copy.sh"
  for i in 1 2 3 4 5; do echo x > "$L/f$i.log"; touch -d "2019-01-0$i 00:00:00" "$L/f$i.log"; done
  make_copy_with_vars "$SRC_ORIG" "$S" "$L" "$B" 2
  bash "$S" >/dev/null 2>&1 || { fail "Скрипт упал"; return; }
  local T; T="$(arc "$B")"
  [[ -n "$T" ]] || { fail "Архив не создан"; return; }
  local list; list="$(tar -tf "$T" | sed 's#.*/##' | sort)"
  if grep -qx "f1.log" <<<"$list" && grep -qx "f2.log" <<<"$list"; then ok "Самые старые попали в архив"
  else fail "Сортировка неверная"; fi
}

echo "=== Archiver tests (not_to_use/archiver.sh) ==="
t_more_than_exist
t_sorting_oldest_first
echo
echo "=== Results: $Pass passed, $Fail failed, $Total total ==="
[[ $Fail -eq 0 ]]
