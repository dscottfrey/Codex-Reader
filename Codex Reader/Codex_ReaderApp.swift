//
//  Codex_ReaderApp.swift
//  Codex Reader
//
//  WHAT THIS FILE IS:
//  The app entry point. Configures the SwiftData ModelContainer (with
//  CloudKit sync per the Sync Engine directive §10) and hands the rest
//  of the UI to ContentView.
//
//  WHY THE SCHEMA LOOKS THE WAY IT DOES:
//  Every @Model class in the app must be listed in the schema below for
//  SwiftData to know about it. The container automatically mirrors the
//  store to the user's CloudKit private database. As new modules add
//  new @Model types (Annotation, Collection, etc.) they get appended
//  here.
//
//  WHY isStoredInMemoryOnly IS FALSE:
//  We want persistence and sync — the in-memory configuration is only
//  ever used by SwiftUI previews.
//

import SwiftUI
import SwiftData

@main
struct Codex_ReaderApp: App {

    /// The SwiftData container the whole app shares. Constructed once
    /// at launch.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self,
            ReaderSettingsRecord.self,
            BookSource.self,
            Collection.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // A failed container is unrecoverable — without persistence
            // the app cannot load any of the user's books, settings, or
            // annotations. Crash with the underlying error so the cause
            // is visible in crash reports.
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
