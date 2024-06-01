//
//  audio_tap_exampleApp.swift
//  audio-tap-example
//
//  Created by Devin Gould on 6/1/24.
//

import SwiftUI
import AudioToolbox

@main
struct audio_tap_exampleApp: App {
    var tapId: AUAudioObjectID
    var aggregateId: AudioObjectID
    private var deviceProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "ProcessTapRecorder", qos: .userInitiated)

    init() {
        tapId=0
        aggregateId=0
        let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        var tapID: AUAudioObjectID = 0
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard err == noErr else {
            print("Process tap creation failed with error \(err)")
            return
        }

        print("Created process tap #\(tapID)")

        tapId = tapID
        
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0

        err = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)

        guard err == noErr else {
            print("Error reading data size for \(address): \(err)")
            return
        }

        var systemOutputId: AudioDeviceID = 0
        err = withUnsafeMutablePointer(to: &systemOutputId) { ptr in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, ptr)
        }

        guard err == noErr else {
            print("Error reading data for \(address): \(err)")
            return
        }
        
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

        dataSize = 0

        err = AudioObjectGetPropertyDataSize(systemOutputId, &address, 0, nil, &dataSize)

        guard err == noErr else {
            print("Error reading data size for \(address): \(err)")
            return
        }

        var outputUID: CFString = "" as CFString
        err = withUnsafeMutablePointer(to: &outputUID) { ptr in
            AudioObjectGetPropertyData(systemOutputId, &address, 0, nil, &dataSize, ptr)
        }

        guard err == noErr else {
            print("Error reading data for \(address): \(err)")
            return
        }


        let aggregateUID = UUID().uuidString

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tap-1234",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

//        self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()
        self.aggregateId = 0
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateId)
        guard err == noErr else {
            print("Failed to create aggregate device: \(err)")
            return
        }

        print("Created aggregate device #\(self.aggregateId)")
        
        let ioBlock: AudioDeviceIOBlock = { inNow, inInputData, inInputTime, outOutputData, inOutputTime in
                print("The value is \(inInputData.pointee.mNumberBuffers)")

        }
        
        
        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateId, queue, ioBlock)
        guard err == noErr else {
            print("Failed to create device I/O proc: \(err)")
            return
        }

        print("Run tap!")

        err = AudioDeviceStart(aggregateId, deviceProcID)
        guard err == noErr else { 
            print("Failed to start audio device: \(err)")
            return;
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
