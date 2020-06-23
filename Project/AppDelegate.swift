//
//  AppDelegate.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 06/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit
import GameKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    override init() {
        super.init()
        GKLocalPlayer.local.register(self)
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("Notification!")
    }

}


// MARK: - GKLocalPlayerListener

extension AppDelegate: GKLocalPlayerListener {
    
    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        print("AppDelegate: Received turn event for match \(match.matchID)!")
    }

}

