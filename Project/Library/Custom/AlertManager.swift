//
//  AlertManager.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 11/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit

class AlertManager {
    
    // MARK: - PROPERTIES
    
    /// Used to retain alerts created while there is already an alert on screen.
    var alertQueue = [QueuedAlert]()
    
    /// The presenter of the alerts being displayed.
    ///
    /// For the sake of simplicity the presenter cannot be changed once set.
    weak var presenter: UIViewController?
    
    // MARK: - Life Cycle
    
    init(presenter: UIViewController) {
        self.presenter = presenter
    }

    
    // MARK: - API
    
    /// Call to have presented alert dismissed iff it is of the correct type.
    ///
    /// Checks the type of the first alert in the queue, then verifies that it is indeed visible
    /// before dismissing it with an animation and advancing the alert queue if needed.
    public func dismissAlert(ofType dismissableType: AlertType) {
        if let presented = alertQueue.first, presented.type == dismissableType {
            
            let alertIsVisible = presented.alert.isViewLoaded && presented.alert.view.window != nil
            guard alertIsVisible else {
                assertionFailure("Tried to dismiss an alert that is not visible")
                return
            }
            
            presenter?.dismiss(animated: true) { [weak self] in
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
    public func presentOrQueueAlert(_ alert: UIAlertController, ofType type: AlertType = .informative) {
        
        if alertQueue.isEmpty {
            presenter?.present(alert, animated: true) { [weak self] in
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
                // print("Inserted alert \"\(alert.title ?? alert.message ?? "Empty Alert")\" at index \(insertIndex).")
            } else {
                // No queued alert found with lower priority then unqeued alert.
                // Appending alert to the end of the queue
                alertQueue.append(unqueuedAlert)
                // print("Appended alert \"\(alert.title ?? alert.message ?? "Empty Alert")\" to end of queue.")
            }
        }
    }
    
    /// Displays the alert controller that is next in the queue.
    ///
    /// - Important: This should be called at the end of any action associated with a queued alert.
    public func advanceAlertQueueIfNeeded() {
        guard !alertQueue.isEmpty else {
            // print("No currently visible alerts.")
            return
        }
        
        guard alertQueue.first?.alert.isBeingPresented == false else {
            assertionFailure("Dequeued an alert that is still being presented.")
            return
        }
        
        alertQueue.removeFirst()
        
        guard let nextUp = alertQueue.first else {
            // print("No more queued alerts to present.")
            return
        }
        
        presenter?.present(nextUp.alert, animated: true) { [weak self] in
            let queuedAlertCount = self?.alertQueue.count ?? 0
            let alertCaption = "\"\(nextUp.alert.title ?? nextUp.alert.message ?? "an empty alert")\""
            print("Presented \(alertCaption) alert from queue (\(queuedAlertCount - 1) remaining).")
        }
    }
    
}
