//
//  Interface.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 11/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit
import GameKit

enum Utility {
    
    static func alert(_ title: String, message: String? = nil, closure: (()->Void)? = nil) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let ok = UIAlertAction(title: "OK", style: .cancel) { _ in
            closure?()
        }
        alert.addAction(ok)
        return alert
    }
    
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
    
}
