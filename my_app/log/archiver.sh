#!/bin/bash

# Базовая директория в домашней папке пользователя
BASE_DIR="$HOME/my_app"
SOURCE_DIR="$BASE_DIR/log"
BACKUP_DIR="$BASE_DIR/backup"

# Создание всей структуры директорий
mkdir -p "$SOURCE_DIR"
mkdir -p "$BACKUP_DIR"

echo "Base directory: $BASE_DIR"
echo "Log directory: $SOURCE_DIR"
echo "Backup directory: $BACKUP_DIR"

# Получаем общий размер диска и размер папки log в байтах
TOTAL_DISK_SIZE=$(df "$BASE_DIR" | awk 'NR==2 {print $2 * 1024}')  # переводим из КБ в байты
LOG_DIR_SIZE=$(du -sb "$SOURCE_DIR" 2>/dev/null | cut -f1)

# Если папка пуста, устанавливаем размер 0
if [ -z "$LOG_DIR_SIZE" ]; then
    LOG_DIR_SIZE=0
fi

# Вычисляем процент папки log от всего диска
if [ "$TOTAL_DISK_SIZE" -gt 0 ]; then
    USAGE=$((LOG_DIR_SIZE * 100 / TOTAL_DISK_SIZE))
else
    USAGE=0
fi

echo "Log directory size: $((LOG_DIR_SIZE / 1024)) KB"
echo "Total disk size: $((TOTAL_DISK_SIZE / 1024 / 1024)) MB"
echo "Log directory usage: $USAGE% of entire disk"

# Проверка превышения порога
THRESHOLD=1
if [ "$USAGE" -le "$THRESHOLD" ]; then
    echo "Log directory usage is below threshold. No action needed."
    exit 0
fi

echo "Threshold exceeded. Calculating files to archive..."

# Вычисляем целевой размер папки log (в байтах)
TARGET_SIZE=$((THRESHOLD * TOTAL_DISK_SIZE / 100))
BYTES_TO_FREE=$((LOG_DIR_SIZE - TARGET_SIZE))

echo "Need to free approximately $((BYTES_TO_FREE / 1024)) KB"

# Поиск ВСЕХ файлов (любого типа) рекурсивно, ИСКЛЮЧАЯ сам скрипт
OLD_FILES=$(find "$SOURCE_DIR" -type f ! -name "archiver.sh" -printf "%T@ %s %p\n" | sort -n)

if [ -z "$OLD_FILES" ]; then
    echo "Files not found"
    exit 1
fi

# Определяем файлы для архивации на основе необходимого объема
FILES_LIST=""
TOTAL_ARCHIVED_SIZE=0
FILE_COUNT=0

while IFS= read -r file_info; do
    if [ -z "$file_info" ]; then
        continue
    fi
    
    # Извлекаем размер и путь к файлу
    file_size=$(echo "$file_info" | awk '{print $2}')
    file_path=$(echo "$file_info" | awk '{for(i=3;i<=NF;i++) printf "%s", $i (i<NF?OFS:ORS)}')
    
    # Проверяем, нужно ли еще освобождать место
    if [ $TOTAL_ARCHIVED_SIZE -lt $BYTES_TO_FREE ]; then
        FILES_LIST="$FILES_LIST $file_path"
        TOTAL_ARCHIVED_SIZE=$((TOTAL_ARCHIVED_SIZE + file_size))
        FILE_COUNT=$((FILE_COUNT + 1))
        echo "Selected for archiving: $file_path ($((file_size / 1024)) KB)"
    else
        break
    fi
done <<< "$OLD_FILES"

if [ $FILE_COUNT -eq 0 ]; then
    echo "No suitable files found for archiving"
    exit 0
fi

echo "Files found (sorted from old to new):"
echo "$FILES_LIST" | tr ' ' '\n' | grep -v '^$' | awk '{print ". " $1}'

echo "Found $FILE_COUNT files to archive (total: $((TOTAL_ARCHIVED_SIZE / 1024)) KB)"

# Создание архива
TIME=$(date +"%Y%m%d_%H%M%S")
NAME="backup_${TIME}.tar.xz"
A_PATH="$BACKUP_DIR/$NAME"

echo "archiving..."

# Архивируем выбранные файлы
tar -cf - $FILES_LIST 2>/dev/null | xz -9 > "$A_PATH"

if [ $? -eq 0 ]; then
    echo "$FILE_COUNT files were successfully archived"
    echo "archive: $A_PATH"
    
    # Удаляем заархивированные файлы
    for file in $FILES_LIST; do
        rm "$file"
        echo "Removed: $file"
    done
    
    # Вычисляем новый процент использования
    NEW_LOG_DIR_SIZE=$(du -sb "$SOURCE_DIR" 2>/dev/null | cut -f1)
    if [ -z "$NEW_LOG_DIR_SIZE" ]; then
        NEW_LOG_DIR_SIZE=0
    fi
    
    if [ "$TOTAL_DISK_SIZE" -gt 0 ]; then
        NEW_USAGE=$((NEW_LOG_DIR_SIZE * 100 / TOTAL_DISK_SIZE))
    else
        NEW_USAGE=0
    fi
    
    echo "Archiving completed. New log directory usage: $NEW_USAGE%"
else
    echo "Error..."
    exit 1
fi
