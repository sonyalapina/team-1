#!/bin/bash

get_log_path(){
        while true; do
                read -p "Enter the path to the folder /log: " path

                path=$(echo "$path" | xargs)

                if [ -z "$path" ]; then
                        echo "The path to the folder cannot be empty"
                        continue
                fi

                path="${path/#\~/$HOME}"
                normalized_path=$(realpath -s "$path" 2>/dev/null)

                if [ ! -d "$normalized_path" ]; then
                        echo "Folder '$path' does not exist or it is not a folder"
                        continue
                fi

        if [ $(basename "$normalized_path") != "log" ]; then
            echo "Folder '$path' is not a log folder"
			continue
		fi

		if [ ! -r "$normalized_path" ] || [ ! -w "$normalized_path" ]; then
			echo "No access rights to the folder"
			continue
		fi

		echo "Folder found: $normalized_path"
		break
	done
}

setup_size_limit() {
    local target_dir="$normalized_path"
    echo "--------------------------------------------------------"
    echo "Проверка ограничения размера для папки: $target_dir"

    if mountpoint -q "$target_dir"; then
        echo "✓ Папка уже имеет ограничение (является отдельной точкой монтирования)."
        return 0
    fi
    
    echo "Внимание: Эта папка не имеет жесткого ограничения по размеру."
    read -p "Хотите создать ограничение для этой папки? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Продолжение без ограничения. Расчет % будет вестись от общего размера диска."
        return 0
    fi

    # ПРОВЕРКА: Папка должна быть пустой для монтирования
    if [ "$(ls -A "$target_dir")" ]; then
        echo "Ошибка: Папку '$target_dir' необходимо очистить перед созданием ограничения."
        exit 1
    fi

    read -p "Введите максимальный размер для папки в МБ (максимальный размер: "$(df -m "$normalized_path" | awk 'NR==2 {print $4}')"МБ): " max_size
    if [ -z "$max_size" ]; then
        echo "Ошибка: Размер не указан."
        exit 1
    fi

    if ! [[ "$max_size" =~ ^[0-9]+$ ]]; then 
        echo "Ошибка: размер указан не верно"
        exit 1
    fi

    if [ $max_size -gt $(df -m "$normalized_path" | awk 'NR==2 {print $4}') ]; then
        echo "Ошибка: превышение допустимого размера."
        exit 1
    fi
    
    local image_storage="/var/disk-images"
    local image_name="$(echo "$target_dir" | sed 's|/|_|g').img"
    local image_path="$image_storage/$image_name"

    echo "Будет создан файл-контейнер '$image_path' размером "$max_size"M."
    read -p "Для продолжения требуются права суперпользователя (sudo). Продолжить? (y/n): " sudo_confirm
    if [[ ! "$sudo_confirm" =~ ^[Yy]$ ]]; then
        echo "Операция отменена."
        exit 1
    fi

    sudo mkdir -p "$image_storage"
    echo "1. Создание файла-контейнера..."
    sudo fallocate -l ""$max_size"M" "$image_path"
    echo "2. Форматирование в ext4..."
    sudo mkfs.ext4 "$image_path"
    echo "3. Монтирование в '$target_dir'..."
    sudo mount -o loop "$image_path" "$target_dir"
    
    sudo chown "$(whoami):$(whoami)" "$target_dir"

    if mountpoint -q "$target_dir"; then
        echo "✓ Папка успешно примонтирована и ограничена размером "$max_size"M."
    else
        echo "✗ Не удалось примонтировать файловую систему."
        sudo rm -f "$image_path" # Очистка
        exit 1
    fi

    read -p "Добавить автоматическое монтирование при перезагрузке системы в /etc/fstab? (y/n): " fstab_confirm
    if [[ "$fstab_confirm" =~ ^[Yy]$ ]]; then
        local fstab_entry="$image_path $target_dir ext4 loop,defaults 0 0"
        # Проверяем, нет ли уже такой записи
        if ! sudo grep -qF "$fstab_entry" /etc/fstab; then
            echo "$fstab_entry" | sudo tee -a /etc/fstab > /dev/null
            echo "✓ Запись добавлена в /etc/fstab."
        else
            echo "Запись уже существует в /etc/fstab."
        fi
    fi
}

input_threshold(){
    while true; do
        read -p "Enter threshold percent (1-100%): " THRESHOLD
        THRESHOLD=$(echo "$THRESHOLD")
        if [ -z "$THRESHOLD" ]; then
            echo "Threshold cannot be empty"
            continue
        fi
        THRESHOLD=$(echo "$THRESHOLD" | tr -d ' ')
        
        case $THRESHOLD in
            *[!0-9]*)
                echo "Threshold must be a number"
                continue
                ;;
        esac 
        
        if [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 100 ]; then
            echo "Threshold must be between 1 and 100"
            continue
        fi

        echo "Threshold set to: $THRESHOLD%"
        break
    done
}

get_log_path
echo "✓ Настройка ограничения по размеру."
setup_size_limit
echo "---------------------------------------------------------"
echo "✓ Папка ограничена."
input_threshold




# Базовая директория в домашней папке
BASE_DIR="$normalized_path/.."
SOURCE_DIR="$BASE_DIR/log"
BACKUP_DIR="$BASE_DIR/backup"

mkdir -p "$BACKUP_DIR"

while true; do
    # Получаем общий и нынешний размер папки log в байтах
    TOTAL_DIR_SIZE=$(df "$SOURCE_DIR" | awk 'NR==2 {print $2 * 1024 - 7 * 1024 * 1024}')  # переводим из КБ в байты убираем размер системной папки
    CURENT_DIR_SIZE=$(df "$SOURCE_DIR" | awk 'NR==2 {print $3 * 1024}')

    # Если папка пуста, устанавливаем размер 0
    if [ -z "$CURENT_DIR_SIZE" ]; then
        CURENT_DIR_SIZE=0
    fi

    # Вычисляем процент папки log от всего диска
    if [ "$TOTAL_DIR_SIZE" -gt 0 ]; then
        USAGE=$((CURENT_DIR_SIZE * 100 / TOTAL_DIR_SIZE))
    else
        USAGE=0
    fi

    echo "Curent directory size: $((CURENT_DIR_SIZE / 1024 / 1024)) MB"
    echo "Total directory size: $((TOTAL_DIR_SIZE / 1024 / 1024)) MB"
    echo "Log directory usage: $USAGE% of entire disk"

    # Проверка превышения порога
    if [ "$USAGE" -le "$THRESHOLD" ]; then
        echo "Log directory usage is below threshold. No action needed."
        read -p "Выполнить повторную проверку? (y/n): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Завершение работы."
            break
        else
            continue
        fi
    fi

    echo "Threshold exceeded. Calculating files to archive..."

    # Вычисляем целевой размер папки log (в байтах)
    TARGET_SIZE=$((THRESHOLD * TOTAL_DIR_SIZE / 100))
    BYTES_TO_FREE=$((CURENT_DIR_SIZE - TARGET_SIZE))

    echo "Need to free approximately $((BYTES_TO_FREE / 1024 / 1024)) MB"

    # Поиск файлов
    OLD_FILES=$(find "$SOURCE_DIR" -maxdepth 1 -printf "%T@ %s %p\n" | sort -n)

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

        read -r -a arr <<< "$file_info"
        file_path=""
        for ((i=2; i < ${#arr[@]}; i++)); do
            file_path+="${arr[i]}"
            if (( i < ${#arr[@]} - 1 )); then
                file_path+=" "
            fi
        done
        
        # Проверяем, нужно ли еще освобождать место
        if [ $TOTAL_ARCHIVED_SIZE -lt $BYTES_TO_FREE ]; then
            FILES_LIST="$FILES_LIST $file_path"
            TOTAL_ARCHIVED_SIZE=$((TOTAL_ARCHIVED_SIZE + file_size))
            FILE_COUNT=$((FILE_COUNT + 1))
            echo "Selected for archiving: $(basename "$file_path") ($((file_size / 1024 / 1024)) MB)"
        else
            break
        fi
    done <<< "$OLD_FILES"

    if [ $FILE_COUNT -eq 0 ]; then
        echo "No suitable files found for archiving"
        read -p "Выполнить повторную проверку? (y/n): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Завершение работы."
            break
        else
            continue
        fi
    fi

    echo "Found $FILE_COUNT files to archive (total: $((TOTAL_ARCHIVED_SIZE / 1024 / 1024)) MB)"

    # Создание архива
    TIME=$(date +"%Y%m%d_%H%M%S")
    NAME="backup_${TIME}.tar.xz"
    A_PATH="$BACKUP_DIR/$NAME"

    echo "archiving..."

    # Архивируем выбранные файлы
    tar -cf - $FILES_LIST 2>/dev/null | xz -9 > "$A_PATH"

    if [ $? -eq 0 ]; then
        echo "$FILE_COUNT files were successfully archived"
        
        # Удаляем заархивированные файлы
        for file in $FILES_LIST; do
            rm "$file"
        done
        
        # Вычисляем новый процент использования
        CURENT_DIR_SIZE=$(df "$SOURCE_DIR" | awk 'NR==2 {print $3 * 1024}')
        if [ -z "$CURENT_DIR_SIZE" ]; then
            CURENT_DIR_SIZE=0
        fi
        
        if [ "$TOTAL_DIR_SIZE" -gt 0 ]; then
            USAGE=$((CURENT_DIR_SIZE * 100 / TOTAL_DIR_SIZE))
        else
            USAGE=0
        fi
        
        echo "Archiving completed. New log directory usage: $USAGE%"
    else
        echo "Error..."
        exit 1
    fi
    read -p "Выполнить повторную проверку? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Завершение работы."
        break
    fi
done
