//
//  BusinessLocationController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 12.02.2024.
//  Copyright © 2024 Telegram. All rights reserved.
//

import Foundation
import TelegramCore
import Postbox
import Cocoa
import TGUIKit
import SwiftSignalKit
import MapKit

#if DEBUG

private final class AnnotationView : MKAnnotationView {
    private let locationPin = ImageView()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        
        
        self.wantsLayer = true
        
        layer?.masksToBounds = false
        
        
        
        locationPin.image = darkAppearance.icons.locationMapPin
        locationPin.sizeToFit()

        
        frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        wantsLayer = true
                        
        
        addSubview(locationPin)

        
        update()
    }
    override var annotation: MKAnnotation? {
        didSet {
            update()
        }
    }
    
    override func layout() {
        super.layout()
        locationPin.center()
        locationPin.setFrameOrigin(NSMakePoint(locationPin.frame.minX, locationPin.frame.minY - locationPin.frame.height / 2))
    }
    
    private func update() {
        
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    static var reuseIdentifier: String {
        return "peer"
    }
    
}



private class MapRowItem: GeneralRowItem {
    let context: AccountContext
    fileprivate let location: State.Location
    init(_ initialSize: NSSize, height: CGFloat, stableId: AnyHashable, context: AccountContext, location: State.Location, viewType: GeneralViewType, action: @escaping()->Void) {
        self.context = context
        self.location = location
        super.init(initialSize, height: height, stableId: stableId, viewType: viewType, action: action)
    }
    
    deinit {
       
    }
    
    override func viewClass() -> AnyClass {
        return MapRowItemView.self
    }
    
}

private final class MapRowItemView : GeneralContainableRowView, MKMapViewDelegate {
    private let mapView: MKMapView = MKMapView()
    private let overlay = Control()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(mapView)
        mapView.register(AnnotationView.self, forAnnotationViewWithReuseIdentifier: AnnotationView.reuseIdentifier)
        mapView.delegate = self
        
        mapView.showsZoomControls = false
        mapView.showsUserLocation = false
        
        mapView.isZoomEnabled = false
        mapView.isScrollEnabled = false
        
        mapView.showsBuildings = false
        addSubview(overlay)
        
        overlay.set(handler: { [weak self] _ in
            if let item = self?.item as? GeneralRowItem {
                item.action()
            }
        }, for: .Click)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        mapView.delegate = nil
    }
    
    override func layout() {
        super.layout()
        mapView.frame = bounds
        overlay.frame = bounds
    }

    
    func focusVenue() {
        guard let item = item as? MapRowItem else {
            return
        }
        let userLocation = item.location.coordinate
        var region = MKCoordinateRegion()
        var span = MKCoordinateSpan()
        span.latitudeDelta = CLLocationDegrees(0.005)
        span.longitudeDelta = CLLocationDegrees(0.005)
        var location = CLLocationCoordinate2D()
        location.latitude = userLocation.latitude
        location.longitude = userLocation.longitude
        region.span = span
        region.center = location
        mapView.setRegion(region, animated: true)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        switch annotation {
        case is State.Location:
            return mapView.dequeueReusableAnnotationView(withIdentifier: AnnotationView.reuseIdentifier, for: annotation)
        default:
            return nil
        }
    }
    
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        guard let item = item as? MapRowItem, let location = userLocation.location else {
            return
        }
    }
    
    func mapViewDidStopLocatingUser(_ mapView: MKMapView) {
        guard let item = item as? MapRowItem, let location = mapView.userLocation.location else {
            return
        }
    }
    
        
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        
    }

    private var location: NSPoint? = nil
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        location = nil
       
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        location = event.locationInWindow
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        let previousItem = self.item
        super.set(item: item, animated: animated)
        
        
        guard let item = item as? MapRowItem else {
            return
        }

        mapView.appearance = theme.appearance
        
        focusVenue()
        
        if let previousItem = previousItem as? MapRowItem {
            mapView.removeAnnotation(previousItem.location)
        }
        
        mapView.addAnnotation(item.location)

    }
}




private final class Arguments {
    let context: AccountContext
    let setLocation:()->Void
    let openMap:()->Void
    init(context: AccountContext, setLocation:@escaping()->Void, openMap:@escaping()->Void) {
        self.context = context
        self.setLocation = setLocation
        self.openMap = openMap
    }
}

private struct State : Equatable {
    class Location : NSObject, MKAnnotation {
        var coordinate: CLLocationCoordinate2D
        var venue: MapVenue?
        init(coordinate: CLLocationCoordinate2D, venue: MapVenue?) {
            self.coordinate = coordinate
            self.venue = venue
        }
    }
    var address: String?
    var location: Location?
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_input = InputDataIdentifier("_id_enabled")

private let _id_map_enabled = InputDataIdentifier("_id_map_enabled")
private let _id_map_map = InputDataIdentifier("_id_map_enabled")


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    entries.append(.custom(sectionId: sectionId, index: 0, value: .none, identifier: _id_header, equatable: nil, comparable: nil, item: { initialSize, stableId in
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: arguments.context, sticker: LocalAnimatedSticker.fly_dollar, text: .initialize(string: "Display the location of your business on your account.", color: theme.colors.listGrayText, font: .normal(.text)))
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    entries.append(.input(sectionId: sectionId, index: 0, value: .string(state.address), error: nil, identifier: _id_input, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: "Enter Address", filter: { $0 }, limit: 256))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
  
    entries.append(.general(sectionId: sectionId, index: 0, value: .none, error: nil, identifier: _id_map_enabled, data: .init(name: "Set Location on Map", color: theme.colors.text, type: .switchable(state.location != nil), viewType: state.location != nil ? .firstItem : .singleItem, action: arguments.setLocation, autoswitch: false)))
    
    if let location = state.location {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_map_map, equatable: .init(state.location), comparable: nil, item: { initialSize, stableId in
            return MapRowItem(initialSize, height: 200, stableId: stableId, context: arguments.context, location: location, viewType: .lastItem, action: arguments.openMap)
        }))
    }
    
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

func BusinessLocationController(context: AccountContext) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State()
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let chatInteraction = ChatInteraction(chatLocation: .peer(context.peerId), context: context)
    
    chatInteraction.sendLocation = { location, venue in
        
        let signal = reverseGeocodeLocation(latitude: location.latitude, longitude: location.longitude) |> deliverOnMainQueue
        
        if stateValue.with({ $0.address == nil || $0.address!.isEmpty }) {
            _ = signal.startStandalone(next: { value in
                updateState { current in
                    var current = current
                    current.address = value?.fullAddress
                    return current
                }
            })
        }
        
        updateState { current in
            var current = current
            current.location = .init(coordinate: location, venue: venue)
            return current
        }
    }
    
    let arguments = Arguments(context: context, setLocation: {
        let value = stateValue.with { $0.location }
        
        if value != nil {
            updateState { current in
                var current = current
                current.location = nil
                return current
            }
        } else {
            showModal(with: LocationModalController(chatInteraction, destination: .business(value?.coordinate)), for: context.window)
        }
    }, openMap: {
        showModal(with: LocationModalController(chatInteraction, destination: .business(stateValue.with { $0.location?.coordinate })), for: context.window)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "Location", removeAfterDisappear: false, hasDone: false)
    
    controller.updateDatas = { datas in
        updateState { current in
            var current = current
            current.address = datas[_id_input]?.stringValue
            return current
        }
        return .none
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
    
}

#endif
