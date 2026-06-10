# Intro
[Screego](https://github.com/screego/server) helps you to share your screen. Nothing else

# Status
needs more testing

# Notes
Screego does not have any hardcoded public STUN servers! Based on sourcecode:
- in [authModeToRoomMode function in frontend](https://github.com/screego/server/blob/f946cee83b61d9f47c2f1c2238fb31f4042b628a/ui/src/useConfig.ts#L61) sets the room type which indecates that this room should be routed through turn server or not(so we should use stun server instead) based on `SCREEGO_AUTH_MODE`
- [Rooms.newSession method](https://github.com/screego/server/blob/f946cee83b61d9f47c2f1c2238fb31f4042b628a/ws/room.go#L49) -> if user needs to connect through stun(room type is "stun") do `outgoing.ICEServer{ "stun" + the_rest_of_provided_server }` or when it needs to be routed through turn server(room type is "turn") do `outgoing.ICEServer{ "turn" + the_rest_of_provided_server }`

so if don't have any turn server and don't want to use screego buildin turn server do something like(`SCREEGO_TURN_EXTERNAL_SECRET` is not used but without it screego refuses to start):
SCREEGO_AUTH_MODE=turn
SCREEGO_TURN_EXTERNAL_IP="dns:stun.l.google.com"
SCREEGO_TURN_EXTERNAL_PORT=19302
SCREEGO_TURN_EXTERNAL_SECRET=dummy

