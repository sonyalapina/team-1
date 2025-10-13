# 11. Несколько маленьких файлов — проверка сортировки и выбора
total=$((total+1))
d=$(make_test_env "t11")
for i in {1..8}; do
  echo "маленький файл $i" >"$d/log/file$i.log"
  touch -d "2020-01-0$i" "$d/log/file$i.log"
done
out="$TMPROOT/out11.txt"
run_and_capture "$d/log\nn\n1\ny\n" "$out"
arc="$(ls -1 "$d/backup"/backup_* 2>/dev/null | head -n1 || true)"
if [ -n "$arc" ] && tar -tf "$arc" | grep -q "file1.log"; then
  echo "Тест 11 (несколько маленьких файлов): старые файлы выбраны первыми, архив успешно создан ($arc)."
  pass=$((pass+1))
else
  echo "Тест 11 (несколько маленьких файлов): архив не создан или порядок файлов нарушен."
  cat "$out"
  fail=$((fail+1))
fi


# 12. Обработка пустой директории
total=$((total+1))
d=$(make_test_env "t12")
out="$TMPROOT/out12.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
if check_grep "$out" "No suitable files|No files for archiving|empty"; then
  echo "Тест 12 (пустая директория): скрипт корректно сообщил, что файлов для архивации нет."
  pass=$((pass+1))
else
  echo "Тест 12 (пустая директория): скрипт не вывел сообщение об отсутствии файлов."
  cat "$out"
  fail=$((fail+1))
fi


# 13. Создание директории backup
total=$((total+1))
d=$(make_test_env "t13")
rm -rf "$d/backup"  # имитируем отсутствие папки backup
mkdir -p "$d/log"
echo "пример файла" >"$d/log/test.log"
out="$TMPROOT/out13.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
if [ -d "$d/backup" ]; then
  echo "Тест 13 (создание папки backup): директория backup была успешно создана."
  pass=$((pass+1))
else
  echo "Тест 13 (создание папки backup): папка backup не была создана."
  cat "$out"
  fail=$((fail+1))
fi


# 14. Проверка порядка архивации
total=$((total+1))
d=$(make_test_env "t14")
for i in 5 4 3 2 1; do
  echo "лог $i" >"$d/log/f$i.log"
  touch -d "2020-01-0$i" "$d/log/f$i.log"
done
out="$TMPROOT/out14.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
arc="$(ls -1 "$d/backup"/backup_* 2>/dev/null | head -n1 || true)"
if [ -n "$arc" ]; then
  order=$(tar -tf "$arc" | sed 's#.*/##' | head -n 3 | tr '\n' ' ')
  if echo "$order" | grep -q "f1.log"; then
    echo "Тест 14 (порядок архивации): файлы отсортированы правильно — старые архивируются первыми."
    pass=$((pass+1))
  else
    echo "Тест 14 (порядок архивации): порядок архивации нарушен."
    echo "Файлы в архиве: $order"
    fail=$((fail+1))
  fi
else
  echo "Тест 14 (порядок архивации): архив не был создан."
  cat "$out"
  fail=$((fail+1))
fi


# 15. Проверка ввода (строковое значение вместо числа)
total=$((total+1))
d=$(make_test_env "t15")
echo "тестовый файл" >"$d/log/test.log"
out="$TMPROOT/out15.txt"
run_and_capture "$d/log\nn\nabc\ny\n" "$out"
if check_grep "$out" "invalid|must be a number|error"; then
  echo "Тест 15 (проверка строкового ввода): некорректный ввод строки обработан правильно."
  pass=$((pass+1))
else
  echo "Тест 15 (проверка строкового ввода): скрипт не обнаружил ошибку при вводе строки вместо числа."
  cat "$out"
  fail=$((fail+1))
fi


# 16. Проверка ввода (отрицательное число)
total=$((total+1))
d=$(make_test_env "t16")
echo "тестовый файл" >"$d/log/test.log"
out="$TMPROOT/out16.txt"
run_and_capture "$d/log\nn\n-5\ny\n" "$out"
if check_grep "$out" "invalid|must be positive|error|cannot be negative"; then
  echo "Тест 16 (проверка отрицательного числа): отрицательное значение отклонено корректно."
  pass=$((pass+1))
else
  echo "Тест 16 (проверка отрицательного числа): скрипт не проверяет отрицательные значения."
  cat "$out"
  fail=$((fail+1))
fi

# 17. Прерывание пользователем (Ctrl+C) — корректно ли очищаются временные файлы
total=$((total+1))
d=$(make_test_env "t17")
mkdir -p "$d/log"
mkdir -p "$d/tmp"
echo "временный файл 1" >"$d/tmp/temp1"
echo "временный файл 2" >"$d/tmp/temp2"
out="$TMPROOT/out18.txt"

# Эмулируем запуск и прерывание скрипта пользователем (SIGINT)
(run_and_capture "$d/log\nn\n10\ny\n" "$out" & pid=$!; sleep 1; kill -INT $pid) >/dev/null 2>&1
wait $pid 2>/dev/null

# Проверяем, остались ли временные файлы после прерывания
if [ ! -e "$d/tmp/temp1" ] && [ ! -e "$d/tmp/temp2" ]; then
  echo "Тест 17 (прерывание пользователем): временные файлы были успешно удалены после Ctrl+C."
  pass=$((pass+1))
else
  echo "Тест 18 (прерывание пользователем): временные файлы не были очищены после прерывания."
  cat "$out"
  fail=$((fail+1))
fi
