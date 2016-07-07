//
//  ViewController.swift
//  rtd
//
//  Created by sehoward15 on 7/5/16.
//  Copyright © 2016 sehoward15. All rights reserved.
//

import UIKit
import MapKit

// MARK: - ViewController

class ViewController: UIViewController {
    @IBOutlet weak var mapView: MKMapView! {
        didSet {
            let span = MKCoordinateSpanMake(0.1, 0.1)
            let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.7392, longitude: -104.9903), span: span)
            mapView.setRegion(region, animated: true)
        }
    }
    private lazy var manager: CLLocationManager = CLLocationManager()
    /// Collection of all *RTD* `Stops`.
    private lazy var stops = parseStops()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        manager.requestWhenInUseAuthorization()
        loadAllBusAnnotations(with: VehiclePositionManager.sharedInstance.vehiclePositionFeed!)
    }
    
    @IBAction func resetButtonPressed(sender: AnyObject) {
        removeAnnotations()
        loadAllBusAnnotations(with: VehiclePositionManager.sharedInstance.vehiclePositionFeed!)
    }
}

extension ViewController {
    private func loadAllBusAnnotations(with feed: TransitRealtime.FeedMessage) {
        for entity in feed.entity {
            addAnnotation(with: entity)
        }
    }
    
    private func removeAnnotations(ignore annotation: BusAnnotation? = nil) {
        let annotationsToRemove = mapView.annotations.filter { $0 !== mapView.userLocation && $0 !== annotation }
        mapView.removeAnnotations(annotationsToRemove)
    }
    
    private func addAnnotation(with entity: TransitRealtime.FeedEntity) {
        if entity.hasVehicle && entity.vehicle.hasTrip {
            let annotation = BusAnnotation(feedEntity: entity)
            mapView.addAnnotation(annotation)
        }
    }
    
    private func add(stopUpdate stop: TransitRealtime.TripUpdate.StopTimeUpdate, to mapView: MKMapView) {
        if let stopInfo = (stops.filter { $0.id == stop.stopId }).first {
            let annotation = MKPointAnnotation()
            annotation.coordinate = stopInfo.coordinate
            annotation.title = stopInfo.description
            
            if let time = stop.arrivalTime {
                annotation.subtitle = "a: \(time)"
            } else if let time = stop.departureTime {
                annotation.subtitle = "d: \(time)"
            }
            
            mapView.addAnnotation(annotation)
        }
    }
}

extension ViewController: MKMapViewDelegate {
    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
        guard let annotation = annotation as? BusAnnotation else { return nil }

        let annotationIdentifier = "AnnotationIdentifier"
        var annotationView: MKAnnotationView!

        if let dequeuedAnnotationView = mapView.dequeueReusableAnnotationViewWithIdentifier(annotationIdentifier) {
            annotationView = dequeuedAnnotationView
            annotationView?.annotation = annotation
        } else {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: annotationIdentifier)
        }
        
        annotationView.canShowCallout = true
        annotationView.image = UIImage(named: "arrow.png")?.rotate(by: CGFloat(annotation.bearing))
        
        return annotationView
    }
    
    func mapView(mapView: MKMapView, didSelectAnnotationView view: MKAnnotationView) {
        guard let annotation = view.annotation as? BusAnnotation else { return }
        
        removeAnnotations(ignore: annotation)
        
        if let stopUpdates = annotation.tripUpdate?.stopTimeUpdate {
            for stop in stopUpdates {
                add(stopUpdate: stop, to: mapView)
            }
        }
    }
}

// MARK: - TripUpdateManager

final class TripUpdateManager {
    static let sharedInstance = TripUpdateManager()
    var tripFeed: TransitRealtime.FeedMessage?
    
    func load(with url: NSURL) throws {
        let tripUpdateData = NSData(contentsOfURL: url)!
        tripFeed = try TransitRealtime.FeedMessage.parseFromData(tripUpdateData)
    }
}

// MARK: - VehiclePositionManager

final class VehiclePositionManager {
    static let sharedInstance = VehiclePositionManager()
    var vehiclePositionFeed: TransitRealtime.FeedMessage?
    
    func load(with url: NSURL) throws {
        let vehiclePositionData = NSData(contentsOfURL: url)!
        vehiclePositionFeed = try TransitRealtime.FeedMessage.parseFromData(vehiclePositionData)
    }
}

// MARK: - BusAnnotation

class BusAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    let feedEntity: TransitRealtime.FeedEntity
    let tripUpdate: TransitRealtime.TripUpdate?
    var bearing: Float {
        return feedEntity.vehicle.position.bearing
    }
    
    required init(feedEntity: TransitRealtime.FeedEntity) {
        coordinate = feedEntity.vehicle.locationCoordinate
        self.feedEntity = feedEntity
        title = feedEntity.vehicle.trip.routeId
        tripUpdate = TripUpdateManager.sharedInstance.tripFeed?.entity.tripUpdate(by: feedEntity.vehicle.vehicleId)
        
        super.init()
    }
}

// MARK: - Stop

struct Stop {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let description: String
}

// MARK: - Parsing Stop

/**
 Parses `Stops` from *stop.txt*.
 
 - returns: All available RTD `Stops`.
 */
private func parseStops() -> [Stop] {
    let stopURL = NSBundle.mainBundle().URLForResource("stops.txt", withExtension: nil)!
    
    let stopText = NSString(data: NSData(contentsOfURL: stopURL)!, encoding: NSUTF8StringEncoding)!
    var location = 0
    
    /**
     Read the next line in the *stop.txt*.
     
     - returns: Next line breaking at *\r\n*.
     */
    func nextLine() -> String? {
        let searchRange = NSMakeRange(location, stopText.length - location)
        let range = stopText.rangeOfString("\r\n", options: [], range: searchRange, locale: nil)
        guard range.location != NSNotFound else { return nil }
        
        let line = stopText.substringWithRange(NSMakeRange(location, range.location - location))
        location = range.location + range.length
        return line
    }
    
    //clear first line.
    nextLine()
    
    /**
     Creates a `Stop` from a line in *stops.txt*.
     
     - parameter string: Comma delimited line via *stops.txt*.
     
     - returns: Associated `Stop`.
     */
    func stop(from string: String) -> Stop {
        enum StopComponentIndex: Int {
            case latitude
            case zoneId
            case longitude
            case url
            case id
            case description
            case name
            case type
        }
        
        let components = string.componentsSeparatedByString(",")
        let coordinate = CLLocationCoordinate2D(latitude: Double(components[StopComponentIndex.latitude.rawValue])!, longitude: Double(components[StopComponentIndex.longitude.rawValue])!)
        let id = components[StopComponentIndex.id.rawValue]
        let description = components[StopComponentIndex.name.rawValue]
        
        return Stop(id: id, coordinate: coordinate, description: description)
    }
    
    var stops = [Stop]()
    
    while let line = nextLine() {
        stops.append(stop(from: line))
    }
    
    return stops
}

// MARK: - Extensions

extension CollectionType where Generator.Element == TransitRealtime.FeedEntity {
    /**
     Convience method to obtain `TripUpdate` from a `FeedEntity`.
     
     - parameter vehicleId: *id* of the vehicle.
     
     - returns: Vehicle's `TripUpdate`.
     */
    func tripUpdate(by vehicleId: String) -> TransitRealtime.TripUpdate? {
        let trip = self.filter {
            guard $0.tripUpdate.hasVehicle == true else { return false }
            return $0.tripUpdate.vehicle.id == vehicleId
        }
        return (trip.first)?.tripUpdate
    }
}

extension TransitRealtime.VehiclePosition {
    var vehicleId: String {
        return vehicle.id
    }
    
    var locationCoordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: Double(position.latitude), longitude: Double(position.longitude))
    }
}

extension TransitRealtime.TripUpdate.StopTimeUpdate {
    var departureTime: NSDate? {
        guard hasDeparture else { return nil }
        return NSDate(timeIntervalSince1970: Double(departure.time))
    }
    
    var arrivalTime: NSDate? {
        guard hasArrival else { return nil }
        return NSDate(timeIntervalSince1970: Double(arrival.time))
    }
}

// MARK: - UIImage Extensions

extension UIImage {
    public func rotate(by degrees: CGFloat) -> UIImage {
        let degreesToRadians: (CGFloat) -> CGFloat = {
            return $0 / 180.0 * CGFloat(M_PI)
        }
        
        // calculate the size of the rotated view's containing box for our drawing space
        let rotatedViewBox = UIView(frame: CGRect(origin: CGPointZero, size: size))
        let t = CGAffineTransformMakeRotation(degreesToRadians(degrees));
        rotatedViewBox.transform = t
        let rotatedSize = rotatedViewBox.frame.size
        
        // Create the bitmap context
        UIGraphicsBeginImageContext(rotatedSize)
        let bitmap = UIGraphicsGetCurrentContext()
        
        // Move the origin to the middle of the image so we will rotate and scale around the center.
        CGContextTranslateCTM(bitmap, rotatedSize.width / 2.0, rotatedSize.height / 2.0)
        
        // Rotate the image context
        CGContextRotateCTM(bitmap, degreesToRadians(degrees))
        CGContextScaleCTM(bitmap, 1.0, -1.0)
        CGContextDrawImage(bitmap, CGRectMake(-size.width / 2, -size.height / 2, size.width, size.height), CGImage)
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
}