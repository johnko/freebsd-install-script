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
LS0tIHpmc2Jvb3QJMjAxNC0xMS0xNyAwNDo0Mzo1NS44MTg5NjE4ODIgKzAwMDAKKysrIC91c3Iv
bGliZXhlYy9ic2RpbnN0YWxsL3pmc2Jvb3QJMjAxNC0xMS0xNyAwNDozNTo0NS40MTY5OTU2MjQg
KzAwMDAKQEAgLTE4Miw5ICsxODIsOSBAQAogQ0hNT0RfTU9ERT0nY2htb2QgJXMgIiVzIicKIERE
X1dJVEhfT1BUSU9OUz0nZGQgaWY9IiVzIiBvZj0iJXMiICVzJwogRUNIT19BUFBFTkQ9J2VjaG8g
IiVzIiA+PiAiJXMiJwotR0VMSV9BVFRBQ0g9J2dlbGkgYXR0YWNoIC1qIC0gLWsgIiVzIiAiJXMi
JworR0VMSV9BVFRBQ0g9J2dlbGkgYXR0YWNoIC1wIC1rICIlcyIgIiVzIicKIEdFTElfREVUQUNI
X0Y9J2dlbGkgZGV0YWNoIC1mICIlcyInCi1HRUxJX1BBU1NXT1JEX0lOSVQ9J2dlbGkgaW5pdCAt
YiAtQiAiJXMiIC1lICVzIC1KIC0gLUsgIiVzIiAtbCAyNTYgLXMgNDA5NiAiJXMiJworR0VMSV9Q
QVNTV09SRF9JTklUPSdnZWxpIGluaXQgLWIgLUIgIiVzIiAtZSAlcyAtUCAtSyAiJXMiIC1sIDI1
NiAtcyA0MDk2ICIlcyInCiBHTk9QX0NSRUFURT0nZ25vcCBjcmVhdGUgLVMgNDA5NiAiJXMiJwog
R05PUF9ERVNUUk9ZPSdnbm9wIGRlc3Ryb3kgIiVzIicKIEdQQVJUX0FERD0nZ3BhcnQgYWRkIC10
ICVzICIlcyInCkBAIC0xMTUwLDE1ICsxMTUwLDYgQEAKIAkjIENyZWF0ZSB0aGUgZ2VsaSg4KSBH
RU9NUwogCSMKIAlpZiBbICIkWkZTQk9PVF9HRUxJX0VOQ1JZUFRJT04iIF07IHRoZW4KLQkJIyBQ
cm9tcHQgdXNlciBmb3IgcGFzc3dvcmQgKHR3aWNlKQotCQlpZiAhIG1zZ19lbnRlcl9uZXdfcGFz
c3dvcmQ9IiRtc2dfZ2VsaV9wYXNzd29yZCIgXAotCQkJZl9kaWFsb2dfaW5wdXRfcGFzc3dvcmQK
LQkJdGhlbgotCQkJZl9kcHJpbnRmICIkZnVuY25hbWU6IFVzZXIgY2FuY2VsbGVkIgotCQkJZl9z
aG93X2VyciAiJG1zZ191c2VyX2NhbmNlbGxlZCIKLQkJCXJldHVybiAkRkFJTFVSRQotCQlmaQot
CiAJCSMgSW5pdGlhbGl6ZSBnZWxpKDgpIG9uIGVhY2ggb2YgdGhlIHRhcmdldCBwYXJ0aXRpb25z
CiAJCWZvciBkaXNrIGluICRkaXNrczsgZG8KIAkJCWZfZGlhbG9nX2luZm8gIiRtc2dfZ2VsaV9z
ZXR1cCIgXAo=
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
bsdinstall zfsboot

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
bsdinstall distfetch
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
bsdinstall distextract

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
# Set ifconfig SYNCDHCP
######################################################################

chroot $mnt sh <<EOF
#!/bin/sh
ifconfig -l | tr ' ' '\n' | while read line ; do if [ "\$line" != "lo0" -a "\$line" != "pflog0" ]; then sysrc -f /boot/rc.conf.append ifconfig_\${line}=DHCP ; fi ; done
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
dd if=/dev/zero of=${mnt}/${bpool}/mfsroot bs=512 count=245760
mdevice=`mdconfig -a -t vnode -f ${mnt}/${bpool}/mfsroot`
install -d -m 755 /mnt2
newfs /dev/${mdevice}
mount /dev/${mdevice} /mnt2
########## Copy everything except /usr
tar -c -f - \
--exclude $bpool \
--exclude /boot \
--exclude null \
--exclude ${release} \
--exclude usr \
-C ${mnt} ./ | tar -C /mnt2 -x -f -
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
    cat /boot/rc.conf.append | grep defaultrouter >> /etc/rc.conf.d/routing
    cat /boot/rc.conf.append | grep static_routes >> /etc/rc.conf.d/routing
    cat /boot/rc.conf.append | grep route_ >> /etc/rc.conf.d/routing
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
tar -c -J -f /mnt2/.usr.tar.xz --exclude ${release} --options xz:compression-level=9 -C ${mnt} usr
########## Unmount
umount /dev/${mdevice}
mdconfig -d -u ${mdevice#md}
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
You should probably change the root password of the new system:
       chroot $mnt passwd
EOF
