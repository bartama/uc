#!/usr/bin/env sh

set -x

WORK_DIR=/tmp
#
# basic system specification and sources
CMD_TARGET=
CMD_PKGROOT=
CMD_RELEASE=
#
# 
TSOCKS=
PROXY=

CFG_FILE=

. ./functions.sh

###############################################################################
_help_() # {{{ 
{
      cat << EOF
$0 { OPTIONS } [ CMD ] [ CMD_ARGS ]
where OPTIONS := { 
                  -h help
                  -c FILE_NAME      Configuration file name
                  -w WORK_DIR       [ $WORK_DIR ] 
                                    Working directory
                  -a TARGET_ARCH    Targe architecture
                  -P PACKAGE_ROOT   
                  -R RELEASE        
                  -p PROXY          HTTP proxy to use
                  -t                Use tsocks
                 }
      CMD     := { 
                   m SRC_DIR DST_DIR   // prepare mroot image
                   s SRC_DIR DST_DIR   // prepare skel image
                   j DST_DIR JAIL_NAME MROOT_DIR USR_DIR SKELETON CFG 
                                       // create jail directory 
                   i DST_DIR NAME      // install additional packages 
                     where NAME := { ns | www | dhcp | mail }
                 }
EOF
} #}}}

###############################################################################
_init_() # {{{ 
{
   return 0
} # }}}

###############################################################################
_prepare_mroot_() # {{{
{
   local SRC DST
   # copy necessary files from $SRC to $DST to compose mroot image
   # parameters:
   #             $1 - source directory
   #             $2 - destination directory
   #
   [ $# -eq 2 ] || return 1
   #
   # initialize
   SRC=$1
   DST=$2
   #
   # check if source directory exists
   [ -d $SRC ] || return 1
   #
   # copy base directories
   _copy_ $SRC $DST 'boot' 'etc' 'home' 'rescue/*' 'root' 'tmp' 'usr/*' 'var'
   #
   # create symbolic links
   cd $DST
   mkdir s
   ln -s usr/home home
   ln -s s/etc etc
   ln -s s/root root
   ln -s s/var var
   ln -s var/tmp tmp
   cd -
   #
   return 0
} # }}}

###############################################################################
_prepare_skel_() # {{{
{
   local SRC DST
   # copy necessary files from $SRC to $DST to compose skeleton image
   # parameters:
   #             $1 - source directory
   #             $2 - destination directory
   #
   [ $# -eq 2 ] || return 1
   #
   # initialize
   SRC=$1
   DST=$2
   #
   # check if source directory exists
   [ -d $SRC ] || return 1
   #
   # copy skel directories
   for i in var etc root
   do
      _copy_ $SRC/$i $DST/$i
   done
   #
   return 0
} # }}}

###############################################################################
_create_jail_() # {{{
{
   local DST NAME MROOT USR SKEL CFG PKGS TMP ARCH PROOT PREL
   # crate jail specific image based on provided skeleton and the jail's 
   # specific configuration
   # parameters:
   #     $1 - destination directory where to create the jail
   #     $2 - jail name 
   #     $3 - mroot directory
   #     $4 - usr directory
   #     $5 - skeleton template directory
   #     $6 - directory with configuration data for jails
   #     $7 - target architecture
   #     $8 - packages root
   #     $9 - packages release
   [ $# -eq 9 ] || return 1
   DST=$1 ; NAME=$( _case_ l $2 ) ; MROOT=$3 ;  USR=$4 ; SKEL=$5 ; CFG=$6
   ARCH=$7 ; PROOT=$8 ; PREL=$9
   #
   # basic checks
   [ -d $MROOT -a -d $SKEL -a -d $CFG ] || return 2
   echo $JAIL_ENABLE | grep $NAME || return 1
   #
   # prepare temporary target directory
   TMP=$WORK_DIR/$$.$NAME
   mkdir -p $TMP || return 1
   mount -t nullfs -o ro $MROOT $TMP
   mount -t devfs devfs $TMP/dev
   mount -t nullfs -o ro $USR   $TMP/usr
   mkdir -p ${TMP}_s/local
   # copy skeleton
   _copy_ $SKEL ${TMP}_s
   mount -t nullfs -o rw ${TMP}_s ${TMP}/s
   mount -t nullfs -o rw ${TMP}_s/local ${TMP}/usr/local
   #
   # install packages
   _install_packages_ $TMP $ARCH $PROOT $PREL \
      $( eval echo \$JAIL_"$( _case_ u $NAME)"_PKG )
   #
   # copy configuration
   rsync -avzKO --no-owner --no-group --exclude '*~' $CFG/$NAME/ $TMP
   #
   #finalize jail
   _copy_ ${TMP}_s $DST 'include' 'src' 'example*' 'man' 'nls' \
      'info' 'i18n' 'doc' 'locale' 'calendar' 'groff_font' 'mk' 'aclocal' \
      'share/emacs' 'share/gettext' 'gtk-doc' 'licenses' \
      'pc-sysinstall' 'snmp' 'share/tmac' 'share/games' 
   # cleanup
   umount ${TMP}/usr/local
   umount ${TMP}/s
   umount $TMP/usr
   umount $TMP/dev
   umount $TMP
   rm -fr ${TMP} ${TMP}_s
   return 0
} # }}}

###############################################################################
_main_() # {{{ 
{
   local CMD TARGET PKGROOT RELEASE
   CMD=$1 ; shift

   TARGET=${CMD_TARGET:-$SYSTEM_TARGET}
   PKGROOT=${CMD_PKGROOT:-$SYSTEM_PKGROOT}
   RELEASE=${CMD_RELEASE:-$SYSTEM_RELEASE}

   case "$CMD" in
      m)    _prepare_mroot_ $* ;;
      s)    _prepare_skel_  $* ;;
      j)    _create_jail_   $* $TARGET $PKGROOT $RELEASE    ;;
      i)    _install_packages_ $TARGET $PKGROOT $RELEASE $* ;;
      *)    _help_ ;;
   esac

   return 0
}
# }}}

###############################################################################
# Parse options {{{
while [ "$(echo $1|cut -c1)" = "-" ] ; do
   case "$1" in
      -h) _help_ ; return 1 ;;
      -w) WORK_DIR=$2 ; shift 2 ;;
      -a) CMD_TARGET=$2 ; echo "Architecture=\"$CMD_TARGET\"" ; shift 2 ;;
      -P) CMD_PKGROOT=$2 ; echo "Packages Root=\"$CMD_PKGROOT\"" ; shift 2 ;;
      -R) CMD_RELEASE=$2 ; echo "Packages Release=\"$CMD_RELEASE\"" ; shift 2 ;;
      -p) PROXY=$2 ; echo "HTTP Proxy=\"$PROXY\"" ; shift 2 ;;
      -t) TSOCKS=$(which tsocks) ; shift 1 ;;
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

###############################################################################
###############################################################################
###############################################################################
_init_ || exit 0

_main_ $@


# vim: set ai fdm=marker tw=80: #

