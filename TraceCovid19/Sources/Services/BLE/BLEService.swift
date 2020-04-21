//
//  BLEService.swift
//  TraceCovid19
//
//  Created by yosawa on 2020/04/10.
//

import UIKit
import CoreBluetooth

enum Service: String, CustomStringConvertible {
    // TODO currently from https://github.com/TCNCoalition/TCN
    case trace = "0000C019-0000-1000-8000-00805F9B34FB"
    func toCBUUID() -> CBUUID {
        return CBUUID(string: self.rawValue)
    }
    var description: String {
        switch self {
        case .trace:
            return "trace"
        }
    }
}

enum Characteristic: String, CustomStringConvertible {
    // TODO currently from https://github.com/TCNCoalition/TCN
    case contact = "D61F4F27-3D6B-4B04-9E46-C9D2EA617F62"

    func toService() -> Service {
        switch self {
        case .contact:
            return .trace
        }
    }
    func toCBUUID() -> CBUUID {
        return CBUUID(string: self.rawValue)
    }
    var description: String {
        switch self {
        case .contact:
            return "contact"
        }
    }
    static func fromCBCharacteristic(_ c: CBCharacteristic) -> Characteristic? {
        return Characteristic(rawValue: c.uuid.uuidString)
    }
}

enum Command {
    case Read(from: Characteristic)
    case Write(to: Characteristic, value: (Peripheral) -> (Data))
    case ReadRSSI
    case Cancel(callback: (Peripheral) -> Void)
}

typealias CharacteristicDidUpdateValue = (Peripheral, Characteristic, Data?, Error?) -> Void
typealias DidReadRSSI = (Peripheral, NSNumber, Error?) -> Void

// BLEService holds all the business logic related to BLE.
final class BLEService {
    private var peripheralController: PeripheralManager!
    private var centralController: CentralManager!
    private var coreData: CoreDataService!
    private var tempId: TempIdService!
    private var timerForScanning: Timer?
    private var traceData: [UUID: TraceDataRecord]!

    private let queue: DispatchQueue!
    var bluetoothDidUpdateStateCallback: ((CBManagerState) -> Void)?

    init(
        queue: DispatchQueue,
        peripheralController: PeripheralManager,
        centralController: CentralManager,
        coreData: CoreDataService,
        tempId: TempIdService
    ) {
        self.queue = queue
        self.peripheralController = peripheralController
        self.centralController = centralController
        self.coreData = coreData
        self.tempId = tempId
        self.traceData = [:]
        centralController.centralDidUpdateStateCallback = centralDidUpdateStateCallback

        self.peripheralController
            .onRead { [unowned self] _, ch in
                switch ch {
                case .contact:
                    return nil
                }
            }
            .onWrite { [unowned self] _, ch, _ in
                switch ch {
                case .contact:
//                    if let userId = UserId(data: data) {
//                        log("Written Successful by \(userId)")
//                        self.peerIds.append(userId)
//                        self.peerIds.save(to: .peerIds)
//                        self.debugNotify(identifier: "Written", message: "Written Successful by \(userId)")
//                        return true
//                    }
//                    log("data to UserId parse failed: \(data)")
                    return false
                }
            }

        // Commands and callbacks should happen in this order
        _ = self.centralController
            .appendCommand(
                command: .ReadRSSI
            )
            .didReadRSSI { [unowned self] peripheral, RSSI, error in
                print("peripheral=\(peripheral), RSSI=\(RSSI), error=\(String(describing: error))")

                guard error == nil else {
                    self.centralController.disconnect(peripheral)
                    return
                }
                var record = self.traceData[peripheral.id] ?? TraceDataRecord()
                record.rssi = RSSI.doubleValue
                self.traceData[peripheral.id] = record
            }
            .appendCommand(
                command: .Write(to: .contact, value: { [unowned self] peripheral in
                    let record = self.traceData[peripheral.id] ?? TraceDataRecord()
                    let tempId = self.tempId.currentTempId ?? self.tempId.latestTempId!

                    // TODO txPower
                    return V2Central.shared.prepareWriteRequestData(tempId: tempId.tempId, rssi: record.rssi ?? 0, txPower: nil)
                        ?? Data()
                })
            )
            .appendCommand(
                command: .Read(from: .contact)
            )
            .didUpdateValue { [unowned self] peripheral, ch, data, error in
                print("[CC] didUpdateValueFor peripheral=\(peripheral), ch=\(ch), data=\(String(describing: data)), error=\(String(describing: error))")

                guard error == nil && data != nil else {
                    self.centralController.disconnect(peripheral)
                    return
                }

                guard let record = V2Central.shared.processReadRequestDataReceived(scannedPeriData: self.traceData[peripheral.id], characteristicValue: data!) else {
                    let s = String(data: data!, encoding: .utf8)
                    print("parse data failed, data=\(String(describing: s))")
                    self.centralController.disconnect(peripheral)
                    return
                }

                self.traceData[peripheral.id] = record
                print("[CC] save: \(record.tempId ?? "nil")")
                self.coreData.save(traceDataRecord: record)
            }
            .appendCommand(
                command: .Cancel(callback: { [unowned self] peripheral in
                    self.centralController.disconnect(peripheral)
                })
            )
    }

    func turnOn() {
        peripheralController.turnOn()
        centralController.turnOn()
    }

    func turnOff() {
        peripheralController.turnOff()
        centralController.turnOff()
    }

    func getCentralStateText() -> String {
        return centralController.getState().toString
    }

    func getPeripheralStateText() -> String {
        return peripheralController.getState().toString
    }

    func isBluetoothAuthorized() -> Bool {
        if #available(iOS 13.1, *) {
            return CBManager.authorization == .allowedAlways
        } else {
            // todo: consider iOS 13.0, which has different behavior from 13.1 onwards
            return CBPeripheralManager.authorizationStatus() == .authorized
        }
    }

    func isBluetoothOn() -> Bool {
        switch centralController.getState() {
        case .poweredOff:
            print("[BLEService] Bluetooth is off")
        case .resetting:
            print("[BLEService] Resetting State")
        case .unauthorized:
            print("[BLEService] Unauth State")
        case .unknown:
            print("[BLEService] Unknown State")
        case .unsupported:
            centralController.turnOn()
            print("[BLEService] Unsupported State")
        default:
            print("[BLEService] Bluetooth is on")
        }
        return centralController.getState() == CBManagerState.poweredOn
    }

    func centralDidUpdateStateCallback(_ state: CBManagerState) {
        bluetoothDidUpdateStateCallback?(state)
        switch state {
        case .poweredOn:
            DispatchQueue.main.async { [unowned self] in
                self.timerForScanning = Timer.scheduledTimer(withTimeInterval: TimeInterval(BluetraceConfig.CentralScanInterval), repeats: true) { [weak self] _ in
                    print("[CC] Restarting a scan")
                    self?.coreData.saveTraceDataWithCurrentTime(for: .scanningStopped)
                    self?.coreData.saveTraceDataWithCurrentTime(for: .scanningStarted)

                    self?.centralController.restartScan()
                }
                self.timerForScanning?.fire()
            }
        default:
            timerForScanning?.invalidate()
        }
    }

    func toggleAdvertisement(_ state: Bool) {
        if state {
            peripheralController.turnOn()
        } else {
            peripheralController.turnOff()
        }
    }

    func toggleScanning(_ state: Bool) {
        if state {
            centralController.turnOn()
        } else {
            centralController.turnOff()
        }
    }
}
