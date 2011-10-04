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

###############################################################################
_help_() # {{{ 
{
      cat << EOF
$0 { OPTIONS } [ CMD ] [ CMD_ARGS ]
where OPTIONS := { 
		  -h help
		  -c FILE_NAME	    Configuration file name
		  -w WORK_DIR	    [ $WORK_DIR ] 
				    Working directory
		  -a TARGET_ARCH    Targe architecture
		  -P PACKAGE_ROOT   
		  -R RELEASE	    
		  -p PROXY	    HTTP proxy to use
		  -t		    Use tsocks
                 }
      CMD     := { 
                   m SRC_DIR DST_DIR   // prepare mroot image
		   s SRC_DIR DST_DIR   // prepare skel image
		   j DST_DIR NAME MROOT SKELETON CFG // create jail directory 
		   i DST_DIR NAME      // install additional packages 
		     where NAME := { ns | www | dhcp | mail }
                 }
EOF
} #}}}

###############################################################################
_case_() # {{{
{
   local CASE
   [ $# -gt 0 ] || return 1
   CASE=$( echo $1 | tr '[:upper:]' '[:lower:]' )
   shift
   case $CASE in
      l|lo|low|lowe|lower) echo $* | tr '[:upper:]' '[:lower:]' ;;
      u|up|upp|uppe|upper) echo $* | tr '[:lower:]' '[:upper:]' ;;
      *) return 1 ;;
   esac
   return 0
} # }}}

###############################################################################
_copy_() # {{{
{
   local SRC DST EXFILE 
   #
   # copy directory using rsync without excluded patterns 
   # parameters:
   #             $1 - source directory
   #             $2 - destination directory
   #             $3,..,$n - exclude patterns
   #
   [ $# -ge 2 ] || return 1
   SRC=$1 ; DST=$2 ; shift 2
   EXFILE=$WORK_DIR/exclude.$$

   [ -d $SRC ] || return 1
   [ -d $DST ] || mkdir -p $DST

   echo '*~' > $EXFILE
   for i in $* ; do
      [ "$i"x != x ] && echo $i/ >> $EXFILE
   done
   
   rsync -avzKO --exclude-from=$EXFILE $SRC/ $DST
   return 0
} # }}}

###############################################################################
_init_() # {{{ 
{
   return 0
} # }}}

###############################################################################
_install_packages_() # {{{
{
   local CHROOT ARCH PROOT PREL PACKAGES NAME PKG
   #
   # install base packages
   # $1 - root directory to install to
   # $2 - target architecture
   # $3 - packages root 
   # $4 - packages release
   # $5, ..., $n - packages

   [ $# -ge 5 ] || return 1
   CHROOT=$1 ; ARCH=$2 ; PROOT=$3 ; PREL=$4
   shift 4
   PACKAGES="$@"

   [ x"$PACKAGES" != x ] || return 0

   cp /etc/resolv.conf $CHROOT/etc/
   for PKG in "$PACKAGES"
   do
      $TSOCKS env \
	 PACKAGESITE=$PROOT/pub/FreeBSD/ports/$ARCH/$PREL/Latest/ \
	 HTTP_PROXY=$PROXY pkg_add -r -C $CHROOT $PKG
   done
   [ -e $CHROOT/resolv.conf ] && rm -f $CHROOT/resolv.conf
   #
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
   _copy_ $SRC $DST 'boot' 'etc' 'home' 'media' 'mnt' 'proc' \
      'rescue' 'root' 'tmp' 'var' \
      'games' 'include' 'local' 'obj' 'share' 'src'
   #
   # create missing directories and skeleton directories
   mkdir -p $DST/usr/home $DST/s
   #
   # create symbolic links
   cd $DST
   ln -s usr/home home
   ln -s s/etc etc
   ln -s s/usr/local usr/local
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
   mkdir -p $DST/usr/local
   _copy_ $SRC/var $DST/var
   _copy_ $SRC/etc $DST/etc/
   _copy_ $SRC/root $DST/root
   #
   return 0
} # }}}

###############################################################################
_create_jail_() # {{{
{
   local DST NAME MROOT SKEL CFG PKGS TMP ARCH PROOT PREL
   # crate jail specific image based on provided skeleton and the jail's 
   # specific configuration
   # parameters:
   #	 $1 - destination directory where to create the jail
   #	 $2 - jail name 
   #	 $3 - mroot directory
   #	 $4 - skeleton template directory
   #	 $5 - directory with configuration data for jails
   #	 $6 - target architecture
   #     $7 - packages root
   #     $8 - packages release
   [ $# -eq 8 ] || return 1
   DST=$1 ; NAME=$( _case_ l $2 ) ; MROOT=$3 ;  SKEL=$4 ; CFG=$5
   test -d $MROOT -a -d $SKEL -a -d $CFG || return 2
   case $NAME in
      ns|www|dhcp|mail) break ;;
      *) return 1 ;;
   esac
   #
   # prepare temporary target directory
   TMP=$WORK_DIR/$$.$NAME
   mkdir -p $TMP || return 1
   mount -t nullfs -o ro $MROOT $TMP
   mkdir -p ${TMP}_s
   # copy skeleton
   _copy_ $SKEL ${TMP}_s
   mount -t nullfs -o rw ${TMP}_s ${TMP}/s
   #
   # install packages
   _install_packages_ $TMP $6 $7 $8 $( eval echo \$JAIL_"$( _case_ u $NAME)"_PKG )
   #
   # copy configuration
   rsync -avzKO --no-owner --no-group --exclude '*~' $CFG/$NAME/ $TMP
   #
   #finalize jail
   _copy_ ${TMP}_s $DST 'include' 'src' 'example*' 'man' 'nls' 'info'\
      'i18n' 'doc' 'locale' 'zoneinfo'
   # cleanup
   umount ${TMP}/s
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

