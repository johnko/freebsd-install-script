freebsd-install-script
=========================

experimental script(s) for installing FreeBSD using bsdinstall

Mildly tested on FreeBSD 10.1-RELEASE

# Usage

freebsd-zfs-geli-pwless.sh -d disk [-d disk ...] [-e disk]
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

# Examples:

  Install on disk 0:
       $0 -d ada0 -z 2g -p mini

  Add disk 1 as mirror to an existing pool that contains disk 0:
       $0 -e ada0 -z 2g -p mini -d ada1

# Other examples:

  Install on 3 mirror disks, a boot pool 1 GB, swap 1 GB, ZFS root pool 2 GB:
       $0 -d ada0 -d ada1 -d ada2 -b 1g -s 1g -z 2g -r mirror

  Make a bootable ZFS USB, which loads as mfs:
       $0 -d da0 -m -p usb
  Note we change the pool name so they don't conflict.

  Minimal mirror mfs server:
       $0 -d ada0 -d ada1 -z 2g -f -m -p mini
