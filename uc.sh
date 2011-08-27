#!/usr/bin/env sh

set -x

###############################################################################
# defaults
#
TARGET=amd64
PKGROOT="http://ftp.cz.freebsd.org"
RELEASE="packages-9-current"
KERN=NANO
MODULES="msdosfs pseudofs procfs nullfs linux ppc ppbus ppi if_vlan if_tun md \
   if_gif if_faith usb/uhid geom/geom_uzip geom/geom_label \
   geom/geom_part/geom_part_gpt vesa zlib wlan_wep wlan_ccmp wlan_tkip \
   wlan_amrr wlan_xauth usb/u3g usb/uhso ath if_bridge bridgestp"

#PACKAGES="hal dbus xorg-minimal xf86-video-vesa xf86-input-mouse \
#  xf86-input-keyboard xf86-video-intel xorg-server xorg-fonts-100dpi \
#  xorg-fonts-75dpi xorg-fonts-truetype xorg-fonts-type1 urwfonts urwfonts-ttf \
#  xkbcomp xsm openbox rxvt-unicode midori thttpd openjdk6 freenx \
#  isc-dhcp41-server"

PACKAGES="isc-dhcp42-server thttpd"

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

ROOT_DIR=$PWD
WORK_DIR=/tmp
USB_IMG=usb.img
USB_DIR=usb

MFS_IMG=mfsroot
MFS_DIR=mfsroot

USR_IMG=$USB_IMG
USR_DIR=usr

VAR_IMG=var.img
VAR_DIR=var

DST_DIR=dst

LOADER=loader.conf
NANOETC=etc.tar.gz

###############################################################################
_init_() # {{{ 
{
   USB_IMG=${ROOT_DIR}/$USB_IMG
   USB_DIR=${WORK_DIR}/$USB_DIR

   MFS_IMG=${ROOT_DIR}/$MFS_IMG
   MFS_DIR=${WORK_DIR}/$MFS_DIR

   USR_IMG=$USB_IMG
   USR_DIR=${WORK_DIR}/$USR_DIR

   VAR_IMG=${ROOT_DIR}/$VAR_IMG
   VAR_DIR=${WORK_DIR}/$VAR_DIR

   DST_DIR=${WORK_DIR}/$DST_DIR

   LOADER=${ROOT_DIR}/$LOADER
   NANOETC=${ROOT_DIR}/$NANOETC
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
_m_() # {{{ 
{
   local DIR IMG DEV RETVAL
   RETVAL=0
   case "$1" in
      usb) DIR=$USB_DIR ; IMG=$USB_IMG ; DEV=s1a ;;
      usr) DIR=$USR_DIR ; IMG=$USR_IMG ; DEV=s1a ;;
      mfs) DIR=$MFS_DIR ; IMG=$MFS_IMG ; DEV=  ;;
      var) DIR=$VAR_DIR ; IMG=$VAR_IMG ; DEV=  ;;
      *) return 1;
   esac

   [ -e $DIR ] || mkdir $DIR
   if [ "$($MOUNT | grep $DIR)"x = x ] ; then
      if [ "$($MDC -lv | grep $IMG)"x = x ] ; then
         DEV=/dev/$($MDC -a -f $IMG)${DEV}
         sleep 1
      else
         DEV=/dev/$($MDC -lv | grep $IMG | cut -f1)${DEV}
      fi
      $MOUNT ${DEV} $DIR
      RETVAL=$?
   fi
   return $RETVAL
}
# }}}

###############################################################################
_u_() # {{{ 
{
   local DIR IMG DEV
   case "$1" in
      usb) DIR=$USB_DIR ; IMG=$USB_IMG ;;
      usr) DIR=$USR_DIR ; IMG=$USR_IMG ;;
      mfs) DIR=$MFS_DIR ; IMG=$MFS_IMG ;;
      var) DIR=$VAR_DIR ; IMG=$VAR_IMG ;;
      *) return 1;
   esac

   [ "$($MOUNT | grep $DIR)"x != x ] && sync && $UMOUNT $DIR
   DEV=$($MDC -lv | grep $IMG)
   [ "$DEV"x != x ] && sync && $MDC -d -u $(echo "$DEV" | cut -f 1)
   return 0
}
# }}}

###############################################################################
_help_() # {{{ 
{
      cat << EOF
$0 { OPTIONS } [ CMD ] [ CMD_ARGS ]
where OPTIONS := { 
         -h help
         -a TARGET_ARCH     [ $TARGET ] 
                            Targe architecture
         -k KERNEL          [ $KERN ] 
                            Kernel configuration file
         -w WORK_DIR        [ $WORK_DIR ] 
                            Working directory
         -r ROOT_DIR        [ $ROOT_DIR ]
                            Root directory
         -p PROXY           HTTP proxy to use
         -t                 Use tsocks
         -P PACKAGE_ROOT    [ $PKGROOT ]
         -R RELEASE         [ $RELEASE ]
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
         im SRC_DIR DST_DIR CFG_DIR   // install boot, mfsroot and usr
         ip DEST_DIR                  // install packages
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
   # install pmbr 
   $GPART bootcode -p /boot/gptzfsboot -i 1 $DEV || return 1
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
   local ARCH KERNEL
   #
   # $1 - architecture
   # $2 - kernel configuration
   #
   [ $# -eq 2 ] || return 1
   ARCH=$1
   KERNEL=$2
   cd /usr/src && env TARGET_ARCH=$ARCH make buildkernel KERNCONF=$KERNEL
   #-DNO_KERNELCLEAN -DKERNFAST
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
   local ARCH KERNEL DEST
   # params
   # $1 - arch
   # $2 - kernel
   # $3 - dest dir
   [ $# -eq 3 ] || return 1
   ARCH=$1
   KERNEL=$2
   DEST=$3

   cd /usr/src && \
      env TARGET_ARCH=$ARCH make installkernel KERNCONF=$KERNEL DESTDIR=$DEST \
      MODULES_OVERRIDE="$MODULES"
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
   [ -e $DEST/tmp ] && [ ! -s $DEST/tmp ] && rm -fr $DEST/tmp
   cd $DEST && ln -s var/tmp tmp
   #
   # home -> usr/home
   [ -e $DEST/home ] && [ ! -s $DEST/home ] && rm -fr $DEST/home
   cd $DEST && ln -s usr/home home
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
   _copy_ $CFG/boot $DST/boot
   _copy_ $CFG/usr $DST/usr
   chown -R root:wheel $DST/boot $DST/usr
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
   _copy_ $CFG/etc $WORK_DIR/$MDEV/etc
   _copy_ $CFG/cfg $WORK_DIR/$MDEV/cfg
   chown -R root:wheel $WORK_DIR/$MDEV/etc $WORK_DIR/$MDEV/cfg
   #
   sync
   $UMOUNT $WORK_DIR/$MDEV
   $MDC -d -u $MDEV
   $ZIP -9 -c $MFS > $DST/boot/mfsroot.gz
   return 0
} # }}}

###############################################################################
_install_packages_() # {{{
{
   local CHROOT HTTP_PROXY
   #
   # install base packages
   # $1 - root directory to install to

   [ $# -eq 1 ] || return 1
   CHROOT=$1
   [ "$PROXY"x != x ] && HTTP_PROXY="HTTP_PROXY=$PROXY"

   for pkg in $PACKAGES ; do
      $TSOCKS env
      PACKAGESITE=$PKGROOT/pub/FreeBSD/ports/$TARGET/$RELEASE/Latest/ \
    $HTTP_PROXY pkg_add -r -C $CHROOT $pkg
      sleep 1
   done
   #
   # jdownloader
   #

   $TSOCKS env $HTTP_PROXY fetch -o ${CHROOT}/usr/local/sbin/jd.sh \
      http://212.117.163.148/jd.sh
   chmod +x ${CHROOT}/usr/local/sbin/jd.sh
   return 0
} # }}}

###############################################################################
_main_() # {{{ 
{
   local CMD
   CMD=$1
   shift
   case "$CMD" in
      m)    _mount_image_                       $* ;;
      u)    _umount_image_       $* ;;
      p)    _prepare_                           $* ;;
      pi)   _prepare_img_                       $* ;;
      ci)   _create_image_                      $* ;;
      bk)   _build_kernel_        $TARGET $KERN    ;;
      bw)   _build_world_         $TARGET          ;;
      ik)   _install_kernel_      $TARGET $KERN $* ;;
      iw)   _install_world_       $TARGET       $* ;;
      im)   _install_mfsroot_                   $* ;; 
      ip)   _install_packages_                  $* ;;
      *)    _help_ ;;

   esac
}
# }}}

###############################################################################
# Parse options {{{
while [ "$(echo $1|cut -c1)" = "-" ] ; do

   case "$1" in
      -h) _help_ ; break ;;
      -a) TARGET=$2 ; echo "Architecture=\"$TARGET\"" ; shift 2 ;;
      -k) KERN=$2 ; echo "Kernel configuration=\"$KERN\"" ; shift 2 ;; 
      -w) WORK_DIR=$2 ; echo "Work dir=\"$WORK_DIR\"" ; shift 2 ;;
      -r) ROOT_DIR=$2 ; echo "Root dir=\"$ROOT_DIR\"" ; shift 2 ;;
      -p) PROXY=$2 ; echo "HTTP Proxy=\"$PROXY\"" ; shift 2 ;;
      -t) TSOCKS=$(which tsocks) ; shift 1 ;;
      -P) PKGROOT=$2 ; echo "Packages Root=\"$PKGROOT\"" ; shift 2 ;;
      -R) RELEASE=$2 ; echo "Packages Release=\"$RELEASE\"" ; shift 2 ;;
      *) echo "Unknown option $1" ; break ;;
   esac
done
# }}}


_init_

_main_ $@

# vim: set ai fdm=marker ts=3 sw=3 tw=80: #
