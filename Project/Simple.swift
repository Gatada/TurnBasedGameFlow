//
//  Simple.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 04/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit
import GameKit


// Register multiple listeners
// ■ AppDelegate for new turn and activations
// ■ Match view controller for updates to the current match


enum MatchUpdateError: Error {
    case waitingForActiveExchangesToComplete
}

typealias QueuedAlert = (type: AlertType, alert: UIAlertController)

enum AlertType: Int {
    // Generic Alerts: sLowest Priority Alerts
    case informative
    
    // Context and Sequence Sensitive: Highest Priority
    case exchangeCancellationNotification = 300
    
    // Context Sensitive
    case creatingExchange = 200
    case waitingForExchangeReplies
    case respondingToExchange
    case matchContextSensitive
    
    // Context Altering
    case alteringMatchContext = 100

    /// The priority level of an alert type.
    ///
    /// A higher value means higher priority. Present the alerts in decending priority level.
    /// In other words, show all alerts with priority level 2 before any with level 1, and so on.
    var priority: Int {
        return self.rawValue/100
    }
}

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
    
    // MARK: - Properties
    
    var player: AVAudioPlayer?

    let turnTimeout: TimeInterval = 60 * 10 // 10 min to speed up testing
    let data = Data()
    
    weak var matchMakerController: GKTurnBasedMatchmakerViewController?
    
    /// Used to retain alerts created while there is already an alert on screen.
    var alertQueue = [QueuedAlert]()
    
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
    
    /// Returns the opponent or `nil` if there is no match selected.
    var opponent: GKTurnBasedParticipant? {
        guard let match = currentMatch else {
            return nil
        }
        
        let opponent = match.participants.filter { (player) -> Bool in
            player.player != GKLocalPlayer.local
        }.first
        
        // print("""
        //     Local   : \(GKLocalPlayer.local.playerID)
        //     Opponent: \(opponent?.status == .matching ? "Searching.." : (opponent?.player?.playerID ?? "n/a"))
        //     Current : \(match.currentParticipant?.player?.playerID == GKLocalPlayer.local.playerID ? "Resolving Turn!" : "Waiting..")
        //     """)
        
        return opponent
    }
    
    var currentMatch: GKTurnBasedMatch? = nil {
        didSet {
            print("Current match was updated..")
        }
    }
    
    // MARK: - Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupGameCenter()
        authenticatePlayer()
        prepareAudio()
        resetInterface()
        versionBuild.text = AppDelegate.versionBuild
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshInterface()
    }
    
    
    // MARK: - Setup
    
    func setupGameCenter() {
        // Registering the GKLocalPlayerListener to receive all events.
        // This must only be done once.
        GKLocalPlayer.local.register(self)
    }
    
    
    // MARK: - Interface
    
    func refreshInterface() {
        
        assert(Thread.isMainThread)
        
        matchMaker.isEnabled = authenticationCompleted && GKLocalPlayer.local.isAuthenticated
        
        guard let match = currentMatch else {
            resetInterface()
            return
        }

        // Various states needed to refresh interface.

        let gameEnded = match.status == .ended
        let isResolvingTurn = match.currentParticipant?.player?.playerID == GKLocalPlayer.local.playerID
        let opponentOutcomeSet = opponent?.matchOutcome != GKTurnBasedMatch.Outcome.none
        let hasLocalOutcome = localParticipant?.matchOutcome != GKTurnBasedMatch.Outcome.none
        let isMatching = match.status == .matching
        
        updateMatch.isEnabled = isResolvingTurn && !opponentOutcomeSet
        endTurn.isEnabled = isResolvingTurn && !opponentOutcomeSet
        endTurnWin.isEnabled = isResolvingTurn
        endTurnLose.isEnabled = isResolvingTurn && !opponentOutcomeSet
        
        // These two occupy same screen real-estate:
        quitInTurn.isHidden = (!isResolvingTurn && !gameEnded) || gameEnded
        rematch.isHidden = !gameEnded
        
        beginExchange.isEnabled = !isMatching && !gameEnded && !opponentOutcomeSet

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
        
        exchangeHistory.text = "\(match.activeExchanges?.count ?? 0) active / \(match.completedExchanges?.count ?? 0) completed / \(match.exchanges?.count ?? 0) total"
        
        // Now check if game is over:
        print("Game is \(gameEnded ? "over" : "active").")
    }

    // MARK: - User Interaction
    
    @IBAction func quitMatchInTurnTap(_ sender: Any) {
        guard let match = currentMatch else {
            print("Tried to quit a match when no match is selected.")
            return
        }
        player(GKLocalPlayer.local, wantsToQuitMatch: match)
    }
    
    @IBAction func matchMakerTap(_ sender: Any) {
        
        let request = prepareMatchRequest(withInviteMessage: "Simple wants you to play!", usingAutomatch: false)
        let matchMaker = GKTurnBasedMatchmakerViewController(matchRequest: request)
        matchMaker.turnBasedMatchmakerDelegate = self
        matchMaker.showExistingMatches = true
        
        currentMatch = nil
        refreshInterface()
        
        self.present(matchMaker, animated: true) {
            print("Presented Match Maker")
            self.matchMakerController = matchMaker
        }
    }
    
    @IBAction func beginExchangeTap(_ sender: Any) {
        print("Tapped to begin Exchange")
        
        guard let match = currentMatch else {
            print("No match selected")
            return
        }

        let stringArguments = [String]()
        let turnTimeout: TimeInterval = 120 // seconds
        
        func sendExchange(to recipient: GKTurnBasedParticipant) {
            currentMatch?.sendExchange(to: [recipient], data: data, localizableMessageKey: "You can decide now or ignore it, however it will timeout in \(turnTimeout) seconds.", arguments: stringArguments, timeout: turnTimeout) { [weak self] exchange, error in
                if let receivedError = error {
                    print("Failed to send exchange for match \(self?.currentMatch?.matchID ?? "N/A"):")
                    self?.handleError(receivedError)
                    return
                }
                
                guard let receivedExchange = exchange else {
                    print("No exchange received")
                    return
                }
                
                print("Sent exchange \(receivedExchange.exchangeID) for match \(self?.currentMatch?.matchID ?? "N/A")")
                self?.refreshInterface()
                
                self?.awaitReplyOrCancelExchange(receivedExchange)
            }
        }

        let alert = UIAlertController(title: "Who do you want to trade with?", message: "Please pick your trading partner.", preferredStyle: .alert)
        for participant in match.participants {
            
            guard participant.status != .matching && participant.player?.playerID != GKLocalPlayer.local.playerID else {
                // Not yet a real participant to trade with.
                continue
            }
            
            let recipient = UIAlertAction(title: participant.player?.displayName ?? "Unknown Player", style: .default) { [weak self] _ in
                sendExchange(to: participant)
                self?.advanceAlertQueueIfNeeded()
            }
            
            alert.addAction(recipient)
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            print("Player cancelled exchange before it began.")
            self?.advanceAlertQueueIfNeeded()
        }
        alert.addAction(cancel)
        
        presentOrQueueAlert(alert, ofType: .creatingExchange)
    }
    
    
    /// A reminder can only be sent when the recipient is not already interacting with the related game.
    @IBAction func sendReminderTap(_ sender: Any) {
        
        guard let match = currentMatch else {
            print("No match set for sending a reminder.")
            return
        }
        
        print("Send reminder for match \(match.matchID)")
        
        let stringArguments = [String]()
        guard let sleepingParticipant = match.currentParticipant else {
            print("No current participant was found for the match!")
            return
        }
                
        currentMatch?.sendReminder(to: [sleepingParticipant], localizableMessageKey: "Want to make a move?", arguments: stringArguments) { [weak self] error in
            if let receivedError = error {
                print("Failed to send reminder for match \(self?.currentMatch?.matchID ?? "N/A"):")
                self?.handleError(receivedError)
                return
            }

            print("Sent reminder for match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
        }
    }
    
    
    /// Updates the match data.
    ///
    /// To be able to update the match data, it seems like all exchanges must be resolved. I can see that
    /// this would make sense, as the update will also affect the match data.
    @IBAction func updateMatchTap(_ sender: Any) {
        do {
            try mergeExchangesAsNeeded() { [weak self] error in
                
                self?.refreshInterface()
                
                if let receivedError = error {
                    self?.handleError(receivedError)
                    return
                }
                
                let matchData = Data()
                print("Update match \(self?.currentMatch?.matchID ?? "N/A")")
                
                self?.currentMatch?.saveCurrentTurn(withMatch: matchData) { [weak self] error in
                    if let receivedError = error {
                        print("Failed to update match \(self?.currentMatch?.matchID ?? "N/A"):")
                        self?.handleError(receivedError)
                        return
                    }
                    
                    print("Updated match \(self?.currentMatch?.matchID ?? "N/A")")
                    self?.refreshInterface()
                }
            }
        } catch let error as MatchUpdateError {
            switch error {
            case .waitingForActiveExchangesToComplete:
                print("Waiting for active exchanges to be cancelled or resolved.")
            }
        } catch {
            print("Error thrown: \(error.localizedDescription)")
        }
    }
    
   
    @IBAction func endTurnTap(_ sender: Any) {
        
        do {
            try mergeExchangesAsNeeded() { [weak self] error in
                
                self?.refreshInterface()
                
                // From session #506 at WWDC 2013:
                // https://developer.apple.com/videos/play/wwdc2013/506/
                // Last participant on list does not time out.
                // Include yourself last.
                
                guard let match = self?.currentMatch else {
                    print("No opponent for match \(self?.currentMatch?.matchID ?? "N/A")")
                    return
                }

                guard let nextParticipants = self?.nextParticipantsForMatch(match) else {
                    print("Failed to obtain next participants")
                    return
                }

                let timeout = self?.turnTimeout ?? 60 * 60
                let updatedData = Data()
                
                // Localized message to be set at end of turn or game:
                self?.currentMatch?.setLocalizableMessageWithKey(":-)", arguments: nil)
                
                self?.currentMatch?.endTurn(withNextParticipants: nextParticipants, turnTimeout: timeout, match: updatedData) { [weak self] error in
                    if let receivedError = error {
                        
                        if (receivedError as NSError).code == 3 {
                            // This error seems to indicate that
                            print("Re-try to end turn?")
                            print(receivedError.localizedDescription)
                        }
                            
                        print("Failed to end turn for match \(self?.currentMatch?.matchID ?? "N/A"):")
                        self?.handleError(receivedError)
                        return
                    }
                    
                    print("Ended turn for match \(self?.currentMatch?.matchID ?? "N/A")")
                    self?.refreshInterface()
                    
                    print("Current player: \(self?.currentMatch?.currentParticipant?.player?.displayName ?? "N/A")")
                }
            }
        } catch let error as MatchUpdateError {
            switch error {
            case .waitingForActiveExchangesToComplete:
                print("Waiting for active exchanges to be cancelled or resolved.")
            }
        } catch {
            print("Error thrown: \(error.localizedDescription)")
        }
    }
    
    @IBAction func endTurnWinTap(_ sender: Any) {
        
        do {
            try mergeExchangesAsNeeded() { [weak self] error in
                
                self?.refreshInterface()
                
                print("Win match \(self?.currentMatch?.matchID ?? "N/A")")
                
                guard let match = self?.currentMatch else {
                    print("No match selected.")
                    return
                }
                
                for participant in match.participants {
                    guard participant.player?.playerID != match.currentParticipant?.player?.playerID else {
                        participant.matchOutcome = .won
                        continue
                    }
                    
                    // All active participants have lost.
                    if participant.matchOutcome == .none {
                        participant.matchOutcome = .lost
                    }
                }
                
                self?.endCurrentMatch()
            }
        } catch let error as MatchUpdateError {
            switch error {
            case .waitingForActiveExchangesToComplete:
                print("Waiting for active exchanges to be cancelled or resolved.")
            }
        } catch {
            print("Error thrown: \(error.localizedDescription)")
        }
    }
    
    @IBAction func endTurnLossTap(_ sender: Any) {
        
        do {
            try mergeExchangesAsNeeded() { [weak self] error in
                
                self?.refreshInterface()
                
                print("Lose match \(self?.currentMatch?.matchID ?? "N/A")")
                
                guard let match = self?.currentMatch else {
                    print("No match selected.")
                    return
                }
                
                // Setting the outcome for all participants
                for participant in match.participants {
                    guard participant.player?.playerID != match.currentParticipant?.player?.playerID else {
                        participant.matchOutcome = .lost
                        continue
                    }
                    
                    // All other active participants have won.
                    if participant.matchOutcome == .none {
                        participant.matchOutcome = .won
                    }
                }

                self?.endCurrentMatch()
            }
        } catch let error as MatchUpdateError {
            switch error {
            case .waitingForActiveExchangesToComplete:
                print("Waiting for active exchanges to be cancelled or resolved.")
            }
        } catch {
            print("Error thrown: \(error.localizedDescription)")
        }
    }
    
    @IBAction func rematchTap(_ sender: Any) {
        guard let match = currentMatch else {
            print("No match selected, this button should've be hidden.")
            return
        }

        match.rematch { [weak self] rematch, error in
            if let receivedError = error {
                print("Failed to start rematch!")
                self?.handleError(receivedError)
            } else {
                print("Successfully created rematch \(rematch?.matchID ?? "N/A").")
                self?.currentMatch = rematch
                self?.refreshInterface()
            }
        }
    }
    
    // MARK: - Audio
    
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
            print("No audio player has been prepared.")
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            if preparedPlayer.play() {
                print("Playing audio..")
                preparedPlayer.prepareToPlay()
            }
        }
    }
    
    // MARK: - Game Center
    
    func authenticatePlayer() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] (controller: UIViewController?, error: Error?) -> Void in
            
            guard error == nil else {
                let code = (error! as NSError).code
                switch code {
                case 15:
                    print("Failed to authenticate local player because application is not recognized by Game Center.")
                    self?.presentErrorWithMessage("Patience! The app still not recognized by Game Center.")
                default:
                    print("Authentication failed with error: \(error!.localizedDescription)")
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
                
                self?.show(authenticationController, sender: self)
                print("User needs to authenticate as a player.")
                
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
            print("Recipient response handler is called! Response: \(response)")
        }
        
        return request
    }
    
    // MARK: - Helpers
    
    
    func dismissAlert(ofType dismissableType: AlertType) {
        if let presented = alertQueue.first, presented.type == dismissableType {
            
            let alertIsVisible = presented.alert.isViewLoaded && presented.alert.view.window != nil
            guard alertIsVisible else {
                assertionFailure("Tried to dismiss an alert that is not visible")
                return
            }
            
            self.dismiss(animated: true) { [weak self] in
                self?.advanceAlertQueueIfNeeded()
            }
        }
    }
    
    /// Adds the passed alert to the queue.
    ///
    /// If the alert is context sensitive, by for example being relevant for the currently showing match,
    /// the `isContextSensitive` should be `true`. This results in the alert being added as the
    /// second alert in the queue (making it the next-up alert).
    /// - Parameters:
    ///   - alert: The alert controller to queue.
    ///   - isContextSensitive: If `true` the alert will be shown next, otherwise last.
    func presentOrQueueAlert(_ alert: UIAlertController, ofType type: AlertType = .informative) {
        
        if alertQueue.isEmpty {
            self.present(alert, animated: true) { [weak self] in
                self?.alertQueue.append((type, alert))
            }
        } else {
            
            // Already showing an alert.
            // Add new alert to queue.
            //
            // The queue is advanced when visible alert calls
            // Simple.advanceAlertQueueIfNeeded() as part of its available
            // actions.

            let unqueuedAlert: QueuedAlert = (type, alert)
            
            if let insertIndex = alertQueue.firstIndex(where: { $0.type.priority < type.priority }) {
                // Found entry with lower priority than unqueued alert.
                // Inserting alert at this location so it'll be presented first.
                alertQueue.insert(unqueuedAlert, at: insertIndex)
                print("Inserted alert \"\(alert.title ?? alert.message ?? "Empty Alert")\" at index \(insertIndex).")
            } else {
                // No queued alert found with lower priority then unqeued alert.
                // Appending alert to the end of the queue
                alertQueue.append(unqueuedAlert)
                print("Appended alert \"\(alert.title ?? alert.message ?? "Empty Alert")\" to end of queue.")
            }
        }
    }
    
    /// Displays the alert controller that is next in the queue.
    ///
    /// - Important: This should be called at the end of any action associated with a queued alert.
    func advanceAlertQueueIfNeeded() {
        guard !alertQueue.isEmpty else {
            print("No currently visible alerts.")
            return
        }
        
        guard alertQueue.first?.alert.isBeingPresented == false else {
            assertionFailure("Dequeued an alert that is still being presented.")
            return
        }
        
        alertQueue.removeFirst()
        
        guard let nextUp = alertQueue.first else {
            print("No more queued alerts to present.")
            return
        }
        
        self.present(nextUp.alert, animated: true) { [weak self] in
            let queuedAlertCount = self?.alertQueue.count ?? 0
            let alertCaption = "\"\(nextUp.alert.title ?? nextUp.alert.message ?? "an empty alert")\""
            print("Presented \(alertCaption) alert from queue (\(queuedAlertCount - 1) remaining).")
        }
    }
    
    func handleError(_ error: Error) {
        
        func gamekitError(_ code: Int) {
            switch code {
            case 3:
                presentErrorWithMessage("Error communicating with the server.")
            case 8:
                presentErrorWithMessage("Sorry, one or more of the participants could not receive the invite.", title: "Failed to create rematch")
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
    }
    
    func presentErrorWithMessage(_ message: String, title: String = "Received Error") {

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let ok = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.advanceAlertQueueIfNeeded()
        }
        alert.addAction(ok)
        print(message)
        
        presentOrQueueAlert(alert)
    }
    
    func resetInterface() {
        matchState.text = " "
        localPlayerState.text = " "
        localPlayerOutcome.text = " "
        opponentStatus.text = " "
        opponentOutcome.text = " "
        exchangeHistory.text = " "

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

    func dataToStringArray(data: Data) -> [String]? {
      return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String]
    }

    func stringArrayToData(stringArray: [String]) -> Data? {
      return try? JSONSerialization.data(withJSONObject: stringArray, options: [])
    }
    
    func mergeMatch(_ match: GKTurnBasedMatch, with data: Data, for exchanges: [GKTurnBasedExchange], closure: ((Error?)->Void)?) {
        print("Saving merged matchData.")
        let updatedGameData = data
        
        match.saveMergedMatch(updatedGameData, withResolvedExchanges: exchanges) { [weak self] error in
            if let receivedError = error {
                print("Failed to save merged data from \(exchanges.count) exchanges:")
                self?.handleError(receivedError)
                closure?(receivedError)
            } else {
                print("Successfully merged data from \(exchanges.count) exchanges!")
                self?.refreshInterface()
                closure?(nil)
            }
        }
    }
    
    /// Ends the match.
    ///
    /// - Important: Before your game calls this method, the matchOutcome property on each
    /// participant object stored in the participants property must have been set to a value other than
    /// GKTurnBasedMatch.Outcome.none.
    func endCurrentMatch() {
        currentMatch?.endMatchInTurn(withMatch: data) { [weak self] error in
            if let receivedError = error {
                print("Failed to end game for match \(self?.currentMatch?.matchID ?? "N/A"):")
                self?.handleError(receivedError)
                return
            }
            print("Ended game for match \(self?.currentMatch?.matchID ?? "N/A")")
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
        print("New Turn Order:")
        var count = 1
        for participant in newTurnOrder {
            print("\(count). \(participant.player?.displayName ?? "N/A")")
            count += 1
        }
        
        return newTurnOrder
    }
    
    func informativeAlertWithTitle(_ title: String, message: String? = nil) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let ok = UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
            self?.advanceAlertQueueIfNeeded()
        }
        alert.addAction(ok)
        return alert
    }
    
    // MARK: Exchange Related
    
    func replyToExchange(_ exchange: GKTurnBasedExchange, accepted: Bool) {
        let argument = accepted ? "accepted" : "declined"
        let arguments = [argument]
        
        guard let exchangeResponse = stringArrayToData(stringArray: arguments) else {
            assertionFailure("Failed to encode arguments to data for exchange reply.")
            return
        }
        
        let stringArguments = [String]()

        exchange.reply(withLocalizableMessageKey: ":-)", arguments: stringArguments, data: exchangeResponse) { [weak self] error in
            if let receivedError = error {
                print("Failed to reply to exchange \(exchange.exchangeID):")
                self?.handleError(receivedError)
                return
            }
            
            print("Replied to exchange \(exchange.exchangeID).")
            self?.refreshInterface()
        }
    }
    
    
    func awaitReplyOrCancelExchange(_ exchange: GKTurnBasedExchange) {
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
            self?.advanceAlertQueueIfNeeded()
        }
        
        alert.addAction(cancel)
        self.presentOrQueueAlert(alert, ofType: .waitingForExchangeReplies)
    }
    
    func mergeExchangesAsNeeded(closure: @escaping (Error?)->Void) throws {
        
        guard let match = currentMatch else {
            print("No match to merge exchanges with")
            return
        }
        
        guard let exchanges = match.completedExchanges else {
            // There are no completed exchanges to merge with match data, so
            // just call the closure.
            closure(nil)
            return
        }
        
        print("Saving merged matchData.")
        
        // This is where I imagine we merge the exchange data with the match data.
        let updatedGameData = data
        
        match.saveMergedMatch(updatedGameData, withResolvedExchanges: exchanges) { [weak self] error in
            if let receivedError = error {
                print("Failed to save merged data from \(exchanges.count) exchanges:")
                self?.handleError(receivedError)
                closure(receivedError)
            } else {
                print("Successfully merged data from \(exchanges.count) exchanges!")
                self?.refreshInterface()
                closure(nil)
            }
        }
    }
    
    
    func printDetailsForExchange(_ exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch, with player: GKPlayer) {
        print("\nDETAILS FOR EXCHANGE \(exchange.exchangeID)")
        print("Match   : \(match.matchID) is \(stringForMatchStatus(match.status))")
        print("Exchange: \(stringForExchangeStatus(exchange.status))")
        print("Message : \(exchange.message ?? "")")
        print("Local   : \(GKLocalPlayer.local.displayName)")
        print("Creator : \(player.displayName)")
        print("Invitee : \(exchange.recipients.first?.player?.displayName ?? "N/A")")
        print("Replies : \(exchange.replies?.count ?? 0)")
        print("Resolve : \(match.currentParticipant?.player?.displayName ?? "N/A") will resolve the data.\n")
    }
}


// MARK: - TURN BASED MATCH MAKER DELEGATE -

extension Simple: GKTurnBasedMatchmakerViewControllerDelegate {
    
    func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
        print("Match Maker was cancelled")
        self.dismiss(animated: true) {
            print("Dismissed Match Maker")
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
            print("Dismissed Match Maker")
        }
    }
    
}


// MARK: - LOCAL PLAYER LISTENER -

extension Simple: GKLocalPlayerListener {

    // This extension is critical, as it handles all Game Center and
    // `GKTurnBasedMatch` related events.

    // MARK: GKTurnBasedEventListener

    /// Calling this will forfeit the match by ending the current turn and passing the turn to the next
    /// player who wins by walkover.
    ///
    /// This may be called by the player or by the game logic.
    func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        print("Wants to quit match \(match.matchID)!")

        let nextUp = nextParticipantsForMatch(match, didQuit: true)
        
        // This could be anything, based on game logic:
        let outcome = GKTurnBasedMatch.Outcome.quit
        
        // Pass the match to the next player by calling
        match.participantQuitInTurn(with: outcome, nextParticipants: nextUp, turnTimeout: turnTimeout, match: data) { [weak self] error in
            if let receivedError = error {
                print("Failed to leave match \(match.matchID) with error: \(receivedError)")
            } else {
                print("Match \(match.matchID) was successfully left by local player.")
                self?.refreshInterface()
            }
        }
    }

    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        print("Match ended")
        
        let alreadyViewingMatch = self.currentMatch?.matchID == match.matchID

        guard let localPlayer = match.participants.filter({ $0.player?.playerID == GKLocalPlayer.local.playerID }).first else {
            print("Local player not found in participants list for match \(match.matchID)")
            return
        }
        
        print("ENDED MATCH OVERVIEW")
        for participant in match.participants {
            print("\(participant.player?.displayName ?? "Unnamed player")\t: \(stringForPlayerOutcome(participant.matchOutcome))")
        }

        var opponents = ""
        var comma = ""
        let opponentCount = match.participants.count - 1
        var nameCount = 0
        for participant in match.participants {
            guard participant.player != GKLocalPlayer.local else {
                continue
            }
            
            if let name = participant.player?.displayName {
                opponents += comma + name
            }

            nameCount += 1
            if nameCount == opponentCount - 1 {
                comma = " and "
            } else {
                comma = ", "
            }
        }
        
        let alert = UIAlertController(title: "You \(stringForPlayerOutcome(localPlayer.matchOutcome).lowercased()) in a match against \(opponents)!", message: "Do you want to see the result now?", preferredStyle: .alert)
        
        if alreadyViewingMatch {
            
            let ok = UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.advanceAlertQueueIfNeeded()
            }
            
            alert.addAction(ok)
            alert.title = "You \(stringForPlayerOutcome(localPlayer.matchOutcome).lowercased()) against \(opponents)."
            alert.message = ""
            
            self.currentMatch = match
            self.refreshInterface()
            
        } else {
            let jump = UIAlertAction(title: "See Result", style: .default) { [weak self] _ in
                print("Player chose to go to match \(match.matchID)")
                self?.currentMatch = match
                self?.refreshInterface()
                self?.advanceAlertQueueIfNeeded()
            }
            let ignore = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                print("Player did not want to go to match \(match.matchID)")
                self?.advanceAlertQueueIfNeeded()
            }
            
            alert.addAction(jump)
            alert.addAction(ignore)
        }
        
        self.presentOrQueueAlert(alert, ofType: .alteringMatchContext)
    }

    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        
        assert(Thread.isMainThread)
        
        print("\n\nTURN EVENT RECEIVED!\n\n")
        
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
            
            if matchMaker != nil {
                dismiss(animated: true, completion: nil)
            }
            
            // Check if there is an ongoing exchange to handle:
            // Seems like received exhange event is only created on first game
            // launch after having received the exchange. After that we have
            // to present the exchange manually.
            
            if let exchanges = match.exchanges {
                for exchange in exchanges {
                    guard let exchangeCreator = exchange.sender.player else {
                        print("Skipping exchange \(exchange.exchangeID) without a sender!")
                        continue
                    }
                    printDetailsForExchange(exchange, for: match, with: exchangeCreator)
                }
            }
            
            if let exchange = match.activeExchanges?.first, let sender = exchange.sender.player {
                self.player(sender, receivedExchangeRequest: exchange, for: match)
            }
            
            // resolveActiveExchanges(forMatch: match)
            
        } else  if match.matchID == self.currentMatch?.matchID {
            
            // In the absence of audio, this is just a simple way to visualize
            // an game update.
            
            currentMatch = match
            self.view.throb(duration: 0.075, toScale: 1.1)
        
        } else {
        
            print("Turn event received for another match.")
                        
            let alert = UIAlertController(title: "A turn was taken in another match.", message: "Do you want to jump to that match?", preferredStyle: .alert)
            let jump = UIAlertAction(title: "Load Match", style: .default) { [weak self] _ in
                print("Player chose to go to match \(match.matchID)")
                self?.currentMatch = match
                self?.refreshInterface()
                self?.advanceAlertQueueIfNeeded()
            }
            let ignore = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                print("Player did not want to go to match \(match.matchID)")
                self?.advanceAlertQueueIfNeeded()
            }
            alert.addAction(jump)
            alert.addAction(ignore)
            
            self.presentOrQueueAlert(alert, ofType: .alteringMatchContext)
        }
        
        print("\nReceived turn event for match \(match.matchID) \(match.matchData == nil ? "without" : "with \(match.matchData!.count) bytes") data.\nDid become active: \(didBecomeActive)\n")
        refreshInterface()
    }

    func player(_ player: GKPlayer, didRequestMatchWithOtherPlayers playersToInvite: [GKPlayer]) {
        print("Did request match with other players ")
    }

    // MARK: Exchange Related
    
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
    // current player. No need to do anything for the creator after the creator
    // received the exchange replies.
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
    

    func player(_ player: GKPlayer, receivedExchangeReplies replies: [GKTurnBasedExchangeReply], forCompletedExchange exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        
        // Hmm... Is this simply received to update the game on the client side?
        // As merging data from here seems to always result in an error.
        
        print("RECEIVED EXHANGE REPLIES!")
        dismissAlert(ofType: .waitingForExchangeReplies)
        
        // The exchange is ready for processing: all invitees have responded.
        printDetailsForExchange(exchange, for: match, with: player)
            
        for reply in replies {
            guard let exchangeResponse = reply.data else {
                print("Reply has no data!")
                continue
            }
            if let array = dataToStringArray(data: exchangeResponse), let response = array.first {
                print("Exchange was \(response)!")
            }
        }

        // If the replies were received by current participant, we might just as well
        // merge the exchange data with the match data right away:
        
        try? mergeExchangesAsNeeded { [weak self] error in
            if let receivedError = error {
                print("Failed to save merged data from exchanges:")
                self?.handleError(receivedError)
            } else {
                print("Successfully merged data from exchanges!")
                self?.refreshInterface()
                self?.view.throb()
            }
        }
    }

    func player(_ player: GKPlayer, receivedExchangeCancellation exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        print("\nExchange creator \(exchange.sender.player?.displayName ?? "N/A") cancelled the exchange \(exchange.exchangeID).")
        
        let sender = exchange.sender.player?.displayName ?? "unknown sender"
        let alert = informativeAlertWithTitle("Exchange with \(sender) was cancelled", message: nil)
        presentOrQueueAlert(alert, ofType: .exchangeCancellationNotification)
        dismissAlert(ofType: .respondingToExchange)
        
        // Reload match data
        refreshInterface()
    }

    func player(_ player: GKPlayer, receivedExchangeRequest exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        
        // It appears as if I get an error if I try to reply .. too quickly? to a received exchange?
        // So, instead of replying directly when received - only to receive an error 100% of the times,
        // I decline the exchange (which will just let the exchange time out), leave the match, load it
        // again in MatchMaker - which shows the exchange. And now, replying to it works on the replier side..
        // However, now I get an error on the exchange creator side when receiving the reply.
        
        let message = exchange.message ?? "Accept the exhange or ignore it for now."
        print("\nReceived exchange \(exchange.exchangeID) from \(player.displayName) for match \(match.matchID)")
        
        guard let sender = exchange.sender.player else {
            print("Echange request has no sender!")
            return
        }

        printDetailsForExchange(exchange, for: match, with: sender)
        
        let alert = UIAlertController(title: "Accept exchange with \(player.displayName)?", message: message, preferredStyle: .alert)
        
        let accept = UIAlertAction(title: "Accept", style: .default) { [weak self] action in
            self?.replyToExchange(exchange, accepted: true)
            self?.refreshInterface()
            self?.advanceAlertQueueIfNeeded()
        }

        let decline = UIAlertAction(title: "Decline", style: .destructive) { [weak self] action in
            self?.replyToExchange(exchange, accepted: false)
            self?.refreshInterface()
            self?.advanceAlertQueueIfNeeded()
        }

        let ignore = UIAlertAction(title: "Ignore", style: .cancel) { [weak self] action in

            // I am starting to think that declining an exchange simply
            // means to let it time out.
            // self?.replyToExchange(exchange, accepted: false)
            
            self?.refreshInterface()
            self?.advanceAlertQueueIfNeeded()
        }
        
        alert.addAction(accept)
        alert.addAction(decline)
        alert.addAction(ignore)

        presentOrQueueAlert(alert, ofType: .respondingToExchange)
    }


    // MARK: GKInviteEventListener

    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        print("Did accept invite")

        // TODO: Pass the match controller to mapper, who then will forward it to the interface.
        // let realTimeMatchMaker = GKMatchmakerViewController(invite: invite)
    }

    func player(_ player: GKPlayer, didRequestMatchWithRecipients recipientPlayers: [GKPlayer]) {
        print("Did request match with recipients")
    }

    func player(_ player: GKPlayer, didRequestMatchWithPlayers playerIDsToInvite: [String]) {
        print("Did request match with players")
    }


}
