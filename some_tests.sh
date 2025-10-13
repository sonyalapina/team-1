# 11. ��������� ��������� ������ � �������� ���������� � ������
total=$((total+1))
d=$(make_test_env "t11")
for i in {1..8}; do
  echo "��������� ���� $i" >"$d/log/file$i.log"
  touch -d "2020-01-0$i" "$d/log/file$i.log"
done
out="$TMPROOT/out11.txt"
run_and_capture "$d/log\nn\n1\ny\n" "$out"
arc="$(ls -1 "$d/backup"/backup_* 2>/dev/null | head -n1 || true)"
if [ -n "$arc" ] && tar -tf "$arc" | grep -q "file1.log"; then
  echo "���� 11 (��������� ��������� ������): ������ ����� ������� �������, ����� ������� ������ ($arc)."
  pass=$((pass+1))
else
  echo "���� 11 (��������� ��������� ������): ����� �� ������ ��� ������� ������ �������."
  cat "$out"
  fail=$((fail+1))
fi


# 12. ��������� ������ ����������
total=$((total+1))
d=$(make_test_env "t12")
out="$TMPROOT/out12.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
if check_grep "$out" "No suitable files|No files for archiving|empty"; then
  echo "���� 12 (������ ����������): ������ ��������� �������, ��� ������ ��� ��������� ���."
  pass=$((pass+1))
else
  echo "���� 12 (������ ����������): ������ �� ����� ��������� �� ���������� ������."
  cat "$out"
  fail=$((fail+1))
fi


# 13. �������� ���������� backup
total=$((total+1))
d=$(make_test_env "t13")
rm -rf "$d/backup"  # ��������� ���������� ����� backup
mkdir -p "$d/log"
echo "������ �����" >"$d/log/test.log"
out="$TMPROOT/out13.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
if [ -d "$d/backup" ]; then
  echo "���� 13 (�������� ����� backup): ���������� backup ���� ������� �������."
  pass=$((pass+1))
else
  echo "���� 13 (�������� ����� backup): ����� backup �� ���� �������."
  cat "$out"
  fail=$((fail+1))
fi


# 14. �������� ������� ���������
total=$((total+1))
d=$(make_test_env "t14")
for i in 5 4 3 2 1; do
  echo "��� $i" >"$d/log/f$i.log"
  touch -d "2020-01-0$i" "$d/log/f$i.log"
done
out="$TMPROOT/out14.txt"
run_and_capture "$d/log\nn\n10\ny\n" "$out"
arc="$(ls -1 "$d/backup"/backup_* 2>/dev/null | head -n1 || true)"
if [ -n "$arc" ]; then
  order=$(tar -tf "$arc" | sed 's#.*/##' | head -n 3 | tr '\n' ' ')
  if echo "$order" | grep -q "f1.log"; then
    echo "���� 14 (������� ���������): ����� ������������� ��������� � ������ ������������ �������."
    pass=$((pass+1))
  else
    echo "���� 14 (������� ���������): ������� ��������� �������."
    echo "����� � ������: $order"
    fail=$((fail+1))
  fi
else
  echo "���� 14 (������� ���������): ����� �� ��� ������."
  cat "$out"
  fail=$((fail+1))
fi


# 15. �������� ����� (��������� �������� ������ �����)
total=$((total+1))
d=$(make_test_env "t15")
echo "�������� ����" >"$d/log/test.log"
out="$TMPROOT/out15.txt"
run_and_capture "$d/log\nn\nabc\ny\n" "$out"
if check_grep "$out" "invalid|must be a number|error"; then
  echo "���� 15 (�������� ���������� �����): ������������ ���� ������ ��������� ���������."
  pass=$((pass+1))
else
  echo "���� 15 (�������� ���������� �����): ������ �� ��������� ������ ��� ����� ������ ������ �����."
  cat "$out"
  fail=$((fail+1))
fi


# 16. �������� ����� (������������� �����)
total=$((total+1))
d=$(make_test_env "t16")
echo "�������� ����" >"$d/log/test.log"
out="$TMPROOT/out16.txt"
run_and_capture "$d/log\nn\n-5\ny\n" "$out"
if check_grep "$out" "invalid|must be positive|error|cannot be negative"; then
  echo "���� 16 (�������� �������������� �����): ������������� �������� ��������� ���������."
  pass=$((pass+1))
else
  echo "���� 16 (�������� �������������� �����): ������ �� ��������� ������������� ��������."
  cat "$out"
  fail=$((fail+1))
fi

# 17. ���������� ������������� (Ctrl+C) � ��������� �� ��������� ��������� �����
total=$((total+1))
d=$(make_test_env "t17")
mkdir -p "$d/log"
mkdir -p "$d/tmp"
echo "��������� ���� 1" >"$d/tmp/temp1"
echo "��������� ���� 2" >"$d/tmp/temp2"
out="$TMPROOT/out18.txt"

# ��������� ������ � ���������� ������� ������������� (SIGINT)
(run_and_capture "$d/log\nn\n10\ny\n" "$out" & pid=$!; sleep 1; kill -INT $pid) >/dev/null 2>&1
wait $pid 2>/dev/null

# ���������, �������� �� ��������� ����� ����� ����������
if [ ! -e "$d/tmp/temp1" ] && [ ! -e "$d/tmp/temp2" ]; then
  echo "���� 17 (���������� �������������): ��������� ����� ���� ������� ������� ����� Ctrl+C."
  pass=$((pass+1))
else
  echo "���� 18 (���������� �������������): ��������� ����� �� ���� ������� ����� ����������."
  cat "$out"
  fail=$((fail+1))
fi
