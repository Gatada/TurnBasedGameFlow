//
//  AlertType.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 10/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import Foundation

/// Priority level for a `UIAlertController`.
///
/// To present the alerts in order of priority, we associate each alert with an `AlertType`.
enum AlertType: Int {
    
    // Generic Alerts - Lowest Priority
    // –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    // Context independent alerts that is currently being queued,
    // but maybe should simply be discarded.
    
    /// A type used for generic Alerts, this type has the lowest priority.
    case informative
    
    
    
    // Follow-ups - Highest Priority
    // –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    // Alerts that has to follow the currently displayed alert.
    
    /// An alert that informs the player that the exchange was cancelled.
    ///
    /// Alerts of this type has to follow directly after the exchange alert that has been
    /// forcibly dismissed.
    case exchangeCancellationNotification = 300
    
    
    
    // Context Sensitive
    // –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    // Alerts associated with a particular match.
    
    /// Alert type offering the opportunity to select one recipient for the exchange.
    case creatingExchange = 200
    
    /// Alert type used for the alert that is shown while waiting for a reply to the current exchange.
    ///
    /// This is only required as this app uses a highly simplified exchange structure.
    case waitingForExchangeReplies
    
    /// Alert type used for the alert that lets the user accept, decline or resolve an exchange.
    case respondingToExchange
    
    /// A generic alert that is associated with the currently displayed match.
    case matchContextSensitive
    
    
    
    // Context Altering
    // –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    // Alerts that affects which match the player is viewing.
    
    /// Alert that can result in loading a match.
    ///
    /// Use this for alerts that offer the player a choice that loads a match.
    case alteringMatchContext = 100

    /// The priority level of an alert type.
    ///
    /// A higher value means higher priority. Present the alerts in decending priority level.
    /// In other words, show all alerts with priority level 2 before any with level 1, and so on.
    var priority: Int {
        return self.rawValue/100
    }
}
