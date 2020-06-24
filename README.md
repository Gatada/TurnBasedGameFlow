# TurnBasedGameFlow
There are a couple of other skeleton projects out there, showing how GameKit is used. However, I have yet to find one that is up-to-date and shows everything with a minimum of code.

This Xcode project contains one view controller, Simple. It does everything: updates the UI, deals with GameKit and all interactions from the player.

## Features
This projects shows how to correctly:

1. End a turn.
1. Quit a game in and out-of-turn.
1. Update the game without ending turn.
1. Request, cancel, reply and resolve exchanges. See how to:
	* Invite one player to trade with (for simplicity, this app only supports one recipient).
	* Reply to an exchange or let it time out, which either way moves the `.active` exchange to `.completed`.
	* And finally how the turn holder resolves a completed exchange (for now this happens only when loading the game).

The app uses a string as game data. For every turn, update and exchange a new string is appended to the match data so you can see what is happening. The tail of the string is shown in the interface as Match Data.

According to Apple, the turn holder should receive a notification when an exchange is completed, however this is not happening. I have reached out to Apple to get this resolved.
Meanwhile, you will have to reload the game to resolve completed exchanges.


## Use Two or Three Devices

To get game related push notifications, you will have to use two devices (not the simulator), each logged in with a different Game Center player. However, the app supports 2 and 3 player games without any modifications. Simply set the number of players in the match maker controller when creating a new game.

To get two random opponents to find each other, I usually have to create at least two games on each device. You should also end the first turn on all the games you create. Of course, to avoid all of that you can simply invite the other player(s).

# Feedback Welcome!

If you have suggestions for improving the project, please create a pull request. Alternatively you can reach me on Twitter @johanhwb.

I hope you find this project useful.
