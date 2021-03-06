//
//  Simple.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 04/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit
import GameKit


// Register multiple listeners:
// ■ AppDelegate for new turn and activations
// ■ Match view controller for updates to the current match


/// One controller to rule them all.
class Simple: UIViewController {
    
    // MARK: - Interface Objects

    @IBOutlet weak var matchMaker: UIButton!
    
    @IBOutlet weak var matchState: UILabel!
    @IBOutlet weak var localPlayerState: UILabel!
    @IBOutlet weak var localPlayerOutcome: UILabel!
    @IBOutlet weak var opponentStatus: UILabel!
    @IBOutlet weak var opponentOutcome: UILabel!
    @IBOutlet weak var exchangeHistory: UILabel!
    @IBOutlet weak var turnSequence: UILabel!
    
    @IBOutlet weak var updateMatch: BackgroundFilledButton!
    @IBOutlet weak var sendReminder: BackgroundFilledButton!
    @IBOutlet weak var endTurn: BackgroundFilledButton!
    @IBOutlet weak var endTurnWin: BackgroundFilledButton!
    @IBOutlet weak var endTurnLose: BackgroundFilledButton!
    @IBOutlet weak var beginExchange: BackgroundFilledButton!
    
    @IBOutlet weak var matchID: UILabel!
    @IBOutlet weak var rematch: UIButton!
    @IBOutlet weak var quitInTurn: UIButton!
    
    @IBOutlet weak var versionBuild: UILabel!
    
    
    // MARK: - PROPERTIES

    /// A manager that handles the alert controller queuing and presentation.
    private var alertManager: AlertManager?
    
    /// An audio player that plays a single sound.
    private var player: AVAudioPlayer?

    /// The time out duration for a turn.
    ///
    /// Set to a value that is helpful for development.
    let turnTimeout: TimeInterval = 60 * 10 // 10 min to speed up testing
    
    /// Match data for currently selected match.
    var matchData: Data?
    
    /// Returns `true` if the local player has been authenticated, `false` otherwise.
    public var localPlayerIsAuthenticated: Bool {
        return GKLocalPlayer.local.isAuthenticated
    }
    
    /// A boolean that is `true` iff authentication returns with an error.
    public var authenticationCompleted: Bool = false
    
    var localParticipant: GKTurnBasedParticipant? {
        guard let match = currentMatch else {
            return nil
        }
        let opponents = match.participants.filter { (participant) -> Bool in
            participant.player == GKLocalPlayer.local
        }
        return opponents.first
    }
    var currentMatch: GKTurnBasedMatch? = nil {
        didSet {
            print("Current match was updated..")
            UIApplication.shared.isIdleTimerDisabled = (currentMatch != nil)
        }
    }
    
    // MARK: - LIFE CYCLE

    override func viewDidLoad() {
        super.viewDidLoad()
        setupGameCenter()
        authenticatePlayer()
        prepareAudio()
        resetInterface()
        versionBuild.text = AppDelegate.versionBuild
        alertManager = AlertManager()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshInterface()
    }
    
    
    // MARK: - SETUP
    
    func setupGameCenter() {
        // Registering the GKLocalPlayerListener to receive all events.
        // This must only be done once.
        GKLocalPlayer.local.register(self)
    }
    
    
    // MARK: - INTERFACE
    
    func refreshInterface() {
        
        assert(Thread.isMainThread)
        
        matchMaker.isEnabled = authenticationCompleted && GKLocalPlayer.local.isAuthenticated
        
        guard let match = currentMatch else {
            resetInterface()
            return
        }
        
        // Various states needed to correctly refresh interface.

        let gameEnded = match.status == .ended
        let isResolvingTurn = match.currentParticipant?.player?.teamPlayerID == GKLocalPlayer.local.teamPlayerID
        let opponentsStillPlaying = !match.participants.filter({ $0.player?.teamPlayerID != GKLocalPlayer.local.teamPlayerID && $0.matchOutcome == .none }).isEmpty
        let hasLocalOutcome = localParticipant?.matchOutcome != GKTurnBasedMatch.Outcome.none
        let isMatching = match.status == .matching
        
        updateMatch.isEnabled = isResolvingTurn && opponentsStillPlaying
        endTurn.isEnabled = isResolvingTurn && opponentsStillPlaying
        endTurnWin.isEnabled = isResolvingTurn
        endTurnLose.isEnabled = isResolvingTurn && opponentsStillPlaying
        
        // These two buttons occupy same screen real-estate:
        quitInTurn.isHidden = gameEnded
        rematch.isHidden = !gameEnded
        
        quitInTurn.isEnabled = !hasLocalOutcome
        
        if !quitInTurn.isHidden {
            quitInTurn.setTitle(isResolvingTurn ? "Quit In Turn!" : "Quit Out-of-Turn!", for: UIControl.State())
        }
        
        beginExchange.isEnabled = !isMatching && !gameEnded && opponentsStillPlaying

        // Only enable reminders while out of turn.
        let canSendReminder = !(gameEnded || isMatching || isResolvingTurn || hasLocalOutcome)
        
        var allowReminder = false
        if let lastMoveDate = localParticipant?.lastTurnDate {
            
            // Reminders are throttled by Apple; here we require the player
            // to wait half the duration of the turn timeout.
            
            let elapsed = Date().timeIntervalSince(lastMoveDate)
            allowReminder = (elapsed > (turnTimeout / 2))
        }
            
        sendReminder.isEnabled = allowReminder && canSendReminder
        
        matchID.text = match.matchID
        matchState.text = "\(stringForMatchStatus(match.status))"

        var aggrigateStatus = ""
        var aggrigateOutcome = ""
        var comma = ""
        for participant in match.participants {
            guard participant != self.localParticipant else {
                localPlayerState.text = stringForPlayerState(participant.status)
                localPlayerOutcome.text = stringForPlayerOutcome(participant.matchOutcome)
                continue
            }
            aggrigateStatus += comma + stringForPlayerState(participant.status)
            aggrigateOutcome += comma + stringForPlayerOutcome(participant.matchOutcome)
            comma = ", "
        }
        opponentStatus.text = aggrigateStatus
        opponentOutcome.text = aggrigateOutcome
        
        if let data = match.matchData, let dataAsString: String = Utility.codableInstance(from: data) {
            turnSequence.text = dataAsString
            print("Match data: \(dataAsString)")
        } else {
            turnSequence.text = " "
            print("Match data: n/a")
        }
        
        exchangeHistory.text = "\(match.activeExchanges?.count ?? 0) active / \(match.completedExchanges?.count ?? 0) completed / \(match.exchanges?.count ?? 0) total"
        
        // Now check if game is over:
        // print("Game is \(gameEnded ? "over" : "active").")
    }

    // MARK: - USER INTERACTION
    
    @IBAction func quitMatchInTurnTap(_ sender: Any) {
        guard let match = currentMatch else {
            // print("Tried to quit a match when no match is selected.")
            return
        }
        player(GKLocalPlayer.local, wantsToQuitMatch: match)
    }
    
    @IBAction func matchMakerTap(_ sender: Any) {
        
        let localPlayerName = GKLocalPlayer.local.displayName
        let request = prepareMatchRequest(withInviteMessage: "\(localPlayerName) wants to play!", usingAutomatch: false)
        
        let matchMaker = GKTurnBasedMatchmakerViewController(matchRequest: request)
        matchMaker.turnBasedMatchmakerDelegate = self
        matchMaker.showExistingMatches = true
        
        currentMatch = nil
        refreshInterface()
        
        self.present(matchMaker, animated: true, completion: nil)
    }
    
    @IBAction func beginExchangeTap(_ sender: Any) {
        // print("Tapped to begin Exchange")
        
        guard let alertManager = alertManager else {
            assertionFailure("No AlertManager has been initialized")
            return
        }
        
        guard let match = currentMatch else {
            assertionFailure("No match set. This button should've been disabled.")
            return
        }

        let alert = tradeAlertForMatch(match)
        alertManager.presentOrQueueAlert(alert, withMatchInfo: (match.matchID, .creatingExchange))
    }
    
    
    /// A reminder can only be sent when the recipient is not already interacting with the related game.
    @IBAction func sendReminderTap(_ sender: Any) {
        
        guard let match = currentMatch else {
            // print("No match set for sending a reminder.")
            return
        }
        
        let stringArguments = [String]()
        guard let sleepingParticipant = match.currentParticipant else {
            return
        }
                
        currentMatch?.sendReminder(to: [sleepingParticipant], localizableMessageKey: "Want to make a move?", arguments: stringArguments) { [weak self] error in
            if let receivedError = error {
                // print("Failed to send reminder for match \(self?.currentMatch?.matchID ?? "N/A"):")
                self?.handleError(receivedError)
                return
            }

            // print("Sent reminder for match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
        }
    }
    
    
    /// Updates the match data.
    ///
    /// To be able to update the match data, it seems like all exchanges must be resolved. I can see that
    /// this would make sense, as the update will also affect the match data.
    @IBAction func updateMatchTap(_ sender: Any) {

        guard let match = currentMatch else {
            // Invalid state
            assertionFailure("Trying to update a match when none is set.")
            return
        }

        print("Update match \(match.matchID)")
        
        guard let matchData = updatedMatchDataWithString(stringForUpdateInMatch(match), forMatch: match) else {
            print("Failed to merge match data")
            return
        }
        
        self.currentMatch?.saveCurrentTurn(withMatch: matchData) { [weak self] error in
            if let receivedError = error {
                self?.handleError(receivedError)
                return
            }
            
            print("Updated match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
        }
    }
    
   
    @IBAction func endTurnTap(_ sender: Any) {
        
        // From session #506 at WWDC 2013:
        // https://developer.apple.com/videos/play/wwdc2013/506/
        // Last participant on list does not time out.
        // Include yourself last.
        
        guard let match = self.currentMatch else {
            // print("No opponent for match \(self?.currentMatch?.matchID ?? "N/A")")
            return
        }
        
        let nextParticipants = self.nextParticipantsForMatch(match)
        let timeout = self.turnTimeout
        
        var turns: String = ""
        if let data = match.matchData, let receivedTurns: String = Utility.codableInstance(from: data) {
            turns += receivedTurns
        }
        
        guard let updatedData = Utility.data(fromCodable: turns + stringForEndTurnInMatch(match)) else {
            print("Failed to encode match data")
            return
        }
        
        // Localized message to be set at end of turn or game:
        self.currentMatch?.setLocalizableMessageWithKey(":-)", arguments: nil)
        
        self.currentMatch?.endTurn(withNextParticipants: nextParticipants, turnTimeout: timeout, match: updatedData) { [weak self] error in
            if let receivedError = error {
                
                if (receivedError as NSError).code == 3 {
                    // This error seems to indicate that
                    // print("Re-try to end turn?")
                    print(receivedError)
                }
                
                // print("Failed to end turn for match \(self?.currentMatch?.matchID ?? "N/A"):")
                self?.handleError(receivedError)
                return
            }
            
            // print("Ended turn for match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
            
            print("Current player: \(self?.currentMatch?.currentParticipant?.player?.displayName ?? "N/A")")
        }
    }
    
    @IBAction func endTurnWinTap(_ sender: Any) {
        
        print("Win match \(self.currentMatch?.matchID ?? "N/A")")
        
        guard let match = self.currentMatch else {
            // print("No match selected.")
            return
        }
        
        for participant in match.participants {
            guard participant.player?.teamPlayerID != match.currentParticipant?.player?.teamPlayerID else {
                participant.matchOutcome = .won
                continue
            }
            
            // All active participants have lost.
            if participant.matchOutcome == .none {
                participant.matchOutcome = .lost
            }
        }
        
        self.endCurrentMatch()
    }
    
    @IBAction func endTurnLossTap(_ sender: Any) {
        
        print("Lose match \(self.currentMatch?.matchID ?? "N/A")")
        
        guard let match = self.currentMatch else {
            // print("No match selected.")
            return
        }
        
        // Setting the outcome for all participants
        for participant in match.participants {
            guard participant.player?.teamPlayerID != match.currentParticipant?.player?.teamPlayerID else {
                participant.matchOutcome = .lost
                continue
            }
            
            // All other active participants have won.
            if participant.matchOutcome == .none {
                participant.matchOutcome = .won
            }
        }
        
        self.endCurrentMatch()
    }
    
    @IBAction func rematchTap(_ sender: Any) {
        guard let match = currentMatch else {
            // print("No match selected, this button should've be hidden.")
            return
        }

        match.rematch { [weak self] rematch, error in
            if let receivedError = error {
                // print("Failed to start rematch!")
                self?.handleError(receivedError)
            } else if let match = rematch {
                // print("Successfully created rematch \(rematch?.matchID ?? "N/A").")
                self?.currentMatch = match
                
                guard let data = Utility.data(fromCodable: "Rematch") else {
                    assertionFailure("Failed to encode intial match data")
                    self?.currentMatch = nil
                    self?.refreshInterface()
                    return
                }
                
                rematch?.saveMergedMatch(data, withResolvedExchanges: [], completionHandler: { [weak self] error in
                    if let receivedError = error {
                        print("Failed to initialize rematch")
                        self?.handleError(receivedError)
                        self?.refreshInterface()
                    } else {
                        print("Successfully initalized rematch \(match.matchID)!")
                        self?.refreshInterface()
                    }
                })
            }
        }
    }
    
    // MARK: - AUDIO
    
    func prepareAudio() {
        let filename = "Simple"
        guard let path = Bundle.main.path(forResource: filename, ofType: "caf") else {
            fatalError("Path for \"\(filename)\" audio file not found")
        }
        
        if let newPlayer = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
            newPlayer.numberOfLoops = 0
            newPlayer.prepareToPlay()
            player = newPlayer
        }
    }
    
    func play() {
        
        guard let preparedPlayer = player else {
            // print("No audio player has been prepared.")
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            if preparedPlayer.play() {
                // print("Playing audio..")
                preparedPlayer.prepareToPlay()
            }
        }
    }
    
    // MARK: - GAME CENTER
    
    func authenticatePlayer() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] (controller: UIViewController?, error: Error?) -> Void in
            
            guard error == nil else {
                let code = (error! as NSError).code
                switch code {
                case 15:
                    // print("Failed to authenticate local player because application is not recognized by Game Center.")
                    self?.presentErrorWithMessage("Patience! The app still not recognized by Game Center.")
                default:
                    // print("Authentication failed with error: \(error!.localizedDescription)")
                    self?.presentErrorWithMessage("Authentication failed with an error.")
                }
                self?.authenticationCompleted = false
                self?.refreshInterface()
                return
            }

            self?.authenticationCompleted = true

            if let authenticationController = controller {
                
                // The authentication controller is only received once during the
                // launch of the app, and only when the player is not already logged in.
                
                self?.present(authenticationController, animated: true, completion: {
                    print("Presented Game Center authentication controller.")
                })
                
                // self?.show(authenticationController, sender: self)
                // print("User needs to authenticate as a player.")
                
            } else if self?.localPlayerIsAuthenticated == false {
                print("Failed to authenticate local player.")
                
            } else {
                
                // Local Player is authenticated.
                self?.refreshInterface()
                print("Local player is authenticated.")
                
            }
        }
    }
    
    private func prepareMatchRequest(withInviteMessage message: String? = nil, playerCount: Int = 2, usingAutomatch: Bool) -> GKMatchRequest {
        
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 3
        request.defaultNumberOfPlayers = playerCount
        request.inviteMessage = message ?? "Would you like to play?"
        
        if #available(iOS 13.0, *) {
            request.restrictToAutomatch = usingAutomatch
        }
        
        request.recipientResponseHandler = { (player, response) in
            // Gets called whenever you programmatically invite specific players to join a match.
            // print("Recipient response handler is called! Response: \(response)")
        }
        
        return request
    }
    
    // MARK: - HELPERS
    
    
    /// Adds the provided string to the match data string and returns the updated data.
    func updatedMatchDataWithString(_ update: String, forMatch match: GKTurnBasedMatch) -> Data? {
        guard let matchData = match.matchData else {
            assertionFailure("Provided match does not have match data")
            return nil
        }
        
        var history = ""

        if let existingHistory: String = Utility.codableInstance(from: matchData) {
            history = existingHistory
        }
        
        history += update
        
        guard let placeholderData = Utility.data(fromCodable: history) else {
            print("Failed to create data")
            return nil
        }
        
        return placeholderData
    }
    
    

    /// A string appended to the match data when the turn holder does an update.
    ///
    /// For this demo the match data is only a String.
    func stringForEndTurnInMatch(_ match: GKTurnBasedMatch) -> String {
        let name = match.currentParticipant?.player?.displayName ?? "??"
        return "|" + name[...2]
    }
    
    /// A string appended to the match data when the turn holder does an update.
    ///
    /// For this demo the match data is only a String.
    func stringForUpdateInMatch(_ match: GKTurnBasedMatch) -> String {
        let name = match.currentParticipant?.player?.displayName ?? "??"
        return "•" + name[...2]
    }

    /// A string appended to the match data when an exchange is resolved.
    ///
    /// For this demo the match data is only a String.
    func stringForCompletedExchange(_ exchange: GKTurnBasedExchange) -> String? {
        
        let requesterName = exchange.sender.player?.displayName ?? "??"
        var outcome = "|" + requesterName[...2] + ":"
        
        guard let replies = exchange.replies else {
            // No replies, so no change to match data.
            return nil
        }
        
        var divider = ""
        
        for reply in replies {
            
            let name = (reply.recipient.player?.displayName ?? "??")[...2]
            
            guard let replyData = reply.data else {
                print("Reply missing data")
                continue
            }
            
            guard let decision: String = Utility.codableInstance(from: replyData) else {
                fatalError("Failed to decode reply data to String")
            }
            
            switch decision {
            case "accepted":
                outcome += divider + name + "/a"
            case "declined":
                outcome += divider + name + "/d"
            default:
                // Exchange was probably ignored.
                outcome += divider + name + "/i"
            }
            divider = "•"
        }
        
        return outcome
    }
    
    /// A string appended to the match data when the turn holder does an update.
    ///
    /// For this demo the match data is only a String.
    var turnStringForLocalPlayer: String {
        guard let match = currentMatch else {
            return ""
        }
        if let turnHolder = match.currentParticipant?.player?.displayName {
            return turnHolder
        } else {
            return "n/a"
        }
    }
    
    func handleError(_ error: Error) {
        
        func gamekitError(_ code: Int) {
            
            switch code {
            case 3:
                
                // There is at least one important error to deal with here, as Apple has a bug on their server
                // preventing turn holder from being notified when an exchange is completed.
                
                if let underlayingError = (error as NSError).userInfo["NSUnderlyingError"] as? NSError {
                    switch underlayingError.code {
                    case 5134:
                        
                        // Server-side bug: turn holder was not notified that an exchange has completed,
                        // so we show an appropriate error code message.
                        //
                        // Alternatively, we could reload the match, resolve the exchange and proceed.
                        
                        presentErrorWithMessage("Please reload the match as one or more exchanges have completed.", title: "Game Center Bug")
                        
                    case 5068:
                        
                        // The player is trying to send a reminder to frequently.
                        
                        presentErrorWithMessage(underlayingError.localizedDescription, title: "Failed To Send Reminder")
                        
                    default:
                        presentErrorWithMessage(underlayingError.localizedDescription)
                    }
                } else {
                    presentErrorWithMessage("Error communicating with the server.")
                }
                
            case 8:
                presentErrorWithMessage("Sorry, one or more of the participants could not receive the invite.", title: "Failed to create rematch")
                
            case 21:
                
                if let underlayingError = (error as NSError).userInfo["NSUnderlyingError"] as? NSError {
                    switch underlayingError.code {
                    case 5068:
                        
                        // The player is trying to sending reminders to frequently.
                        
                        let message = underlayingError.localizedDescription
                        
                        let numbers = message.components(separatedBy: CharacterSet.decimalDigits.inverted).filter({ !$0.isEmpty })

                        guard let delay = Int(numbers[1]), let elapsed = Int(numbers[2]) else {
                            presentErrorWithMessage("Please wait at least 10 minutes before sending another reminder.", title: "Could Not Send Reminder")
                            return
                        }
                        
                        let waitInMinutes = ((delay - elapsed) / 60000) + 1
                        
                        presentErrorWithMessage("Please wait \(waitInMinutes) minutes before attempting to send another reminder.", title: "Could Not Send Reminder")
                        
                    default:
                        presentErrorWithMessage(underlayingError.localizedDescription)
                    }
                } else {
                    presentErrorWithMessage("Operation failed. Please wait a while before trying again.")
                }
                
            default:
                presentErrorWithMessage("GameKit Error \(code): \(error.localizedDescription)")
            }
        }
        
        let givenError = error as NSError
        switch givenError.domain {
                
        case "GKErrorDomain":
            gamekitError(givenError.code)
        case "NSCocoaErrorDomain":
            fallthrough
        default:
            presentErrorWithMessage("Received error \(givenError.domain) (\(givenError.code)): \(error.localizedDescription)")
        }
        
        print("\(givenError.domain) Error details: \(error)")
    }
    
    func presentErrorWithMessage(_ message: String, title: String = "Received Error") {
        
        let alert = Utility.alert(title, message: message) { [weak alertManager] in
            alertManager?.advanceAlertQueueIfNeeded()
        }
        
        alertManager?.presentOrQueueAlert(alert)
    }
    
    func resetInterface() {
        matchState.text = " "
        localPlayerState.text = " "
        localPlayerOutcome.text = " "
        opponentStatus.text = " "
        opponentOutcome.text = " "
        exchangeHistory.text = " "
        turnSequence.text = " "

        updateMatch.isEnabled = false
        sendReminder.isEnabled = false
        beginExchange.isEnabled = false

        endTurn.isEnabled = false
        endTurnWin.isEnabled = false
        endTurnLose.isEnabled = false

        matchID.text = "No Match Selected"
        
        rematch.isHidden = true
        quitInTurn.isHidden = true
    }
    
    //    func mergeMatch(_ match: GKTurnBasedMatch, with data: Data, for exchanges: [GKTurnBasedExchange], closure: ((Error?)->Void)?) {
    //        // print("Saving merged matchData.")
    //
    //        guard let placeholderData = stringArrayToData(stringArray: [Date().description]) else {
    //            print("Failed to merge match data")
    //            return
    //        }
    //
    //        match.saveMergedMatch(placeholderData, withResolvedExchanges: exchanges) { [weak self] error in
    //            if let receivedError = error {
    //                // print("Failed to save merged data from \(exchanges.count) exchanges:")
    //                self?.handleError(receivedError)
    //                closure?(receivedError)
    //            } else {
    //                // print("Successfully merged data from \(exchanges.count) exchanges!")
    //                self?.refreshInterface()
    //                closure?(nil)
    //            }
    //        }
    //    }
    

    
    /// Ends the match.
    ///
    /// - Important: Before your game calls this method, the matchOutcome property on each
    /// participant object stored in the participants property must have been set to a value other than
    /// GKTurnBasedMatch.Outcome.none.
    func endCurrentMatch() {
        
        guard let match = currentMatch else {
            assertionFailure("No match is set when calling endCurrentMatch.Button should have been disabled")
            return
        }
        
        guard let updatedMatchData = updatedMatchDataWithString(stringForEndTurnInMatch(match), forMatch: match) else {
            assertionFailure("No match was set when trying to end match")
            return
        }

        match.endMatchInTurn(withMatch: updatedMatchData) { [weak self] error in
            if let receivedError = error {
                // print("Failed to end game for match \(self?.currentMatch?.matchID ?? "N/A"):")
                self?.handleError(receivedError)
                return
            }
            // print("Ended game for match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
        }
    }

    func nextParticipantsForMatch(_ match: GKTurnBasedMatch, didQuit: Bool = false) -> [GKTurnBasedParticipant] {
        var foundCurrentParticipant = false
        var tail = [GKTurnBasedParticipant]()
        var head = [GKTurnBasedParticipant]()
        for participant in match.participants {
            guard participant.matchOutcome == .none else {
                // Player has already exited the game.
                continue
            }
            if foundCurrentParticipant {
                head.append(participant)
            } else {
                tail.append(participant)
            }
            
            foundCurrentParticipant = (participant == match.currentParticipant)
        }
        
        let newTurnOrder = head + tail
        // print("New Turn Order:")
        var count = 1
        for participant in newTurnOrder {
            print("\(count). \(participant.player?.displayName ?? "N/A")")
            count += 1
        }
        
        return newTurnOrder
    }
    
    // MARK: Exchange Related
    
    func ignore(_ exchange: GKTurnBasedExchange) {
        replyToExchange(exchange, accepted: nil)
    }
    
    @discardableResult
    func presentNextExchange() -> Bool {
        
        print("There are currently \(currentMatch?.activeExchanges?.count ?? 0) active exchange(s).")
                
        if let match = currentMatch, let exchange = match.activeExchanges?.first, let sender = exchange.sender.player {
            self.player(sender, receivedExchangeRequest: exchange, for: match)
            return true
        } else {
            return false
        }
    }
    
    func replyToExchange(_ exchange: GKTurnBasedExchange, accepted: Bool?) {
        
        let mood: String
        let argument: String

        if let wasAccepted = accepted {
            argument = wasAccepted ? "acc" : "dec"
            mood = wasAccepted ? "smile" : "cry"
        } else {
            // The exchange timed out (or was deliberately ignored)
            argument = "shrug"
            mood = "indifferent"
        }
        
        // Because ..
        // 1. an exchange can be between any players in the match.
        // 2. only the turn holder can update the match data.
        // 3. the turn holder does not have to take part in an exchange.
        // 4. Only players participating in the exchange knows it is happening.
        //
        // We have include in the exchange data everything required to update
        // the match data with the exchange result.
        
        // PROCESSING EXCHANGE DATA
        // For this simple mockup game project, that simply means to append
        // the exchange response to the exchange data (both are strings).
                
        guard let exchangeData = exchange.data, let exchangeDataString: String = Utility.codableInstance(from: exchangeData) else {
            print("Unable to decode string from exchange data")
            return
        }
        
        let processedExchangeDataSource = exchangeDataString + GKLocalPlayer.local.displayName[...2] + ":" + argument
        
        guard let responseData = Utility.data(fromCodable: processedExchangeDataSource) else {
            assertionFailure("Failed to encode arguments to data for exchange reply.")
            return
        }
        
        let stringArguments = [mood]
        
        exchange.reply(withLocalizableMessageKey: "This exchange made me %@", arguments: stringArguments, data: responseData) { [weak self] error in
            if let receivedError = error {
                print("Failed to reply to exchange \(exchange.exchangeID):")
                self?.handleError(receivedError)
                return
            }
            
            print("Replied to exchange \(exchange.exchangeID).")
            self?.refreshInterface()
        }
    }
    
    
    func awaitReplyOrCancelExchange(_ exchange: GKTurnBasedExchange, forMatch match: GKTurnBasedMatch) {
        let alert = UIAlertController(title: "Exchange", message: "Awaiting reply or timeout.", preferredStyle: .actionSheet)
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] action in
            let noArguments = [String]()
            exchange.cancel(withLocalizableMessageKey: ":-/", arguments: noArguments) { [weak self] error in
                if let receivedError = error {
                    print("Failed to cancel exchange \(exchange.exchangeID):")
                    self?.handleError(receivedError)
                } else {
                    print("Cancelled exchange \(exchange.exchangeID)!")
                }
                self?.refreshInterface()
            }
            self?.alertManager?.advanceAlertQueueIfNeeded()
        }
        
        alert.addAction(cancel)
        alertManager?.presentOrQueueAlert(alert, withMatchInfo: (match.matchID, .waitingForExchangeReplies))
    }
    
    func mergeCompletedExchangesAsNeeded(resolvedData: Data, closure: @escaping (Result<Bool, Error>)->Void) {
        
        guard let match = currentMatch else {
            assertionFailure("No match to merge exchanges with")
            return
        }
        
        guard let exchanges = match.completedExchanges else {
            // There are no completed exchanges to merge with match data, so
            // just call the closure.
            print("Found no completed exchanges to save!")
            closure(.success(false))
            return
        }
        
        // print("Saving merged matchData.")
        
        // Maybe if the match data has not actually changed, it will not trigger
        // a turn event to the other or current player?
        
        print("Match data from exchange: \(resolvedData)")
        
        // PROCESS DATA BEFORE MERGING
        
        guard let processedExchangeData: String = Utility.codableInstance(from: resolvedData) else {
            print("Unexpected data received with exchange")
            return
        }
        
        print("Exchange match data description: \(processedExchangeData)")
        
        guard let matchData = match.matchData, let currentMatchDataString: String = Utility.codableInstance(from: matchData) else {
            print("Match data does not contain expected data")
            return
        }
        
        let updatedMatchDataSource = currentMatchDataString + processedExchangeData
        
        guard let updatedMatchData = Utility.data(fromCodable: updatedMatchDataSource) else {
            print("Unable to decode match data source")
            return
        }
        
        match.saveMergedMatch(updatedMatchData, withResolvedExchanges: exchanges) { [weak self] error in
            if let receivedError = error {
                self?.handleError(receivedError)
                closure(.failure(receivedError))
            } else {
                closure(.success(true))
            }
        }
    }

    
    func printDetailsForExchange(_ exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch, with player: GKPlayer) {
        
        var comma = ""
        var invitees = ""
        exchange.recipients.forEach({ (recipient) in
            invitees += comma + player.displayName
            comma = ", "
        })
        
        print( """
            Match   : \(match.matchID) is \(stringForMatchStatus(match.status))
            Exchange: \(exchange.exchangeID)
            Status  : \(stringForExchangeStatus(exchange.status))
            Message : \(exchange.message ?? "")
            Local   : \(GKLocalPlayer.local.displayName)
            Creator : \(player.displayName)
            Invitee : \(invitees)
            Replies : \(exchange.replies?.count ?? 0)
            Resolve : \(match.currentParticipant?.player?.displayName ?? "N/A") will resolve the data.\n
            """)
        
        guard let replies = exchange.replies else {
            print("Exchange had no replies.")
            return
        }
        
        for reply in replies {
            guard let exchangeResponse = reply.data else {
                print("Reply has no data!")
                continue
            }
            if let array: [String] = Utility.codableInstance(from: exchangeResponse), let response = array.first {
                print("Exchange was \(response) by \(reply.recipient.player?.displayName ?? "N/A")!")
            }
        }

    }
}


// MARK: - TURN BASED MATCH MAKER DELEGATE -

extension Simple: GKTurnBasedMatchmakerViewControllerDelegate {
    
    func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {

        self.dismiss(animated: true) {
            print("Dismissed Match Maker as match creation was cancelled.")
        }
    }
    
    func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController, didFailWithError error: Error) {
        
        let code = (error as NSError).code
        
        switch code {
        case 15:
            print("Application is not recognized by Game Center.")
        default:
            print("MatchMaker failed with error (\(code)): \(error.localizedDescription)")
        }
        
        self.dismiss(animated: true) {
            print("Dismissed Match Maker due to an error creating a match.")
        }
    }
    
}


// MARK: - LOCAL PLAYER LISTENER -

extension Simple: GKLocalPlayerListener {
    
    // MARK: GKSavedGameListener
    
    func player(_ player: GKPlayer, hasConflictingSavedGames savedGames: [GKSavedGame]) {
        print("\(player.displayName) has conflicting saved games!")
    }

    func player(_ player: GKPlayer, didModifySavedGame savedGame: GKSavedGame) {
        print("\(player.displayName) did modify saved game!")
    }
    
    // This extension is critical, as it handles all Game Center and
    // `GKTurnBasedMatch` related events.

    // MARK: - GKTurnBasedEventListener

    /// Calling this will forfeit the match by ending the current turn and passing the turn to the next
    /// player who wins by walkover.
    ///
    /// This may be called by the player or by the game logic.
    func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        // print("Wants to quit match \(match.matchID)!")
        
        print( """

            –––––––––––––––––––––
            PLAYER WANTS TO QUIT!
            –––––––––––––––––––––
            \(Utility.timestamp)

            """)


        guard match.currentParticipant?.player?.teamPlayerID == player.teamPlayerID  else {
            
            // Player want to quit out of turn.
            //
            // Quitting will not cause the game to end.
            //
            // The quitter will not be notified of the final result when the
            // game eventually ends.
            
            match.participantQuitOutOfTurn(with: .lost) { [weak self] error in
                            if let receivedError = error {
                    print("Failed to quit out of turn from match \(match.matchID) with error: \(receivedError)")
                } else {
                    print("Match \(match.matchID) was successfully left by local player out of turn.")
                    self?.refreshInterface()
                }
            }
            return
        }
        
        
        let nextUp = nextParticipantsForMatch(match, didQuit: true)
        
        // This could be anything, based on game logic:
        let outcome = GKTurnBasedMatch.Outcome.quit
        
        let turnString = stringForEndTurnInMatch(match) + "/q"
        guard let placeholderData = updatedMatchDataWithString(turnString, forMatch: match) else {
            print("Failed to create data")
            return
        }
        
        // Pass the match to the next player by calling
        match.participantQuitInTurn(with: outcome, nextParticipants: nextUp, turnTimeout: turnTimeout, match: placeholderData) { [weak self] error in
            if let receivedError = error {
                print("Failed to leave match \(match.matchID) with error: \(receivedError)")
            } else {
                print("Match \(match.matchID) was successfully left by local player.")
                self?.refreshInterface()
            }
        }
    }

    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        
        print( """

            –––––––––––––––––––––––––––
            MATCH ENDED EVENT RECEIVED!
            –––––––––––––––––––––––––––
            \(Utility.timestamp)
            
            """)
        
        let alreadyViewingMatch = self.currentMatch?.matchID == match.matchID

        guard let localPlayer = match.participants.filter({ $0.player?.teamPlayerID == GKLocalPlayer.local.teamPlayerID }).first else {
            // print("Local player not found in participants list for match \(match.matchID)")
            return
        }
        
        // print("ENDED MATCH OVERVIEW")
        for participant in match.participants {
            print("\(participant.player?.displayName ?? "Unnamed player")\t: \(stringForPlayerOutcome(participant.matchOutcome))")
        }

        let names = Utility.opponentNamesForMatch(match)
        
        let alert = UIAlertController(title: "You \(stringForPlayerOutcome(localPlayer.matchOutcome).lowercased()) in a match against \(names)!", message: "Do you want to see the result now?", preferredStyle: .alert)
        
        if alreadyViewingMatch {
            
            let ok = UIAlertAction(title: "OK", style: .cancel) { [weak alertManager] _ in
                alertManager?.advanceAlertQueueIfNeeded()
            }
            
            alert.addAction(ok)
            alert.title = "You \(stringForPlayerOutcome(localPlayer.matchOutcome).lowercased()) against \(names)."
            alert.message = ""
            
            self.currentMatch = match
            self.refreshInterface()
            
            alertManager?.presentOrQueueAlert(alert, withMatchInfo: (match.matchID, .matchContextSensitive))
            
        } else {
            let jump = UIAlertAction(title: "See Result", style: .default) { [weak self, weak alertManager] _ in
                // print("Player chose to go to match \(match.matchID)")
                self?.currentMatch = match
                self?.refreshInterface()
                alertManager?.advanceAlertQueueIfNeeded()
            }
            let ignore = UIAlertAction(title: "Cancel", style: .cancel) { [weak alertManager] _ in
                // print("Player did not want to go to match \(match.matchID)")
                alertManager?.advanceAlertQueueIfNeeded()
            }
            
            alert.addAction(jump)
            alert.addAction(ignore)
            
            alertManager?.presentOrQueueAlert(alert, withMatchInfo: (match.matchID, .alteringMatchContext))
        }
    }

    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        
        assert(Thread.isMainThread)
        
        print( """

            ––––––––––––––––––––
            TURN EVENT RECEIVED!
            ––––––––––––––––––––
            \(Utility.timestamp)

            """)
        
        // TODO: When a turn update is received, we need to check for completed exchanges,
        // as a turn timing out seem to also time out any outstanding exchanges.

        print("\n\nFinding most recent Turn Date:")
        var mostRecentTurnDate: Date?
        for participant in match.participants {
            if let lastTurnDate = participant.lastTurnDate {
                guard let mostRecentDate = mostRecentTurnDate else {
                    mostRecentTurnDate = lastTurnDate
                    print("First turn date found - this is for \(participant.player?.displayName ?? "Placeholder"): \(lastTurnDate)")
                    continue
                }
                
                if lastTurnDate > mostRecentDate {
                    mostRecentTurnDate = lastTurnDate
                    print("Most recent turn for \(participant.player?.displayName ?? "Placeholder"): \(lastTurnDate)")
                } else {
                    print("Player \(participant.player?.displayName ?? "Placeholder") turn date found to be older, nil or invalid: \(String(describing: participant.lastTurnDate))")
                }
            }
        }
        if let turnDate = mostRecentTurnDate {
            print("Match Most Recent Turn Date: \(turnDate)\n\n")
        } else {
            print("This is a brand new game! No turns have been submitted.\n\n")
        }
        
        
        if didBecomeActive {
            
            // Present the game whenever didBecomeActive is true.
            //
            // Updates do not make the game go active: no push notification
            // is sent for an update when the game is in the background.
            //
            // An event is received for updates only when the app is in the
            // foreground (active), but then the didBecomeActive is false.
            
            currentMatch = match
            play()
                        
            if match.matchData?.isEmpty == true, let data = Utility.data(fromCodable: "New") {
                // Match is new. No match data has been merged yet.
                match.saveMergedMatch(data, withResolvedExchanges: []) { [weak self] error in
                    if let receivedError = error {
                        print("Failed to initialize new game with initial data")
                        self?.handleError(receivedError)
                    } else {
                        print("Successfully initialized match \(match.matchID)!")
                        self?.refreshInterface()
                    }
                }
            } else {
                print("Match \(match.matchID) already has match data.")
            }
            
            // Present first active exchange to player, but only after
            // dismissing the match maker - if it is presented:
            
            if matchMaker != nil {
                dismiss(animated: true) { [weak self] in
                    if self?.presentNextExchange() == false {
                        self?.alertManager?.advanceAlertQueueIfNeeded()
                    }
                }
            } else if self.presentNextExchange() == false {
                self.alertManager?.advanceAlertQueueIfNeeded()
            }
            
            // Check if there is an ongoing exchange to handle:
            // Seems like received exhange event is only created on first game
            // launch after having received the exchange. After that we have
            // to present the exchange manually.
            
            //            if let exchanges = match.exchanges {
            //                for exchange in exchanges {
            //                    guard let exchangeCreator = exchange.sender.player else {
            //                        // print("Skipping exchange \(exchange.exchangeID) without a sender!")
            //                        continue
            //                    }
            //                    printDetailsForExchange(exchange, for: match, with: exchangeCreator)
            //                }
            //            }

            /// Present the player with an active exchange.
            // if let exchange = match.activeExchanges?.first, let sender = exchange.sender.player {
            //     self.player(sender, receivedExchangeRequest: exchange, for: match)
            // }
            
            
            /// Merge the completed exchanges - if there are any.
            if let completedExchanges = match.completedExchanges {
                var exchangeResult = ""
                
                for exchange in completedExchanges {
                    if let exchangeString = stringForCompletedExchange(exchange) {
                        exchangeResult += exchangeString
                    }
                }
                
                guard let placeholderData = updatedMatchDataWithString(exchangeResult, forMatch: match) else {
                    print("Failed to merge match data")
                    return
                }
                
                mergeCompletedExchangesAsNeeded(resolvedData: placeholderData) { [weak self] result in
                    switch result {
                    case .failure(let error):
                        self?.handleError(error)
                    case .success(let didMergeCompletedExchanges):
                        if didMergeCompletedExchanges {
                            print("Updated match data with completed exchanges.")
                            self?.refreshInterface()
                            self?.view.throb(duration: 0.05, toScale: 0.85)
                        } else {
                            print("Match data remains unchanged.")
                        }
                    }
                }
            }
            
        } else  if match.matchID == self.currentMatch?.matchID {
            
            // In the absence of audio, this is just a simple way to visualize
            // a game update.
            
            currentMatch = match
            self.view.throb(duration: 0.075, toScale: 1.1)
            
            // Merge the completed exchanges - if there are any.
            //
            // When a turn update is received, we need to check for completed exchanges,
            // as a turn timing-out seem to also time out any outstanding exchanges?

            if let completedExchanges = match.completedExchanges {
                var exchangeResult = ""
                
                for exchange in completedExchanges {
                    if let exchangeString = stringForCompletedExchange(exchange) {
                        exchangeResult += exchangeString
                    }
                }
                
                guard let placeholderData = updatedMatchDataWithString(exchangeResult, forMatch: match) else {
                    print("Failed to merge match data")
                    return
                }
                
                mergeCompletedExchangesAsNeeded(resolvedData: placeholderData) { [weak self] result in
                    switch result {
                    case .failure(let error):
                        self?.handleError(error)
                    case .success(let didMergeCompletedExchanges):
                        if didMergeCompletedExchanges {
                            print("Updated match data with completed exchanges.")
                            self?.refreshInterface()
                            self?.view.throb(duration: 0.05, toScale: 0.85)
                        } else {
                            print("Match data remains unchanged.")
                        }
                    }
                }
            }
            
        
        } else {
        
            // Attention is required for another match.

            let alert = alertForTurnTaken(in: match)
            alertManager?.presentOrQueueAlert(alert, withMatchInfo: (match.matchID, .alteringMatchContext))
        }
        
        // print("\nReceived turn event for match \(match.matchID) \(match.matchData == nil ? "without" : "with \(match.matchData!.count) bytes") data.\nDid become active: \(didBecomeActive)\n")
        refreshInterface()
    }

    func player(_ player: GKPlayer, didRequestMatchWithOtherPlayers playersToInvite: [GKPlayer]) {
        print("Did request match with other players ")
    }

    // MARK: - Exchange Related -
    
    
    func player(_ player: GKPlayer, receivedExchangeRequest exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        
        print( """

            ––––––––––––––––––––––––––
            RECEIVED EXCHANGE REQUEST!
            ––––––––––––––––––––––––––
            local player: \(player.displayName)
            \(Utility.timestamp)


            """)
        
        currentMatch = match
        
        guard let sender = exchange.sender.player else {
            print("Exchange request has no sender!")
            return
        }

        // Removing this as Apple Tech Support confirms that the turn holder
        // does NOT need to be included in the exchange - despite documentation:
        //
        // "All exchanges must include the current turn holder" from
        // https://developer.apple.com/documentation/gamekit/gkturnbasedexchange
        //
        // guard let ID = payload["recipient"], GKLocalPlayer.local.playerID == ID else {
        //
        //     // This exchange is intended for another player, so it is ignored
        //     // by sending nil as accepted status.
        //
        //     ignore(exchange)
        //     currentMatch = match
        //
        //     refreshInterface()
        //     view.throb(duration: 0.05, toScale: 0.85)
        //
        //     return
        // }
        
        printDetailsForExchange(exchange, for: match, with: sender)
        
        let alert = acceptTradeAlert(for: exchange)
        alertManager?.presentOrQueueAlert(alert, withMatchInfo: (match.matchID, .respondingToExchange))
    }
    
    // From: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/GameKit_Guide/ImplementingaTurn-BasedMatch/ImplementingaTurn-BasedMatch.html
    //
    // 1) After an exchange request is created, the players in the recipients array
    // receive a push notification.
    // -> Assumed to mean: only the players that should be involved with the exchange
    // should be part of the recipients array (unlike a regular turn which has
    // the current player as a fallback).
    //
    // 2) Opening the game will present the exchange message.
    // -> Assumed to mean: Only if the player opens the game before the exchange has
    // timed out, the exchange will be shown.
    //
    // 3) The recipient can choose to respond to the exchange request or let it
    // time out.
    // -> Assumed to mean: for the receiver of a request there is no way to
    // cancel, instead simply let it time out.
    //
    // 4) After the exchange is completed, the exchange result is sent to the
    // current player.
    // -> Assumed to mean: the completed exchange is automatically sent to
    // current player. The exchange creator does not need to do anything for
    // the turn holder to receive the result of the completed exchange.
    //
    // 5) The exchange is reconciled at the end of the current player’s turn.
    // -> Assumed to mean: merge data from exchange and game, then end turn as
    // normal. Alternatively, merge data directly, to let all players see what
    // has happened.
    //
    // From: Quick Help
    //
    // An error is returned if any of the participants are inactive.
    // -> This seems to contradict pt.1 which says a push notification
    // will be sent to the recipients of the exchange.
    //
    // The result is then sent to the current player and the initiator of the exchange.
    // -> Seems to suggest that when exchanges are resolved, the creator of the exchange
    // as well as the current participant receives the resulting data. But how is it sent?

    func player(_ player: GKPlayer, receivedExchangeReplies replies: [GKTurnBasedExchangeReply], forCompletedExchange exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        print( """

            ––––––––––––––––––––––––––
            RECEIVED EXCHANGE REPLIES!
            ––––––––––––––––––––––––––
            \(Utility.timestamp)

            """)

        alertManager?.dismissAlert(ofType: .waitingForExchangeReplies)
        currentMatch = match
        
        // The exchange is ready for processing: all invitees have responded.
        printDetailsForExchange(exchange, for: match, with: player)

        // When a reply is received by the current turn holder, what should be
        // done depends on your game. You may have "first-come-first-served"
        // exchanges, or you may have somelike like an auction. For the latter
        // you will have to wait until everyone has replied, or exchange times
        // out if not everyone has replied.
        
        let recipientName = exchange.recipients.first?.player?.displayName ?? "N/A"
        
        guard let firstReply = exchange.replies?.first, let data = firstReply.data else {
             print("Exchange \(exchange.exchangeID) has no data, bailing!")
             return
         }
        
        // In this mockup game project, the data is just a string. So we convert
        // it here to make handling it easier:
        let exchangeDataString = String(data: data, encoding: String.Encoding.utf8)!
        
         print("Exchange Data Received: \(exchangeDataString)")

        guard let exchangeOutcome: String = Utility.codableInstance(from: data) else {
             print("Exchange \(exchange.exchangeID) has unexpected data format!")
             return
         }
        
        
        let exchangeIsComplete = exchange.status == .complete

        self.mergeCompletedExchangesAsNeeded(resolvedData: data) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.handleError(error)
            case .success(let didMergeCompletedExchanges):
                
                // ------------------------------------------------------------------------------------------------------------------------
                // Apple documenation and WWDC sessions clearly states that it is possible to cancel
                // even completed exchanges - as long as it hasn't been merged/resolved.
                //
                // The Apple Engineer I'm emailing however, suggests that this isn't the case.
                // And the result is: Engineer 0 - Documenation 1
                
                // let message = String(format: firstReply.message, firstReply.)
                
                if !didMergeCompletedExchanges {
                
                    let exchangeOutcomeDisplayString: String
                    if exchangeOutcome == "acc" {
                        exchangeOutcomeDisplayString = "accepted"
                    } else if exchangeOutcome == "dec" {
                        exchangeOutcomeDisplayString = "declined"
                    } else {
                        exchangeOutcomeDisplayString = "ignored exchange"
                    }
                    
                    let exchangeResult = Utility.alert("\(recipientName) \(exchangeOutcomeDisplayString)!", message: firstReply.message) { [weak self] in
                        self?.alertManager?.advanceAlertQueueIfNeeded()
                    }
                    
                    let cancelCompletedExchange = UIAlertAction(title: "Cancel Exchange!", style: .destructive) { _ in
                        exchange.cancel(withLocalizableMessageKey: "Cancelled despite being completed!", arguments: []) { error in
                            if let receivedError = error {
                                self?.handleError(receivedError)
                                return
                            }
                            
                            print("Updated match \(self?.currentMatch?.matchID ?? "N/A")")
                            self?.refreshInterface()
                        }
                        self?.alertManager?.advanceAlertQueueIfNeeded()
                    }
                    exchangeResult.addAction(cancelCompletedExchange)
                    
                    self?.alertManager?.presentOrQueueAlert(exchangeResult, withMatchInfo: (match.matchID, .respondingToExchange))
                }

                // ------------------------------------------------------------------------------------------------------------------------

                

                
                if didMergeCompletedExchanges {
                    print("Updated match data with completed exchanges.")
                    self?.refreshInterface()
                    self?.view.throb(duration: 0.05, toScale: 0.85)
                } else {
                    print("Match data remains unchanged.")
                }
            }
        }
    }

    func player(_ player: GKPlayer, receivedExchangeCancellation exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        
        print( """

            –––––––––––––––––––––––––––––––
            RECEIVED EXCHANGE CANCELLATION!
            –––––––––––––––––––––––––––––––
            \(Utility.timestamp)
            
            """)

        // print("\nExchange creator \(exchange.sender.player?.displayName ?? "N/A") cancelled the exchange \(exchange.exchangeID).")
        
        let sender = exchange.sender.player?.displayName ?? "unknown sender"
        let alert = Utility.alert("Exchange with \(sender) was cancelled", message: nil) { [weak alertManager] in
            alertManager?.advanceAlertQueueIfNeeded()
        }

        alertManager?.dismissAlert(ofType: .respondingToExchange)
        alertManager?.presentOrQueueAlert(alert, withMatchInfo: (match.matchID, .exchangeCancellationNotification))
        
        // Reload match data
        refreshInterface()
    }


    // MARK: - GKInviteEventListener

    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        print("Did accept invite")

        // TODO: Pass the match controller to mapper, who then will forward it to the interface.
        // let realTimeMatchMaker = GKMatchmakerViewController(invite: invite)
    }

    func player(_ player: GKPlayer, didRequestMatchWithRecipients recipientPlayers: [GKPlayer]) {
        print("Did request match with recipients")
    }
}




// MARK: - INTERFACE RELATED -

extension Simple {
    
    func alertForTurnTaken(in match: GKTurnBasedMatch) -> UIAlertController {
        
        let title: String
        let message: String
        
        let names = Utility.opponentNamesForMatch(match)
        let isTurnHolder = match.currentParticipant?.player?.teamPlayerID == GKLocalPlayer.local.teamPlayerID
        let isReminder = match.matchData == currentMatch?.matchData
        
        if isTurnHolder && isReminder {
            title = "Please take your turn!"
            message = "Turn reminder received for a game with \(names)."
        
        } else if isTurnHolder {
            title = "It's your turn!"
            message = "You are the turn holder in a match with \(names)."
            
        } else {
            title = "Match Updated"
            message = "An action was taken in a match with \(names)."
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let jump = UIAlertAction(title: "Load Match", style: .default) { [weak self, weak alertManager] _ in
            self?.currentMatch = match
            self?.refreshInterface()
            
            if alertManager?.topmostController is GKTurnBasedMatchmakerViewController {
                self?.dismiss(animated: true, completion: nil)
            }

            alertManager?.advanceAlertQueueIfNeeded()
        }
        let ignore = UIAlertAction(title: "Cancel", style: .cancel) { [weak alertManager] _ in
            // print("Player did not want to go to match \(match.matchID)")
            alertManager?.advanceAlertQueueIfNeeded()
        }
        alert.addAction(jump)
        alert.addAction(ignore)
        
        return alert
    }
    
    /// An alert allowing the creator of an exchange to select the player to trade with.
    ///
    /// For the sake of simplicity only a single recipient is supported.
    func tradeAlertForMatch(_ match: GKTurnBasedMatch) -> UIAlertController {
        let alert = UIAlertController(title: "Who do you want to trade with?", message: "Please pick your trading partner.", preferredStyle: .alert)
        for participant in match.participants where participant.player?.teamPlayerID != GKLocalPlayer.local.teamPlayerID {

            // Supposedly there should be no reason to verify that the particiapnt is indeed a real player.
            // guard participant.status != .matching && participant.player?.playerID != GKLocalPlayer.local.playerID else {
            //     // Not yet a real participant to trade with.
            //     continue
            // }
            
            let recipient = UIAlertAction(title: participant.player?.displayName ?? "Unknown Player", style: .default) { [weak self, weak alertManager] _ in
                self?.sendExchange(for: match, to: [participant])
                alertManager?.advanceAlertQueueIfNeeded()
            }
            
            alert.addAction(recipient)
        }
        
        if match.participants.count > 2 {
            let both = UIAlertAction(title: "Both Players", style: .default) { [weak self, weak alertManager] _ in
                
                let recipients = match.participants.filter { $0.player?.teamPlayerID != GKLocalPlayer.local.teamPlayerID }
                self?.sendExchange(for: match, to: recipients)
                
                alertManager?.advanceAlertQueueIfNeeded()
            }
            alert.addAction(both)
        }

        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { [weak alertManager] _ in
            alertManager?.advanceAlertQueueIfNeeded()
        }

        alert.addAction(cancel)
        return alert
    }
    
    
    /// Creates an alert allowing the recipient of an exchange to either accept, decline or ignore an exhange.
    func acceptTradeAlert(for exchange: GKTurnBasedExchange) -> UIAlertController {
        
        let message = exchange.message ?? "Do you want to trade?"
        let name = exchange.sender.player?.displayName ?? "unknown player"
        
        let alert = UIAlertController(title: "Accept exchange with \(name)?", message: message, preferredStyle: .alert)
        
        let accept = UIAlertAction(title: "Accept", style: .default) { [weak self, weak alertManager] action in
            self?.replyToExchange(exchange, accepted: true)
            self?.refreshInterface()
            alertManager?.advanceAlertQueueIfNeeded()
        }

        let decline = UIAlertAction(title: "Decline", style: .destructive) { [weak self, weak alertManager] action in
            self?.replyToExchange(exchange, accepted: false)
            self?.refreshInterface()
            alertManager?.advanceAlertQueueIfNeeded()
        }

        let ignore = UIAlertAction(title: "Ignore", style: .cancel) { [weak self, weak alertManager] action in
            
            // There is no way to cancel a received request.
            // Either reply with a decline or let the request time-out.
            //
            // Letting an exchange time out will slow down the game, as the
            // exchange is not completed until everyone has replied.
            
            self?.refreshInterface()
            alertManager?.advanceAlertQueueIfNeeded()
        }
        
        alert.addAction(accept)
        alert.addAction(decline)
        alert.addAction(ignore)
        
        return alert
    }

}


// MARK: - UTILITIES -

extension Simple {
    
    func sendExchange(for match: GKTurnBasedMatch, to recipients: [GKTurnBasedParticipant]) {

        let stringArguments = [String]()
        let exchangeTimeout: TimeInterval = self.turnTimeout / 2

        // An exchange can include any players in the match, it can be between
        // two or more players.
        //
        // Only the turn holder can update the match data, which is why the
        // turn holder is notified when an exchange has completed - so the
        // exchange outcome can affect the match data (be merged with match data).
        //
        // This has never worked as documented, until Apple fixed it in 2020
        // after I reported the issue during WWDC. This issue had gone unnoticed
        // since Game Center was launched in 2010, which is hard to fadom!
        
        let playerDisplayName = GKLocalPlayer.local.displayName[...2]
        guard let exchangeData = Utility.data(fromCodable: "+\(playerDisplayName)?") else {
            print("Failed to create data")
            return
        }
        
        match.sendExchange(to: recipients, data: exchangeData, localizableMessageKey: "You want to trade?", arguments: stringArguments, timeout: exchangeTimeout) { [weak self] exchange, error in
            if let receivedError = error {
                // print("Failed to send exchange for match \(self?.currentMatch?.matchID ?? "N/A"):")
                self?.handleError(receivedError)
                return
            }
            
            guard let receivedExchange = exchange else {
                // print("No exchange received")
                return
            }
            
            // print("Sent exchange \(receivedExchange.exchangeID) for match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
            
            self?.awaitReplyOrCancelExchange(receivedExchange, forMatch: match)
        }
    }
}
