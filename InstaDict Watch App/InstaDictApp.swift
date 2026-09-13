//
//  InstaDictApp.swift
//  InstaDict Watch App
//
//  Created by maoawa on 14/9/26.
//

import SwiftUI

@main
struct InstaDict_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
