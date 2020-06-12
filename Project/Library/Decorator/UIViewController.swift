//
//  UIViewController.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 12/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import UIKit

extension UIViewController {
    
    var isVisible: Bool {
        self.isViewLoaded == true && self.view.window != nil
    }

}
