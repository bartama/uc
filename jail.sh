#!/usr/bin/env sh

#set -x

WORK_DIR=/tmp
#
# basic system specification and sources
TARGET=i386
PKGROOT="http://ftp.cz.freebsd.org"
RELEASE="packages-9-current"
#
# 
TSOCKS=
PROXY=
#
# define additional packages to be installed
PKG_NS=
PKG_WWW="thttpd python27 zodb-py27"
PKG_DHCP="isc-dhcp42-server"
PKG_MAIL=

###############################################################################
_help_() # {{{ 
{
      cat << EOF
$0 { OPTIONS } [ CMD ] [ CMD_ARGS ]
where OPTIONS := { 
		  -h help
		  -w WORK_DIR	    [ $WORK_DIR ] 
				    Working directory
		  -a TARGET_ARCH    [ $TARGET ] 
				    Targe architecture
		  -P PACKAGE_ROOT   [ $PKGROOT ]
		  -R RELEASE	    [ $RELEASE ]
		  -p PROXY	    HTTP proxy to use
		  -t		    Use tsocks
                 }
      CMD     := { 
                   m SRC_DIR DST_DIR   // prepare mroot image
		   s SRC_DIR DST_DIR   // prepare skel image
		   j DST_DIR NAME SKELETON CFG // create jail directory 
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
   
   rsync -avz --exclude-from=$EXFILE $SRC/ $DST
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
   local CHROOT PACKAGES NAME PKG
   #
   # install base packages
   # $1 - root directory to install to
   # $2 - packages set

   [ $# -eq 2 ] || return 1
   CHROOT=$1
   NAME=$( _case_ u $2 )
   PACKAGES=$( eval echo \$PKG_$NAME)

   [ x"$PACKAGES" != x ] || return 1

   for PKG in "$PACKAGES"
   do
      $TSOCKS env \
	 PACKAGESITE=$PKGROOT/pub/FreeBSD/ports/$TARGET/$RELEASE/Latest/ \
	 HTTP_PROXY=$PROXY pkg_add -r -C $CHROOT $PKG
   done
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
   local DST NAME SKEL CFG PKGS
   # crate jail specific image based on provided skeleton and the jail's 
   # specific configuration
   # parameters:
   #             $1 - destination directory where to create the jail
   #             $2 - jail name := { ns | http | dhcp }
   #             $3 - skeleton template directory
   #             $4 - directory with configuration data for jails
   [ $# -eq 4 ] || return 1
   DST=$1 ; NAME=$( _case_ l $2 ) ; SKEL=$3 ; CFG=$4
   test -d $SKEL -a -d $CFG || return 1
   case $NAME in
      ns|www|dhcp) break ;;
      *) return 1 ;;
   esac
   #
   # copy skeleton
   _copy_ $SKEL $DST
   #
   # copy configuration
   _copy_ $CFG/$NAME $DST
   #
   return 0
} # }}}

###############################################################################
_main_() # {{{ 
{
   local CMD
   CMD=$1
   shift
   case "$CMD" in
      m)    _prepare_mroot_ $* ;;
      s)    _prepare_skel_  $* ;;
      j)    _create_jail_   $* ;;
      i)    _install_packages_ $* ;;
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
      -a) TARGET=$2 ; echo "Architecture=\"$TARGET\"" ; shift 2 ;;
      -P) PKGROOT=$2 ; echo "Packages Root=\"$PKGROOT\"" ; shift 2 ;;
      -R) RELEASE=$2 ; echo "Packages Release=\"$RELEASE\"" ; shift 2 ;;
      -p) PROXY=$2 ; echo "HTTP Proxy=\"$PROXY\"" ; shift 2 ;;
      -t) TSOCKS=$(which tsocks) ; shift 1 ;;
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

