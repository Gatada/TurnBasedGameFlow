//
//  UIView.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 08/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit

extension UIView {
    
    /// Briefly scales the view up and back down, like
    /// a the beating or throbbing of a heart.
    ///
    /// The default values creates a visible throb, not really useful as a tap or refresh reponse.
    /// If the throb is being used to visualize a content refresh, then you may find a duration of 0.05
    /// and a scale of 1.15 to be more suitable.
    ///
    /// - Parameters:
    ///   - duration: The default duration of the entire animation, default is 0.1 seconds.
    ///   - scale: How much the view will be scaled, default is 1.3.
    func throb(duration: CFTimeInterval = 0.1, toScale scale: Double = 1.3) {
        let animationKey = "Throb"
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.duration = duration
        pulseAnimation.toValue = scale
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = 1
        self.layer.add(pulseAnimation, forKey: animationKey)
    }
}
