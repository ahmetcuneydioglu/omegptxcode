//
//  omegptnativeApp.swift
//  omegptnative
//
//  Created by AHMETCND on 1.03.2026.
//

import SwiftUI

@main
struct omegptnativeApp: App {
    init() {
        AuthManager.shared.configureGoogleSignIn()
        AuthManager.shared.checkSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
