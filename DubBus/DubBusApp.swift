//
//  DubBusApp.swift
//  DubBus
//
//

import SwiftUI
import SwiftData

@main
struct DubBusApp: App {
    // Define the container
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([BusStop.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Keep the app running during schema mismatches by falling back to in-memory.
            print("SwiftData persistent store failed: \(error). Falling back to in-memory for this run.")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                fatalError("Could not create any ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Seed data on first launch
                    DataHandler.seedStopsIfEmpty(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer) // Inject the container
    }
}
