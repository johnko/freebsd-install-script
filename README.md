freebsd-install-script
=========================

experimental script(s) for installing FreeBSD using bsdinstall

Mildly tested on FreeBSD 10.2-RELEASE

# GPT Disk Partitions
```
ada0
   +- ada0p1 (bootcode)
   +- ada0p2
   |       `- geli onetime from fstab
   |               `- swap
   +- ada0p3
   |       `- zfs "pool"
   `- ada0p4
           `- geli manual unlock or optionally with /etc/rc.d/zpoolimportthengeli
                   `- zfs "tank"
```
