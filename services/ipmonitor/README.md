# Intro
Some services like Coturn, IPFS, DDNS updater... needs know their own public IP or needs to be restarted when public IP address has changed. this service periodically checks public IP to fix this problem.

# Status
Seems working

# TODO
currenly it needs a static URL to curl to findout our public IP, but there are some alternates:
- use a public STUN server
- use upnp client
- query IP address of own domain using DNS(and then confirm it it's really ours public IP)
