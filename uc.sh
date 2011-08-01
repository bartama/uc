#!/usr/bin/env sh

set -x

TARGET=amd64
KERN=NANO_LOCAL_GW_USB
MODULES="msdosfs pseudofs procfs nullfs linux ppc ppbus ppi if_vlan if_tun md \
   if_gif if_faith usb/uhid geom/geom_uzip vesa zlib wlan_wep wlan_ccmp \
   wlan_tkip wlan_amrr wlan_xauth usb/u3g usb/uhso ath if_bridge bridgestp drm"

PACKAGES="hal dbus xorg-minimal xf86-video-vesa xf86-input-mouse \
  xf86-input-keyboard xf86-video-intel xorg-server xorg-fonts-100dpi \
  xorg-fonts-75dpi xorg-fonts-truetype xorg-fonts-type1 urwfonts urwfonts-ttf \
  xdm xkbcomp xsm openbox rxvt-unicode midori thttpd openjdk6 freenx"

# x11vnc 

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

ROOT_DIR=/home/test
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

   [ "$($MOUNT | grep $DIR)"x != x ] && $UMOUNT $DIR
   DEV=$($MDC -lv | grep $IMG)
   [ "$DEV"x != x ] && $MDC -d -u $(echo "$DEV" | cut -f 1)
   return 0
}
# }}}

###############################################################################
_help_() # {{{ 
{
      cat << EOF
$0 { OPTIONS } [ CMD ] [ CMD_ARGS ]
where OPTIONS := { -a TARGET_ARCH [ targe architecture  ] |
		   -w WORK_DIR [ specify work directory ] |
		   -r ROOT_DIR [ specify root directory ] |
		   -p PROXY [ specify http proxy to use ] |
		   -t [ use tsocks for downloading packages ] }
      CMD     := { [ usb [m|u]           ]
		   [ mfs [m|u]           ]
		   [ usr [m|u|sync]      ]
		   [ var [m|u|c]         ]
		   [ bk|bw|ik|iw|ic|ip   ]
		   [ prepare             ]
		   [ install DEV         ]
		   [ install_zfs POOL    ] }
EOF
} #}}}

###############################################################################
_upper_() # {{{
{
   [ $# -gt 0 ] || return 1
   echo "$@" | tr '[:lower:]' '[:upper:]'
} # }}}

###############################################################################
_prepare_image_() # {{{
{
   # $1 - image name 
   # $2 - image size, optional 
   #
   local YESNO IMG_NAME IMG_SIZE
   #
   # defaults 
   IMG_NAME=
   IMG_SIZE=2048
   #
   # get arguments
   if   [ $# -eq 1 ] ; then IMG_NAME=$1
   elif [ $# -eq 2 ] ; then IMG_NAME=$1 ; IMG_SIZE=$2
   else return 1 ; fi

   if [ -f $IMG_NAME ] ; then
      echo -n "Rewrite existing image: \"$IMG_NAME\" [y/N]? "
      read YESNO
      [ $(_upper_ $YESNO) != "Y" ] && return 0
   fi
   [ -f $IMG_NAME ] && rm -f $IMG_NAME
   dd if=/dev/zero of=$IMG_NAME bs=1024k count=$IMG_SIZE
} # }}}

###############################################################################
_prepare_() # {{{
{
   _u_ usb
   _prepare_image_ $USB_IMG 2048

   $MDC -a -f $USB_IMG
   [ $? -eq 0 ] || return 1
   DEV=$($MDC -lv | grep $USB_IMG | cut -f1)
   $FDISK -BI /dev/$DEV
   [ $? -eq 0 ] || return 1
   boot0cfg -o noupdate $DEV
   boot0cfg -B $DEV
   boot0cfg -s 1 $DEV
   $BSDLABEL -Bw ${DEV}s1
   [ $? -eq 0 ] || return 1
   $NEWFS -U -O1 ${DEV}s1a
   [ $? -eq 0 ] || return 1
   sleep 1
   $MDC -d -u $DEV
   sleep 1
   # TODO
   #/usr/bin/env sh $0 ik
   #/usr/bin/env sh $0 iw
   # copy content of etc
   # tar -C $USB_DIR -xf $NANOETC
   #mergemaster -pi -D ${USB_DIR}
   #
} #}}}

###############################################################################
_prepare_zfs_() # {{{
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
   # create GPT geometry
   $GPART create -s gpt $DEV
   #
   # create slices
   $GPART gpart add -s 64K -t freebsd-boot $DEV
   # $GPART add -t freebsd $DEV
   $GPART add -t freebsd-zfs -l disk0 $DEV
   #
   # install pmbr 
   $GPART bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $DEV
   #
   # activate the partition
   #$GPART set -a active -i 1 $DEV
   #
   # create pool
   #$ZPOOL create $POOL /dev/${DEV}s1
   $ZPOOL create $POOL /dev/gpt/disk0
   #
   # install boot manager
   gpart bootcode -b /boot/boot0 $DEV
   #
   # export pool
   $ZPOOL export $POOL
   #
   # install boot1 stage
   dd if=/boot/zfsboot of=/dev/${DEV}s1 count=1
   #
   # install boot2 stage
   dd if=/boot/zfsboot of=/dev/${DEV}s1 skip=1 seek=1024
   #
   # import pool
   $ZPOOL import $POOL
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
   #
   # export pool
   sleep 3
   $ZPOOL export $POOL

} #}}}

###############################################################################
_install_boot_ () # {{{
{
   local DST SRC LDR MFS YESNO MDEV
   # parameters
   # $1 - target dir
   # $2 - source dir
   # $3 - loader 
   [ $# -eq 3 ] || return 1
   [ -d $DST ] && [ -d $SRC ] && [ -f $LDR ] || exit 1
   #
   # install kernel
   cp -pvr $DST/boot $SRC/boot
   [ -e $DST/boot/kernel/kernel.gz ] || ZIP -9 ${DST}/boot/kernel/kernel
   [ -e $DST/boot/loader.conf ] || cp -pv $LDR $DST/boot/
   #
   ##### create mfsroot #####
   #
   # erase existing
   MFS=$WORK_DIR/mfsroot
   if [ -f $MFS ] ; then 
      echo -n "Rewrite existing mfsroot image: \"$MFS\" [y/N]? "
      read YESNO
      [ $(_upper_ $YESNO) != "Y" ] && return 0
   fi
   [ -e $MFS ] && rm -f $MFS
   #
   # create new image
   dd if=/dev/zero of=$MFS bs=1024 count bs=32
   MDEV=$($MDC -a -f $MFS)
   [ $? -eq 0 ] || return 1
   #
   # create file system
   $NEWFS -O1 /dev/$MDEV
   [ $? -eq 1 ] && $MDC -d -u $MDEV && return 1
   [ -d /dev/$MDC ] || mkdir /dev/$MDC
   #
   # mount the image
   $MOUNT /dev/$MDEV /tmp
   #
   # install mfsroot
   tar --exclude 'boot/*' --exclude 'mnt/*' --exclude 'rescue/*' \
       --exclude 'usr/*' --exclude 'var/*' -C $SRC \
       -cf - ./ | tar -C /dev/$MDC -xvf -
   sleep 1
   $UMOUNT /dev/$MDC
   $MDC -d -u $MDEV
   $ZIP -9 -c $MFS > $DST/boot/mfsroot.gz
   return 0
} # }}}

###############################################################################
_install_zfs_() # {{{
{
   local POOL SRC
   # parameters
   # $1 - pool name
   # $2 - source image name
   #
   [ $# -eq 2 ] || return 1
   POOL=$1
   SRC=$2

   zpool import $POOL

   [ -d "/$POOL" ] || return 1

   # TODO

   #
   # loader.conf
   cp $ROOT_DIR/loader.conf.zfs /$POOL/boot/loader.conf
   sleep 5
   zpool export -f $POOL
} # }}}

###############################################################################
_install_packages_() # {{{
{
   _m_ usb
   #
   # install base packages
   # xorg
   #
   [ -e ${USB_DIR}/etc/resolv.conf ] || cp /etc/resolv.conf ${USB_DIR}/etc/resolv.conf
   for pkg in $PACKAGES ; do
      $TSOCKS env PACKAGEROOT=http://ftp.cz.freebsd.org HTTP_PROXY=$PROXY pkg_add -r -C $USB_DIR $pkg
      sleep 1
   done
   #
   # jdownloader
   #

   $TSOCKS env HTTP_PROXY=$PROXY fetch -o ${USB_DIR}/usr/local/sbin/jd.sh \
      http://212.117.163.148/jd.sh
   chmod +x ${USB_DIR}/usr/local/sbin/jd.sh
   #
   _u_ usb
}
# }}}

###############################################################################
_main_() # {{{ 
{
   case "$1" in
      usb|mfs)
	 case $2 in
	    m|M) _m_ $1 ;;
	    u|U) _u_ $1 ;;
	    *) echo "Invalid command $1" ;;
	 esac
	 ;;
      usr)
	 case $2 in
	    m|M) _m_ $1 ;;
	    u|U) _u_ $1 ;;
	    sync)
	       _m_ $1
   #           tar --exclude 'src/*' --exclude 'obj/*' --exclude 'ports/*' -C /usr -c -f - ./ | tar -C $USR_DIR -vx -f -
	       rsync -avz  --exclude 'src/*' --exclude 'obj/*' --exclude 'ports/*' ${WORK_DIR}/world/usr/ $USR_DIR/usr
   #           env TARGET_ARCH=${TARGET} \
   #            make installworld DESTDIR=${NANO_WORLDDIR} 
	       _u_ $1
	       ;;
	    *) echo "Invalid command $1" ;;
	 esac
	 ;;
      var)
	 case $2 in
	    m|M) _m_ $1 ;;
	    u|U) _u_ $1 ;;
	    c|C)
	       _m_ mfs
	       ZIP -c -9 $VAR_IMG > ${MFS_DIR}/var.gz
	       _u_ mfs
	       ;;
	    *) echo "Invalid command $1" ;;
	 esac
	 ;;
      bk)
   #      env TARGET_ARCH=$TARGET make buildkernel KERNCONF=$KERN
   #      env TARGET_ARCH=$TARGET make buildkernel KERNCONF=$KERN -DKERNFAST
	 cd /usr/src && env TARGET_ARCH=$TARGET make buildkernel KERNCONF=$KERN #-DNO_KERNELCLEAN
	 ;;
      bw)
	 cd /usr/src && env TARGET_ARCH=$TARGET make buildworld ;;
      ik)
	 _m_ usb
	 cd /usr/src
	 #env TARGET_ARCH=$TARGET make installkernel KERNCONF=$KERN DESTDIR=$USB_DIR MODULES_OVERRIDE="$MODULES"
	 env TARGET_ARCH=$TARGET make installkernel KERNCONF=$KERN DESTDIR=$USB_DIR 
	 #ZIP -9 ${USB_DIR}/boot/kernel/kernel
   #      rsync --exclude 'kernel/' -avz /boot/* $USB_DIR/boot
	 cp  $LOADER $USB_DIR/boot/
	 sync
	 _u_ usb
	 ;;
      ik_zfs)
	 POOL=$2
	 $ZPOOL import $POOL
	 sleep 1
	 [ -d /$POOL ] || break;
	 cd /usr/src
	 env TARGET_ARCH=$TARGET make installkernel KERNCONF=$KERN DESTDIR=/$POOL
	 cp ${LOADER}.zfs /$POOL/boot/loader.conf
	 sleep 2
	 $ZPOOL export $POOL
	 ;;
      iw)
	 _m_ usb
	 cd /usr/src && env TARGET_ARCH=$TARGET make installworld DESTDIR=$USB_DIR
	 mergemaster -i -D ${USB_DIR}
	 #cp /etc/resolv.conf ${USB_DIR}/etc/resolv.conf
	 #
	 [ -e $USB_DIR/tmp ] && [ ! -s $USB_DIR/tmp ]  && rm -fr $USB_DIR/tmp
	 cd $USB_DIR && ln -s var/tmp tmp
	 # TODO 
	 # home -> usr/home
	 sync
	 _u_ usb
	 ;;
      ie)
	 _m_ usb
	 [ -f $ROOT_DIR/etc.tar ] && tar -v -C $USB_DIR -xf $ROOT_DIR/etc.tar
	 ;;
      ic)
	 _m_ usb
	 cp  $LOADER $USB_DIR/boot/
	 sync
	 _u_ usb
	 ;;
      install)
	 if [ -e "$2" ] ; then
	    [ -d $DST_DIR ] || mkdir $DST_DIR
	    # sync boot
	    _m_ usb
	    mount ${2}s1a $DST_DIR
	    rsync -av $USB_DIR/ $DST_DIR
	    umount $DST_DIR
	    _u_ usb
	 fi
	 ;;
      prepare_zfs) _prepare_zfs_ $2 $3 ;;
      install_zfs) _install_zfs_ $2 $3 ;;
      prepare)     _prepare_  ;;
      ip)          _install_packages_ ;;
      *)           _help_ ;;

   esac
}
# }}}

###############################################################################
# Parse options {{{
while [ "$(echo $1|cut -c1)" = "-" ] ; do

   case "$1" in
      -a) TARGET=$2 ; echo "Architecture=\"$TARGET\"" ; shift 2 ;;
      -w) WORK_DIR=$2 ; echo "Work dir=\"$WORK_DIR\"" ; shift 2 ;;
      -r) ROOT_DIR=$2 ; echo "Root dir=\"$ROOT_DIR\"" ; shift 2 ;;
      -p) PROXY=$2 ; echo "HTTP Proxy=\"$PROXY\"" ; shift 2 ;;
      -t) TSOCKS=$(which tsocks) ; shift 1 ;;
      *) echo "Unknown option $1" ;;
   esac
done
# }}}


_init_

_main_ $@
