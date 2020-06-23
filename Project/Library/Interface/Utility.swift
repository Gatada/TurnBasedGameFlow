//
//  Utility.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 11/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit
import GameKit


/// A namespace for universally useful methods.
enum Utility {
    
    
    /// A simply alert with OK action.
    ///
    /// Tappin the only action available will execute the provided closure.
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - message: The message seen below the title in the alert.
    ///   - closure: The closure to execute when the user dismisses the alert.
    /// - Returns: <#description#>
    static func alert(_ title: String, message: String? = nil, closure: (()->Void)? = nil) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let ok = UIAlertAction(title: "OK", style: .cancel) { _ in
            closure?()
        }
        alert.addAction(ok)
        return alert
    }
    
    /// Returns a string including the display names of all participants, except the local player.
    static func opponentNamesForMatch(_ match: GKTurnBasedMatch) -> String {
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
        return opponents
    }
    
    
    static func data<T: Codable>(fromCodable instance: T) -> Data? {
        guard let data = try? JSONEncoder().encode(instance) else {
            return nil
        }
        return data
    }
    
    static func codableInstance<T: Codable>(from data: Data) -> T? {
        guard let data = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return data
    }
    
    static var timestamp: String {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        return dateFormatter.string(from: date)
    }
}
