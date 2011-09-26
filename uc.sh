#!/usr/bin/env sh

set -x

###############################################################################
# defaults
#
TARGET=
PKGROOT=
RELEASE=
KERN=
MODULES=

ZIP=gzip
MOUNT=/sbin/mount
UMOUNT=/sbin/umount
MDC=/sbin/mdconfig
FDISK=/sbin/fdisk
BSDLABEL=/sbin/bsdlabel
NEWFS=/sbin/newfs
GPART=/sbin/gpart
ZPOOL=/sbin/zpool
ZFS=/sbin/zfs
TSOCKS=
PROXY=

CFG_FILE=

ROOT_DIR=$PWD
WORK_DIR=/tmp

###############################################################################
_init_() # {{{ 
{
	return 0
} # }}}

###############################################################################
_mount_image_() # {{{
{
   local IMG TYPE PART DEV
   PART=
   # 
   # $1 - disk image
   # $2 - fstype = ufs | zfs
   # $3 - partition name for ufs
   #      pool name for zfs

   [ $# -eq 3 ] || return 1
   IMG=$1
   TYPE=$( _upper_ $2 )
   PART=$3
   
   [ -f $IMG ] || return 1
   case $TYPE in
      UFS|ZFS) break ;;
      *) return 1 ;;
   esac
   [ x$PART != x ] || return 1
   #
   DEV=$($MDC -a -f $IMG)
   [ $? -eq 0 ] || return 1
   #
   sleep 1
   case $TYPE in
      UFS)
         [ -d $WORK_DIR/$DEV ] || mkdir $WORK_DIR/$DEV
         #
         $MOUNT /dev/${DEV}$PART $WORK_DIR/$DEV
         [ $? -eq 1 ] && $MDC -d -u $DEV && return 1
         #
         echo "Image \"${IMG}:${PART}\" mounted in \"$WORK_DIR/$DEV\""
         ;;
      ZFS)
         zpool import $PART
         ;;
      *) break ;;
   esac
   return 0
} # }}}

###############################################################################
_umount_image_() # {{{
{
   local PART DEV
   # 
   # $1 - dev name
   [ $# -eq 1 ] || return 1
   DEV=$1
   PART=$(mount | grep $DEV)
   [ "$PART"x != x ] && umount $(echo $PART | cut -d ' ' -f 1)
   $MDC -lv | grep $DEV && $($MDC -d -u $DEV)
   return 0
} # }}}

###############################################################################
_help_() # {{{ 
{
      cat << EOF
$0 { OPTIONS } [ CMD ] [ CMD_ARGS ]
where OPTIONS := { 
         -h help
         -c FILE_NAME       Configuration file name
         -a TARGET_ARCH     Targe architecture
         -k KERNEL_CFG_FILE Kernel configuration file
         -w WORK_DIR        [ $WORK_DIR ] 
                            Working directory
         -r ROOT_DIR        [ $ROOT_DIR ]
                            Root directory
         -p PROXY           HTTP proxy to use
         -t                 Use tsocks
         -P PACKAGE_ROOT    Address where to download packages
         -R RELEASE         The release of packages
      }
      CMD     := { 
         m  IMG_FILE TYPE NAME        // mount partition/pool from image 
            TYPE := { ufs | zfs }
         u  DEV        // umount 
         p  DEV MBR_FS { ARGS }       // prepare disk 
         pi IMG MBR_FS { ARGS }       // prepare disk image
            MBR:= { mbr | gpt }
            FS := { ufs | zfs }
            ARGS   := { POOL_NAME }
         ci IMG_FILE SIZE             // create disk image
         pg DEV         // prepare disk, gpt and ufs
         bk                           // build kernel
         bw                           // build world
         ik DEST_DIR                  // install kernel
         iw DEST_DIR                  // install world
         i  SRC_DIR DST_DIR CFG_DIR   // install plain system and configuration
         im SRC_DIR DST_DIR CFG_DIR   // install boot, mfsroot and usr
         ip DEST_DIR                  // install packages
         ch NANO_DIR                  // chroot to nano installation
      }
EOF
} #}}}

###############################################################################
_upper_() # {{{
{
   [ $# -gt 0 ] || return 1
   echo $* | tr '[:lower:]' '[:upper:]'
   return 0
} # }}}

###############################################################################
_copy_() # {{{
{
   local SRC DST EXFILE COUNT
   #
   # copy directory using tar 
   # $1 - source directory
   # $2 - destination directory
   # $3,..,$n - exclude patterns
   [ $# -ge 2 ] || return 1
   SRC=$1 ; DST=$2 ; shift 2
   EXFILE=$WORK_DIR/exclude.$$

   [ -d $SRC ] || return 1
   [ -d $DST ] || mkdir -p $DST

   echo '*~' > $EXFILE
   for i in $* ; do
      [ "$i"x != x ] && echo $i/ >> $EXFILE
   done
   
   rsync -avz --exclude-from=$EXFILE $SRC/ $DST
   [ -f $WORK_DIR/exclude.$$ ] && rm -f $WORK_DIR/exclude.$$ 
   return 0
} # }}}

###############################################################################
_create_image_() # {{{
{
   # $1 - image name 
   # $2 - image size
   #
   local YESNO IMG_NAME IMG_SIZE
   #
   # defaults 
   [ $# -eq 2 ] || return 1
   IMG_NAME=$1
   IMG_SIZE=$2
   #
   if [ -f $IMG_NAME ] ; then
      echo -n "Rewrite existing image: \"$IMG_NAME\" [y/N]? "
      read YESNO
      [ $(_upper_ $YESNO) != "Y" ] && return 0
   fi
   [ -f $IMG_NAME ] && rm -f $IMG_NAME
   dd if=/dev/zero of=$IMG_NAME bs=1024k count=$IMG_SIZE
   return 0
} # }}}

###############################################################################
_prepare_() # {{{
{
   local DEV M
   # prepare target disk image
   # $1 - disk device 
   # $2 - prepare methdod, mbr, gpt, zfs, ...
   # $3, ... optional arguments
   [ $# -ge 2 ] || return 1
   #
   DEV=$1
   M=$2
   shift 2
   eval "_prepare_${M}_ $DEV $*"
} #}}}

###############################################################################
_prepare_img_() # {{{
{
   local DEV 
   # prepare target disk image
   # $1 - disk device image
   # $2 - prepare methdod, mbr, gpt, zfs, ...
   [ $# -ge 2 ] || return 1
   #
   DEV=$($MDC -a -f $1)
   shift 1
   _prepare_ $DEV $*
   $MDC -d -u $DEV
} #}}}

###############################################################################
_prepare_mbr() # {{{
{
   local DEV
   # prepare target disk image as MBR 
   # $1 - disk device
   [ $# -eq 1 ] || return 1
   #
   DEV=$1
   #
   $FDISK -BI $DEV
   #$GPART create -s MBR $DEV || return 1
   #
   boot0cfg -o noupdate $DEV
   boot0cfg -v -B $DEV
   boot0cfg -s 1 $DEV
   #$GPART add -t freebsd $DEV || return 1
   #
   #$GPART create -s BSD ${DEV}s1 || return 1
   #
   #$GPART add -t freebsd-ufs ${DEV}s1 || return 1
   #
   $BSDLABEL -Bw ${DEV}s1
   #$GPART set -a active -i 1 $DEV || return 1
   #
   #$GPART bootcode -b /boot/boot0 $DEV || return 1
   #
   #$GPART bootcode -i 1 -p /boot/boot1 ${DEV} || return 1
   #
   $NEWFS -O1 ${DEV}s1a || return 1
   return 0
} #}}}

###############################################################################
_prepare_mbr_ufs() # {{{
{
   local DEV
   # prepare target disk image as MBR 
   # $1 - disk device
   [ $# -eq 1 ] || return 1
   #
   DEV=$1
   #
   $FDISK -BI $DEV
   #$GPART create -s MBR $DEV || return 1
   #
   boot0cfg -o noupdate $DEV
   boot0cfg -v -B $DEV
   boot0cfg -s 1 $DEV
   #$GPART add -t freebsd $DEV || return 1
   #
   #$GPART create -s BSD ${DEV}s1 || return 1
   #
   #$GPART add -t freebsd-ufs ${DEV}s1 || return 1
   #
   $BSDLABEL -Bw ${DEV}s1
   #$GPART set -a active -i 1 $DEV || return 1
   #
   #$GPART bootcode -b /boot/boot0 $DEV || return 1
   #
   #$GPART bootcode -i 1 -p /boot/boot1 ${DEV} || return 1
   #
   $NEWFS -O1 ${DEV}s1a || return 1
   return 0
} #}}}

###############################################################################
_prepare_mbrg_() # {{{
{
   local DEV
   # prepare target disk image
   # $1 - disk device
   [ $# -eq 1 ] || return 1
   DEV=$1
   #
   $GPART create -s MBR $DEV || return 1
   $GPART bootcode -b /boot/boot0 $DEV || return 1
   #
   $GPART add -t freebsd $DEV || return 1
   $GPART set -a active -i 1 $DEV || return 1
   #
   $GPART create -s BSD ${DEV}s1 || return 1
   #
   $GPART add -t freebsd-ufs ${DEV}s1 || return 1
   #
   $GPART bootcode -i 1 -p /boot/boot1 ${DEV} || return 1
   #
   $NEWFS -O1 ${DEV}s1a || return 1
   return 0
} #}}}

###############################################################################
_prepare_gpt_() # {{{
{
   local DEV
   # prepare target disk image as GPT
   # $1 - disk device
   [ $# -eq 1 ] || return 1
   DEV=$1
   #
   # create GPT geometry
   $GPART create -s GPT $DEV || return 1
   #
   # create slices
   $GPART add -b 34 -s 128 -t freebsd-boot $DEV || return 1
   # 
   # install pmbr 
   $GPART bootcode -b /boot/pmbr $DEV || return 1
   #
   return 0
} #}}}

###############################################################################
_prepare_gpt_ufs_() # {{{
{
   local DEV
   # prepare target disk image
   # $1 - disk device
   [ $# -eq 1 ] || return 1
   DEV=$1
   #
   _prepare_gpt_ $DEV || return 1
   #
   $GPART add -t freebsd-ufs $DEV || return 1
   #
   # install bootcode
   $GPART bootcode -p /boot/gptboot -i 1 $DEV || return 1
   #
   $NEWFS -O2 -U /dev/${DEV}p2 || return 1
   return 0
} #}}}

###############################################################################
_prepare_gpt_zfs_() # {{{
{
   # parameters
   # $1 - device name to work on
   # $2 - pool name 
   #
   local DEV POOL
   #
   [ $# -eq 2 ] || return 1
   DEV=$1
   POOL=$2
   #
   _prepare_gpt_ $DEV || return 1
   # 
   $GPART add -t freebsd-zfs $DEV || return 1
   #
   # install pmbr -TODO copy compiled boot code instead of host's
   # $GPART bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $DEV || return 1
   #
   # create pool
   $ZPOOL create $POOL /dev/${DEV}p2
   $ZPOOL set bootfs=$POOL $POOL
   #
   # create ZFS filesystem
   $ZFS set checksum=fletcher4 $POOL
   $ZFS create $POOL/usr
   $ZFS create $POOL/usr/home
   #
   # finalize
   cd /$POOL 
   ln -s usr/home home
   mkdir var
   ln -s var/tmp tmp
   cd -
   #
   [ -d /$POOL/boot/zfs ] || mkdir -p /$POOL/boot/zfs
   cp /boot/zfs/zpool.cache /$POOL/boot/zfs/zpool.cache
   # export pool
   sleep 3
   $ZPOOL export $POOL
   return 0
} #}}}

###############################################################################
_build_kernel_() # {{{
{
   local ARCH KERNEL KNAME KMAKE KERNCONF
   #
   # $1 - architecture
   # $2 - kernel configuration, optional
   # $3 - kernel build options, optional
   #
   [ $# -ge 1 ] || return 1
   ARCH=$1
   shift 1
   if [ $# -ge 1 ] ; then
      KERNEL=$1
      [ -f $KERNEL ] || return 1
      KNAME=/usr/src/sys/$ARCH/conf/${1##*/}
      KERNCONF="KERNCONF=${1##*/}"
      shift 1
   fi
   KMAKE="$*"
   [ x$KNAME != x -a ! -h $KNAME ] && ln -s $KERNEL $KNAME
   cd /usr/src && env TARGET_ARCH=$ARCH make buildkernel $KERNCONF $KMAKE
   [ x$KNAME != x -a -h $KNAME ] && unlink $KNAME

   return 0
} # }}}

###############################################################################
_build_world_() # {{{
{
   local ARCH
   #
   # $1 - architecture
   #
   [ $# -eq 1 ] || return 1
   ARCH=$1
   cd /usr/src && env TARGET_ARCH=$ARCH make buildworld
   return 0
} # }}}

###############################################################################
_install_kernel_() # {{{
{
   local ARCH KERNEL KNAME DEST MODULES KERNCONF
   # params
   # $1 - dest dir
   # $2 - arch
   # $3 - kernel cfg file, optional
   # $4 - modules, optional
   [ $# -ge 2 ] || return 1
   DEST=$1
   ARCH=$2
   shift 2
   if [ $# -ge 1 ] ; then
      KERNEL=$1
      [ -f $KERNEL ] || return 1
      KNAME=/usr/src/sys/$ARCH/conf/${1##*/}
      KERNCONF="KERNCONF=${1##*/}"
      shift 1
   fi
   [ $# -ge 1 ] && MODULES=MODULES_OVERRIDE=$@ || MODULES=" "

   [ x$KNAME != x -a ! -h $KNAME ] && ln -s $KERNEL $KNAME

   cd /usr/src && \
      env TARGET_ARCH=$ARCH make installkernel \
          $KERNCONF DESTDIR=$DEST "$MODULES"
   [ x$KNAME != x -a -h $KNAME ] && unlink $KNAME
   return 0
} # }}}

###############################################################################
_install_world_() # {{{
{
   local ARCH DEST
   # params
   # $1 - arch
   # $2 - dest dir
   [ $# -eq 2 ] || return 1
   ARCH=$1
   DEST=$2
   #
   # install
   cd /usr/src && \
      env TARGET_ARCH=$ARCH make installworld DESTDIR=$DEST
   #
   # build etc
   mergemaster -i -D ${DEST}
   #
   # create links
   #
   # tmp -> var/tmp
   [ -e $DEST/tmp ] && rm -fr $DEST/tmp
   [ ! -h $DEST/tmp ] && cd $DEST && ln -s var/tmp tmp
   #
   # home -> usr/home
   [ -e $DEST/home ] && [ ! -s $DEST/home ] && rm -fr $DEST/home
   [ ! -h $DEST/home ] && cd $DEST && ln -s usr/home home
   #
   return 0
} # }}}

###############################################################################
_install_mfsroot_ () # {{{
{
   local DST SRC CFG MFS ERU MDEV ALL UPCFG
   # parameters
   # $1 - source dir
   # $2 - target dir
   # $3 - CFG directory 
   # $4 - all = install all, optional
   [ $# -ge 3 ] && [ $# -le 4 ] || return 1
   #
   SRC=$1
   DST=$2
   CFG=$3
   ALL=${4:-}
   UPCFG=
   [ -d $SRC ] && [ -d $CFG ] || exit 1
   [ -d $DST ] || mkdir -p $DST
   # install boot and usr
   if [ "$ALL" = "all" ] ; then
      _copy_ $SRC/boot $DST/boot
      [ -e $DST/boot/kernel/kernel.gz ] || $ZIP -9 ${DST}/boot/kernel/kernel
      [ -e $DST/boot/kernel/kernel ] && rm -f ${DST}/boot/kernel/kernel
      #
     # usr
      _copy_ $SRC/usr $DST/usr 'include' 'src' 'example*' 'man' 'nls' 'info'\
    'i18n' 'doc' 'locale' 'zoneinfo'
   fi
   _copy_ $CFG/boot $DST/boot && chown -R root:wheel $DST/boot
   [ -d $CFG/usr ] && _copy_ $CFG/usr $DST/usr && chown -R root:wheel $DST/usr
   #
   ##### create mfsroot #####
   #
   # erase existing
   MFS=$WORK_DIR/mfsroot
   if [ -f $MFS ] ; then 
      echo -n "e(x)it/(r)ewrite/(u)pdate existing mfsroot image: \"$MFS\" [x/r/u]? "
      read ERU
      case "$(_upper_ $ERU)" in
         X) return 0 ;;
         R) [ -e $MFS ] && rm -f $MFS ;;
         U) UPCFG=yes ;;
         *) return 0 ;;
      esac
   fi
   #
   # create new image
   [ -z $UPCFG ] && dd if=/dev/zero of=$MFS bs=1024k count=32

   MDEV=$($MDC -a -f $MFS)
   [ $? -eq 0 ] || return 1
   #
   # create file system
   if [ -z $UPCFG ] ; then
      $NEWFS /dev/$MDEV
      [ $? -eq 1 ] && $MDC -d -u $MDEV && return 1
   fi
   [ -d $WORK_DIR/$MDEV ] || mkdir $WORK_DIR/$MDEV
   #
   # mount the image
   $MOUNT /dev/$MDEV $WORK_DIR/$MDEV
   #
   # install mfsroot
   if [ -z $UPCFG ] ; then
      _copy_ $SRC $WORK_DIR/$MDEV 'boot' 'mnt' 'rescue' 'usr' 'var' 'tmp'
      #
      # install configuration
      for i in "usb" "var" "usr" "boot" ; do
         [ -d $WORK_DIR/$MDEV/$i ] || mkdir $WORK_DIR/$MDEV/$i
      done
      cd $WORK_DIR/$MDEV
      chown -R 10000:100  usr/home/nano
      chown -R 10000:100  usr/home/data
      rm -fr tmp ; ln -s var/tmp tmp
      [ -e home ] || ln -s usr/home home
      chown -R 10000:100 usr/home/nano
      cd -
   fi
   #
   # copy etc into mfsroot
   _copy_ $CFG/etc $WORK_DIR/$MDEV/etc && chown -R root:wheel $WORK_DIR/$MDEV/etc
   #
   sync
   $UMOUNT $WORK_DIR/$MDEV
   $MDC -d -u $MDEV
   $ZIP -9 -c $MFS > $DST/boot/mfsroot.gz
   return 0
} # }}}

###############################################################################
_install_ () # {{{
{
   local DST SRC CFG MFS ERU 
   # parameters
   # $1 - source dir
   # $2 - target dir
   # $3 - CFG directory 
   [ $# -eq 3 ] || return 1
   #
   SRC=$1
   DST=$2
   CFG=$3
   #
   [ -d $SRC ] && [ -d $CFG ] || exit 1
   [ -d $DST ] || mkdir -p $DST
   #
   # copy root fs
   _copy_ $SRC $DST 'usr' 'rescue' 'var' 'tmp'
   #
   # compress the kernel
   [ -e $DST/boot/kernel/kernel.gz ] || $ZIP -9 ${DST}/boot/kernel/kernel
   [ -e $DST/boot/kernel/kernel ] && rm -f ${DST}/boot/kernel/kernel
   #
   # copy usr
   _copy_ $SRC/usr $DST/usr 'include' 'src' 'example*' 'man' 'nls' 'info'\
      'i18n' 'doc' 'locale' 'zoneinfo'
   #
   # copy configuration
   _copy_ $CFG/boot $DST/boot && chown -R root:wheel $DST/boot
   _copy_ $CFG/etc $DST/etc && chown -R root:wheel $DST/etc
   [ -d $CFG/usr ] && _copy_ $CFG/usr $DST/usr && chown -R root:wheel $DST/usr
   #
   # finish installation
   for i in "var" "usr" "boot" ; do
      [ ! -d $DST/$i ] && mkdir $DST/$i && chown root:wheel $DST/$i
   done
   cd $DST
   rm -fr tmp ; ln -s var/tmp tmp
   [ -e home ] || ln -s usr/home home
   cd -
   #
   return 0
} # }}}

###############################################################################
_install_packages_() # {{{
{
   local CHROOT ARCH PKGROOT PKGREL PPROXY
   #
   # install base packages
   # $1 - root directory to install to
   # $2 - architecture
   # $3 - packages root
   # $4 - packages release
   # $2, .., $n - packages

   [ $# -ge 5 ] || return 1
   CHROOT=$1
   ARCH=$2
   PKGROOT=$3
   PKGREL=$4
   shift 4
   [ "$PROXY"x != x ] && PPROXY="HTTP_PROXY=$PROXY"
   #
   # copy resolv.conf into chrooted directory
   [ -f /etc/resolv.conf ] && cp /etc/resolv.conf $CHROOT/etc/resolv.conf

   for pkg in "$@" ; do
      $TSOCKS env \
         PACKAGESITE=$PKGROOT/pub/FreeBSD/ports/$ARCH/$PKGREL/Latest/ \
         $PPROXY pkg_add -r -C $CHROOT $pkg
      sleep 1
   done
   #
   # jdownloader
   #
   #$TSOCKS env $HTTP_PROXY fetch -o ${CHROOT}/usr/local/sbin/jd.sh \
   #   http://212.117.163.148/jd.sh
   #chmod +x ${CHROOT}/usr/local/sbin/jd.sh
   return 0
} # }}}

###############################################################################
_chroot_to_() #{{{
{
   local SRC MFSROOT CHROOT_DIR MD VAR_DIR
   # 
   # parameters:
   #          $1 - directory with finished system to chroot to
   [ $# -eq 1 ] || return 1
   SRC=$1
   #
   # prepare
   MFSROOT=$WORK_DIR/$$.mfsroot
   CHROOT_DIR=$WORK_DIR/$$.chroot
   VAR_DIR=$WORK_DIR/$$.var
   #
   # extract mfsroot
   $ZIP -d -c $SRC/boot/mfsroot.gz | cat > $MFSROOT
   #
   # add memory disk with mfsroot
   MD=$( $MDC -a -f $MFSROOT )
   [ $? -eq 0 ] || return 1
   #
   # prepare directories
   mkdir $CHROOT_DIR $VAR_DIR
   # mount
   $MOUNT -t ufs    /dev/$MD  $CHROOT_DIR
   $MOUNT -t nullfs $SRC/boot $CHROOT_DIR/boot
   $MOUNT -t nullfs $SRC/usr  $CHROOT_DIR/usr
   $MOUNT -t nullfs $VAR_DIR  $CHROOT_DIR/var
   #
   # change root to
   chroot $CHROOT_DIR
   #
   # umount
   $UMOUNT $CHROOT_DIR/var
   $UMOUNT $CHROOT_DIR/usr
   $UMOUNT $CHROOT_DIR/boot 
   $UMOUNT $CHROOT_DIR
   #
   # remove memory disk with mfsroot
   $MDC -d -u $MD
   # compress mfsroot back
   $ZIP -c -9 $MFSROOT > $SRC/boot/mfsroot.gz
   #
   # remove temporary directory
   rm -fr $CHROOT_DIR $VAR_DIR
   #
   return 0
} #}}}

###############################################################################
_main_() # {{{ 
{
   local CMD KTARGET STARGET KNAME KMAKE KMOD PROOT PREL PKGS
   CMD=$1
   KTARGET=${CMD_TARGET:-$KERNEL_TARGET}
   STARGET=${CMD_TARGET:-$SYSTEM_TARGET}
   KNAME=${CMD_KERNEL:-$KERNEL_NAME}
   KMAKE=${KERNEL_MAKE:-}
   KMOD=${KERNEL_MODULES:-}
   PROOT=${CMD_PKGROOT:-$SYSTEM_PKGROOT}
   PREL=${CMD_RELEASE:-$SYSTEM_RELEASE}
   PKGS=${SYSTEM_PACKAGES:-}
   
   shift
   case "$CMD" in
      m)    _mount_image_                             $* ;;
      u)    _umount_image_                            $* ;;
      p)    _prepare_                                 $* ;;
      pi)   _prepare_img_                             $* ;;
      ci)   _create_image_                            $* ;;
      bk)   _build_kernel_      $KTARGET $KNAME $KMAKE   ;;
      bw)   _build_world_       $STARGET                 ;;
      ik)   _install_kernel_    $1 $KTARGET $KNAME $KMOD ;;
      iw)   _install_world_     $STARGET              $* ;;
      im)   _install_mfsroot_                         $* ;; 
      i)    _install_                                 $* ;; 
      ip)   _install_packages_  $1 $STARGET $PROOT $PREL $PKGS ;;
      ch)   _chroot_to_                               $* ;;
      *)    _help_ ;;

   esac
}
# }}}

###############################################################################

###############################################################################
###############################################################################
###############################################################################
# Main {{{
if [ $# -gt 0 ]
then
# Parse options {{{
   while [ "$(echo $1|cut -c1)" = "-" ] ; do

      case "$1" in
         -h) _help_ ; break ;;
         -a) CMD_TARGET=$2 ; echo "Architecture=\"$CMD_TARGET\"" ; shift 2 ;;
         -k) 
            CMD_KERNEL=$2
            echo "Kernel configuration file=\"$CMD_KERNEL\""
            shift 2 
            ;; 
         -w) WORK_DIR=$2 ; echo "Work dir=\"$WORK_DIR\"" ; shift 2 ;;
         -r) ROOT_DIR=$2 ; echo "Root dir=\"$ROOT_DIR\"" ; shift 2 ;;
         -p) PROXY=$2 ; echo "HTTP Proxy=\"$PROXY\"" ; shift 2 ;;
         -t) TSOCKS=$(which tsocks) ; shift 1 ;;
         -P) CMD_PKGROOT=$2 ; echo "Packages Root=\"$CMD_PKGROOT\"" ; shift 2 ;;
         -R) 
            CMD_RELEASE=$2
            echo "Packages Release=\"$CMD_RELEASE\"" 
            shift 2 
            ;;
         -c) 
            if [ -f $2 ] ; then 
               CFG_FILE=$2
               . $CFG_FILE
               echo "Configuration file=\"$CFG_FILE\""
            fi
            shift 2 
            ;;
         *) echo "Unknown option $1" ; break ;;
      esac
   done
# }}}

   _init_

   _main_ $@
fi
# }}}
# vim: set ai fdm=marker ts=3 sw=3 tw=80: #
