#!/bin/bash
SCRIPT="./lr1.sh"
TEST_DIR="$(pwd)/test_env"
LOG_DIR="$TEST_DIR/log"
BACKUP_DIR="$TEST_DIR/backup"
mkdir -p "$LOG_DIR" "$BACKUP_DIR"

run_test() {
    local description="$1"
    local input="$2"
    local condition="$3"

    echo "------------------------------------------------------------"
    echo "🔹 TEST: $description"
    echo "------------------------------------------------------------"

    echo -e "$input" | bash "$SCRIPT" > output.log 2>&1
    sleep 1

    if eval "$condition"; then
        echo "✅ PASS — $description"
    else
        echo "❌ FAIL — $description"
        echo "----- Script output -----"
        cat output.log
        echo "--------------------------"
    fi
    echo
    sleep 1
}

# 1️⃣ Проверка пустого пути
run_test "Проверка пустого пути" "\n\n" \
    "grep -q 'cannot be empty' output.log"

# 2️⃣ Проверка несуществующего пути
run_test "Несуществующая папка" "/fake/path\n\n" \
    "grep -q 'does not exist' output.log"

# 3️⃣ Проверка неправильной папки (не log)
run_test "Папка не log" "$TEST_DIR\n\n" \
    "grep -q 'is not a log folder' output.log"

# 4️⃣ Проверка правильной папки log
run_test "Правильная папка log" "$LOG_DIR\n10\nn\nn\nn\n" \
    "grep -q 'Folder found' output.log"

# 5️⃣ Проверка установки порога
run_test "Порог 50%" "$LOG_DIR\nn\n50\n" \
    "grep -q 'Threshold set to: 50%' output.log"

# 6️⃣ Проверка переполнения (создаём большие файлы)
echo "Создание тестовых файлов..."
for i in {1..5}; do dd if=/dev/zero of="$LOG_DIR/file_$i.log" bs=1M count=10 &>/dev/null; done

run_test "Переполнение и архивация" "$LOG_DIR\nn\n10\ny\n" \
    "grep -q 'archived' output.log"

# 7️⃣ Проверка удаления заархивированных файлов
run_test "Удаление заархивированных файлов" "$LOG_DIR\nn\n10\ny\n" \
    "[[ ! \$(ls $LOG_DIR) ]]"

# 8️⃣ Проверка повторной проверки после завершения
run_test "Повторная проверка (отказ)" "$LOG_DIR\nn\n10\nn\n" \
    "grep -q 'Завершение работы' output.log"

# 9️⃣ Проверка без ограничения размера
run_test "Пропуск создания ограничения" "$LOG_DIR\nn\n10\nn\n" \
    "grep -q 'Продолжение без ограничения' output.log"

# 🔟 Проверка невозможности монтирования при непустой папке
echo "test" > "$LOG_DIR/file_test.txt"
run_test "Монтирование при непустой папке" "$LOG_DIR\ny\n100\n" \
    "grep -q 'Папку .\\+ необходимо очистить' output.log"

echo "=========================================================="
echo "✅ Тестирование завершено. Проверяй вывод выше."
echo "=========================================================="
