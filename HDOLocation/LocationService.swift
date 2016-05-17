//
//  LocationService.swift
//  HDOLocation
//
//  Created by Daniel Nichols on 5/16/16.
//  Copyright © 2016 Hey Danno. All rights reserved.
//

import Foundation
import HDOPromise
import CoreLocation

/// The quality to favor when comparing locations
public enum LocationServicePreference {
    case
    MostAccurate,
    MostRecent
}

/// Simple service to get the current location
public class LocationService {
    
    /// Quality to look at when comparing locations
    public var preference = LocationServicePreference.MostAccurate
    
    /// Whether or not location detection is available on the device
    public var enabled: Bool {
        get {
            return CLLocationManager.locationServicesEnabled()
        }
    }
    
    /// The app's current location usage authorization status
    public var authorization: CLAuthorizationStatus {
        get {
            return CLLocationManager.authorizationStatus()
        }
    }
    
    /// The required accuracy level for locations retrieved
    public var desiredAccuracy: CLLocationAccuracy {
        get {
            return self._locationManager.desiredAccuracy
        }
        set(value) {
            self._locationManager.desiredAccuracy = value
        }
    }
    
    /// The number of seconds to cache locations before attempting to acquire a new location
    public var cacheInterval: NSTimeInterval = 0
    
    /// Retrieve the current location
    /// - returns: A promise that resolves with the best location
    public func current() -> Promise<CLLocation> {
        if let cached = self._locationManager.location where cached.timestamp.timeIntervalSinceNow <= self.cacheInterval {
            return Promise.resolve(cached)
        }
        guard self.enabled else {
            return Promise.reject(NSError(domain: "com.heydanno.HDOLocation", code: 403, userInfo: ["message": "Location services are disabled"]))
        }
        if !self._isUpdatingLocation {
            self._locationManager.startUpdatingLocation()
        }
        return Promise { (onFulfilled, onRejected) in
            self._fulfillmentHandlers.append(onFulfilled)
            self._rejectionHandlers.append(onRejected)
        }
    }
    
    // Private
    
    private var _isUpdatingLocation = false
    
    private lazy var _fulfillmentHandlers: [Promise<CLLocation>.ResolveCallback] = {
        return []
    }()

    private lazy var _rejectionHandlers: [Promise<CLLocation>.RejectCallback] = {
        return []
    }()
    
    private lazy var _locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self._locationManagerDelegate
        return manager
    }()
    
    private lazy var _locationManagerDelegate: CLLocationManagerDelegate = {
        return LocationManagerDelegate(owner: self)
    }()
    
    private func reset() {
        self._locationManager.stopUpdatingLocation()
        self._isUpdatingLocation = false
        self._fulfillmentHandlers.removeAll()
        self._rejectionHandlers.removeAll()
    }
    
    private func didReceiveLocation(location: CLLocation) {
        let callbacks = self._fulfillmentHandlers
        self.reset()
        for callback in callbacks {
            callback(location)
        }
    }
    
    private func didReceiveError(error: ErrorType) {
        let callbacks = self._rejectionHandlers
        self.reset()
        for callback in callbacks {
            callback(error)
        }
    }
    
    private func favoriteOfLocations(locations: [CLLocation]) -> CLLocation? {
        return locations.reduce(nil) { (best, location) -> CLLocation? in
            guard let best = best else {
                return location
            }
            if self.preference == .MostRecent && location.timestamp.timeIntervalSinceDate(best.timestamp) > 0 {
                return location
            } else if best.verticalAccuracy > location.verticalAccuracy && best.horizontalAccuracy > location.horizontalAccuracy {
                return best
            } else {
                return location
            }
        }
    }

}

@objc private class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    
    weak var owner: LocationService?
    
    init(owner: LocationService) {
        self.owner = owner
    }
    
    @objc func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let result = self.owner?.favoriteOfLocations(locations) else {
            // Do nothing
            return
        }
        self.owner?.didReceiveLocation(result)
    }
}