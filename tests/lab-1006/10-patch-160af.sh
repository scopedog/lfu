F=/tmp/lab1006-gnew/lustre/tests/sanity.sh
cp -n $F $F.orig
grep -n 'find $DIR/$tdir --changelog $mdt --since 1' $F
sed -i 's|out=$($LFS find $DIR/$tdir --changelog $mdt --since 1 \\|out=$($LFS find $MOUNT --changelog $mdt --since 1 \\|' $F
grep -n 'find $MOUNT --changelog $mdt --since 1' $F
diff $F.orig $F
