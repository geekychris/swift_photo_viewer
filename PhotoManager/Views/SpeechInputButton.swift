import SwiftUI
import Speech

struct SpeechInputButton: View {
    @Binding var text: String
    @State private var isRecording = false
    @State private var isAuthorized = false
    @State private var showingPermissionAlert = false
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var startingText = ""
    
    var body: some View {
        Button(action: toggleRecording) {
            Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle")
                .foregroundColor(isRecording ? .red : .blue)
                .font(.title2)
        }
        .buttonStyle(PlainButtonStyle())
        .help(isRecording ? "Stop recording" : "Start voice input")
        .onAppear {
            Task {
                isAuthorized = await requestSpeechAuthorization()
            }
        }
        .onChange(of: speechRecognizer.partialText) { _, newValue in
            // Show partial results in real-time (overwrite, don't append)
            if isRecording && !newValue.isEmpty {
                if startingText.isEmpty {
                    text = newValue
                } else if startingText.hasSuffix(" ") {
                    text = startingText + newValue
                } else {
                    text = startingText + " " + newValue
                }
            }
        }
        .onChange(of: speechRecognizer.finalText) { _, newValue in
            // Only append the final result when recording stops
            if !newValue.isEmpty {
                if startingText.isEmpty {
                    text = newValue
                } else if startingText.hasSuffix(" ") {
                    text = startingText + newValue
                } else {
                    text = startingText + " " + newValue
                }
            }
        }
        .alert("Microphone Access Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable microphone access in System Settings to use voice input.")
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            speechRecognizer.stopRecording()
            isRecording = false
        } else {
            if isAuthorized {
                startingText = text
                speechRecognizer.startRecording()
                isRecording = true
            } else {
                showingPermissionAlert = true
            }
        }
    }
    
    private func requestSpeechAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

// Speech recognizer using the Speech framework
class SpeechRecognizer: ObservableObject {
    @Published var partialText = ""
    @Published var finalText = ""
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    func startRecording() {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        partialText = ""
        finalText = ""
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Get audio input
        let inputNode = audioEngine.inputNode
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcribedText = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    if result.isFinal {
                        self.finalText = transcribedText
                        self.partialText = ""
                    } else {
                        self.partialText = transcribedText
                    }
                }
            }
            
            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        // Start audio recording
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start: \\(error)")
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
    }
}
