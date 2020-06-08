//
//  Simple.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 04/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit
import GameKit


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
    
    @IBOutlet weak var endGame: UIButton!
    
    // MARK: - Properties
    
    var player: AVAudioPlayer?

    let turnTimeout: TimeInterval = 60 * 2 // 60 * 60 * 24 * 7 // One Week
    let data = Data()
    
    var alert: UIAlertController?
    
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
        
        print("""
            
            Local   : \(GKLocalPlayer.local.teamPlayerID)
            Opponent: \(opponent?.status == .matching ? "Searching.." : (opponent?.player?.teamPlayerID ?? "n/a"))
            
            Current : \(match.currentParticipant?.player?.teamPlayerID == GKLocalPlayer.local.teamPlayerID ? "Resolving Turn!" : "Waiting..")
            
            """)
        
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
        let isResolvingTurn = match.currentParticipant?.player == GKLocalPlayer.local
        let opponentOutcomeSet = opponent?.matchOutcome != GKTurnBasedMatch.Outcome.none
        let hasLocalOutcome = localParticipant?.matchOutcome != GKTurnBasedMatch.Outcome.none
        let isMatching = match.status == .matching
        let canSubmitTurn = isResolvingTurn && !opponentOutcomeSet && !gameEnded
        
        updateMatch.isEnabled = canSubmitTurn
        endTurn.isEnabled = canSubmitTurn
        endTurnWin.isEnabled = canSubmitTurn
        endTurnLose.isEnabled = canSubmitTurn
        
        beginExchange.isEnabled = !gameEnded && !opponentOutcomeSet

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
        
        if let localPlayer = self.localParticipant {
            localPlayerState.text = "\(stringForPlayerState(localPlayer.status))"
            localPlayerOutcome.text = "\(stringForPlayerOutcome(localPlayer.matchOutcome))"
        } else {
            localPlayerState.text = "N/A"
            localPlayerOutcome.text = "N/A"
        }

        if let currentOpponent = self.opponent {
            opponentStatus.text = stringForPlayerState(currentOpponent.status)
            opponentOutcome.text = stringForPlayerOutcome(currentOpponent.matchOutcome)
        } else {
            opponentStatus.text = "N/A"
            opponentOutcome.text = "N/A"
        }
        
        exchangeHistory.text = "\(match.activeExchanges?.count ?? 0) active / \(match.exchanges?.count ?? 0) total"
        
        // Now check if game is over:
        endGame.isEnabled = opponentOutcomeSet && !gameEnded
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
        
        currentMatch?.sendExchange(to: recipients, data: data, localizableMessageKey: "Do you want to trade?", arguments: stringArguments, timeout: turnTimeout) { [weak self] exchange, error in
            if let receivedError = error {
                print("Failed to send exchange for match \(self?.currentMatch?.matchID ?? "N/A") with error: \(receivedError)")
                return
            }
            
            guard let receivedExchange = exchange else {
                print("No exchange received")
                return
            }
            
            print("Sent exchange \(receivedExchange) for match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
            
            self?.presentActionSheetForExchange(receivedExchange)
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
                print("Failed to send reminder for match \(self?.currentMatch?.matchID ?? "N/A") with error: \(receivedError)")
                return
            }

            print("Sent reminder for match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
        }
    }
    
    @IBAction func updateMatchTap(_ sender: Any) {
        print("Update match \(currentMatch?.matchID ?? "N/A")")
        currentMatch?.saveCurrentTurn(withMatch: data) { [weak self] error in
            if let receivedError = error {
                print("Failed to update match \(self?.currentMatch?.matchID ?? "N/A") with error: \(receivedError)")
                return
            }
            
            print("Updated match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
        }
    }
    
    @IBAction func endTurnTap(_ sender: Any) {
        print("End turn of match \(currentMatch?.matchID ?? "N/A")")
        
        guard let currentOpponent = opponent else {
            print("No opponent for match \(currentMatch?.matchID ?? "N/A")")
            return
        }
        
        currentMatch?.endTurn(withNextParticipants: [currentOpponent], turnTimeout: turnTimeout, match: data) { [weak self] error in
            if let receivedError = error {
                
                let code = (receivedError as NSError).code
                
                switch code {
                case 3:
                    print("Failed to reach server.")
                default:
                    print("Failed to end turn for match \(self?.currentMatch?.matchID ?? "N/A") with error: \(receivedError)")
                }
                
                return
            }

            print("Ended turn for match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
        }
    }
    
    @IBAction func endTurnWinTap(_ sender: Any) {
        print("Win match \(currentMatch?.matchID ?? "N/A")")
        
        guard let match = currentMatch else {
            print("No match selected.")
            return
        }
        
        match.currentParticipant?.matchOutcome = .won
        endTurnTap(self)
    }
    
    @IBAction func endTurnLossTap(_ sender: Any) {
        print("Lose match \(currentMatch?.matchID ?? "N/A")")
        
        guard let match = currentMatch else {
            print("No match selected.")
            return
        }
        
        match.currentParticipant?.matchOutcome = .lost
        endTurnTap(self)
    }
    
    /// Ends the match.
    ///
    /// - Important: Before your game calls this method, the matchOutcome property on each
    /// participant object stored in the participants property must have been set to a value other than
    /// GKTurnBasedMatch.Outcome.none.
    @IBAction func endMatchTap(_ sender: Any) {
        
        // If current player cannot score more points, the game is over.
         // This is checked by the previous player, who's outcome is set
         // according to the score.
         //
         // Which means the outcome of the current participant is basically
         // deduced from the outcome of the opponent.
        
        guard let currentOpponent = opponent else {
            print("No opponent for match \(currentMatch?.matchID ?? "N/A")")
            return
        }
         
         guard let localParticipant = currentMatch?.currentParticipant else {
             print("Failed to obtain current participant from match \(currentMatch?.matchID ?? "N/A")")
             return
         }
         
         switch currentOpponent.matchOutcome {
         case .lost, .timeExpired, .quit:
             localParticipant.matchOutcome = .won
         case .tied:
             localParticipant.matchOutcome = .tied
         case .won:
             localParticipant.matchOutcome = .lost
         default:
             assertionFailure("Opponent has an unexpected game outcome \"\(stringForPlayerOutcome(currentOpponent.matchOutcome))\"")
             localParticipant.matchOutcome = .won
         }
         
         print("Local player \(stringForPlayerOutcome(localParticipant.matchOutcome)) the match!")
         
        currentMatch?.endMatchInTurn(withMatch: data) { [weak self] error in
            if let receivedError = error {
                print("Failed to end game for match \(self?.currentMatch?.matchID ?? "N/A") with error: \(receivedError)")
                return
            }

            print("Ended game for match \(self?.currentMatch?.matchID ?? "N/A")")
            self?.refreshInterface()
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
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
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
    
    func presentErrorWithMessage(_ message: String) {
        let alert = UIAlertController(title: "Received Error", message: message, preferredStyle: .alert)
        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        alert.addAction(ok)
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

        endGame.isEnabled = false

        matchID.text = "No Match Selected"
    }

    func dataToStringArray(data: Data) -> [String]? {
      return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String]
    }

    func stringArrayToData(stringArray: [String]) -> Data? {
      return try? JSONSerialization.data(withJSONObject: stringArray, options: [])
    }
    
    
    func replyToExchange(_ exchange: GKTurnBasedExchange, accepted: Bool) {
        let argument = accepted ? "accepted" : "declined"
        let arguments = [argument]
        
        guard let jsonData = stringArrayToData(stringArray: arguments) else {
            assertionFailure("Failed to encode arguments to data for exchange reply.")
            return
        }
        
        let stringArguments = [String]()

        exchange.reply(withLocalizableMessageKey: ":-)", arguments: stringArguments, data: jsonData) { [weak self] error in
            if let receivedError = error {
                print("Failed to reply to exchange \"\(exchange.message ?? "N/A")\" with error: \(receivedError)")
                return
            }
            
            print("Replied to exchange with message: \(exchange.message ?? "N/A")")
            self?.refreshInterface()
        }
    }
    
    
    func presentActionSheetForExchange(_ exchange: GKTurnBasedExchange) {
        let alert = UIAlertController(title: "Exchange", message: "Awaiting reply or timeout.", preferredStyle: .actionSheet)
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { action in
            let noArguments = [String]()
            exchange.cancel(withLocalizableMessageKey: ":-/", arguments: noArguments) { [weak self] error in
                if let receivedError = error {
                    print("Failed to cancel exchange \(exchange.exchangeID) with error: \(receivedError)")
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
    
    func mergeMatch(_ match: GKTurnBasedMatch, with data: Data, for exchanges: [GKTurnBasedExchange]) {
        print("Saving merged matchData.")
        let updatedGameData = data
        
        match.saveMergedMatch(updatedGameData, withResolvedExchanges: exchanges) { [weak self] error in
            if let receivedError = error {
                print("Failed to save merged data from \(exchanges.count) exchanges. Receveid error: \(receivedError)")
            } else {
                print("Successfully merged data from \(exchanges.count) exchanges!")
                self?.refreshInterface()
            }
        }
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
            
            play()
        }
        
        print("\nReceived turn event for match \(match.matchID) \(match.matchData == nil ? "without" : "with \(match.matchData!.count) bytes") data.\nDid become active: \(didBecomeActive)\n")
        dismiss(animated: true, completion: nil)
        currentMatch = match
        refreshInterface()
    }

    func player(_ player: GKPlayer, didRequestMatchWithOtherPlayers playersToInvite: [GKPlayer]) {
        print("Did request match with other players ")
    }

    // MARK: Exchange Related

    func player(_ player: GKPlayer, receivedExchangeReplies replies: [GKTurnBasedExchangeReply], forCompletedExchange exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        
        print("RECEIVED REPLIES: Exchange \(exchange.exchangeID) completed.")
        
        if alert != nil {
            self.dismiss(animated: true) {
                print("Dismissed alert")
                self.alert = nil
            }
        }
        
        // The exchange is ready for processing: all invitees have responded.
        
        print("Created by: \(player.teamPlayerID)")
        print("Received \(replies.count) exchange replies")
        print("Current player \(match.currentParticipant?.player?.alias ?? "N/A") will resolve the data.")
                
        for reply in replies {
            print(reply)
        }
        
        if localParticipant?.player == match.currentParticipant {
            // Let the exchange affect the game by having the
            // the current player merge the updated match data.
            self.mergeMatch(match, with: data, for: [exchange])
        }
        
        self.refreshInterface()
    }

    func player(_ player: GKPlayer, receivedExchangeCancellation exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        print("CANCEL: Exchange creator \(exchange.sender.player?.alias ?? "N/A") cancelled the exchange with message: \(exchange.message ?? "N/A")")
        print(exchange)
        refreshInterface()
    }

    func player(_ player: GKPlayer, receivedExchangeRequest exchange: GKTurnBasedExchange, for match: GKTurnBasedMatch) {
        
        let message = exchange.message ?? "Accept the exhange with \(player.displayName)?"
        print("RECEIVED REQUEST: Received exchange request with message: \"\(message)\"")
        
        let alert = UIAlertController(title: "Exchange", message: message, preferredStyle: .alert)
        
        let accept = UIAlertAction(title: "Accept", style: .default) { [weak self] action in
            self?.replyToExchange(exchange, accepted: true)
            self?.refreshInterface()
        }
        
        let decline = UIAlertAction(title: "Decline", style: .destructive) { [weak self] action in
            self?.replyToExchange(exchange, accepted: false)
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
