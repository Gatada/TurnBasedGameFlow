# TurnBasedGameFlow

There are a couple of other skeleton projects out there, showing how GameKit is used.
However, I have yet to find one that is up-to-date, shows everything with a minimum of code.

This Xcode project contains one view controller, Simple. It does everything: updates the UI, deals with GameKit and all
interactions from the player.

The game data is just a date. Everything works, however any completed exchanges are not resolved until the match is reloaded by the current turn holder. According to Apple, the turn holder should receive a notification when an exchange is resolved - however I'm not seeing any event happening.

If you know how to get exhanges to work properly, then please let me know.

## Use Two Devices

To get the push notifications, you will have to use two devices. Each device logged in with a different Game Center player.

To get to random opponent games to find each other, I usually have to create at least two games on each device. I also
find that committing the first turn on all the games helps. Of course, to avoid this you can simply invite the other player.

# Feedback Welcome!

If you know how to make exchanges work, please create a pull request.

I hope you find this project useful.
