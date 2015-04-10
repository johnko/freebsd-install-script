freebsd-install-script
=========================

experimental script(s) for installing FreeBSD using bsdinstall

Uses geom_eli, aka [geli](http://www.freebsd.org/cgi/man.cgi?geli%288%29) under ZFS.

Mildly tested on FreeBSD 10.1-RELEASE

# GPT Disk Partitions
```
ada0
   +- ada0p1 (bootcode)
   +- ada0p2
   |       `- zfs "bootpool", contains /boot, 10.1-RELEASE dist files, and may contain mfsroot
   +- ada0p3
   |       `- geli onetime from fstab
   |               `- swap
   +- ada0p4
   |       `- geli auto unlock with settings from /boot/loader.conf.local
   |               `- zfs "pool"
   `- ada0p5
           `- geli manual unlock (fzg -u) or optionally add settings in /boot/loader.conf.local
                   `- zfs "tank"
```

# Usage

```
usage:  fzg -d disk [-d disk ...] [-e disk]
    [-b boot_size] [-D] [-h] [-m] [-M /mnt] [-p poolname]
    [-r stripe|mirror|raidz|raidz2|raidz3] [-s swap_size] [-v]
    [-z pool_size]

    -b size     Boot partition size.
    -c          Configure sshd_config, loader.conf and rc.conf, rc.conf.d.
    -C          Same as -c plus loader.conf.local and rc.conf.local.
    -D          Dedup on.
    -d disk     Disk to install on (eg. da0).
    -e disk     Attach to this existing disk that is part of -p pool.
    -h          Help.
    -m          Create mfsroot type of system.
    -M mount    Mountpoint, if not using /mnt.
    -n          Don't prompt to change password.
    -p name     ZFS pool name, must be unique.
    -r          Select ZFS raid mode if multiple -d given.
    -s size     Swap partition size.
    -v          Version.
    -z size     ZFS pool size.

    fzg -f [-n] [-p poolname]

    -f          freebsd-update / make a new mfsroot.

    fzg -i -d vdev [-d vdev ...] [-p poolname] [-x] [-D]
    fzg -i -e vdev -d vdev [-p poolname] [-D]
    fzg -u -d vdev [-d vdev ...] [-p poolname]
    fzg -l [-p poolname]

    -i          Initialize data partition with geli and create pool.
                Automatically create partition 5 unless -x is set.
    -l          Export pool and lock data partition.
    -u          Unlock data partition and mount pool.
    -x          Explicit -d device, don't create partition 5 automatically.
    -D          Dedup on.
    -d vdev     Virtual device to grab gptid label from (eg. da0p5)
```

# Typical usage:

```
Install on mirror, make /bootpool/mfsroot
    fzg -d ada0 -d ada1 -z 2g -m -D
Update /bootpool/mfsroot, reboot to take effect
    fzg -f
    reboot
Create /tank
    fzg -i -D
Unlock /tank
    fzg -u
Unmount and lock /tank
    fzg -l
```

# Examples:

```
Install on disk 0, pool name mini with size 2 GB:
    fzg -d ada0 -z 2g -p mini -D
Add disk 1 as mirror to existing pool mini that contains disk ada0:
    fzg -e ada0 -d ada1 -z 2g -p mini
After rebooting again, add data partition automatically + create pool tank:
    fzg -i -d ada0 -p tank -D
Create another data partition and attach to pool tank:
    fzg -i -e ada0p5 -d ada1 -p tank
```

# Other examples:

```
Install on 3 mirror disks, a boot pool 1 GB, swap 1 GB, ZFS root pool 2 GB:
    fzg -d ada0 -d ada1 -d ada2 -b 1g -s 1g -z 2g -r mirror -D
Make a bootable ZFS USB, which loads as mfs:
Note we change the pool name so they don't conflict.
    fzg -d da0 -m -p usb -D
Minimal mirror mfs server:
    fzg -d ada0 -d ada1 -z 2g -m -p mini -D
After rebooting into the new mfsroot system, it can be updated with:
    fzg -f -p mini
Create data pool with these devices, no auto partition creation:
    fzg -i -d ada0p5 -d ada1p5 -p data -x -D
```

# FAQ

## Why name it "fzg"?
**F**reeBSD **Z**FS on **G**ELI Installer. I cut out the "i" because I wanted to be able to type 'fzg' with my left hand.
```
