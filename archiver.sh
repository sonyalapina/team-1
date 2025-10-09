SOURCE_DIR="/var/log"
FILES_TO_ARCHIVE=5
BACKUP_DIR="$HOME/backup"

FILE_EXTENSIONS=("*.log" "*.txt")

mkdir -p "$BACKUP_DIR"

OLD_FILES=$(find "$SOURCE_DIR" -maxdepth 1 -type f \
\( -name "*.log" -o -name "*.txt" \) \
-printf "%T@ %p\n" | \
sort -n | \
head -n "$FILES_TO_ARCHIVE" | \
cut -d' ' -f2-)


if [ -z "$OLD_FILES" ]; then
echo "Files not found"
exit 1
fi

echo "Files found(sorted from old to new):"
echo "$OLD_FILES" | awk '{print ". " $1}'

TIME=$(date +"%Y%m%d_%H%M%S")
NAME="backup_${TIME}.tar.xz"
A_PATH="$BACKUP_DIR/$NAME"

echo "archiving..."

tar -cf - $OLD_FILES 2>/dev/null | xz -9 > "$A_PATH"

if [ $? -eq 0 ]; then
echo "$FILES_TO_ARCHIVE files were successfully archived"
echo "archieve: $A_PATH"
else
echo "Error..."
exit 1
fi 


