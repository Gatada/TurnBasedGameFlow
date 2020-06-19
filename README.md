# TurnBasedGameFlow

There are a couple of other skeleton projects out there, showing how GameKit is used. However, I have yet to find one that is up-to-date and shows everything with a minimum of code. This projects shows how to correctly:

1. End a turn.
1. Update the game without ending turn.
1. Implement exchanges:
	* Invite one player to trade with (this app only supports one recipient).
	* Reply to an exchange.
	* And finally how turn holder resolves an exchange (currently only when loading the game).

This Xcode project contains one view controller, Simple. It does everything: updates the UI, deals with GameKit and all interactions from the player.

The game data is just a date. Everything works, however any completed exchanges are not resolved until the match is reloaded by the current turn holder. According to Apple, the turn holder should receive a notification when an exchange is resolved - however I'm not seeing any event happening.

If you know how to get exhanges to work properly, then please let me know.

## Use Two or Three Devices

To get the push notifications, you will have to use two devices, each logged in with a different Game Center player. However, the app supports 2 and 3 player games without any modifications. Simply set the number of players in the match maker controller when creating a new game.

To get two random opponents to find each other, I usually have to create at least two games on each device. You should also end the first turn on all the games you create. Of course, to avoid all of that you can simply invite the other player(s).

# Feedback Welcome!

If you know how to make exchanges work, please create a pull request.

I hope you find this project useful.
