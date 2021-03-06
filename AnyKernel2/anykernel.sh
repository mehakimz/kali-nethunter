#!/sbin/sh
# AnyKernel 2.0 Ramdisk Mod Script 
# osm0sis @ xda-developers

## AnyKernel setup
# EDIFY properties
kernel.string="Nethunter kernel"
do.devicecheck=1
do.initd=1
do.modules=1
do.cleanup=1
device.name1=dogo
device.name2=C5503
device.name3=C5502
device.name4=
device.name5=

# shell variables
block=/dev/block/platform/msm_sdcc.1/by-name/boot;

## end setup


## AnyKernel methods (DO NOT CHANGE)
# set up extracted files and directories
ramdisk=/tmp/anykernel/ramdisk;
ramdiskroot=/tmp/anykernel/ramdiskroot;
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;
patch=/tmp/anykernel/patch;

chmod -R 755 $bin;
mkdir -p $ramdisk $split_img $ramdiskroot;
cd $ramdisk;

OUTFD=`ps | grep -v "grep" | grep -oE "update(.*)" | cut -d" " -f3`;
ui_print() { echo "ui_print $1" >&$OUTFD; echo "ui_print" >&$OUTFD; }

# dump boot and extract ramdisk
dump_boot() {
  dd if=$block of=/tmp/anykernel/boot.img;
  $bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
  if [ $? != 0 ]; then
    ui_print " "; ui_print "Dumping/unpacking image failed. Aborting...";
    echo 1 > /tmp/anykernel/exitcode; exit;
  fi;
  cd $ramdiskroot;
  gunzip -c $split_img/boot.img-ramdisk.gz | cpio -i;
#we have cpio archive of ramdisk and ramdisk-recovery in dogo
  cd $ramdisk;
  cpio -i --no-absolute-filenames --preserve-modification-time < $ramdiskroot/sbin/ramdisk.cpio;
# rm $ramdiskroot/sbin/ramdisk.cpio;
}

# repack ramdisk then build and write image
write_boot() {
  cd $split_img;
  cmdline=`cat *-cmdline`;
  base=`cat *-base`;
  pagesize=`cat *-pagesize`;
  kerneloff=`cat *-kerneloff`;
  ramdiskoff=`cat *-ramdiskoff`;
  tagsoff=`cat *-tagsoff`;
  if [ -f /tmp/anykernel/zImage ]; then
    kernel=/tmp/anykernel/zImage;
  else
    kernel=`ls *-zImage`;
    kernel=$split_img/$kernel;
  fi;
  if [ -f /tmp/anykernel/boot.img-ramdisk.gz ]; then
    ramd=/tmp/anykernel/boot.img-ramdisk.gz;
  else
    ramd=`ls *-ramdisk.gz`;
    ramd=$split_img/$ramd;
  fi;
  cd $ramdisk;
#archive ramdisk as cpio
  find . | cpio -o > $ramdiskroot/sbin/ramdisk.cpio;
#make main boot.img-ramdisk.gz with ramdisk and ramdiskrecovery cpio as in
  cd $ramdiskroot;
  find . | cpio -H newc -o | gzip > /tmp/anykernel/boot.img-ramdisk.gz;
  $bin/mkbootimg --kernel $kernel --ramdisk $ramd --cmdline "$cmdline" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff --tags_offset $tagsoff --output /tmp/anykernel/boot-new.img;
  if [ $? != 0 -o `wc -c < /tmp/anykernel/boot-new.img` -gt `wc -c < /tmp/anykernel/boot.img` ]; then
    ui_print " "; ui_print "Repacking image failed. Aborting...";
    echo 1 > /tmp/anykernel/exitcode; exit;
  fi;
  dd if=/tmp/anykernel/boot-new.img of=$block;
}

# backup_file <file>
backup_file() { cp $1 $1~; }

# replace_string <file> <if search string> <original string> <replacement string>
replace_string() {
  if [ -z "$(grep "$2" $1)" ]; then
      sed -i "s;${3};${4};" $1;
  fi;
}

# insert_line <file> <if search string> <before/after> <line match string> <inserted line>
insert_line() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | cut -d: -f1` + offset));
    sed -i "${line}s;^;${5};" $1;
  fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | cut -d: -f1`;
    sed -i "${line}s;.*;${3};" $1;
  fi;
}

# remove_line <file> <line match string>
remove_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | cut -d: -f1`;
    sed -i "${line}d" $1;
  fi;
}

# prepend_file <file> <if search string> <patch file>
prepend_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo "$(cat $patch/$3 $1)" > $1;
  fi;
}

# append_file <file> <if search string> <patch file>
append_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo -ne "\n" >> $1;
    cat $patch/$3 >> $1;
    echo -ne "\n" >> $1;
  fi;
}

# replace_file <file> <permissions> <patch file>
replace_file() {
  cp -fp $patch/$3 $1;
  chmod $2 $1;
}

## end methods

## AnyKernel permissions
# set permissions for included files
chmod -R 755 $ramdisk
chmod 644 $ramdisk/sbin/media_profiles.xml

## AnyKernel install
dump_boot;

# begin ramdisk changes

# direct patch ramdisk!!
# init.environ
#echo "export TERMINFO /system/etc/terminfo" >> $ramdisk/init.environ.rc;
#echo "export TERM linux" >> $ramdisk/init.environ.rc;

# adb (un)secure
backup_file default.prop;
replace_string default.prop "ro.adb.secure=0" "ro.adb.secure=1" "ro.adb.secure=0";
replace_string default.prop "ro.secure=0" "ro.secure=1" "ro.secure=0";

# init.rc <-- Run busybox init.d
backup_file init.rc;
append_file init.rc "run-parts" init;

# init.usb.rc <-- Add HID option to easily switch vendor with command: setprop sys.usb.state hid
backup_file init.usb.rc;
append_file init.usb.rc "property:sys.usb.config=hid" init.usb;

# init.environ.rc
backup_file init.environ.rc;
append_file init.environ.rc "TERMINFO" init.environ;

# end ramdisk changes

write_boot;

## end install

