//
//  AlertManager.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 11/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit

/// A structure used to associate an instance of a `UIAlertController` with
/// an `AlertType` and match identifier.
struct QueuedAlert {
    weak var alert: UIAlertController?
    let type: AlertType
    let matchID: String?
}

enum AlertManagerError: Error {
    case keyWindowNotFound
}


class AlertManager {
    
    // MARK: - PROPERTIES
    
    /// The key window used to dig out the currently visible view controller.
    var keyWindow: UIWindow
    
    
    /// Returns the topmost view controller.
    ///
    /// Starting from the root view controller of the key window, it parses the entire
    /// view stack to eventually locate the topmost view controller.
    var topmostController: UIViewController {
        guard var topController = self.keyWindow.rootViewController else {
            fatalError("Failed to find rootViewController")
        }
        while let presentedViewController = topController.presentedViewController {
            topController = presentedViewController
        }
        return topController
    }
    
    /// Used to retain alerts created while there is already an alert on screen.
    var alertQueue = [QueuedAlert]()
    
    // MARK: - Life Cycle
    
    init() {
        guard let keyWindow = UIApplication.shared.windows.first else {
            fatalError("Failed to obtain key window from application delegate.")
        }
        self.keyWindow = keyWindow
    }

    
    // MARK: - API
    
    /// Call to have presented alert dismissed iff it is of the correct type.
    ///
    /// Checks the type of the first alert in the queue, then verifies that it is indeed visible
    /// before dismissing it with an animation and advancing the alert queue if needed.
    public func dismissAlert(ofType dismissableType: AlertType) {
        if let presented = alertQueue.first, presented.type == dismissableType {
            
            let alertIsVisible = presented.alert?.isViewLoaded == true && presented.alert?.view.window != nil
            guard alertIsVisible else {
                assertionFailure("Tried to dismiss an alert that is not visible")
                return
            }
            
            topmostController.dismiss(animated: true) { [weak self] in
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
    public func presentOrQueueAlert(_ alert: UIAlertController, withMatchID id: String? = nil, ofType type: AlertType = .informative) {
        
        let alertDetails = QueuedAlert(alert: alert, type: type, matchID: id)

        if alertQueue.isEmpty {
            topmostController.present(alert, animated: true) { [weak self] in
                self?.alertQueue.append(alertDetails)
            }
        } else {
            
            // Already showing an alert.
            // Verify that the alert is not a duplicate, then add alert to queue.
            //
            // The queue is advanced when visible alert calls
            // Simple.advanceAlertQueueIfNeeded() as part of its available
            // actions.
            
            guard alertQueue.firstIndex(where: { $0.matchID == alertDetails.matchID && $0.type == alertDetails.type }) == nil else {
                print("Discarding alert as queue already contains an alert with similar purpose.")
                return
            }
            

            if let insertIndex = alertQueue.firstIndex(where: { $0.type.priority < type.priority }) {
                // Found entry with lower priority than unqueued alert.
                // Inserting alert at this location so it'll be presented first.
                alertQueue.insert(alertDetails, at: insertIndex)
                // print("Inserted alert \"\(alert.title ?? alert.message ?? "Empty Alert")\" at index \(insertIndex).")
            } else {
                // No queued alert found with lower priority then unqeued alert.
                // Appending alert to the end of the queue
                alertQueue.append(alertDetails)
                // print("Appended alert \"\(alert.title ?? alert.message ?? "Empty Alert")\" to end of queue.")
            }
        }
    }
    
    /// Displays the alert controller that is next in the queue.
    ///
    /// - Important: This should be called at the end of any action associated with a queued alert.
    public func advanceAlertQueueIfNeeded() {
        guard !alertQueue.isEmpty else {
            print("Empty alert queue, bailing. Currently there should be no alert visible on screen?")
            return
        }
        
        alertQueue.removeFirst()
        
        guard let nextUp = alertQueue.first, let nextAlert = nextUp.alert else {
            print("No more queued alerts to present.")
            return
        }

        presentAlert(nextAlert)
    }
    
    
    /// Presents the alert controller using topmost view controller.
    ///
    /// To find the topmost view controller the entire view stack is parsed,
    /// which is then used to modally present the alert.
    func presentAlert(_ alert: UIAlertController) {
        
        guard let nextUp = alertQueue.first, let nextAlert = nextUp.alert else {
            print("No more queued alerts to present.")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let topmostController = self?.topmostController else {
                fatalError("No topmost controller identified")
            }
            topmostController.present(nextAlert, animated: true) { [weak self] in
                let queuedAlertCount = self?.alertQueue.count ?? 0
                let alertCaption = "\"\(nextAlert.title ?? nextAlert.message ?? "an empty alert")\""
                print("Presented \(alertCaption) alert from queue (\(queuedAlertCount - 1) remaining).")
            }
        }
    }
    
}
