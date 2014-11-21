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
: ${bsize:=1g}
: ${bename:=rfs}
: ${bfsname:=default}
: ${ssize:=2g}
: ${release:=10.1-RELEASE}

######################################################################
# Usage
######################################################################

usage() {
  cat <<EOF
usage: $0 -d disk [-d disk ...] [-b boot_size] [-f] [-h] [-m]
       [-p poolname] [-r stripe|mirror|raidz|raidz2|raidz3] [-s swap_size] [-v]

       -b size  Boot partition size.
       -d disk  Disk to install on (eg. da0).
       -f       Force export of existing pool.
       -h       Help.
       -m       Create mfsroot type of system.
       -M mount Mountpoint, if not using /mnt.
       -p name  ZFS pool name, must be unique.
       -r       Select ZFS raid mode if multiple -d given.
       -s size  Swap partition size.
       -v       Version.
       -z       ZFS partition size.

examples:

  Install on mirror disks:
       $0 -d ada0 -d ada1 -r mirror

  Make a bootable ZFS USB, which loads as mfs:
       $0 -d da0 -m -p usb
  Note we change the pool name so they don't conflict.
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

while getopts b:d:p:r:s:M:z:mfvh o; do
  case "$o" in
    b) bsize="$OPTARG" ;;
    d) disks="$disks ${OPTARG##/dev/}" ;;
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
elif [ "$count" -gt "2" -a "$raidtype" != "mirror" -a "$raidtype" != "raidz" -a "$raidtype" != "raidz2" -a "$raidtype" != "raidz3" ]; then
  echo "Error: please choose raid mode with the -r switch (mirror or raidz{1,2,3})" ; exit 1
fi

######################################################################
# If force, delete pools and detach partition 3 and 4
######################################################################

if [ "$FORCEEXPORT" ]; then
  zpool status $bpool >/dev/null 2>/dev/null && zpool export -f $bpool # have to export bpool before rpool
  zpool status $rpool >/dev/null 2>/dev/null && zpool export -f $rpool
  for D in $disks ; do test -e /dev/${D}p3.eli && geli detach ${D}p3 ; test -e /dev/${D}p4.eli && geli detach ${D}p4 ; done
fi

######################################################################
# Quit if pools exist
######################################################################

if zpool status $rpool >/dev/null 2>/dev/null ; then
  echo "ERROR: A pool named $rpool already exists."
  exit 1
fi
if zpool status $bpool >/dev/null 2>/dev/null ; then
  echo "ERROR: A pool named $bpool already exists."
  exit 1
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
# diff -u zfsboot /usr/libexec/bsdinstall/zfsboot | b64encode -

######################################################################
# Patch zfsboot for passwordless (-P,-p) geli
######################################################################

chmod 755 /usr/libexec/bsdinstall/zfsboot

b64decode -o /dev/stdout <<EOF | patch -N -l /usr/libexec/bsdinstall/zfsboot
begin-base64 644 -
LS0tIHpmc2Jvb3QJMjAxNC0xMS0yMSAwMDo1OToxMi4wMDAwMDAwMDAgKzAwMDAKKysrIC91c3Iv
bGliZXhlYy9ic2RpbnN0YWxsL3pmc2Jvb3QJMjAxNC0xMS0yMSAwMjoxNTo1MS4wMDAwMDAwMDAg
KzAwMDAKQEAgLTQ1LDYgKzQ1LDExIEBACiA6ICR7WkZTQk9PVF9QT09MX05BTUU6PXpyb290fQog
CiAjCisjIERlZmF1bHQgcG9vbCBzaXplCisjCis6ICR7WkZTQk9PVF9QT09MX1NJWkU9fQorCisj
CiAjIERlZmF1bHQgb3B0aW9ucyB0byB1c2Ugd2hlbiBjcmVhdGluZyB6cm9vdCBwb29sCiAjCiA6
ICR7WkZTQk9PVF9QT09MX0NSRUFURV9PUFRJT05TOj0tTyBjb21wcmVzcz1sejQgLU8gYXRpbWU9
b2ZmfQpAQCAtMTgyLDkgKzE4Nyw5IEBACiBDSE1PRF9NT0RFPSdjaG1vZCAlcyAiJXMiJwogRERf
V0lUSF9PUFRJT05TPSdkZCBpZj0iJXMiIG9mPSIlcyIgJXMnCiBFQ0hPX0FQUEVORD0nZWNobyAi
JXMiID4+ICIlcyInCi1HRUxJX0FUVEFDSD0nZ2VsaSBhdHRhY2ggLWogLSAtayAiJXMiICIlcyIn
CitHRUxJX0FUVEFDSD0nZ2VsaSBhdHRhY2ggLXAgLWsgIiVzIiAiJXMiJwogR0VMSV9ERVRBQ0hf
Rj0nZ2VsaSBkZXRhY2ggLWYgIiVzIicKLUdFTElfUEFTU1dPUkRfSU5JVD0nZ2VsaSBpbml0IC1i
IC1CICIlcyIgLWUgJXMgLUogLSAtSyAiJXMiIC1sIDI1NiAtcyA0MDk2ICIlcyInCitHRUxJX1BB
U1NXT1JEX0lOSVQ9J2dlbGkgaW5pdCAtYiAtQiAiJXMiIC1lICVzIC1QIC1LICIlcyIgLWwgMjU2
IC1zIDQwOTYgIiVzIicKIEdOT1BfQ1JFQVRFPSdnbm9wIGNyZWF0ZSAtUyA0MDk2ICIlcyInCiBH
Tk9QX0RFU1RST1k9J2dub3AgZGVzdHJveSAiJXMiJwogR1BBUlRfQUREPSdncGFydCBhZGQgLXQg
JXMgIiVzIicKQEAgLTI0Niw2ICsyNTEsNyBAQAogbXNnX2ludmFsaWRfYm9vdF9wb29sX3NpemU9
IkludmFsaWQgYm9vdCBwb29sIHNpemUgXGAlcyciCiBtc2dfaW52YWxpZF9kaXNrX2FyZ3VtZW50
PSJJbnZhbGlkIGRpc2sgYXJndW1lbnQgXGAlcyciCiBtc2dfaW52YWxpZF9pbmRleF9hcmd1bWVu
dD0iSW52YWxpZCBpbmRleCBhcmd1bWVudCBcYCVzJyIKK21zZ19pbnZhbGlkX3Bvb2xfc2l6ZT0i
SW52YWxpZCBwb29sIHNpemUgXGAlcyciCiBtc2dfaW52YWxpZF9zd2FwX3NpemU9IkludmFsaWQg
c3dhcCBzaXplIFxgJXMnIgogbXNnX2ludmFsaWRfdmlydHVhbF9kZXZpY2VfdHlwZT0iSW52YWxp
ZCBWaXJ0dWFsIERldmljZSB0eXBlIFxgJXMnIgogbXNnX2xhc3RfY2hhbmNlX2FyZV95b3Vfc3Vy
ZT0iTGFzdCBDaGFuY2UhIEFyZSB5b3Ugc3VyZSB5b3Ugd2FudCB0byBkZXN0cm95XG50aGUgY3Vy
cmVudCBjb250ZW50cyBvZiB0aGUgZm9sbG93aW5nIGRpc2tzOlxuXG4gICAlcyIKQEAgLTg2Niw4
ICs4NzIsMTMgQEAKIAkJIwogCQkjIDQuIEFkZCBmcmVlYnNkLXpmcyBwYXJ0aXRpb24gbGFiZWxl
ZCBgemZzIycgZm9yIHpyb290CiAJCSMKKwkgICAgICAgaWYgWyAiJFpGU0JPT1RfUE9PTF9TSVpF
IiBdOyB0aGVuCisJCWZfZXZhbF9jYXRjaCAkZnVuY25hbWUgZ3BhcnQgIiRHUEFSVF9BRERfTEFC
RUxfV0lUSF9TSVpFIiBcCisJCSAgICAgICAgICAgICB6ZnMkaW5kZXggZnJlZWJzZC16ZnMgJHtw
b29sc2l6ZX1iICRkaXNrIHx8IHJldHVybiAkRkFJTFVSRQorCSAgICAgICBlbHNlCiAJCWZfZXZh
bF9jYXRjaCAkZnVuY25hbWUgZ3BhcnQgIiRHUEFSVF9BRERfTEFCRUwiIFwKIAkJICAgICAgICAg
ICAgIHpmcyRpbmRleCBmcmVlYnNkLXpmcyAkZGlzayB8fCByZXR1cm4gJEZBSUxVUkUKKwkgICAg
ICAgZmkKIAkJZl9ldmFsX2NhdGNoIC1kICRmdW5jbmFtZSB6cG9vbCAiJFpQT09MX0xBQkVMQ0xF
QVJfRiIgXAogCQkgICAgICAgICAgICAgICAgL2Rldi8kZGlzayR0YXJnZXRwYXJ0CiAJCTs7CkBA
IC0xMDI5LDcgKzEwNDAsNyBAQAogCSMgRXhwYW5kIFNJIHVuaXRzIGluIGRlc2lyZWQgc2l6ZXMK
IAkjCiAJZl9kcHJpbnRmICIkZnVuY25hbWU6IEV4cGFuZGluZyBzdXBwbGllZCBzaXplIHZhbHVl
cy4uLiIKLQlsb2NhbCBzd2Fwc2l6ZSBib290c2l6ZQorCWxvY2FsIHN3YXBzaXplIGJvb3RzaXpl
IHBvb2xzaXplCiAJaWYgISBmX2V4cGFuZF9udW1iZXIgIiRaRlNCT09UX1NXQVBfU0laRSIgc3dh
cHNpemU7IHRoZW4KIAkJZl9kcHJpbnRmICIkZnVuY25hbWU6IEludmFsaWQgc3dhcCBzaXplIFxg
JXMnIiBcCiAJCSAgICAgICAgICAiJFpGU0JPT1RfU1dBUF9TSVpFIgpAQCAtMTA0MywxMCArMTA1
NCwxOSBAQAogCQkgICAgICAgICAgICIkWkZTQk9PVF9CT09UX1BPT0xfU0laRSIKIAkJcmV0dXJu
ICRGQUlMVVJFCiAJZmkKKwlpZiAhIGZfZXhwYW5kX251bWJlciAiJFpGU0JPT1RfUE9PTF9TSVpF
IiBwb29sc2l6ZTsgdGhlbgorCQlmX2RwcmludGYgIiRmdW5jbmFtZTogSW52YWxpZCBwb29sIHNp
emUgXGAlcyciIFwKKwkJICAgICAgICAgICIkWkZTQk9PVF9QT09MX1NJWkUiCisJCWZfc2hvd19l
cnIgIiRtc2dfaW52YWxpZF9wb29sX3NpemUiIFwKKwkJICAgICAgICAgICAiJFpGU0JPT1RfUE9P
TF9TSVpFIgorCQlyZXR1cm4gJEZBSUxVUkUKKwlmaQogCWZfZHByaW50ZiAiJGZ1bmNuYW1lOiBa
RlNCT09UX1NXQVBfU0laRT1bJXNdIHN3YXBzaXplPVslc10iIFwKIAkgICAgICAgICAgIiRaRlNC
T09UX1NXQVBfU0laRSIgIiRzd2Fwc2l6ZSIKIAlmX2RwcmludGYgIiRmdW5jbmFtZTogWkZTQk9P
VF9CT09UX1BPT0xfU0laRT1bJXNdIGJvb3RzaXplPVslc10iIFwKIAkgICAgICAgICAgIiRaRlNC
T09UX0JPT1RfUE9PTF9TSVpFIiAiJGJvb3RzaXplIgorCWZfZHByaW50ZiAiJGZ1bmNuYW1lOiBa
RlNCT09UX1BPT0xfU0laRT1bJXNdIHBvb2xzaXplPVslc10iIFwKKwkgICAgICAgICAgIiRaRlNC
T09UX1BPT0xfU0laRSIgIiRwb29sc2l6ZSIKIAogCSMKIAkjIERlc3Ryb3kgdGhlIHBvb2wgaW4t
Y2FzZSB0aGlzIGlzIG91ciBzZWNvbmQgdGltZSAncm91bmQgKGNhc2Ugb2YKQEAgLTExNTAsMTUg
KzExNzAsNiBAQAogCSMgQ3JlYXRlIHRoZSBnZWxpKDgpIEdFT01TCiAJIwogCWlmIFsgIiRaRlNC
T09UX0dFTElfRU5DUllQVElPTiIgXTsgdGhlbgotCQkjIFByb21wdCB1c2VyIGZvciBwYXNzd29y
ZCAodHdpY2UpCi0JCWlmICEgbXNnX2VudGVyX25ld19wYXNzd29yZD0iJG1zZ19nZWxpX3Bhc3N3
b3JkIiBcCi0JCQlmX2RpYWxvZ19pbnB1dF9wYXNzd29yZAotCQl0aGVuCi0JCQlmX2RwcmludGYg
IiRmdW5jbmFtZTogVXNlciBjYW5jZWxsZWQiCi0JCQlmX3Nob3dfZXJyICIkbXNnX3VzZXJfY2Fu
Y2VsbGVkIgotCQkJcmV0dXJuICRGQUlMVVJFCi0JCWZpCi0KIAkJIyBJbml0aWFsaXplIGdlbGko
OCkgb24gZWFjaCBvZiB0aGUgdGFyZ2V0IHBhcnRpdGlvbnMKIAkJZm9yIGRpc2sgaW4gJGRpc2tz
OyBkbwogCQkJZl9kaWFsb2dfaW5mbyAiJG1zZ19nZWxpX3NldHVwIiBcCkBAIC0xNDc2LDcgKzE0
ODcsOCBAQAogCiAJCSMgTWFrZSBzdXJlIGVhY2ggZGlzayB3aWxsIGJlIGF0IGxlYXN0IDUwJSBa
RlMKIAkJaWYgZl9leHBhbmRfbnVtYmVyICIkWkZTQk9PVF9TV0FQX1NJWkUiIHN3YXBzaXplICYm
Ci0JCSAgIGZfZXhwYW5kX251bWJlciAiJFpGU0JPT1RfQk9PVF9QT09MX1NJWkUiIGJvb3RzaXpl
CisJCSAgIGZfZXhwYW5kX251bWJlciAiJFpGU0JPT1RfQk9PVF9QT09MX1NJWkUiIGJvb3RzaXpl
ICYmCisJCSAgIGZfZXhwYW5kX251bWJlciAiJFpGU0JPT1RfUE9PTF9TSVpFIiBwb29sc2l6ZQog
CQl0aGVuCiAJCQltaW5zaXplPSRzd2Fwc2l6ZSB0ZWVueV9kaXNrcz0KIAkJCVsgIiRaRlNCT09U
X0JPT1RfUE9PTCIgXSAmJgo=
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
# Copy the generated /boot/loader.conf and /etc/fstab
######################################################################

cat /tmp/bsdinstall_boot/loader.conf.* > /mnt/boot/loader.conf
chmod 644 /mnt/boot/loader.conf
install -d -m 755 /mnt/etc
install    -m 644 /tmp/bsdinstall_etc/fstab /mnt/etc/fstab

######################################################################
# Check if local distribution exists, if so copy to mnt
######################################################################

########## this notation /boot/.. is in case /boot is a symlink (eg. mfsroot)
distdir=/boot/../${release}
if [ ! -e $distdir/kernel.txz -o ! -e $distdir/base.txz ]; then
distdir=/mnt/boot/../${release}
else
install -d -m 755 /mnt/${release}
tar cf - -C /boot/.. ${release} | tar -C /mnt/boot/.. -xf -
fi
install -d -m 755 $distdir

######################################################################
# Fetch distribution if no local copy exists
######################################################################

if [ ! -e $distdir/kernel.txz -o ! -e $distdir/base.txz ]; then
DISTRIBUTIONS="kernel.txz base.txz" \
BSDINSTALL_DISTDIR=$distdir \
BSDINSTALL_DISTSITE="http://ftp4.freebsd.org/pub/FreeBSD/releases/`uname -m`/`uname -p`/${release}" \
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
# Set some loader.conf options
######################################################################

/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" aesni_load="YES"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" ahci_load="YES"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" autoboot_delay="1"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" geom_eli_load="YES"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" geom_label_load="YES"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" geom_mirror_load="YES"
########## hw.bge.allow_asf for my HP server to stop network disconnect
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "hw.bge.allow_asf=0"
########## hw.usb.no_shutdown_wait allows USB not to stall poweroff
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "hw.usb.no_shutdown_wait=1"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" if_lagg_load="YES"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "kern.cam.boot_delay=10000"
########## I prefer no disk ID
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "kern.geom.label.disk_ident.enable=0"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "kern.geom.label.gpt.enable=0"
########## But I allow UUID
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "kern.geom.label.gptid.enable=1"
########## Kernel max
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "kern.maxfiles=65530"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "kern.maxswzone=512M"
########## loader_logo should stop logo from showing, appears to be BROKEN
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" loader_logo="none"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" nullfs_load="YES"
########## tmpfs_load for mfsroot /usr
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" tmpfs_load="YES"
########## vfs.zfs.arc_max limit arc usage on low RAM systems
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "vfs.zfs.arc_max=256M"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" zfs_load="YES"

######################################################################
# Set some rc.conf options
######################################################################

#	/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" ntpdate_hosts=""
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" auditd_enable="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" entropy_file="/var/db/entropy-file"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" ftpproxy_enable="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" ntpdate_enable="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" openntpd_enable="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" pf_enable="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" pf_rules="/etc/pf/pf.conf"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" pflog_enable="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" pflog_logfile="/var/log/pflog"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" sendmail_enable="NO"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" sendmail_submit_enable="NO"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" sendmail_outbound_enable="NO"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" sendmail_msp_queue_enable="NO"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" sshd_enable="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" sshd_rsa1_enable="NO"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" sshd_dsa_enable="NO"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" syslogd_flags="-s -b127.0.0.1"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" zfs_enable="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" virtio_load="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" virtio_pci_load="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" virtio_blk_load="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" if_vtnet_load="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" virtio_balloon_load="YES"
/usr/sbin/sysrc -f "${mnt}/etc/rc.conf" linux_enable="YES"

######################################################################
# Set ifconfig DHCP
######################################################################

chroot $mnt sh <<EOF
#!/bin/sh
ifconfig -l | tr ' ' '\n' | while read line ; do if [ "\$line" != "lo0" -a "\$line" != "pflog0" ]; then sysrc -f /boot/rc.conf.append ifconfig_\${line}=DHCP ; fi ; done
EOF

######################################################################
# Set lagg as optional comments
######################################################################

chroot $mnt sh <<EOF
#!/bin/sh
echo '########## To enable Link Aggregation: BEGIN' >> /boot/rc.conf.append
ifconfig -l | tr ' ' '\n' | while read line ; do if [ "\$line" != "lo0" -a "\$line" != "pflog0" ]; then echo 'ifconfig_\${line}="up"' >> /boot/rc.conf.append ; fi ; done
ifconfig -l | tr ' ' '\n' | while read line ; do if [ "\$line" != "lo0" -a "\$line" != "pflog0" ]; then nics="\$nics laggport \${line}" ; fi ; done
echo '# cloned_interfaces="lagg0"' >> /boot/rc.conf.append
echo '# ifconfig_lagg0="laggproto failover \$nics DHCP"' >> /boot/rc.conf.append
echo '########## To enable Link Aggregation: END' >> /boot/rc.conf.append
EOF

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
install -d -m 755 /mnt2
echo "Making new fs on /dev/${mdevice}"
newfs /dev/${mdevice} || exiterror $?
echo "Mouting /dev/${mdevice} to /mnt2"
mount /dev/${mdevice} /mnt2 || exiterror $?
########## Copy everything except /usr
echo "Copying ${mnt} to /mnt2"
tar -c -f - \
--exclude $bpool \
--exclude /boot \
--exclude null \
--exclude ${release} \
--exclude usr \
-C ${mnt} ./ | tar -C /mnt2 -x -f - || exiterror $?
########## rc script for tmpfs /usr
########## modified from https://github.com/mmatuska/mfsbsd
cat >/mnt2/etc/rc.d/mdinit <<EOF
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
    echo "Something went wrong in mdinit while extracting /usr, entering shell:"
    /rescue/sh
  fi
  if zfs list -H -o name,canmount,mountpoint | awk '\$2 ~ /on/ {print}' | grep 'on[^/]*/\$' ; then
    echo "Disabling some zfs datasets that mount to /"
    DATASETS=\$(zfs list -H -o name,canmount,mountpoint | awk '\$2 ~ /on/ {print}' | grep 'on[^/]*/\$' | awk '{print \$1}')
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
chmod 555 /mnt2/etc/rc.d/mdinit
########## appendconf because we are in mfs and harder to persist
cat >/mnt2/etc/rc.d/appendconf <<EOF
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
  if [ -f /boot/rc.conf.append ]; then
    cat /boot/rc.conf.append | grep hostname >> /etc/rc.conf.d/hostname
    cat /boot/rc.conf.append | grep ifconfig_ >> /etc/rc.conf.d/network
    cat /boot/rc.conf.append | grep cloned_interfaces >> /etc/rc.conf.d/network
    cat /boot/rc.conf.append | grep defaultrouter >> /etc/rc.conf.d/routing
    cat /boot/rc.conf.append | grep static_routes >> /etc/rc.conf.d/routing
    cat /boot/rc.conf.append | grep route_ >> /etc/rc.conf.d/routing
    cat /boot/rc.conf.append | \
      grep -v hostname | \
      grep -v ifconfig_ | \
      grep -v defaultrouter | \
      grep -v static_routes | \
      grep -v route_ >> /etc/rc.conf
  fi
  if [ -f /boot/resolv.conf.overwrite ]; then
    cat /boot/resolv.conf.overwrite > /etc/resolv.conf
  elif [ -f /boot/resolv.conf.append ]; then
    cat /boot/resolv.conf.append >> /etc/resolv.conf
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
chmod 555 /mnt2/etc/rc.d/appendconf
########## Package /usr
echo "Compressing ${mnt}/usr to /mnt2/.usr.tar.xz"
tar -c -J -f /mnt2/.usr.tar.xz --exclude ${release} --options xz:compression-level=9 -C ${mnt} usr || exiterror $?
########## Unmount
echo "Unmounting /dev/${mdevice}"
umount /dev/${mdevice} || exiterror $?
mdconfig -d -u ${mdevice#md} || exiterror $?
########## mfs_ settings in loader.conf
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" mfs_load="YES"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" mfs_type="mfs_root"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" mfs_name="/mfsroot"
/usr/sbin/sysrc -f "${mnt}/boot/loader.conf" "vfs.root.mountfrom=ufs:/dev/md0"
########## optional set mdinit_shell
# /usr/sbin/sysrc -f "${mnt}/boot/loader.conf" mdinit_shell="YES"
fi

######################################################################
# Remind user that they should change password of new system
######################################################################

cat <<EOF
Don't export the ZFS pools!
You may want to set the hostname:
       sysrc -f "${mnt}/boot/rc.conf.append" hostname="name"
You should probably change the root password of the new system:
       chroot $mnt passwd
EOF
