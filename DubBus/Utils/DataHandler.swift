//
//  DataHandler.swift
//  DubBus
//
//


import Foundation
import SwiftData

@MainActor
class DataHandler {
    static func seedStopsIfEmpty(context: ModelContext) {
        // Check if database already has stops
        let descriptor = FetchDescriptor<BusStop>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }
        print("checking for stops...")

        if count > 0 { return } else {
            print("no stops, seeding...")
            // 1. Locate JSON
            guard let url = Bundle.main.url(forResource: "stops", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return }

            // 2. Decode using a temporary Decodable struct (since @Model is tricky to decode directly)
            struct RawStop: Decodable {
                let stop_id: String
                let stop_code: Int
                let stop_name: String
                let stop_lat: Double
                let stop_lon: Double

                enum CodingKeys: String, CodingKey {
                    case stop_id
                    case stop_code
                    case stop_name
                    case stop_lat
                    case stop_lon
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)

                    // stop_id may be String or Int in the JSON
                    if let stringId = try? container.decode(String.self, forKey: .stop_id) {
                        stop_id = stringId
                    } else if let intId = try? container.decode(Int.self, forKey: .stop_id) {
                        stop_id = String(intId)
                    } else {
                        let ctx = DecodingError.Context(codingPath: [CodingKeys.stop_id], debugDescription: "stop_id is neither String nor Int")
                        throw DecodingError.typeMismatch(String.self, ctx)
                    }

                    // stop_code may sometimes be represented as a String; normalize to Int
                    if let code = try? container.decode(Int.self, forKey: .stop_code) {
                        stop_code = code
                    } else if let codeStr = try? container.decode(String.self, forKey: .stop_code), let code = Int(codeStr) {
                        stop_code = code
                    } else {
                        let ctx = DecodingError.Context(codingPath: [CodingKeys.stop_code], debugDescription: "stop_code is neither Int nor String convertible to Int")
                        throw DecodingError.typeMismatch(Int.self, ctx)
                    }

                    stop_name = try container.decode(String.self, forKey: .stop_name)
                    stop_lat = try container.decode(Double.self, forKey: .stop_lat)
                    stop_lon = try container.decode(Double.self, forKey: .stop_lon)
                }
            }

            do {
                let decoded = try JSONDecoder().decode([RawStop].self, from: data)
                
                // 3. Insert into SwiftData
                for rs in decoded {
                    let newStop = BusStop(stopCode: rs.stop_code,
                                          name: rs.stop_name,
                                          latitude: rs.stop_lat,
                                          longitude: rs.stop_lon,
                                          gtfsStopId: rs.stop_id)
                    context.insert(newStop)
                }
                try context.save()
            } catch {
                print("Failed to seed database: \(error)")
            }
        }
        
    }
}

