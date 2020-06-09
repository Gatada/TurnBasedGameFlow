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

/// One controller to rule them all.
class Simple: UIViewController {
    
    // MARK: - Interface Objects

    @IBOutlet weak var matchMaker: UIButton!
    @IBOutlet weak var versionBuild: UILabel!
    
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
    
    // MARK: - Properties
    
    var player: AVAudioPlayer?

    let turnTimeout: TimeInterval = 60 * 10 // 10 min to speed up testing
    let data = Data()
    
    weak var matchMakerController: GKTurnBasedMatchmakerViewController?
    weak var alert: UIAlertController?
    
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
    
    var currentMatch: GKTurnBasedMatch? = nil
    
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
        
        exchangeHistory.text = "\(match.activeExchanges?.count ?? 0) active / \(match.exchanges?.count ?? 0) total"
        
        // Now check if game is over:
        print("Game is \(gameEnded ? "over" : "active").")
    }

    // MARK: - User Interaction
    
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
        
        guard let currentOpponent = opponent else {
            print("No opponent for match \(currentMatch?.matchID ?? "N/A")")
            return
        }

        let stringArguments = [String]()
        let recipients = [currentOpponent]
        let turnTimeout: TimeInterval = 120 // seconds
        
        currentMatch?.sendExchange(to: recipients, data: data, localizableMessageKey: "Do you want to trade?", arguments: stringArguments, timeout: turnTimeout) { [weak self] exchange, error in
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
    
    
    /// A reminder can only be sent when the recipient is not already interacting with the related game.
    @IBAction func sendReminderTap(_ sender: Any) {
        print("Send reminder for match \(currentMatch?.matchID ?? "N/A")")
        
        guard let currentOpponent = opponent else {
            print("No opponent for match \(currentMatch?.matchID ?? "N/A")")
            return
        }
        
        let stringArguments = [String]()
        
        currentMatch?.sendReminder(to: [currentOpponent], localizableMessageKey: ":-)", arguments: stringArguments) { [weak self] error in
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
    

    
    func mergeExchangesAsNeeded(closure: @escaping (Error?)->Void) throws {
        
        guard let match = currentMatch else {
            print("No match to merge exchanges with")
            return
        }

        guard let exchanges = match.exchanges else {
            // There are no open exchanges that will prevent turn and game from ending.
            closure(nil)
            return
        }

        guard match.activeExchanges == nil || (match.activeExchanges?.count == 0 && exchanges.count > 0) else {
            throw MatchUpdateError.waitingForActiveExchangesToComplete
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
                        print("Failed to end turn for match \(self?.currentMatch?.matchID ?? "N/A"):")
                        self?.handleError(receivedError)
                        return
                    }
                    
                    print("Ended turn for match \(self?.currentMatch?.matchID ?? "N/A")")
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
                    guard participant != match.currentParticipant else {
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
                
                for participant in match.participants {
                    guard participant != match.currentParticipant else {
                        participant.matchOutcome = .lost
                        continue
                    }
                    
                    // All other active participants have lost.
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
    
    private func prepareMatchRequest(withInviteMessage message: String? = nil, usingAutomatch: Bool) -> GKMatchRequest {
        
        let request = GKMatchRequest()
        request.minPlayers = 3
        request.maxPlayers = 3
        request.defaultNumberOfPlayers = 3
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
    
    func handleError(_ error: Error) {
        
        func gamekitError(_ code: Int) {
            switch code {
            case 3:
                presentErrorWithMessage("Error communicating with the server.")
            default:
                presentErrorWithMessage("Received error \(code): \(error.localizedDescription)")
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
    
    func presentErrorWithMessage(_ message: String) {
        
        if self.alert != nil {
            self.dismiss(animated: true) {
                print("Auto-dismissed already showing alert.")
            }
        }
        
        let alert = UIAlertController(title: "Received Error", message: message, preferredStyle: .alert)
        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        alert.addAction(ok)
        self.alert = alert
        print(message)

        self.present(alert, animated: true) {
            print("Presented error alert")
            self.refreshInterface()
        }
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

    func nextParticipantsForMatch(_ match: GKTurnBasedMatch) -> [GKTurnBasedParticipant] {
        var foundCurrentParticipant = false
        var tail = [GKTurnBasedParticipant]()
        var head = [GKTurnBasedParticipant]()
        for participant in match.participants {
            guard participant != match.currentParticipant else {
                // Current partitipant is last element in tail.
                // Following participants are added to the head.
                tail.append(participant)
                foundCurrentParticipant = true
                continue
            }
            if foundCurrentParticipant {
                head.append(participant)
            } else {
                tail.append(participant)
            }
        }
        
        let newTurnOrder = head + tail
        print("New Turn Order:")
        var count = 1
        for participant in newTurnOrder {
            print("\(count) \(participant.player?.alias ?? "N/A")")
            count += 1
        }
        
        return head + tail
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
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { action in
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
        }
        
        alert.addAction(cancel)
        
        self.present(alert, animated: true) {
            print("Presented response alert for exhange")
            self.alert = alert
            self.refreshInterface()
        }
    }
    
    func printDetailsForExchange(_ exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch, with player: GKPlayer) {
        print("\nREPLIES FOR EXCHANGE \(exchange.exchangeID)")
        print("Match   : \(match.matchID) is \(stringForMatchStatus(match.status))")
        print("Exchange: \(stringForExchangeStatus(exchange.status))")
        print("Message : \(exchange.message ?? "")")
        print("Local   : \(GKLocalPlayer.local.alias)")
        print("Creator : \(player.alias)")
        print("Invitee : \(exchange.recipients.first?.player?.alias ?? "N/A")")
        print("Replies : \(exchange.replies?.count ?? 0)")
        print("Resolve : \(match.currentParticipant?.player?.alias ?? "N/A") will resolve the data.\n")
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
    func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        print("Wants to quit match \(match.matchID)!")

        let opponent = match.participants.filter { (player) -> Bool in
            player != GKLocalPlayer.local
        }
        
        // Pass the match to the next player by calling
        match.participantQuitInTurn(with: .quit, nextParticipants: opponent, turnTimeout: turnTimeout, match: data) { (error) in
            if let receivedError = error {
                print("Failed to quit match \(match.matchID) with error: \(receivedError)")
            } else {
                print("Match \(match.matchID) was successfully quit by local player.")
            }
        }
    }

    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        print("Match ended")
        
        guard self.currentMatch != match else {
            // Player is already on the board.
            // Just update the UI
            refreshInterface()
            return
        }

        guard let localPlayer = match.participants.filter({ $0.player?.playerID == GKLocalPlayer.local.playerID }).first else {
            print("Local player not found in participants list for match \(match.matchID)")
            return
        }
        
        guard let opponent = match.participants.filter({ $0.player != GKLocalPlayer.local }).first else {
            print("Match \(match.matchID) ending without an opponent!")
            return
        }
        
        print("Current player: \(match.currentParticipant != nil ? match.currentParticipant?.player?.alias ?? "N/A" : "None")")
        
        let alert = UIAlertController(title: "You \(stringForPlayerOutcome(localPlayer.matchOutcome)) a Match against \(opponent.player?.alias ?? "N/A")!", message: "Do you want to see the result now?", preferredStyle: .alert)
        let jump = UIAlertAction(title: "See Result", style: .default) { [weak self] _ in
            print("Player chose to go to match \(match.matchID)")
            self?.currentMatch = match
            self?.refreshInterface()
        }
        let ignore = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            print("Player did not want to go to match \(match.matchID)")
        }
        
        alert.addAction(jump)
        alert.addAction(ignore)
        
        self.present(alert, animated: true)
        self.alert = alert
    }

    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        
        assert(Thread.isMainThread)
        
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
                        
            let opponent = match.participants.filter { (player) -> Bool in
                player.player != GKLocalPlayer.local
            }.first
            
            let alert = UIAlertController(title: "It's your turn in a game against \(opponent?.player?.alias ?? "N/A")!", message: "Do you want to jump to that match?", preferredStyle: .alert)
            let jump = UIAlertAction(title: "Load Match", style: .default) { [weak self] _ in
                print("Player chose to go to match \(match.matchID)")
                self?.currentMatch = match
                self?.refreshInterface()
            }
            let ignore = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                print("Player did not want to go to match \(match.matchID)")
            }
            alert.addAction(jump)
            alert.addAction(ignore)
            
            self.present(alert, animated: true, completion: {
                print("Presented turn dialog")
            })
            self.alert = alert
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
        
        if alert != nil {
            self.dismiss(animated: true) {
                print("Dismissed alert")
                self.alert = nil
            }
        }
        
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

        self.refreshInterface()
    }

    func player(_ player: GKPlayer, receivedExchangeCancellation exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        print("\nExchange creator \(exchange.sender.player?.alias ?? "N/A") cancelled the exchange \(exchange.exchangeID).")
        if self.alert != nil {
            self.dismiss(animated: true) {
                self.alert = nil
                print("Dismissed cancelled exchange dialog.")
            }
        }
        // Rewind any changes from the exchange?
        refreshInterface()
    }

    func player(_ player: GKPlayer, receivedExchangeRequest exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        
        // It appears as if I get an error if I try to reply .. too quickly? to a received exchange?
        // So, instead of replying directly when received - only to receive an error 100% of the times,
        // I decline the exchange (which will just let the exchange time out), leave the match, load it
        // again in MatchMaker - which shows the exchange. And now, replying to it works on the replier side..
        // However, now I get an error on the exchange creator side when receiving the reply.
        
        let message = exchange.message ?? "Accept the exhange with \(player.displayName)?"
        print("\nReceived exchange \(exchange.exchangeID) from \(player.alias) for match \(match.matchID)")
        
        printDetailsForExchange(exchange, for: match, with: player)
        
        let alert = UIAlertController(title: "Exchange", message: message, preferredStyle: .alert)
        
        let accept = UIAlertAction(title: "Accept", style: .default) { [weak self] action in
            self?.replyToExchange(exchange, accepted: true)
            self?.refreshInterface()
        }
        
        let decline = UIAlertAction(title: "Decline", style: .destructive) { [weak self] action in

            // I am starting to think that declining an exchange simply
            // means to let it time out.
            // self?.replyToExchange(exchange, accepted: false)
            
            self?.refreshInterface()
        }
        
        alert.addAction(accept)
        alert.addAction(decline)

        self.present(alert, animated: true) {
            print("Presented exhange")
            self.alert = alert
        }
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
