//
//  UIColor.swift
//  JBits
//
//  Created by Johan Basberg on 04/08/2016.
//

import UIKit

public extension UIColor {
    
    /// Returns a color with an adjusted intensity, increasingly darker by a higher shadow value.
    ///
    /// If the color is not in a compatible color space, the returned color will
    /// be the same as the source color (i.e. unchanged); additionally an assert
    /// failure is thrown.
    ///
    /// - Parameter shadow: The darkness level of the shadow, 0 is no shadow and 1 is maximum shadow.
    /// - Returns: A new color where a shadow of 1 results in a black color, while 0 returns an unchanged color (no shadow).
    func withShadowComponent(_ shadow: CGFloat) -> UIColor {
        
        let shadow = 1 - shadow
        var current: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) = (0, 0, 0, 0)
        
        guard getRed(&current.red, green: &current.green, blue: &current.blue, alpha: &current.alpha) else {
            assertionFailure("Color is not in a compatible color space")
            return self
        }

        return UIColor(red: current.red * shadow, green: current.green * shadow, blue: current.blue * shadow, alpha: current.alpha)
    }

    
    /// Returns a new `UIColor` with the provided saturation level.
    ///
    /// With a new saturation value of 0 the returned color is unchanged. Providing
    /// a value of 1 will return a fully desaturated color.
    ///
    /// If the color is not in a compatible color space, the returned color will
    /// be the same as the source color (i.e. unchanged); additionally an assert
    /// failure is thrown.
    ///
    /// - Parameter newSaturation: The new saturation level, ranging from 0 (no change) to 1 (full desaturated).
    func withSaturation(_ newSaturation: CGFloat) -> UIColor {
        
        var current: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) = (0, 0, 0, 0)
        
        guard getRed(&current.red, green: &current.green, blue: &current.blue, alpha: &current.alpha) else {
            assertionFailure("Color is not in a compatible color space")
            return self
        }

        let invertedSaturation = 1 - newSaturation

        let brightnessRed = 0.299 * pow(current.red, 2)
        let brightnessGreen = 0.587 * pow(current.green, 2)
        let brightnessBlue = 0.114 * pow(current.blue, 2)
        let perceivedBrightness = sqrt(brightnessRed + brightnessGreen + brightnessBlue)
        
        let newRed = current.red + invertedSaturation * (perceivedBrightness - current.red)
        let newGreen = current.green + invertedSaturation * (perceivedBrightness - current.green)
        let newBlue = current.blue + invertedSaturation * (perceivedBrightness - current.blue)
        
        return UIColor(red: newRed, green: newGreen, blue: newBlue, alpha: current.alpha)
    }
    
    
}
