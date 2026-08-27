# tests/cases.sh — the case list, sourced by nurlbox_test.sh.
#
# Grouped by applet. `dt` compares text output, `dtb` compares raw bytes
# (so a missing or extra trailing newline fails), `expect` states an
# answer outright.

echo "[echo]"
dt  echo hello world
dt  echo -n no trailing newline
dt  echo -e 'tab\there\nand a line'
dt  echo -E 'literal\tbackslash'
dt  echo
dt  echo -- --not-an-option
dt  echo -x -- keeps the dash

echo "[cat]"
dtb cat four.txt
dtb cat four.txt words.txt
dtb cat nonl.txt
dtb cat crlf.txt
dtb cat binary.bin
dtb cat empty.txt
dtb --stdin four.txt cat
dtb --stdin four.txt cat -
dtb cat -n four.txt
dtb cat -b words.txt
dtg cat -E four.txt
dtg cat -T tabs.txt
dtb cat -A tabs.txt
dtg cat -s words.txt
dtg cat -n nonl.txt
dtb cat -n crlf.txt

echo "[head]"
dtb head four.txt
dtb head -n 2 four.txt
dtb head -2 four.txt
dtb head -n 0 four.txt
dtb head -n 99 four.txt
dtb head -c 5 four.txt
dtb head four.txt words.txt
dtb head -q four.txt words.txt
dtb head -v four.txt
dtb --stdin hundred.txt head -n 3
dtb head -n 3 nonl.txt

echo "[tail]"
dtb tail four.txt
dtb tail -n 2 four.txt
dtb tail -2 four.txt
dtb tail -n 99 hundred.txt
dtb tail -n +95 hundred.txt
dtb tail -c 6 four.txt
dtb tail four.txt words.txt
dtb --stdin hundred.txt tail -n 3
dtb tail -n 1 nonl.txt

echo "[wc]"
dt  wc four.txt
dt  wc -l four.txt
dt  wc -w words.txt
dt  wc -c four.txt
dt  wc -L words.txt
dt  wc -lw four.txt
dt  wc four.txt words.txt
dt  wc -c four.txt words.txt
dt  --stdin words.txt wc
dt  wc empty.txt
dt  wc nonl.txt

echo "[seq]"
dt  seq 5
dt  seq 3 7
dt  seq 2 2 10
dt  seq 10 -2 2
dt  seq -s , 1 4
dt  seq 0

echo "[true/false]"
dt  true
dt  false

echo "[pwd/basename/dirname]"
dt  basename /a/b/c.txt
dt  basename /a/b/c.txt .txt
dt  basename /a/b/
dt  basename c.txt .txt
dt  dirname /a/b/c.txt
dt  dirname c.txt
dt  dirname /
dt  dirname /a/

echo "[system]"
dt  uname
dt  uname -a
dt  uname -srm
dt  hostname
dt  whoami
dt  id
dt  id -u
dt  id -g
dt  groups
dt  nproc
dt  arch
dt  which sh
dtg printenv HOME

echo "[printf]"
dt  printf 'plain\n'
dt  printf '%s|%s\n' a b
dt  printf '%d %i %u\n' 42 -7 9
dt  printf '%x %X %o\n' 255 255 8
dt  printf '%5d|%-5d|%05d\n' 42 42 42
dt  printf '%c%c\n' ab cd
dt  printf '%s\n' one two three
dt  printf 'tab\there\n'
dt  printf '%%\n'
dt  printf '%.2s\n' abcdef

echo "[ls]"
dt  ls .
dt  ls -1 .
dt  ls -a .
dt  ls -A .
dt  ls sub
dt  ls -R .
dt  ls -F .
dt  ls -d .
dt  ls four.txt words.txt
dt  ls nonexistent-entry
dt  ls -i four.txt
dt  ls -s four.txt

echo "[stat]"
dt  stat four.txt
dt  stat sub
dt  stat -c '%n %s %F %a %A %h %u %g' four.txt
dt  stat -c '%n' nonexistent-entry

echo "[du]"
dt  du sub
dt  du -s sub
dt  du -a sub
dt  du -k sub
dt  du -c sub

echo "[find]"
# find emits in directory order, which is the filesystem's business;
# nurlbox sorts each directory so a run is reproducible. Compare the two
# as SETS — the contents are the contract, the order is not.
dtsort find sub
dtsort find . -maxdepth 1 -type d
dtsort find . -name '*.txt'
dtsort find . -type f -name 'four*'
dtsort find . -maxdepth 1 ! -type d
dtsort find . -name 'a*' -o -name 'b*'

echo "[mutating: mkdir/rm/cp/mv/ln/touch]"
dtfs mkdir newdir
dtfs mkdir -p a/b/c
dtfs rmdir empty
dtfs rm src/a.txt
dtfs rm -r src
dtfs rm -f nonexistent
dtfs cp src/a.txt dst/
dtfs cp src/a.txt dst/renamed.txt
dtfs cp -r src dst/copied
dtfs cp -a src dst/arch
dtfs mv src/a.txt dst/
dtfs mv src dst/moved
dtfs ln -s a.txt src/newlink
dtfs ln src/a.txt src/hard.txt
dtfs touch src/brand-new
dtfs touch -c src/absent
dtfs chmod 600 src/a.txt
dtfs chmod u+x,go-r src/b.txt
dtfs chmod -R 700 src
dtfs truncate -s 2 src/a.txt

echo "[filters]"
dtb tac four.txt
dtb rev four.txt
dtb nl four.txt
dtb nl -ba words.txt
dtg nl -nrz -w4 four.txt
dtb sort dupes.txt
dtb sort -r dupes.txt
dtb sort -u dupes.txt
dtb sort -n hundred.txt
dtb sort -f dupes.txt
dtb uniq dupes.txt
dtb uniq -c dupes.txt
dtb uniq -d dupes.txt
dtb uniq -u dupes.txt
dtb cut -c1-3 four.txt
dtb cut -c2- four.txt
dtb cut -f1 tabs.txt
dtb cut -f2,3 tabs.txt
dtb cut -d: -f1 four.txt
dtb --stdin four.txt tac
dtb --stdin four.txt rev
dtb --stdin four.txt sort

echo "[tr]"
dtb --stdin four.txt tr a-z A-Z
dtb --stdin four.txt tr -d aeiou
dtb --stdin words.txt tr -s ' '
dtb --stdin four.txt tr '[:lower:]' '[:upper:]'
dtb --stdin four.txt tr -c 'a-z\n' .

echo "[hashes]"
dt  md5sum four.txt
dt  sha1sum four.txt
dt  sha256sum four.txt
dt  sha512sum four.txt
dt  md5sum four.txt words.txt
dt  md5sum binary.bin
dt  crc32 four.txt
dtg cksum four.txt
dt  --stdin four.txt md5sum
dtb base64 four.txt
dtb base64 binary.bin
dt  base64 -d /dev/null

echo "[grep]"
dt  grep alpha four.txt
dt  grep -i ALPHA four.txt
dt  grep -v alpha four.txt
dt  grep -n a four.txt
dt  grep -c a four.txt
dt  grep -l a four.txt words.txt
dt  grep -w one words.txt
dt  grep -x alpha four.txt
dt  grep -o 'a.*a' four.txt
dt  grep -E 'al(pha|ph)' four.txt
dt  grep 'al\(pha\|ph\)' four.txt
dt  grep -F 'a.*a' four.txt
dt  grep '^b' four.txt
dt  grep 'a$' four.txt
dt  grep nomatch four.txt
dt  grep -e alpha -e bravo four.txt
dt  grep -r alpha sub
dt  --stdin four.txt grep alpha

echo "[test]"
dt  test 1 -eq 1
dt  test 1 -eq 2
dt  test 1 -ne 2
dt  test 3 -lt 4
dt  test 4 -le 4
dt  test 5 -gt 4
dt  test 5 -ge 6
dt  test -f four.txt
dt  test -f sub
dt  test -d sub
dt  test -e four.txt
dt  test -s four.txt
dt  test -s empty.txt
dt  test -z ""
dt  test -n abc
dt  test abc = abc
dt  test abc != def
dt  test ! -f nope
dt  test 1 -eq 1 -a 2 -eq 2
dt  test 1 -eq 2 -o 2 -eq 2
dt  test -r four.txt
dt  test -w four.txt

echo "[expr]"
dt  expr 1 + 2
dt  expr 7 - 9
dt  expr 6 '*' 7
dt  expr 10 / 3
dt  expr 10 % 3
dt  expr 10 '>' 9
dt  expr 2 '<' 10
dt  expr abc = abc
dt  expr abc = def
dt  expr length abcdef
dt  expr substr abcdef 2 3
dt  expr index abcdef d
dt  expr 1 '|' 0
dt  expr 0 '&' 1

echo "[xargs]"
dtb --stdin four.txt xargs echo
dtb --stdin four.txt xargs -n1 echo
dtb --stdin four.txt xargs -n2 echo

echo "[sed]"
dtb sed 's/a/A/' four.txt
dtb sed 's/a/A/g' four.txt
dtb sed 's/a/A/2' words.txt
dtb sed -n '2p' four.txt
dtb sed -n '2,3p' four.txt
dtb sed '2d' four.txt
dtb sed '$d' four.txt
dtb sed -n '/bravo/p' four.txt
dtb sed '/bravo/d' four.txt
dtb sed -n '/alpha/,/charlie/p' four.txt
dtb sed 's/\(al\)\(pha\)/\2\1/' four.txt
dtb sed -E 's/(al)(pha)/\2\1/' four.txt
dtb sed 's/alpha/[&]/' four.txt
dtb sed 'y/abc/xyz/' four.txt
dtb sed -n '$=' four.txt
dtb sed '2q' four.txt
dtb sed -n '2{p;p}' four.txt
dtb sed '1!d' four.txt
dtb sed -e 's/a/A/' -e 's/b/B/' four.txt
dtb sed 'G' four.txt
dtb sed -n '1h;2,$H;${g;p}' four.txt
dtb sed '2i\INSERTED' four.txt
dtb sed '2a\APPENDED' four.txt
dtb sed '2c\CHANGED' four.txt
dtb --stdin four.txt sed 's/a/A/'
dtb sed 's/x/y/' nonl.txt
