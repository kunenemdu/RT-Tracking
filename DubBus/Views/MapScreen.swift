//
//  MapScreen.swift
//  DubBus
//
//

import SwiftUI
import SwiftData
import MapKit

struct MapScreen: View {

    @State private var showStopSheet = false
    @StateObject private var viewModel = BusViewModel()
    @StateObject private var stopRoutesVM = StopRoutesViewModel()
    @StateObject private var mapScreenModel = MapScreenModel()
    @State var searchInput = ""
    @State private var filteredStops: [BusStop] = []
    
    @State private var position: MapCameraPosition = .automatic
    
    @State var sheetPresented: Bool = false
    @State var nearbyButtonVisibility: Bool = true
    @Query var allStops: [BusStop]
    @State private var nearbyStopsState: [BusStop] = []
    @State private var recomputeToken = UUID()
    @State private var hasCenteredOnUser = false
    @State private var lastRecomputeLocation: CLLocation? = nil
    private let recomputeThreshold: CLLocationDistance = 100
    
    @State private var selectedRoute: GTFSRouteInfo? = nil
    @State private var followingBus: Bus? = nil
    @State private var stopSheetTab: Int = 0

    @State private var searchWorkItem: DispatchWorkItem? = nil
    @State private var searchIndex: [StopSearchEntry] = []
    @State private var ignoreNextMapTapClose = false

    @State private var selectedRoutePolyline: MKPolyline? = nil
    
    let fallbackLocation = CLLocation(latitude: 53.2875, longitude: -6.3664)
    
    // MARK: - Main Body
    var body: some View {
        Map(position: $position) {
            mapContent
        }
        .simultaneousGesture(TapGesture().onEnded {
            if ignoreNextMapTapClose {
                ignoreNextMapTapClose = false
                return
            }
            showStopSheet = false
            sheetPresented = false
            searchInput = ""
            filteredStops = []
            selectedRoute = nil
            selectedRoutePolyline = nil
            followingBus = nil
        })
        .overlay(alignment: .top) {
            topSearchOverlay
        }
        .overlay(alignment: .bottomTrailing) {
            followCancelButton
        }
        .onAppear(perform: onAppearAction)
        .onDisappear { viewModel.stopLiveUpdates() }
        .onChange(of: mapScreenModel.lastKnownLocation, handleLocationUpdate)
        .onChange(of: allStops.count, handleStopsCountChange)
        .onChange(of: searchInput, handleSearchInputChange)
        .onChange(of: selectedRoute, handleRouteChange)
        .onChange(of: showStopSheet, handleSheetToggle)
        .onChange(of: viewModel.buses, handleBusesUpdate)
        .sheet(isPresented: $sheetPresented) { nearbyStopsSheet }
        .sheet(isPresented: $showStopSheet, onDismiss: onStopSheetDismiss) { stopDetailSheet }
    }

    // MARK: - Map Content
    @MapContentBuilder
    private var mapContent: some MapContent {
        UserAnnotation()
        
        // Bus Stop Annotations
        ForEach(nearbyStopsState) { stop in
            Annotation(String(stop.stopCode), coordinate: stop.coordinate) {
                BusStopIcon {
                    ignoreNextMapTapClose = true
                    viewModel.select(stop: stop)
                    selectedRoute = nil
                    selectedRoutePolyline = nil
                    followingBus = nil
                    stopSheetTab = 0
                    sheetPresented = false
                    showStopSheet = true
                }
            }
        }
        
        // Route Polyline
        if let polyline = selectedRoutePolyline {
            MapPolyline(polyline)
                .stroke(Color.blue, lineWidth: 5)
        }

        // Live Bus Annotations
        if let route = selectedRoute {
            let filteredBuses = viewModel.buses.filter { $0.routeId == route.id }
            ForEach(filteredBuses) { bus in
                Annotation(bus.id, coordinate: bus.coordinate) {
                    BusLiveIcon(
                        shortName: route.shortName,
                        isFollowing: followingBus?.id == bus.id
                    )
                    .onTapGesture {
                        ignoreNextMapTapClose = true
                        followingBus = bus
                        withAnimation {
                            position = .camera(MapCamera(centerCoordinate: bus.coordinate, distance: 1000))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Overlays
    @ViewBuilder
    private var topSearchOverlay: some View {
        VStack {
            SearchOverlay(
                searchText: $searchInput,
                filteredStops: filteredStops,
                onSelect: { selectedStop in
                    self.searchInput = ""
                    self.filteredStops = []
                    self.position = .camera(MapCamera(centerCoordinate: selectedStop.coordinate, distance: 150))
                    viewModel.select(stop: selectedStop)
                    selectedRoute = nil
                    selectedRoutePolyline = nil
                    followingBus = nil
                    stopSheetTab = 0
                    showStopSheet = true
                    sheetPresented = false
                }
            )
            
            Spacer()
            
            if !sheetPresented && searchInput.isEmpty {
                NearbyStopsButton { sheetPresented = true }
            }
        }
    }

    @ViewBuilder
    private var followCancelButton: some View {
        if followingBus != nil {
            Button {
                followingBus = nil
            } label: {
                Label("Stop Following", systemImage: "eye.slash.fill")
                    .font(.subheadline.bold())
                    .padding()
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding()
            .padding(.bottom, showStopSheet ? 300 : 0)
        }
    }

    // MARK: - Sheets
    @ViewBuilder
    private var nearbyStopsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby Stops").font(.headline)
                Spacer()
                Button { sheetPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(nearbyStopsState) { stop in
                        NearbyStopRow(stop: stop) {
                            viewModel.select(stop: stop)
                            selectedRoute = nil
                            selectedRoutePolyline = nil
                            followingBus = nil
                            stopSheetTab = 0
                            sheetPresented = false
                            showStopSheet = true
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .presentationDetents([.fraction(0.30), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .presentationBackgroundInteraction(.enabled)
    }

    @ViewBuilder
    private var stopDetailSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let stop = viewModel.selectedStop {
                StopHeaderView(stop: stop) { showStopSheet = false }

                Picker("Stop Details", selection: $stopSheetTab) {
                    Text("Routes").tag(0)
                    Text("Tracking").tag(1)
                }
                .pickerStyle(.segmented)

                if stopSheetTab == 0 {
                    routesTabView(for: stop)
                } else {
                    trackingTabView
                }
            }
        }
        .padding(16)
        .presentationDetents([.fraction(0.35), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .presentationBackgroundInteraction(.enabled)
    }

    @ViewBuilder
    private func routesTabView(for stop: BusStop) -> some View {
        let routes = stopRoutesVM.routesFor(stop: stop)
        if routes.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading routes...").font(.subheadline).foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                    ForEach(routes) { route in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedRoute = route
                                stopSheetTab = 1
                            }
                        } label: {
                            RoutePill(title: route.shortName,
                                      isSelected: selectedRoute?.id == route.id,
                                      baseColor: colorForRoute(route.shortName))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trackingTabView: some View {
        if let route = selectedRoute {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RoutePill(title: route.shortName, isSelected: true, baseColor: colorForRoute(route.shortName))
                    Text(route.longName).font(.subheadline.bold())
                }
                
                let activeBuses = viewModel.buses.filter { $0.routeId == route.id }
                if activeBuses.isEmpty {
                    ContentUnavailableView("No Buses Found", systemImage: "bus", description: Text("There are currently no live buses for this route."))
                        .scaleEffect(0.8)
                } else {
                    Text("\(activeBuses.count) active buses on map").font(.caption).foregroundStyle(.secondary)
                    
                    if let followed = followingBus {
                        HStack {
                            Image(systemName: "eye.fill").foregroundStyle(.green)
                            Text("Following Bus \(followed.id)").font(.subheadline)
                            Spacer()
                            Button("Cancel") { followingBus = nil }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .padding()
                        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("Tap a bus icon on the map to track it.").font(.caption.italic()).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ContentUnavailableView("No Route Selected", systemImage: "route", description: Text("Select a route from the Routes tab to see live tracking."))
        }
    }

    // MARK: - Logic Handlers
    private func onAppearAction() {
        mapScreenModel.checkLocationEnabled()
        if let userLoc = mapScreenModel.lastKnownLocation {
            recomputeNearbyStops(for: userLoc)
            lastRecomputeLocation = userLoc
        } else {
            position = .camera(MapCamera(centerCoordinate: fallbackLocation.coordinate, distance: 2000))
        }
        stopRoutesVM.loadStaticStopRoutes()
        searchIndex = allStops.map { StopSearchEntry(stop: $0, code: String($0.stopCode), nameLower: $0.name.lowercased()) }
    }

    private func onStopSheetDismiss() {
        selectedRoute = nil
        selectedRoutePolyline = nil
        followingBus = nil
    }

    private func handleLocationUpdate(_ oldVal: CLLocation?, _ newVal: CLLocation?) {
        guard let loc = newVal else { return }
        if !hasCenteredOnUser {
            position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 2000))
            hasCenteredOnUser = true
        }
        if let last = lastRecomputeLocation {
            let distance = loc.distance(from: last)
            guard distance >= recomputeThreshold else { return }
        }
        lastRecomputeLocation = loc
        recomputeNearbyStops(for: loc)
    }

    private func handleStopsCountChange() {
        if let loc = mapScreenModel.lastKnownLocation { recomputeNearbyStops(for: loc) }
        searchIndex = allStops.map { StopSearchEntry(stop: $0, code: String($0.stopCode), nameLower: $0.name.lowercased()) }
    }

    private func handleSearchInputChange(_ oldVal: String, _ newVal: String) {
        searchWorkItem?.cancel()
        let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { filteredStops = []; return }
        let work = DispatchWorkItem {
            let qLower = trimmed.lowercased()
            let indexSnapshot = self.searchIndex
            var results: [BusStop] = []
            results.reserveCapacity(50)
            var seenCodes = Set<String>()
            func appendIfNew(_ entry: StopSearchEntry) -> Bool {
                if seenCodes.insert(entry.code).inserted {
                    results.append(entry.stop)
                    return results.count >= 50
                }
                return false
            }
            for entry in indexSnapshot { if entry.code.hasPrefix(trimmed) { if appendIfNew(entry) { break } } }
            if results.count < 50 { for entry in indexSnapshot { if entry.nameLower.hasPrefix(qLower) { if appendIfNew(entry) { break } } } }
            if results.count < 50 { for entry in indexSnapshot { if entry.code.contains(trimmed) { if appendIfNew(entry) { break } } } }
            if results.count < 50 { for entry in indexSnapshot { if entry.nameLower.contains(qLower) { if appendIfNew(entry) { break } } } }
            DispatchQueue.main.async { self.filteredStops = results }
        }
        searchWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func handleRouteChange(_ oldVal: GTFSRouteInfo?, _ newVal: GTFSRouteInfo?) {
        if let route = newVal {
            Task {
                selectedRoutePolyline = await GTFSMapper.shared.loadSnappedRoutePolyline(forRouteId: route.id)
                if let polyline = selectedRoutePolyline {
                    let mapRect = polyline.boundingMapRect
                    let paddedRect = mapRect.insetBy(dx: -mapRect.width * 0.2, dy: -mapRect.height * 0.2)
                    withAnimation { position = .rect(paddedRect) }
                }
            }
        } else {
            selectedRoutePolyline = nil
        }
    }

    private func handleSheetToggle(_ oldVal: Bool, _ isShowing: Bool) {
        if isShowing { viewModel.startLiveUpdates() } else { viewModel.stopLiveUpdates() }
    }

    private func handleBusesUpdate(_ oldVal: [Bus], _ newBuses: [Bus]) {
        guard let followed = followingBus else { return }
        if let updatedBus = newBuses.first(where: { $0.id == followed.id }) {
            withAnimation(.easeInOut) {
                position = .camera(MapCamera(centerCoordinate: updatedBus.coordinate, distance: 1000))
            }
        }
    }

    private func recomputeNearbyStops(for location: CLLocation) {
        let stops = allStops
        let token = UUID()
        recomputeToken = token
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
            if self.recomputeToken != token { return }
            let sorted = stops.sorted {
                let loc1 = CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                let loc2 = CLLocation(latitude: $1.latitude, longitude: $1.longitude)
                return loc1.distance(from: location) < loc2.distance(from: location)
            }
            let top10 = Array(sorted.prefix(10))
            DispatchQueue.main.async {
                if self.recomputeToken != token { return }
                self.nearbyStopsState = top10
            }
        }
    }
}

// MARK: - Subviews
private struct BusStopIcon: View {
    let action: () -> Void
    var body: some View {
        VStack {
            Image(systemName: "bus")
                .padding(8)
                .background(Color.yellow)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black, lineWidth: 2))
                .onTapGesture(perform: action)
        }
    }
}

private struct BusLiveIcon: View {
    let shortName: String
    let isFollowing: Bool
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isFollowing ? .green : .blue)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                Image(systemName: "bus.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(shortName)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct NearbyStopsButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").font(.headline)
                Text("Nearby Stops").font(.headline.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding()
        .transition(.opacity.combined(with: .scale))
    }
}

private struct NearbyStopRow: View {
    let stop: BusStop
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.thinMaterial).frame(width: 40, height: 40)
                    Image(systemName: "bus.fill").foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.name).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                    Text("Stop \(String(stop.stopCode))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct StopHeaderView: View {
    let stop: BusStop
    let closeAction: () -> Void
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name).font(.title3).bold().lineLimit(2)
                Text("Stop \(String(stop.stopCode))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: closeAction) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct StopSearchEntry {
    let stop: BusStop
    let code: String
    let nameLower: String
}

private func colorForRoute(_ key: String) -> Color {
    var hasher = Hasher()
    hasher.combine(key)
    let hash = hasher.finalize()
    let positive = abs(hash)
    let hue = Double(positive % 256) / 255.0
    return Color(hue: hue, saturation: 0.65, brightness: 0.85)
}

private struct RoutePill: View {
    let title: String
    let isSelected: Bool
    let baseColor: Color

    var body: some View {
        let gradient = LinearGradient(colors: [baseColor.opacity(0.95), baseColor.opacity(0.75)],
                                      startPoint: .topLeading,
                                      endPoint: .bottomTrailing)
        Text(title)
            .font(.headline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Capsule(style: .continuous).fill(gradient))
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(isSelected ? 0.9 : 0.25), lineWidth: isSelected ? 2 : 1))
            .shadow(color: baseColor.opacity(0.25), radius: 8, x: 0, y: 4)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}

struct MapScreen_Previews: PreviewProvider {
    static var previews: some View {
        MapScreen()
    }
}

