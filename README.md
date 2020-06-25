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
	* And finally how the turn holder resolves the completed exchange after receiving a notification (this notification is currently not being sent by Apple, further details below).

The app uses a string as game data. For every turn, update and exchange a new string is appended to the match data so you can see what is happening. The tail of the string is shown in the interface as Match Data.

### Missing Notification for Turn Holder
Apple has confirmed that the turn holder should receive a notification when an exchange is completed, and also confirmed that this is currently not happening. Apple will fix it as soon as possible (as this is entirely on the server side, the fix may be rolled out independently from any iOS update).

The Apple tech I talked to recommends that you simply develop your game that uses GKTurnBasedExchanges as if your game will receive the notification.

I would also recommend that you find an elegant way to handle the error that the turn holder will get when trying to end a turn or update the game while one or more completed exhanges remain unresolved. This project already handles this, albeit with a very crude error handling (I may update this later).

In other words, when the turn holder tries to end the turn or update the game, when you get the error simply inform the player and reload the game (so that the completed exchanges are resolved).

I have created [this thread on the Apple developer forum](https://developer.apple.com/forums/thread/649766).

## Use Two or Three Devices

To get game related push notifications, you will have to use two devices (not the simulator), each logged in with a different Game Center player. However, the app supports 2 and 3 player games without any modifications. Simply set the number of players in the match maker controller when creating a new game.

To get two random opponents to find each other, I usually have to create at least two games on each device. You should also end the first turn on all the games you create. Of course, to avoid all of that you can simply invite the other player(s).

# Feedback Welcome!

If you have suggestions for improving the project, please create a pull request. Alternatively you can reach me on Twitter @johanhwb.

I hope you find this project useful.
