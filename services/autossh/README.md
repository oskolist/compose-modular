# Intro
[this image](https://github.com/jnovack/autossh) contains a customizable AutoSSH docker container

# Status
seems ok

# TODO
- although this image seems ok but it does not have support for `-D`(dynamic port port forwarding) and does not allow custom ssh options. I prefer to just a simple alpine-based image with autossh and ncat(for socks5 support) preinstall which allows me to use custom `autossh` command
