# 9p filesystem
Implementation of [9p](http://9p.cat-v.org/) protocol/serving a filesystem over 9p.

This starts a server in `./exampleroot/` (or any other selected directory) over 9p so it can be mounted remotely.

This is also a recreational programming project so basically don't expect high quality anything. works on my machine.


Basically, this is a server/filesystem that you can mount remotely (with something like `mount -t 9p -o trans=tcp,port=4000,version=9p2000 [SERVER_IP] [MOUNT_POINT]`), and you can use it as any other linux file/directory.
