import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

/// A location as CloudKit stores it, with every value a `CLLocation` saves
/// to a record, and the property wrapper that marks a location property.
///
/// ```swift
/// struct Place: Codable {
///     @Location var home: Location
/// }
///
/// place.home.latitude              // 41.88
/// place.$home                      // CLLocation, on Apple platforms
/// ```
///
/// `Location` is its own wrapped value, so the property reads and writes a
/// plain `Location` and the wrapper adds only the projected `CLLocation`.
/// It is `Codable` by synthesis, so JSON holds every value and a record
/// encoder can recognize a location by its type. CoreLocation exists only
/// on Apple platforms, so on Linux a `Location` has no projected value.
///
/// Values a location did not measure use CoreLocation's conventions: a
/// negative accuracy, course or speed means the value is invalid.
@propertyWrapper
public struct Location: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Meters above sea level.
    public var altitude: Double
    /// Meters. Negative when the coordinate is invalid.
    public var horizontalAccuracy: Double
    /// Meters. Negative when the altitude is invalid.
    public var verticalAccuracy: Double
    /// Degrees from true north. Negative when invalid.
    public var course: Double
    /// Degrees. Negative when the course is invalid.
    public var courseAccuracy: Double
    /// Meters per second. Negative when invalid.
    public var speed: Double
    /// Meters per second. Negative when the speed is invalid.
    public var speedAccuracy: Double
    /// When the location was measured.
    public var timestamp: Date

    /// A location with the defaults `CLLocation(latitude:longitude:)` uses
    /// for anything not given.
    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        horizontalAccuracy: Double = 0,
        verticalAccuracy: Double = -1,
        course: Double = -1,
        courseAccuracy: Double = -1,
        speed: Double = -1,
        speedAccuracy: Double = -1,
        timestamp: Date = Date()
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.timestamp = timestamp
    }

    public init(wrappedValue: Location) {
        self = wrappedValue
    }

    /// The location itself, so the property reads and writes a `Location`.
    public var wrappedValue: Location {
        get { self }
        set { self = newValue }
    }

    #if canImport(CoreLocation)
    /// The location as a `CLLocation`, for CoreLocation and MapKit.
    public var projectedValue: CLLocation {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        if #available(macOS 10.15.4, iOS 13.4, tvOS 13.4, watchOS 6.2, *) {
            return CLLocation(coordinate: coordinate, altitude: altitude, horizontalAccuracy: horizontalAccuracy, verticalAccuracy: verticalAccuracy, course: course, courseAccuracy: courseAccuracy, speed: speed, speedAccuracy: speedAccuracy, timestamp: timestamp)
        }
        return CLLocation(coordinate: coordinate, altitude: altitude, horizontalAccuracy: horizontalAccuracy, verticalAccuracy: verticalAccuracy, course: course, speed: speed, timestamp: timestamp)
    }
    #endif
}

#if canImport(CoreLocation)
extension Location {
    /// The values of a `CLLocation`.
    public init(_ location: CLLocation) {
        var courseAccuracy = -1.0
        var speedAccuracy = -1.0
        if #available(macOS 10.15.4, iOS 13.4, tvOS 13.4, watchOS 6.2, *) {
            courseAccuracy = location.courseAccuracy
            speedAccuracy = location.speedAccuracy
        }
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            course: location.course,
            courseAccuracy: courseAccuracy,
            speed: location.speed,
            speedAccuracy: speedAccuracy,
            timestamp: location.timestamp
        )
    }
}
#endif
