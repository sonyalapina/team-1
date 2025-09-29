DIR=$(get_log_path)

read -p "Enter max folder size in MB: " MAX_SIZE_MB
read -p "Enter threshold percent (N%): " THRESHOLD
read -p "Enter number of old files to archive (M): " M

MAX_SIZE=$((MAX_SIZE_MB * 1024 * 1024))

CURRENT_SIZE=$(du -sb "$DIR" | awk '{print $1}')

USAGE=$((CURRENT_SIZE * 100 / MAX_SIZE))

echo "Folder size: $CURRENT_SIZE bytes (~$((CURRENT_SIZE/1024/1024)) MB)"
echo "Usage: $USAGE% of $MAX_SIZE_MB MB"
