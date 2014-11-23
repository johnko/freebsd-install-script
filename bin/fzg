#!/bin/sh

######################################################################
# Script version is YYmmdd-HHMM in UTC, date +%y%m%d-%H%M%S
######################################################################
SCRIPTVERSION=141123-205948

######################################################################
# Variables you can edit / pass
######################################################################

: ${rpool:=pool}
: ${bpool:=bootpool}
: ${raidtype:=stripe}
: ${mnt:=/mnt}
: ${mfsmnt:=/mnt2}
: ${bsize:=2g}
: ${bename:=rfs}
: ${bfsname:=default}
: ${ssize:=2g}
: ${release:=10.1-RELEASE}
: ${distsite:="http://ftp4.freebsd.org/pub/FreeBSD/releases"}

######################################################################
# Usage
######################################################################

usage() {
  cat <<EOF
usage: $0 -d disk [-d disk ...] [-e disk]
       [-b boot_size] [-f] [-h] [-m] [-M /mnt] [-p poolname]
       [-r stripe|mirror|raidz|raidz2|raidz3] [-s swap_size] [-v]
       [-z pool_size]

       -b size  Boot partition size.
       -d disk  Disk to install on (eg. da0).
       -e disk  Attach to this existing disk that is part of -p pool.
       -f       Force export of existing pool.
       -h       Help.
       -m       Create mfsroot type of system.
       -M mount Mountpoint, if not using /mnt.
       -p name  ZFS pool name, must be unique.
       -r       Select ZFS raid mode if multiple -d given.
       -s size  Swap partition size.
       -v       Version.
       -z       ZFS pool size.

examples:

  Install on disk 0:
       $0 -d ada0 -z 2g -p mini

  Add disk 1 as mirror to an existing pool that contains disk ada0:
       $0 -e ada0 -z 2g -p mini -d ada1

other examples:

  Install on 3 mirror disks, a boot pool 1 GB, swap 1 GB, ZFS root pool 2 GB:
       $0 -d ada0 -d ada1 -d ada2 -b 1g -s 1g -z 2g -r mirror

  Make a bootable ZFS USB, which loads as mfs:
       $0 -d da0 -m -p usb
  Note we change the pool name so they don't conflict.

  Minimal mirror mfs server:
       $0 -d ada0 -d ada1 -z 2g -f -m -p mini
EOF
}

exiterror() {
  echo "ERROR: Exit code $1"
  exit $1
}

######################################################################
# Options parsing
# modified from https://github.com/mmatuska/mfsbsd
######################################################################

while getopts b:d:e:p:r:s:M:z:mfvh o; do
  case "$o" in
    b) bsize="$OPTARG" ;;
    d) disks="$disks ${OPTARG##/dev/}" ;;
    e) edisk="$OPTARG" ; ADDTOPOOL=1 ;;
    p) rpool="$OPTARG" ; bpool="boot${rpool}" ;;
    r) raidtype="$OPTARG" ;;
    s) ssize="$OPTARG" ;;
    M) mnt="$OPTARG" ;;
    z) zsize="$OPTARG" ;;
    m) MAKEMFSROOT=1 ;;
    f) FORCEEXPORT=1 ;;
    v) echo $SCRIPTVERSION ; exit 1 ;;
    h) usage; exit 1 ;;
    [?]) usage; exit 1 ;;
  esac
done

######################################################################
# Disk parsing for testing raid type
# modified from https://github.com/mmatuska/mfsbsd
######################################################################

if [ -z "$ADDTOPOOL" -o "$ADDTOPOOL" = "0" ]; then
  count=$( echo "$disks" | wc -w | awk '{ print $1 }' )
  if [ "$count" -lt "3" -a "$raidtype" = "raidz" ]; then
    echo "Error: raidz needs at least three devices (-d switch)" ; exit 1
  elif [ "$count" -lt "4" -a "$raidtype" = "raidz2" ]; then
    echo "Error: raidz2 needs at least four devices (-d switch)" ; exit 1
  elif [ "$count" -lt "5" -a "$raidtype" = "raidz3" ]; then
    echo "Error: raidz3 needs at least five devices (-d switch)" ; exit 1
  elif [ "$count" = "1" -a "$raidtype" = "mirror" ]; then
    echo "Error: mirror needs at least two devices (-d switch)" ; exit 1
  elif [ "$count" = "2" -a "$raidtype" != "mirror" ]; then
    echo "Notice: two drives selected, automatically choosing mirror mode"
    raidtype="mirror"
  elif [ "$count" -gt "2" -a "$raidtype" != "mirror" -a "$raidtype" != "raidz" \
    -a "$raidtype" != "raidz2" -a "$raidtype" != "raidz3" ]; then
    echo \
    "Error: please choose raid mode with the -r switch (mirror or raidz{1,2,3})"
    exit 1
  fi
fi

######################################################################
# If force, delete pools and detach partition 3 and 4
######################################################################

if [ -z "$ADDTOPOOL" -o "$ADDTOPOOL" = "0" ]; then
  if [ "$FORCEEXPORT" ]; then
    ########## have to export bpool before rpool
    zpool status $bpool >/dev/null 2>&1 && zpool export -f $bpool
    zpool status $rpool >/dev/null 2>&1 && zpool export -f $rpool
    for D in $disks ; do
      test -e /dev/${D}p3.eli && geli detach ${D}p3
      test -e /dev/${D}p4.eli && geli detach ${D}p4
    done
  fi
fi

######################################################################
# Quit if pools exist, but if ADDTOPOOL, quit if not exist
######################################################################

if [ -z "$ADDTOPOOL" -o "$ADDTOPOOL" = "0" ]; then
  if zpool status $rpool >/dev/null 2>&1 ; then
    echo "ERROR: A pool named $rpool already exists."
    exit 1
  fi
  if zpool status $bpool >/dev/null 2>&1 ; then
    echo "ERROR: A pool named $bpool already exists."
    exit 1
  fi
elif [ "$ADDTOPOOL" = "1" ]; then
  if ! zpool status $rpool >/dev/null 2>&1 ; then
    echo "ERROR: A pool named $rpool doesn't exists."
    exit 1
  fi
  if ! zpool status $bpool >/dev/null 2>&1 ; then
    echo "ERROR: A pool named $bpool doesn't exists."
    exit 1
  fi
fi

######################################################################
# Bootstrap pkgng
######################################################################

if [ ! -f /usr/sbin/p ]; then
  test -e /usr/local/sbin/pkg-static || pkg bootstrap
fi

######################################################################
# How to create a b64 patch
######################################################################
# diff -u zfsboot /usr/libexec/bsdinstall/zfsboot | xz | b64encode -

######################################################################
# Patch zfsboot for passwordless (-P,-p) geli
######################################################################

chmod 755 /usr/libexec/bsdinstall/zfsboot

b64decode -o /dev/stdout <<EOF | xz -d | patch -N -l /usr/libexec/bsdinstall/zfsboot
begin-base64 644 -
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
====
EOF

chmod 555 /usr/libexec/bsdinstall/zfsboot

######################################################################
# load geli and remove past bsdinstall temporary files
######################################################################

geli load

rm -r /tmp/bsdinstall*

######################################################################
# Perform creation of zfsboot
######################################################################

if [ "$ADDTOPOOL" = "1" ]; then
  bpoolreal=$bpool
  bpooltmp=tmpbpool
  bpool=$bpooltmp
  rpoolreal=$rpool
  rpooltmp=tmprpool
  rpool=$rpooltmp
fi
########## No ZFSBOOT_GNOP_4K_FORCE_ALIGN because can't add mirror later
ZFSBOOT_DISKS="$disks" \
ZFSBOOT_VDEV_TYPE=$raidtype \
ZFSBOOT_POOL_NAME=$rpool \
ZFSBOOT_POOL_SIZE=$zsize \
ZFSBOOT_BEROOT_NAME=$bename \
ZFSBOOT_BOOTFS_NAME=$bfsname \
ZFSBOOT_GELI_ENCRYPTION=1 \
ZFSBOOT_BOOT_POOL_NAME=$bpool \
ZFSBOOT_BOOT_POOL_SIZE=$bsize \
ZFSBOOT_SWAP_SIZE=$ssize \
ZFSBOOT_SWAP_ENCRYPTION=1 \
nonInteractive=0 \
bsdinstall zfsboot || exiterror $?

######################################################################
# Do ADDTOPOOL stuff
######################################################################

if [ "$ADDTOPOOL" = "1" ]; then
bootpart=p2 swappart=p3 targetpart=p3
[ -n "$ssize" ] && targetpart=p4
########## get existing disk
bpoolrealdisk=`zpool status $bpoolreal | grep -v state | \
grep ONLINE | tail -1 | awk '{print $1}'`
rpoolrealdisk=`zpool status $rpoolreal | grep -v state | \
grep ONLINE | tail -1 | awk '{print $1}'`
########## get new disk
bpooltmpdisk=`zpool status $bpooltmp | grep -v state | \
grep ONLINE | tail -1 | awk '{print $1}'`
rpooltmpdisk=`zpool status $rpooltmp | grep -v state | \
grep ONLINE | tail -1 | awk '{print $1}'`
########## destroy pool
zpool destroy -f $bpooltmp
zpool destroy -f $rpooltmp
########## attach bpool
echo "Trying: zpool attach -f $bpoolreal $bpoolrealdisk $bpooltmpdisk"
zpool attach -f $bpoolreal $bpoolrealdisk $bpooltmpdisk
########## attach rpool
geli detach $rpooltmpdisk
safefilename=` echo $rpooltmpdisk | sed 's#/#_#'`
if [ -f /${bpoolreal}/boot/encryption.key ]; then
  echo "Trying: geli init"
  geli init -b \
    -B "/${bpoolreal}/boot/${safefilename}" -e AES-XTS -P \
    -K "/${bpoolreal}/boot/encryption.key" \
    -l 256 -s 4096 ${rpooltmpdisk%.eli}
  echo "Trying: geli attach"
  geli attach -p -k "/${bpoolreal}/boot/encryption.key" \
    ${rpooltmpdisk%.eli}
elif [ -f ${mnt}/${bpoolreal}/boot/encryption.key ]; then
  echo "Trying: geli init"
  geli init -b \
    -B "${mnt}/${bpoolreal}/boot/${safefilename}" -e AES-XTS -P \
    -K "${mnt}/${bpoolreal}/boot/encryption.key" \
    -l 256 -s 4096 ${rpooltmpdisk%.eli}
  echo "Trying: geli attach"
  geli attach -p -k "${mnt}/${bpoolreal}/boot/encryption.key" \
    ${rpooltmpdisk%.eli}
fi
echo "Trying: zpool attach -f $rpoolreal $rpoolrealdisk $rpooltmpdisk"
zpool attach -f $rpoolreal $rpoolrealdisk $rpooltmpdisk || exiterror $?
cat <<EOF
Please wait for resilver to complete!
You can see the status of the process with:
       zpool status
EOF
fi

######################################################################
# Copy the generated /boot/loader.conf and /etc/fstab
######################################################################

if [ "$ADDTOPOOL" = "1" ]; then
  mnt=
fi
if [ "$ADDTOPOOL" = "1" -o "$MAKEMFSROOT" ]; then
  cat /tmp/bsdinstall_boot/loader.conf.* | \
    grep -v vfs.root.mountfrom | \
    grep -v aesni_load | \
    grep -v geom_eli_load | \
    grep -v zfs_load | \
    grep -v kern.geom.label.gptid.enable >> ${mnt}/boot/loader.conf.local
else
  cat /tmp/bsdinstall_boot/loader.conf.* | \
    grep -v aesni_load | \
    grep -v geom_eli_load | \
    grep -v zfs_load | \
    grep -v kern.geom.label.gptid.enable >> ${mnt}/boot/loader.conf.local
  chmod 644 ${mnt}/boot/loader.conf.local
fi
if [ "$ADDTOPOOL" = "1" ]; then
  exit
fi
install -d -m 755 ${mnt}/etc
install    -m 644 /tmp/bsdinstall_etc/fstab ${mnt}/boot/fstab.append

######################################################################
# Check if local distribution exists, if so copy to mnt
######################################################################

########## this notation /boot/.. is in case /boot is a symlink (eg. mfsroot)
distdir=/boot/../${release}
if [ ! -e $distdir/kernel.txz -o ! -e $distdir/base.txz ]; then
distdir=${mnt}/boot/../${release}
else
install -d -m 755 ${mnt}/${release}
tar -c -f - -C /boot/.. ${release} | tar -C ${mnt}/boot/.. -x -f -
fi
install -d -m 755 $distdir

######################################################################
# Fetch distribution if no local copy exists
######################################################################

if [ ! -e $distdir/kernel.txz -o ! -e $distdir/base.txz ]; then
DISTRIBUTIONS="kernel.txz base.txz lib32.txz" \
BSDINSTALL_DISTDIR=$distdir \
BSDINSTALL_DISTSITE="$distsite/`uname -m`/`uname -p`/${release}" \
nonInteractive=0 \
bsdinstall distfetch || exiterror $?
fi

######################################################################
# Create some extra datasets if mfsroot
######################################################################

if [ "$MAKEMFSROOT" ]; then
  zfs create -o canmount=off -o mountpoint=/etc $rpool/etc
  zfs create $rpool/etc/pf
  zfs create $rpool/etc/ssh
  zfs create -o canmount=off -o mountpoint=/root $rpool/root
  zfs create $rpool/root/.ssh
  chmod 700 ${mnt}/root/.ssh
  zfs create $rpool/root/bin
  chmod 700 ${mnt}/root/bin
  zfs create $rpool/usr/local
  zfs create $rpool/var/backups
  zfs create $rpool/var/cache
  zfs create $rpool/var/db
  zfs create $rpool/var/lib
  zfs create $rpool/var/run
fi

######################################################################
# Extract ditribution
######################################################################

DISTRIBUTIONS="kernel.txz base.txz" \
BSDINSTALL_DISTDIR=$distdir \
BSDINSTALL_CHROOT=$mnt \
nonInteractive=0 \
bsdinstall distextract || exiterror $?

######################################################################
# Copy pkg-static
######################################################################

if [ -f /usr/sbin/p ]; then
  install -m 755 -o root -g wheel /usr/sbin/p $mnt/usr/sbin/p
elif [ -f /usr/local/sbin/pkg-static ]; then
  install -m 755 -o root -g wheel /usr/local/sbin/pkg-static $mnt/usr/sbin/p
fi

######################################################################
# Fetch some packages we can cache in /boot/packages
######################################################################

install -d -m 755 ${mnt}/boot/packages
if [ -d /boot/packages ]; then
  echo "Copying /boot/packages to ${mnt}/boot/packages"
  tar -c -f - -C /boot/ packages | tar -C ${mnt}/boot/ -x -f - || exiterror $?
else
  if [ -f /usr/local/etc/pkg.conf ]; then
    cat /usr/local/etc/pkg.conf > /usr/local/etc/pkg.conf.bkp
  fi
  install -d -m 755 /usr/local/etc
  echo "PKG_CACHEDIR = \"${mnt}/boot/packages\";" >> /usr/local/etc/pkg.conf
p fetch -y \
cmdwatch \
gnupg libksba libgpg-error gettext indexinfo libgcrypt libassuan pth \
    curl ca_root_nss \
ezjail \
iftop \
openntpd \
openssl \
rsync \
tmux libevent2 \
ucarp \
wget indexinfo libidn gettext \
pkg
# git expat p5-Authen-SASL p5-GSSAPI perl5 p5-Digest-HMAC p5-Net-SMTP-SSL \
#   p5-IO-Socket-SSL p5-Mozilla-CA p5-Net-SSLeay: 1.66 p5-Socket \
#   p5-IO-Socket-IP python27 libffi indexinfo gettext p5-Error \
#   curl ca_root_nss cvsps p5-MIME-Base64 \
# subversion serf apr expat gdbm indexinfo gettext db5 sqlite3
# xfce xfce4-terminal libxfce4menu xfce4-conf libxfce4util perl5 pcre glib \
#   python27 libffi indexinfo gettext libiconv libX11 xproto libxcb libXdmcp \
#   libXau libxml2 libpthread-stubs kbproto pango libXrender renderproto \
#   xorg-fonts-truetype font-misc-meltho mkfontscale libfontenc freetype2 \
#   mkfontdir fontconfig expat font-misc-ethiopic font-bh-ttf encodings \
#   font-util dejavu libXft harfbuzz graphite2 cairo xcb-util-renderutil \
#   xcb-util pixman libXext xextproto png icu gnomehier gtk2 libXrandr \
#   randrproto libXinerama xineramaproto libXi libXfixes fixesproto \
#   inputproto libXdamage damageproto libXcursor libXcomposite compositeproto \
#   cups-client shared-mime-info hicolor-icon-theme python python2 \
#   gtk-update-icon-cache gdk-pixbuf2 libXt libSM libICE tiff jpeg jbigkit \
#   jasper atk dbus-glib dbus gnome_subr startup-notification vte \
#   gnome-pty-helper xfce4-wm libwnck libXres gobject-introspection \
#   xfce4-session iceauth upower polkit consolekit xfce4-panel libexo p5-URI \
#   desktop-file-utils garcon xfce4-desktop Thunar libexif libnotify libIDL \
#   gvfs libcdio-paranoia libcdio libcddb hal policykit dmidecode pciids \
#   libvolume_id gnome-mount policykit-gnome libxslt libgcrypt libgpg-error \
#   gnome-doc-utils rarian docbook-xsl xmlcatmgr docbook sdocbook-xml \
#   docbook-xml xmlcharent docbook-sgml iso8879 bash getopt py27-libxml2 \
#   py27-setuptools27 gconf2 dconf ORBit2 libgnome-keyring libtasn1 \
#   samba36-libsmbclient tevent talloc pkgconf tdb avahi-app libdaemon gdbm \
#   libgphoto2 libgd libltdl libsoup-gnome glib-networking p11-kit \
#   ca_root_nss gnutls trousers-tddl nettle gmp libidn libproxy \
#   gsettings-desktop-schemas cantarell-fonts libsoup sqlite3 xfce4-tumbler \
#   poppler-glib poppler-data poppler openjpeg15 lcms2 exif popt libgsf \
#   icons-tango-extras icons-tango gtk-xfce-engine xfce4-settings libxklavier \
#   xkbcomp libxkbfile iso-codes xfce4-appfinder mousepad gtksourceview2 \
#   xfce4-notifyd orage
  if [ -f /usr/local/etc/pkg.conf.bkp ]; then
    cat /usr/local/etc/pkg.conf.bkp > /usr/local/etc/pkg.conf
    rm /usr/local/etc/pkg.conf.bkp
  else
    rm /usr/local/etc/pkg.conf
  fi
fi

######################################################################
# Set some loader.conf options
######################################################################

sysrc -f "${mnt}/boot/loader.conf" aesni_load="YES" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" ahci_load="YES" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" autoboot_delay="1" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" geom_eli_load="YES" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" geom_label_load="YES" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" geom_mirror_load="YES" >/dev/null
########## hw.bge.allow_asf for my HP server to stop network disconnect
sysrc -f "${mnt}/boot/loader.conf" "hw.bge.allow_asf=0" >/dev/null
########## hw.usb.no_shutdown_wait allows USB not to stall poweroff
sysrc -f "${mnt}/boot/loader.conf" "hw.usb.no_shutdown_wait=1" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" if_lagg_load="YES" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" "kern.cam.boot_delay=10000" >/dev/null
########## I prefer no disk ID
sysrc -f "${mnt}/boot/loader.conf" "kern.geom.label.disk_ident.enable=0" \
>/dev/null
sysrc -f "${mnt}/boot/loader.conf" "kern.geom.label.gpt.enable=0" >/dev/null
########## But I allow UUID
sysrc -f "${mnt}/boot/loader.conf" "kern.geom.label.gptid.enable=1" >/dev/null
########## Kernel max
sysrc -f "${mnt}/boot/loader.conf" "kern.maxfiles=65530" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" "kern.maxswzone=512M" >/dev/null
########## loader_logo should stop logo from showing, appears to be BROKEN
sysrc -f "${mnt}/boot/loader.conf" loader_logo="none" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" nullfs_load="YES" >/dev/null
########## tmpfs_load for mfsroot /usr
sysrc -f "${mnt}/boot/loader.conf" tmpfs_load="YES" >/dev/null
########## vfs.zfs.arc_max limit arc usage on low RAM systems
sysrc -f "${mnt}/boot/loader.conf" "vfs.zfs.arc_max=256M" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" zfs_load="YES" >/dev/null

######################################################################
# Set some rc.conf options
######################################################################

sysrc -f "${mnt}/etc/rc.conf" auditd_enable="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" entropy_file="/var/db/entropy-file" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" ftpproxy_enable="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" ntpdate_enable="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" openntpd_enable="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" pf_enable="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" pf_rules="/etc/pf/pf.conf" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" pflog_enable="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" pflog_logfile="/var/log/pflog" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" sendmail_enable="NO" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" sendmail_submit_enable="NO" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" sendmail_outbound_enable="NO" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" sendmail_msp_queue_enable="NO" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" sshd_enable="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" sshd_rsa1_enable="NO" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" sshd_dsa_enable="NO" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" syslogd_flags="-s -b127.0.0.1" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" zfs_enable="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" virtio_load="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" virtio_pci_load="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" virtio_blk_load="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" if_vtnet_load="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" virtio_balloon_load="YES" >/dev/null
sysrc -f "${mnt}/etc/rc.conf" linux_enable="YES" >/dev/null

######################################################################
# Set ifconfig DHCP
######################################################################

ifconfig -l | tr ' ' '\n' | while read line ; do
  if [ "$line" != "lo0" -a "$line" != "pflog0" ]; then
    echo "# ifconfig_${line}=\"up\"" >> ${mnt}/boot/loader.conf.local
  fi
done

ifconfig -l | tr ' ' '\n' | while read line ; do
  if [ "$line" != "lo0" -a "$line" != "pflog0" ]; then
    sysrc -f "${mnt}/boot/loader.conf.local" ifconfig_${line}="DHCP"
  fi
done

######################################################################
# Set lagg as optional comments
######################################################################

echo '########## To enable Link Aggregation: BEGIN' >> ${mnt}/boot/loader.conf.local
nics=`ifconfig -l | tr ' ' '\n' | \
awk '$1 !~ /lo[0-9]/ && \
$1 !~ /pflog[0-9]/ && \
$1 !~ /lagg[0-9]/ {print "laggport "$1}' | tr '\n' ' '`
echo "# cloned_interfaces=\"lagg0\"" >> ${mnt}/boot/loader.conf.local
echo "# ifconfig_lagg0=\"DHCP laggproto loadbalance $nics\"" \
>> ${mnt}/boot/loader.conf.local
echo "# ifconfig_lagg0=\"inet 192.168.0.2/24 laggproto loadbalance $nics\"" \
>> ${mnt}/boot/loader.conf.local
echo '########## To enable Link Aggregation: END' >> ${mnt}/boot/loader.conf.local

######################################################################
# Set SSH options
######################################################################

echo PermitRootLogin yes >> "${mnt}/etc/ssh/sshd_config"
echo UseDNS no >> "${mnt}/etc/ssh/sshd_config"

######################################################################
# Change password of new system to blank
######################################################################

yes '' | chroot $mnt passwd

######################################################################
# Actually make the MFSROOT
######################################################################

if [ "$MAKEMFSROOT" ]; then
echo "Creating mfsroot container at ${mnt}/${bpool}/mfsroot with dd"
dd if=/dev/zero of=${mnt}/${bpool}/mfsroot bs=512 count=245760 || exiterror $?
mdevice=`mdconfig -a -t vnode -f ${mnt}/${bpool}/mfsroot`
install -d -m 755 $mfsmnt
echo "Making new fs on /dev/${mdevice}"
newfs /dev/${mdevice} || exiterror $?
echo "Mouting /dev/${mdevice} to $mfsmnt"
mount /dev/${mdevice} $mfsmnt || exiterror $?
########## Copy everything except /usr
echo "Copying ${mnt} to $mfsmnt"
tar -c -f - \
--exclude $bpool \
--exclude /boot \
--exclude null \
--exclude ${release} \
--exclude usr \
-C ${mnt} ./ | tar -C $mfsmnt -x -f - || exiterror $?
########## rc script for tmpfs /usr
########## modified from https://github.com/mmatuska/mfsbsd
cat >$mfsmnt/etc/rc.d/mdinit <<EOF
#!/bin/sh
# \$Id\$
# PROVIDE: mdinit
# BEFORE: zfs FILESYSTEMS
# REQUIRE: mountcritlocal
# KEYWORD: FreeBSD
. /etc/rc.subr
name="mdinit"
start_cmd="mdinit_start"
stop_cmd=":"
mdinit_start()
{
  if [ -f /.usr.tar.xz ]; then
    /rescue/test -d /usr || /rescue/mkdir /usr
    /rescue/test -d /usr && /rescue/mount -t tmpfs tmpfs /usr
    /rescue/test -d /usr && /rescue/tar -x -C / -f /.usr.tar.xz
  elif [ -f /.usr.tar.bz2 ]; then
    /rescue/test -d /usr || /rescue/mkdir /usr
    /rescue/test -d /usr && /rescue/mount -t tmpfs tmpfs /usr
    /rescue/test -d /usr && /rescue/tar -x -C / -f /.usr.tar.bz2
  elif [ -f /.usr.tar.gz ]; then
    /rescue/test -d /usr || /rescue/mkdir /usr
    /rescue/test -d /usr && /rescue/mount -t tmpfs tmpfs /usr
    /rescue/test -d /usr && /rescue/tar -x -C / -f /.usr.tar.gz
  fi
  if [ ! -f /usr/bin/which ]; then
    echo "Error in mdinit while extracting /usr, entering shell:"
    /rescue/sh
  fi
  if zfs list -H -o name,canmount,mountpoint | \
    awk '\$2 ~ /on/ {print}' | grep 'on[^/]*/\$' ; then
    echo "Disabling some zfs datasets that mount to /"
    DATASETS=\$(zfs list -H -o name,canmount,mountpoint | \
    awk '\$2 ~ /on/ {print}' | grep 'on[^/]*/\$' | awk '{print \$1}')
    for Z in \$DATASETS ; do
      echo zfs set canmount=off \$Z
      zfs set canmount=off \$Z
    done
  fi
  if /bin/kenv -q mdinit_shell | grep YES ; then
    echo "Found mdinit_shell, entering shell:"
    /rescue/sh
  fi
}
load_rc_config \$name
run_rc_command "\$1"
EOF
chmod 555 $mfsmnt/etc/rc.d/mdinit
########## appendconf because we are in mfs and harder to persist
cat >$mfsmnt/etc/rc.d/appendconf <<EOF
#!/bin/sh
# \$Id\$
# PROVIDE: appendconf
# BEFORE: hostname netif
# REQUIRE: mdinit FILESYSTEMS
# KEYWORD: FreeBSD
. /etc/rc.subr
name="appendconf"
start_cmd="appendconf_start"
stop_cmd=":"
appendconf_start()
{
  if /bin/kenv -v hostname 2>/dev/null ; then
    /bin/kenv -v hostname >> /etc/rc.conf.d/hostname
  fi
  if /bin/kenv | grep netwait_ >/dev/null 2>&1 ; then
    /bin/kenv | grep netwait_ >> /etc/rc.conf.d/netwait
  fi
  if /bin/kenv | grep ifconfig_ >/dev/null 2>&1 ; then
    /bin/kenv | grep ifconfig_ >> /etc/rc.conf.d/network
  fi
  if /bin/kenv | grep cloned_interfaces >/dev/null 2>&1 ; then
    /bin/kenv | grep cloned_interfaces >> /etc/rc.conf.d/network
  fi
  if /bin/kenv | grep ntpdate_ >/dev/null 2>&1 ; then
    /bin/kenv | grep ntpdate_ >> /etc/rc.conf.d/ntpdate
  fi
  if /bin/kenv | grep defaultrouter >/dev/null 2>&1 ; then
    /bin/kenv | grep defaultrouter >> /etc/rc.conf.d/routing
  fi
  if /bin/kenv | grep static_routes >/dev/null 2>&1 ; then
    /bin/kenv | grep static_routes >> /etc/rc.conf.d/routing
  fi
  if /bin/kenv | grep route_ >/dev/null 2>&1 ; then
    /bin/kenv | grep route_ >> /etc/rc.conf.d/routing
  fi
  ########## import before trying /boot/*
  if /bin/kenv -q zpool_import 2>/dev/null ; then
    /sbin/zpool import \$( /bin/kenv -q zpool_import )
  fi
  if [ -f /boot/resolv.conf.overwrite ]; then
    cat /boot/resolv.conf.overwrite > /etc/resolv.conf
  elif [ -f /boot/resolv.conf.append ]; then
    cat /boot/resolv.conf.append >> /etc/resolv.conf
  fi
  if [ -f /boot/fstab.overwrite ]; then
    cat /boot/fstab.overwrite > /etc/fstab
  elif [ -f /boot/fstab.append ]; then
    cat /boot/fstab.append >> /etc/fstab
  fi
  if [ -f /boot/periodic.conf.overwrite ]; then
    cat /boot/periodic.conf.overwrite > /etc/periodic.conf
  elif [ -f /boot/periodic.conf.append ]; then
    cat /boot/periodic.conf.append >> /etc/periodic.conf
  fi
  if [ -f /boot/sysctl.conf.overwrite -o -f /boot/sysctl.conf.append ]; then
    if [ -f /boot/sysctl.conf.overwrite ]; then
      cat /boot/sysctl.conf.overwrite > /etc/sysctl.conf
    elif [ -f /boot/sysctl.conf.append ]; then
      cat /boot/sysctl.conf.append >> /etc/sysctl.conf
    fi
    service sysctl start
  fi
}
load_rc_config \$name
run_rc_command "\$1"
EOF
chmod 555 $mfsmnt/etc/rc.d/appendconf
########## packages because we are in mfs and harder to persist
cat >$mfsmnt/etc/rc.d/packages <<EOF
#!/bin/sh
# \$Id\$
# PROVIDE: packages
# REQUIRE: FILESYSTEMS NETWORKING SERVERS DAEMON LOGIN dhclient
# KEYWORD: FreeBSD
. /etc/rc.subr
name="packages"
start_cmd="packages_start"
stop_cmd=":"
packages_start()
{
  for P in \$( /bin/kenv -q packages ) ; do
    echo -n "Installing \$P..."
    p install -y \$P >/var/log/packages.net.log 2>&1
    echo "done"
  done
  if ls /boot/packages/*.t?z >/dev/null 2>&1 ; then
    p add \$( ls /boot/packages/*.t?z ) >/var/log/packages.local.log 2>&1
  fi
}
load_rc_config \$name
run_rc_command "\$1"
EOF
chmod 555 $mfsmnt/etc/rc.d/packages
########## Package /usr
echo "Compressing ${mnt}/usr to $mfsmnt/.usr.tar.xz"
tar -c -J -f $mfsmnt/.usr.tar.xz --exclude ${release} \
--options xz:compression-level=9 -C ${mnt} usr || exiterror $?
########## Unmount
echo "Unmounting /dev/${mdevice}"
umount /dev/${mdevice} || exiterror $?
mdconfig -d -u ${mdevice#md} || exiterror $?
########## mfs_ settings in loader.conf
sysrc -f "${mnt}/boot/loader.conf.local" mfs_load="YES" >/dev/null
sysrc -f "${mnt}/boot/loader.conf.local" mfs_type="mfs_root" >/dev/null
sysrc -f "${mnt}/boot/loader.conf.local" mfs_name="/mfsroot" >/dev/null
sysrc -f "${mnt}/boot/loader.conf.local" "vfs.root.mountfrom=ufs:/dev/md0" >/dev/null
########## set defaultrouter
sysrc -f "${mnt}/boot/loader.conf.local" \
defaultrouter="`netstat -nr | grep default | awk '{print $2}'`" >/dev/null
########## optional set mdinit_shell
# sysrc -f "${mnt}/boot/loader.conf" mdinit_shell="YES" >/dev/null
########## optional set packages to list we can pkg install -y ____
sysrc -f "${mnt}/boot/loader.conf.local" packages="" >/dev/null
########## optional set netwait_
sysrc -f "${mnt}/boot/loader.conf.local" netwait_enable="YES" >/dev/null
sysrc -f "${mnt}/boot/loader.conf.local" \
netwait_ip="`netstat -nr | grep default | awk '{print $2}'`" >/dev/null
########## optional set ntpdate_hosts
sysrc -f "${mnt}/boot/loader.conf.local" ntpdate_hosts="pool.ntp.org" >/dev/null
fi

######################################################################
# Remind user that they should change password of new system
######################################################################

cat <<EOF
Don't export the ZFS pools!
You may want to set the hostname with:
       sysrc -f "${mnt}/boot/loader.conf.local" hostname="name"
See file ${mnt}/boot/loader.conf.local for more options.
You should probably change the root password of the new system with:
       chroot $mnt passwd
EOF
