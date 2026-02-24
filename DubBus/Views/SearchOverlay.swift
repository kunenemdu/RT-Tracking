//
//  SearchOverlay.swift
//  DubBus
//
//

import SwiftUI


struct SearchOverlay: View {
    @Binding var searchText: String
    var filteredStops: [BusStop]
    var onSelect: (BusStop) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            searchBarField
            
            // Results List
            if !searchText.isEmpty {
                resultsList
            }
        }
    }
    
    private var searchBarField: some View {
        TextField("Search stops...", text: $searchText)
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding()
    }
    
    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filteredStops) { stop in
                    Button {
                        onSelect(stop)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(stop.name).font(.headline)
                                Text("Stop \(stop.stopCode)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                    }
                    Divider()
                }
            }
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding(.horizontal)
            .frame(maxHeight: 300)
        }
    }
}
