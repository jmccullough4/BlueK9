import Foundation
import CoreLocation

final class CoordinateFormatter {
    static let shared = CoordinateFormatter()

    private init() {}

    func string(from coordinate: CLLocationCoordinate2D, mode: CoordinateDisplayMode) -> String {
        switch mode {
        case .latitudeLongitude:
            return latLonString(from: coordinate)
        case .mgrs:
            return mgrsString(from: coordinate)
        }
    }

    private func latLonString(from coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f°, %.5f°", coordinate.latitude, coordinate.longitude)
    }

    private func mgrsString(from coordinate: CLLocationCoordinate2D) -> String {
        guard abs(coordinate.latitude) <= 90, abs(coordinate.longitude) <= 180 else {
            return "Invalid" 
        }

        let zoneNumber = zoneNumber(for: coordinate.longitude)
        let zoneLetter = zoneLetter(for: coordinate.latitude)

        let utm = utmCoordinates(for: coordinate, zoneNumber: zoneNumber)
        var easting = utm.easting
        var northing = utm.northing

        // Determine 100k grid designator
        let columnLetters = ["ABCDEFGH", "JKLMNPQR", "STUVWXYZ", "ABCDEFGH", "JKLMNPQR", "STUVWXYZ"]
        let rowLetters = [
            "ABCDEFGHJKLMNPQRSTUV",
            "FGHJKLMNPQRSTUVABCDE",
            "ABCDEFGHJKLMNPQRSTUV",
            "FGHJKLMNPQRSTUVABCDE",
            "ABCDEFGHJKLMNPQRSTUV",
            "FGHJKLMNPQRSTUVABCDE"
        ]
        let setIndex = (zoneNumber - 1) % 6
        let columnSet = columnLetters[setIndex]
        let rowSet = rowLetters[setIndex]

        let easting100k = Int(floor(easting / 100000.0))
        var northing100k = Int(floor(northing / 100000.0))

        let columnLetterIndex = ((easting100k - 1) % columnSet.count + columnSet.count) % columnSet.count
        let columnLetter = columnSet[columnSet.index(columnSet.startIndex, offsetBy: columnLetterIndex)]

        northing100k = ((northing100k % rowSet.count) + rowSet.count) % rowSet.count
        let rowLetter = rowSet[rowSet.index(rowSet.startIndex, offsetBy: northing100k)]

        // Strip the 100k designator from easting and northing
        easting = easting.truncatingRemainder(dividingBy: 100000)
        northing = northing.truncatingRemainder(dividingBy: 100000)
        if easting < 0 { easting += 100000 }
        if northing < 0 { northing += 100000 }

        let eastingString = String(format: "%05.0f", easting)
        let northingString = String(format: "%05.0f", northing)

        return "\(zoneNumber)\(zoneLetter) \(columnLetter)\(rowLetter) \(eastingString) \(northingString)"
    }

    private func zoneNumber(for longitude: CLLocationDegrees) -> Int {
        Int((longitude + 180) / 6) + 1
    }

    private func zoneLetter(for latitude: CLLocationDegrees) -> String {
        if latitude < -72 { return "C" }
        if latitude < -64 { return "D" }
        if latitude < -56 { return "E" }
        if latitude < -48 { return "F" }
        if latitude < -40 { return "G" }
        if latitude < -32 { return "H" }
        if latitude < -24 { return "J" }
        if latitude < -16 { return "K" }
        if latitude <  -8 { return "L" }
        if latitude <   0 { return "M" }
        if latitude <   8 { return "N" }
        if latitude <  16 { return "P" }
        if latitude <  24 { return "Q" }
        if latitude <  32 { return "R" }
        if latitude <  40 { return "S" }
        if latitude <  48 { return "T" }
        if latitude <  56 { return "U" }
        if latitude <  64 { return "V" }
        if latitude <  72 { return "W" }
        return "X"
    }

    private func utmCoordinates(for coordinate: CLLocationCoordinate2D, zoneNumber: Int) -> (easting: Double, northing: Double) {
        let latRad = coordinate.latitude * .pi / 180
        let lonRad = coordinate.longitude * .pi / 180
        let lonOrigin = Double(zoneNumber - 1) * 6 - 180 + 3
        let lonOriginRad = lonOrigin * .pi / 180

        let a = 6378137.0
        let f = 1 / 298.257223563
        let k0 = 0.9996

        let eSq = f * (2 - f)
        let ePrimeSq = eSq / (1 - eSq)

        let n = a / sqrt(1 - eSq * pow(sin(latRad), 2))
        let t = pow(tan(latRad), 2)
        let c = ePrimeSq * pow(cos(latRad), 2)
        let aTerm = cos(latRad) * (lonRad - lonOriginRad)

        let m = a * ((1 - eSq / 4 - 3 * pow(eSq, 2) / 64 - 5 * pow(eSq, 3) / 256) * latRad
                     - (3 * eSq / 8 + 3 * pow(eSq, 2) / 32 + 45 * pow(eSq, 3) / 1024) * sin(2 * latRad)
                     + (15 * pow(eSq, 2) / 256 + 45 * pow(eSq, 3) / 1024) * sin(4 * latRad)
                     - (35 * pow(eSq, 3) / 3072) * sin(6 * latRad))

        let easting = k0 * (n * (aTerm + (1 - t + c) * pow(aTerm, 3) / 6 + (5 - 18 * t + pow(t, 2) + 72 * c - 58 * ePrimeSq) * pow(aTerm, 5) / 120)) + 500_000.0

        var northing = k0 * (m + n * tan(latRad) * (pow(aTerm, 2) / 2 + (5 - t + 9 * c + 4 * pow(c, 2)) * pow(aTerm, 4) / 24 + (61 - 58 * t + pow(t, 2) + 600 * c - 330 * ePrimeSq) * pow(aTerm, 6) / 720))

        if coordinate.latitude < 0 {
            northing += 10_000_000.0
        }

        return (easting, northing)
    }
}
