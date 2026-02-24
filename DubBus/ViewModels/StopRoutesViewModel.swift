import Foundation
import Combine

final class StopRoutesViewModel: ObservableObject {
    // stop_id -> [GTFSRouteInfo]
    @Published var stopRoutes: [String: [GTFSRouteInfo]] = [:]

    /// Loads the static mapping from stop_id to routes using GTFS datasets bundled with the app.
    func loadStaticStopRoutes() {
        DispatchQueue.global(qos: .userInitiated).async {
            let map = GTFSMapper.generateStopToRouteMapping() ?? [:]
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
