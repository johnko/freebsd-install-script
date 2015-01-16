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
fzg -d disk [-d disk ...] [-e disk]
        [-b boot_size] [-h] [-m] [-M /mnt] [-p poolname]
        [-r stripe|mirror|raidz|raidz2|raidz3] [-s swap_size] [-v]
        [-z pool_size]

        -b size  Boot partition size.
        -d disk  Disk to install on (eg. da0).
        -e disk  Attach to this existing disk that is part of -p pool.
        -h       Help.
        -m       Create mfsroot type of system.
        -M mount Mountpoint, if not using /mnt.
        -p name  ZFS pool name, must be unique.
        -r       Select ZFS raid mode if multiple -d given.
        -s size  Swap partition size.
        -v       Version.
        -z size  ZFS pool size.

fzg -f [-p poolname]

        -f       freebsd-update / make a new mfsroot.

fzg -i -d vdev [-d vdev ...] [-p poolname] [-x]
fzg -i -e vdev -d vdev [-p poolname]
fzg -u -d vdev [-d vdev ...] [-p poolname]
fzg -l [-p poolname]

        -i       Initialize data partition with geli and create pool.
                 Automatically create partition 5 unless -x is set.
        -l       Export pool and lock data partition.
        -u       Unlock data partition and mount pool.
        -x       Explicit -d device, don't create partition 5 automatically.
        -d vdev  Virtual device to grab gptid label from (eg. da0p5)

```

# Typical usage:

Install on mirror, make /bootpool/mfsroot
```
fzg -d ada0 -d ada1 -z 2g -m
```

Update /bootpool/mfsroot
```
fzg -f
reboot
```

Create /tank
```
fzg -i
```

Unlock /tank
```
fzg -u
```

Unmount and lock /tank
```
fzg -l
```

# Examples:

Install on disk 0, pool name mini with size 2 GB:
```
fzg -d ada0 -z 2g
```

Add disk 1 as mirror to existing pool mini that contains disk ada0:
```
fzg -e ada0 -d ada1 -z 2g
```

After rebooting again, we can add data partition automatically and create pool tank:
```
fzg -i
```

Create another data partition and attach to pool tank:
```
fzg -i -e ada0p5 -d ada1
```

# Other examples:

Install on 3 mirror disks, a boot pool 1 GB, swap 1 GB, ZFS root pool 2 GB:
```
fzg -d ada0 -d ada1 -d ada2 -b 1g -s 1g -z 2g -r mirror
```

Make a bootable ZFS USB, which loads as mfs:
Note we change the pool name so they don't conflict.
```
fzg -d da0 -m -p usb
```

Minimal mirror mfs server:
```
fzg -d ada0 -d ada1 -z 2g -m
```

After rebooting into the mfsroot system, it can be updated with:
```
fzg -f
```

Create data pool with these devices, no auto partition creation:
```
fzg -i -d ada0p5 -d ada1p5 -x
```

# FAQ

## Why name it "fzg"?
**F**reeBSD **Z**FS on **G**ELI Installer. I cut out the "i" because I wanted to be able to type 'fzg' with my left hand.
```
