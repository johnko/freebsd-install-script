#!/bin/sh

######################################################################
# Script version is YYmmdd-HHMM in UTC, date +%y%m%d-%H%M%S
######################################################################
SCRIPTVERSION=141118-231600

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
usage: $0 -d disk [-d disk ...] [-e disk] [-b boot_size] [-f] [-h] [-m]
       [-M /mnt] [-p poolname] [-r stripe|mirror|raidz|raidz2|raidz3]
       [-s swap_size] [-v] [-z pool_size]

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

  Check that a zpool named mini exists, note the vdev:
       zpool status mini

  Add disk 1 as mirror to an existing pool that contains disk ada0:
       $0 -d ada1 -z 2g -p mini -e ada0

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
AgAAAAAEWVo=
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
ZFSBOOT_GNOP_4K_FORCE_ALIGN= \
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
bpoolrealdisk=`zpool status $bpoolreal | grep -v $bpoolreal | grep -v state | \
grep ONLINE | tail -1 | awk '{print $1}'`
########## get new disk
bpooltmpdisk=`zpool status $bpooltmp | grep -v $bpooltmp | grep -v state | \
grep ONLINE | tail -1 | awk '{print $1}'`
rpooltmpdisk=`zpool status $rpooltmp | grep -v $rpooltmp | grep -v state | \
grep ONLINE | tail -1 | awk '{print $1}'`
########## destroy pool
zpool destroy -f $bpooltmp
zpool destroy -f $rpooltmp
########## gnop for bpooltmpdisk
# gnop create -S 4096 ${disks}${bootpart}
# echo "Trying: zpool attach -f $bpoolreal $bpoolrealdisk ${disks}${bootpart}.nop"
# zpool attach -f $bpoolreal $bpoolrealdisk ${disks}${bootpart}.nop
echo "Trying: zpool attach -f $bpoolreal $bpoolrealdisk $bpooltmpdisk"
zpool attach -f $bpoolreal $bpoolrealdisk $bpooltmpdisk
########## attach rpool
geli detach $rpooltmpdisk
if [ -f /${bpoolreal}/boot/encryption.key ]; then
  echo "Trying: geli init"
  geli init -b \
    -B "/${bpoolreal}/boot/${rpooltmpdisk}" -e AES-XTS -P \
    -K "/${bpoolreal}/boot/encryption.key" \
    -l 256 -s 4096 ${rpooltmpdisk%.eli}
  echo "Trying: geli attach"
  geli attach -p -k "/${bpoolreal}/boot/encryption.key" \
    ${rpooltmpdisk%.eli}
elif [ -f ${mnt}/${bpoolreal}/boot/encryption.key ]; then
  echo "Trying: geli init"
  geli init -b \
    -B "${mnt}/${bpoolreal}/boot/${rpooltmpdisk}" -e AES-XTS -P \
    -K "${mnt}/${bpoolreal}/boot/encryption.key" \
    -l 256 -s 4096 ${rpooltmpdisk%.eli}
  echo "Trying: geli attach"
  geli attach -p -k "${mnt}/${bpoolreal}/boot/encryption.key" \
    ${rpooltmpdisk%.eli}
fi
echo "Trying: zpool attach -f $rpoolreal ${edisk}${targetpart}.eli ${disks}${targetpart}.eli"
zpool attach -f $rpoolreal ${edisk}${targetpart}.eli ${disks}${targetpart}.eli || exiterror $?
cat <<EOF
Please wait for resilver to complete!
You can see the status of the process with:
       zpool status
EOF
exit
fi

######################################################################
# Copy the generated /boot/loader.conf and /etc/fstab
######################################################################

cat /tmp/bsdinstall_boot/loader.conf.* > /mnt/boot/loader.conf
chmod 644 /mnt/boot/loader.conf
install -d -m 755 /mnt/etc
install    -m 644 /tmp/bsdinstall_etc/fstab /mnt/boot/fstab.append

######################################################################
# Check if local distribution exists, if so copy to mnt
######################################################################

########## this notation /boot/.. is in case /boot is a symlink (eg. mfsroot)
distdir=/boot/../${release}
if [ ! -e $distdir/kernel.txz -o ! -e $distdir/base.txz ]; then
distdir=/mnt/boot/../${release}
else
install -d -m 755 /mnt/${release}
tar -c -f - -C /boot/.. ${release} | tar -C /mnt/boot/.. -x -f -
fi
install -d -m 755 $distdir

######################################################################
# Fetch distribution if no local copy exists
######################################################################

if [ ! -e $distdir/kernel.txz -o ! -e $distdir/base.txz ]; then
DISTRIBUTIONS="kernel.txz base.txz" \
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
  tar -c -f - -C /boot/ packages | tar -C /mnt/boot/ -x -f - || exiterror $?
else
  if [ -f /usr/local/etc/pkg.conf ]; then
    cat /usr/local/etc/pkg.conf > /usr/local/etc/pkg.conf.bkp
  fi
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
# REQUIRE: FILESYSTEMS NETWORKING SERVERS DAEMON LOGIN
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
sysrc -f "${mnt}/boot/loader.conf" mfs_load="YES" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" mfs_type="mfs_root" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" mfs_name="/mfsroot" >/dev/null
sysrc -f "${mnt}/boot/loader.conf" "vfs.root.mountfrom=ufs:/dev/md0" >/dev/null
########## optional set mdinit_shell
# sysrc -f "${mnt}/boot/loader.conf" mdinit_shell="YES" >/dev/null
########## optional set packages to list we can pkg install -y ____
sysrc -f "${mnt}/boot/loader.conf" packages="" >/dev/null
########## optional set ntpdate_hosts
sysrc -f "${mnt}/boot/loader.conf.local" netwait_enable="YES" >/dev/null
sysrc -f "${mnt}/boot/loader.conf.local" \
netwait_ip="`netstat -nr | grep default | awk '{print $2}'`" >/dev/null
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
