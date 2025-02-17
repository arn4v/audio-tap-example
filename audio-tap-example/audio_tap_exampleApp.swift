import SwiftUI
import AudioToolbox
import AVFoundation

class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    private var audioBuffer: [Float] = []
    private var audioFile: AVAudioFile?
    private var tapId: AUAudioObjectID = 0
    private var aggregateId: AudioObjectID = 0
    private var deviceProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "ProcessTapRecorder", qos: .userInitiated)
    
    func startRecording() {
        audioBuffer = []
        setupAudioTap()
        isRecording = true
    }
    
    func stopRecording() {
        if let procID = deviceProcID {
            AudioDeviceStop(aggregateId, procID)
        }
        isRecording = false
    }
    
    func saveRecording(to url: URL) -> Bool {
        guard !audioBuffer.isEmpty else { return false }
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            
            let bufferFormat = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioBuffer.count))!
            bufferFormat.floatChannelData?[0].assign(from: audioBuffer, count: audioBuffer.count)
            bufferFormat.frameLength = AVAudioFrameCount(audioBuffer.count)
            
            try audioFile?.write(from: bufferFormat)
            return true
        } catch {
            print("Error saving audio file: \(error)")
            return false
        }
    }
    
    private func setupAudioTap() {
        let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapId)
        
        guard err == noErr else {
            print("Process tap creation failed with error \(err)")
            return
        }
        
        // Get system output device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var systemOutputId: AudioDeviceID = 0
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &deviceSize, &systemOutputId)
        guard err == noErr else {
            print("Error getting system output device: \(err)")
            return
        }
        
        // Get output device UID
        address.mSelector = kAudioDevicePropertyDeviceUID
        var propertySize: UInt32 = 0
        
        // First get the size needed for the UID
        err = AudioObjectGetPropertyDataSize(systemOutputId, &address, 0, nil, &propertySize)
        guard err == noErr else {
            print("Error getting UID property size: \(err)")
            return
        }
        
        var outputUID: CFString = "" as CFString
        err = AudioObjectGetPropertyData(systemOutputId, &address, 0, nil, &propertySize, &outputUID)
        guard err == noErr else {
            print("Error getting device UID: \(err)")
            return
        }
        
        // Create aggregate device
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tap-1234",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]
        
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateId)
        
        let ioBlock: AudioDeviceIOBlock = { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self = self else { return }
            
            let inputDataPtr = inInputData.pointee
            let buffer = inputDataPtr.mBuffers
            
            // Get audio data as float array
            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let audioData = buffer.mData?.assumingMemoryBound(to: Float.self)
            
            if let audioData = audioData {
                let audioArray = Array(UnsafeBufferPointer(start: audioData, count: frameCount))
                self.audioBuffer.append(contentsOf: audioArray)
            }
        }
        
        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateId, queue, ioBlock)
        
        if let procID = deviceProcID {
            err = AudioDeviceStart(aggregateId, procID)
        }
    }
}

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var showingSavePanel = false
    @State private var showingSaveAlert = false
    @State private var savedURL: URL?
    
    var body: some View {
        VStack(spacing: 20) {
            Text(audioRecorder.isRecording ? "Recording..." : "Ready")
                .font(.title)
                .foregroundColor(audioRecorder.isRecording ? .red : .primary)
            
            Button(action: {
                if audioRecorder.isRecording {
                    audioRecorder.stopRecording()
                    showingSavePanel = true
                } else {
                    audioRecorder.startRecording()
                }
            }) {
                Text(audioRecorder.isRecording ? "Stop Recording" : "Start Recording")
                    .padding()
                    .background(audioRecorder.isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .fileExporter(
            isPresented: $showingSavePanel,
            document: AudioDocument(initialData: Data()),
            contentType: .wav,
            defaultFilename: "recording_\(Date().formatted(.dateTime.year().month().day().hour().minute().second()))"
        ) { result in
            switch result {
            case .success(let url):
                if audioRecorder.saveRecording(to: url) {
                    savedURL = url
                    showingSaveAlert = true
                }
            case .failure(let error):
                print("Error saving file: \(error.localizedDescription)")
            }
        }
        .alert("Recording Saved", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let url = savedURL {
                Text("Recording saved to:\n\(url.path)")
            }
        }
    }
}

// Required for fileExporter
struct AudioDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.wav]
    
    var initialData: Data
    
    init(initialData: Data = Data()) {
        self.initialData = initialData
    }
    
    init(configuration: ReadConfiguration) throws {
        initialData = configuration.file.regularFileContents ?? Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: initialData)
    }
}

@main
struct AudioRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
