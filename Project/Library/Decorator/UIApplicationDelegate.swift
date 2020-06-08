//
//  UIApplicationDelegate.swift
//  JBits
//
//  Created by Basberg, Johan on 22/03/2019.
//  Copyright © 2019 Basberg, Johan. All rights reserved.
//

import UIKit

extension UIApplicationDelegate {

    
    /// Returns current version and build number as a string.
    ///
    /// It fetches the information from the info dictionary from
    /// the main bundle.
    ///
    static var versionBuild: String {
        let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let build: String = Bundle.main.infoDictionary?[kCFBundleVersionKey as String] as! String
        return "\(version) (\(build))"
    }
    
}
