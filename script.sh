setup_size_limit() {
    local target_dir=$1
    echo "--------------------------------------------------------"
    echo "Проверка ограничения размера для папки: $target_dir"

    if mountpoint -q "$target_dir"; then
        echo "✓ Папка уже имеет ограничение (является отдельной точкой монтирования)."
        df -h "$target_dir"
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

    read -p "Введите максимальный размер для папки (например, 500M, 2G): " max_size
    if [ -z "$max_size" ]; then
        echo "Ошибка: Размер не указан."
        exit 1
    fi
    
    local image_storage="/var/disk-images"
    local image_name=$(basename "$target_dir").img
    local image_path="$image_storage/$image_name"

    echo "Будет создан файл-контейнер '$image_path' размером $max_size."
    read -p "Для продолжения требуются права суперпользователя (sudo). Продолжить? (y/n): " sudo_confirm
    if [[ ! "$sudo_confirm" =~ ^[Yy]$ ]]; then
        echo "Операция отменена."
        exit 1
    fi

    sudo mkdir -p "$image_storage"
    echo "1. Создание файла-контейнера..."
    sudo fallocate -l "$max_size" "$image_path"
    echo "2. Форматирование в ext4..."
    sudo mkfs.ext4 "$image_path"
    echo "3. Монтирование в '$target_dir'..."
    sudo mount -o loop "$image_path" "$target_dir"
    
    sudo chown "$(whoami):$(whoami)" "$target_dir"

    if mountpoint -q "$target_dir"; then
        echo "✓ Папка успешно примонтирована и ограничена размером $max_size."
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

echo "Укажите папку для работы"
LOG_DIRECTORY=$(get_log_path)

echo
echo "Настройка ограничения по размеру."
setup_size_limit "$LOG_DIRECTORY"

echo "--------------------------------------------------------"
echo "✓ Предварительная настройка завершена."
echo "Папка для работы: $LOG_DIRECTORY"
