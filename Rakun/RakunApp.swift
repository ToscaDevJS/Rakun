//
//  RakunApp.swift
//  Rakun
//
//  Created by Orlando Jesus Abril Tosca on 30/09/2026.
//

import SwiftUI

@main
struct RakunApp: App {
    var body: some Scene {
        WindowGroup {
            #if canImport(SceneKit)
            SandboxView()
            #else
            Text("El banco de pruebas necesita SceneKit.")
            #endif
        }
    }
}
