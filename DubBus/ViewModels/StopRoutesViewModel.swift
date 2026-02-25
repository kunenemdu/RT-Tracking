import Foundation
import Combine
// Assuming GTFSRouteInfo and BusStop are defined in other files within the same module,
// they should be accessible. If they were in separate modules, explicit imports would be needed.
// For GTFSMapper, it's nested, so we need to use its qualified name.

final class StopRoutesViewModel: ObservableObject {
    // stop_id -> [GTFSRouteInfo]
    @Published var stopRoutes: [String: [GTFSRouteInfo]] = [:]

    /// Loads the static mapping from stop_id to routes using GTFS datasets bundled with the app.
    func loadStaticStopRoutes() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Correctly reference GTFSMapper as it's nested within MappedRoute
            let map = MappedRoute.GTFSMapper.generateStopToRouteMapping() ?? [:]
            DispatchQueue.main.async {
                self.stopRoutes = map
            }
        }
    }

    /// Returns route infos (id, shortName, longName) that serve the given stop.
    func routesFor(stop: BusStop) -> [GTFSRouteInfo] {
        return stopRoutes[stop.gtfsStopId] ?? []
    }
}

