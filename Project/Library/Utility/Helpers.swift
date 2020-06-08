//
//  Helpers.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 06/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import Foundation
import GameKit


func stringForExchangeStatus(_ status: GKTurnBasedExchangeStatus) -> String {
    switch status {
    case .unknown:
        return "Unknown"
    case .active:
        return "Active"
    case .complete:
        return "Complete"
    case .resolved:
        return "Resolved"
    case .canceled:
        return "Canceled"
    default:
        return "Status \(status)"
    }
    
}

func stringForMatchStatus(_ status: GKTurnBasedMatch.Status) -> String {
    switch status {
    case .ended:
        return "Ended"
    case .matching:
        return "Matching"
    case .open:
        return "Open"
    case .unknown:
        return "Unknown"
    @unknown default:
        return "Unrecognized (\(status.rawValue))"
    }
}

func stringForPlayerOutcome(_ outcome: GKTurnBasedMatch.Outcome) -> String {
    switch outcome {
    case .lost:
        return "Lost"
    case .none:
        return "None"
    case .quit:
        return "Quit"
    case .tied:
        return "Tied"
    case .timeExpired:
        return "Time Expired"
    case .won:
        return "Won"
    default:
        return "Other (\(outcome.rawValue))"
    }
}

func stringForPlayerState(_ outcome: GKTurnBasedParticipant.Status) -> String {
    switch outcome {
    case .active:
        return "Active"
    case .declined:
        return "Declined"
    case .done:
        return "Done"
    case .invited:
        return "Invited"
    case .matching:
        return "Matching"
    case .unknown:
        return "Unknown"
    @unknown default:
        return "Unrecognized (\(outcome.rawValue))"
    }
}
