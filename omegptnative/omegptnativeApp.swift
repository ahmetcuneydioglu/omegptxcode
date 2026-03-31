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
        RevenueCatManager.shared.configureIfNeeded(appUserID: AuthManager.shared.currentUser?.id)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
