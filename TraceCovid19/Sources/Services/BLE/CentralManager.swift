// Copyright (c) 2020- Masakazu Ohtsuka / maaash.jp
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
// OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import CoreBluetooth

class CentralManager: NSObject {
    private var started: Bool = false
    private var centralManager: CBCentralManager!
    private let services: [Service]
    private var commands: [Command] = []

    private var peripherals: [UUID: Peripheral] = [:]
    private var androidIdentifiers: [Data] = []

    private var didUpdateValue: CharacteristicDidUpdateValue!
    private var didReadRSSI: DidReadRSSI!
    var centralDidUpdateStateCallback: ((CBManagerState) -> Void)?

    init(queue: DispatchQueue, services: [Service]) {
        self.services = services
        super.init()
        let options = [
            // CBCentralManagerOptionShowPowerAlertKey: 1,
            CBCentralManagerOptionRestoreIdentifierKey: "com.decurret.TraceCovid19JP"
        ] as [String: Any]
        centralManager = CBCentralManager(delegate: self, queue: queue, options: options)
    }

    func turnOn() {
        started = true
        startScanning()
    }

    func turnOff() {
        started = false
        stopScan()
    }

    func restartScan() {
        stopScan()
        peripherals.values.forEach { peripheral in
            disconnect(peripheral)
        }
        peripherals = [:]
        androidIdentifiers = []

        startScanning()
    }

    func getState() -> CBManagerState {
        return centralManager.state
    }

    private func startScanning() {
        guard centralManager.state == .poweredOn else { return }

        let options = [CBCentralManagerScanOptionAllowDuplicatesKey: false as NSNumber]
        let cbuuids = services.map { $0.toCBUUID() }
        centralManager.scanForPeripherals(withServices: cbuuids, options: options)
    }

    private func stopScan() {
        centralManager.stopScan()
    }

    func appendCommand(command: Command) -> CentralManager {
        self.commands.append(command)
        return self // for chaining
    }

    func didUpdateValue(_ callback :@escaping CharacteristicDidUpdateValue) -> CentralManager {
        didUpdateValue = callback
        return self
    }

    func didReadRSSI(_ callback: @escaping DidReadRSSI) -> CentralManager {
        didReadRSSI = callback
        return self
    }

    func disconnect(_ peripheral: Peripheral) {
        centralManager.cancelPeripheralConnection(peripheral.peripheral)
    }

    func addPeripheral(_ peripheral: CBPeripheral) {
        let p = Peripheral(peripheral: peripheral, services: services, commands: commands, didUpdateValue: didUpdateValue, didReadRSSI: didReadRSSI)
        peripherals[peripheral.identifier] = p
    }
}

extension CentralManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("state=\(central.state)")
        if central.state == .poweredOn && started {
            startScanning()
        }
        centralDidUpdateStateCallback?(central.state)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("peripheral=\(peripheral)")

        let p = peripherals[peripheral.identifier]
        if let p = p {
            p.discoverServices()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("peripheral=\(peripheral), error=\(String(describing: error))")
        peripherals.removeValue(forKey: peripheral.identifier)
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print("peripheral=\(peripheral.identifier.uuidString.prefix(8)), rssi=\(RSSI)")

        // Android
        // iphones will "mask" the peripheral's identifier for android devices, resulting in the same android device being discovered multiple times with different peripheral identifier. Hence android is using CBAdvertisementDataServiceDataKey data for identifying an android pheripheral
        if let manuData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            let androidIdentifierData = manuData.subdata(in: 2..<manuData.count)
            if androidIdentifiers.contains(androidIdentifierData) {
                print("[CC] Android Peripheral \(peripheral) has been discovered already in this window, will not attempt to connect to it again")
                return
            }
            androidIdentifiers.append(androidIdentifierData)
            addPeripheral(peripheral)
            central.connect(peripheral, options: nil)
//                scannedPeripherals.updateValue((peripheral, TraceDataRecord(rssi: RSSI.doubleValue, txPower: advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Double)), forKey: peripheral.identifier)
//                central.connect(peripheral)
            return
        }

//                scannedPeripherals.updateValue((peripheral, TraceDataRecord(rssi: RSSI.doubleValue, txPower: advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Double)), forKey: peripheral.identifier)

        print("[CC] CBAdvertisementDataManufacturerDataKey Data not found. Peripheral is likely not android")
        if peripherals[peripheral.identifier] != nil {
            print("[CC] iOS Peripheral \(peripheral) has been discovered already in this window, will not attempt to connect to it again")
            return
        }
        addPeripheral(peripheral)
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("peripheral=\(peripheral), error=\(String(describing: error))")
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        print("dict=\(dict)")

        // Hmm, no we want to reconnect to them and re-record the proximity event
//        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
//            peripherals.forEach { (peripheral) in
//                addPeripheral(peripheral)
//            }
//        }
    }
}
