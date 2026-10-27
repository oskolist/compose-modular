# Intro
a golang-based lightweight but moderm IRC server

# Status
good

# Notes
Unfortunately customizing simple configuration such as enable/disabling SSL and ... using `.env` is not possible. i tried to do it anyway in `ergo-todo.yaml` but because of buggy `envsubst`, it does not work either. So for enable/disable ssl, raw irc support... you need to edit `ergo.yaml` and then `compose.yaml`(i guess)
