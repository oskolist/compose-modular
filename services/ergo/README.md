# Intro
a golang-based lightweight but moderm IRC server

# Status
good

# Notes
unfortunately customizing simple configuration such as enable/disabling SSL and ... using `.env` is not possible(needs who understand `jq` which i don't). i tried to do it anyway in `ergo-todo.yaml` but because of buggy `envsubst` which does not work either.
so for enable/disable ssl, raw irc support... you need to edit `ergo.yaml` and then `compose.yaml`(i guess)
