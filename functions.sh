###############################################################################
_upper_() # {{{
{
   [ $# -gt 0 ] || return 1
   echo $* | tr '[:lower:]' '[:upper:]'
   return 0
} # }}}

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
_copy_() #{{{
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
      [ "$i"x = x ] && continue
      case "$i" in
         */) echo $i >> $EXFILE ;;
         *) [ "${i##*/}" = "*" ] && echo $i >> $EXFILE || echo $i/ >> $EXFILE ;;
      esac
   done

   rsync -avz --exclude-from=$EXFILE $SRC/ $DST
   [ -f $WORK_DIR/exclude.$$ ] && rm -f $WORK_DIR/exclude.$$ 
   return 0
} #}}}

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
   # $5, .., $n - packages

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

   for PKG in $@
   do
      $TSOCKS env \
         PACKAGESITE=$PKGROOT/pub/FreeBSD/ports/$ARCH/$PKGREL/Latest/ \
         $PPROXY pkg_add -r -C $CHROOT $PKG
   done
   sleep 1
   [ -e $CHROOT/etc/resolv.conf ] && rm -f $CHROOT/etc/resolv.conf
   return 0
} # }}}
