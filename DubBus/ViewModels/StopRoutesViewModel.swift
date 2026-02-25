import Foundation
import Combine

final class StopRoutesViewModel: ObservableObject {
    // stop_id -> [GTFSRouteInfo]
    @Published var stopRoutes: [String: [GTFSRouteInfo]] = [:]

    /// Loads the static mapping from stop_id to routes using GTFS datasets bundled with the app.
    func loadStaticStopRoutes() {
        // Use a Task to bridge into Swift's concurrency system
        Task {
            // Use the 'shared' instance and 'await' the async method call.
            let map = await GTFSMapper.shared.generateStopToRouteMapping() ?? [:]
            
            // Ensure UI updates occur on the Main Actor
            await MainActor.run {
                self.stopRoutes = map
            }
        }
    }

    /// Returns route infos (id, shortName, longName) that serve the given stop.
    func routesFor(stop: BusStop) -> [GTFSRouteInfo] {
        return stopRoutes[stop.gtfsStopId] ?? []
    }
}

