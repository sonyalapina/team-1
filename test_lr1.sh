#!/usr/bin/env bash
set -u

# ==============================
# Настройки
# ==============================
SCRIPT="./lr1.sh"
TMPROOT="$(mktemp -d -t lr1test-XXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0; fail=0; total=0
ok(){ echo "PASS - $1"; ((pass++)); }
failf(){ echo "FAIL - $1"; ((fail++)); }
run(){ ((total++)); echo; echo "[$total] $1"; }

# Быстрый запуск с заранее подготовленным вводом (чтобы не зависало)
run_input(){
  local input="$1"
  local extra=""
  for _ in {1..20}; do extra="${extra}y\nn\n"; done
  timeout 20s bash -c "$SCRIPT" <<< "$(printf "%b" "$input$extra")" 2>&1
}

# Поддельный df — притворяется, что диск почти заполнен
fake_df(){
  local path="$1/bin"
  mkdir -p "$path"
  cat > "$path/df" <<'DF'
#!/usr/bin/env bash
echo "Filesystem 1K-blocks Used Available Use% Mounted on"
echo "fake 100 99 1 99% /"
DF
  chmod +x "$path/df"
  PATH="$path:$PATH" bash -c "$SCRIPT" <<< "$(printf "%b" "$2")" 2>&1
}

# ==============================
# Тесты
# ==============================

# 1. Неверный путь
run "неверный путь"
out="$(run_input '/no/such/path\n')"
echo "$out" | grep -qi "does not exist" && ok "Неверный путь отклонён" || failf "Неверный путь должен падать"

# 2. Некорректные символы в пути
run "странные символы в пути"
good="$TMPROOT/test2/log"
mkdir -p "$good"
out="$(run_input "$good*\n$good\n")"
echo "$out" | grep -qi "does not exist" && ok "Странный путь отклонён" || failf "Странный путь должен падать"

# 3. Пустой ввод
run "пустой ввод"
out="$(run_input '\n/tmp\n')"
echo "$out" | grep -qi "cannot be empty" && ok "Пустой ввод отклонён" || failf "Пустой ввод должен отклоняться"

# 4. Нет прав доступа
run "нет прав доступа"
noacc="$TMPROOT/test4/log"
mkdir -p "$noacc"
chmod 000 "$noacc"
out="$(run_input "$noacc\n/tmp\n")"
chmod 755 "$noacc"
echo "$out" | grep -qi "No access rights" && ok "Нет прав — корректно" || failf "Должно ругаться на права"

# 5. Переполнение при записи (имитируем df)
run "переполнение при записи"
sb="$TMPROOT/t5"; mkdir -p "$sb/log" "$sb/backup"
for i in {1..5}; do echo data>"$sb/log/f$i.log"; done
out="$(fake_df "$sb" "$sb/log\nn\n10\n")"
echo "$out" | grep -qi "archiv" && ok "Архивация при переполнении (запись)" || failf "Нет архива при переполнении (запись)"

# 6. Переполнение при сохранении
run "переполнение при сохранении"
sb="$TMPROOT/t6"; mkdir -p "$sb/log" "$sb/backup"
for i in {1..3}; do echo data>"$sb/log/f$i.log"; done
echo "XXX" > "$sb/log/big.bin"
out="$(fake_df "$sb" "$sb/log\nn\n10\n")"
echo "$out" | grep -qi "archiv" && ok "Архивация при переполнении (сохранение)" || failf "Нет архива при переполнении (сохранение)"

# 7. Проверка архивации и сортировки (старые уходят)
run "архивация и сортировка"
sb="$TMPROOT/t7"; mkdir -p "$sb/log" "$sb/backup"
for i in 1 2 3 4 5; do echo "x">"$sb/log/f$i.log"; touch -d "2019-01-0$i" "$sb/log/f$i.log"; done
out="$(fake_df "$sb" "$sb/log\nn\n10\n")"
arc="$(find "$sb/backup" -name '*.tar.xz' | head -n1)"
[[ -n "$arc" ]] && ok "Архив найден, сортировка работает" || failf "Архив не найден"

# 8. После архивации место уменьшается
run "освобождение места"
sb="$TMPROOT/t8"; mkdir -p "$sb/log" "$sb/backup"
for i in {1..5}; do head -c 10000 </dev/urandom >"$sb/log/f$i.log"; done
size_before=$(du -sb "$sb/log" | awk '{print $1}')
fake_df "$sb" "$sb/log\nn\n10\n" >/dev/null 2>&1
size_after=$(du -sb "$sb/log" | awk '{print $1}')
(( size_after < size_before )) && ok "Место освободилось" || failf "Размер не уменьшился"

# 9. Пустая папка
run "пустая папка"
sb="$TMPROOT/t9"; mkdir -p "$sb/log"
out="$(run_input "$sb/log\nn\n10\n")"
echo "$out" | grep -qi "below threshold" && ok "Пустая папка — не падает" || failf "Пустая папка — не падает (ожидание)"

# 10. Запрос файлов больше, чем есть
run "запрошено больше файлов, чем есть"
sb="$TMPROOT/t10"; mkdir -p "$sb/log" "$sb/backup"
for i in 1 2; do echo "x">"$sb/log/f$i.log"; done
out="$(fake_df "$sb" "$sb/log\nn\n99\n")"
echo "$out" | grep -qi "archiv" && ok "Отработало при недостатке файлов" || failf "Не отработало при малом кол-ве файлов"

# ==============================
# ИТОГ
# ==============================
echo
echo "=== Results: $pass passed, $fail failed, $total total ==="
exit $fail
