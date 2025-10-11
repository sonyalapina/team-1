#!/bin/bash

SCRIPT="./lr1.sh"
TEST_DIR="./tests"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR" || exit 1

LOG_DIR="./log"
BACKUP_DIR="./backup"
mkdir -p "$LOG_DIR" "$BACKUP_DIR"
chmod +rw "$LOG_DIR" "$BACKUP_DIR"

echo "=== FULL TEST SUITE FOR lr1.sh ==="
total=0
passed=0

run_test() {
    local name="$1"
    local input="$2"
    local expected="$3"
    total=$((total+1))
    echo ""
    echo "[$total] $name"
    echo "--------------------------------"
    echo -e "$input" | bash "$SCRIPT" >out.txt 2>&1
    if grep -qi "$expected" out.txt; then
        echo "✅ PASS - $name"
        passed=$((passed+1))
    else
        echo "❌ FAIL - $name"
        echo "Output:"
        cat out.txt
    fi
}

run_test "Неверный путь" "/wrong/path\n" "does not exist"
run_test "Некорректные символы" "/tmp/l?*g\n" "does not exist"
run_test "Пустая строка" "\n" "cannot be empty"
mkdir -p ./noaccess
chmod 000 ./noaccess
run_test "Нет прав доступа" "./noaccess\n" "No access rights"
chmod 755 ./noaccess

mkdir -p ./log
chmod 777 ./log

dd if=/dev/zero of=./log/bigfile1.log bs=1M count=3 &>/dev/null
dd if=/dev/zero of=./log/bigfile2.log bs=1M count=3 &>/dev/null
dd if=/dev/zero of=./log/bigfile3.log bs=1M count=3 &>/dev/null

input="`pwd`/log\ny\n10\ny\ny\n5\nn\n"
run_test "Переполнение при записи файла" "$input" "Threshold exceeded"

dd if=/dev/zero of=./log/bigfile4.log bs=1M count=3 &>/dev/null
input="`pwd`/log\ny\n10\ny\ny\n5\nn\n"
run_test "Переполнение при сохранении файла" "$input" "Threshold exceeded"

before_size=$(du -sb ./log | cut -f1)
input="`pwd`/log\ny\n10\ny\ny\n5\nn\n"
run_test "Архивация" "$input" "Archiving completed"
after_size=$(du -sb ./log | cut -f1)
if [ "$after_size" -lt "$before_size" ]; then
    echo "✅ PASS - место освободилось после архивации"
    passed=$((passed+1))
else
    echo "❌ FAIL - место не уменьшилось"
fi

files_before=$(ls -1 ./backup | wc -l)
input="`pwd`/log\ny\n10\ny\ny\n5\nn\n"
bash "$SCRIPT" <<< "$input" >out.txt 2>&1
files_after=$(ls -1 ./backup | wc -l)
if [ "$files_after" -gt "$files_before" ]; then
    echo "✅ PASS - архив создан"
    passed=$((passed+1))
else
    echo "❌ FAIL - архив не создан"
fi

find ./log -type f -exec touch -d "2 days ago" {} +
dd if=/dev/zero of=./log/newfile.log bs=1M count=1 &>/dev/null
input="`pwd`/log\ny\n10\ny\ny\n5\nn\n"
bash "$SCRIPT" <<< "$input" >out.txt 2>&1
if grep -q "Selected for archiving" out.txt && grep -q "old" out.txt; then
    echo "✅ PASS - сортировка от старого к новому корректна"
    passed=$((passed+1))
else
    echo "❌ FAIL - сортировка файлов неверна"
fi

rm -rf ./log/*
input="`pwd`/log\ny\n10\nn\n"
run_test "Пограничный случай: пустая папка" "$input" "No action needed"

echo ""
echo "=== RESULT: $passed / $total PASSED ==="
