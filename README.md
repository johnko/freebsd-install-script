freebsd-install-script
=========================

experimental script(s) for installing FreeBSD using bsdinstall

Mildly tested on FreeBSD 10.1-RELEASE

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

# Examples:

Install on disk 0, pool name mini with size 2 GB:
```
fzg -d ada0 -z 2g -p mini
```

Add disk 1 as mirror to existing pool mini that contains disk ada0:
```
fzg -e ada0 -d ada1 -z 2g -p mini
```

After rebooting into the new system, it can be updated with:
```
fzg -f -p mini
```

After rebooting again, we can add data partition automatically and create pool tank:
```
fzg -i -d ada0 -p tank
```

Create another data partition and attach to pool tank:
```
fzg -i -e ada0p5 -d ada1 -p tank
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
fzg -d ada0 -d ada1 -z 2g -m -p mini
```

Create data pool with these devices, no auto partition creation:
```
fzg -i -d ada0p5 -d ada1p5 -p data -x
```
