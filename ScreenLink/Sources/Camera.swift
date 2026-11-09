import SwiftUI
import AVFoundation

final class Camera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "screenlink.camera")
    private var device: AVCaptureDevice?
    private var decoder: Decoder?
    private var lastUI = 0.0
    @Published var status = "Start camera, then aim the center box at the picture."
    @Published var received = ""
    @Published var checksum = ""
    @Published var fps = 0.0
    @Published var recording = false
    @Published var packet: Packet?
    private var previousTime: Double?
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { DispatchQueue.main.async { self.status = "Camera permission denied. Enable it in Settings." }; return }
            self.queue.async {
                guard self.session.inputs.isEmpty else { self.session.startRunning(); return }
                do {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .vga640x480
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        throw NSError(domain: "No rear camera", code: 1)
                    }
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard self.session.canAddInput(input) else { throw NSError(domain: "Camera input unavailable", code: 2) }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(output) else { throw NSError(domain: "Camera output unavailable", code: 3) }
                    self.session.addOutput(output)
                    try camera.lockForConfiguration()
                    if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                    }
                    camera.unlockForConfiguration()
                    self.device = camera
                    self.session.commitConfiguration()
                    self.session.startRunning()
                    DispatchQueue.main.async { self.status = "Camera ready. Wait for focus, then tap Listen." }
                } catch {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.status = error.localizedDescription }
                }
            }
        }
    }
    func listen(symbol: Double) {
        queue.async {
            do {
                guard let d = self.device else { return }
                try d.lockForConfiguration()
                if d.isExposureModeSupported(.locked) { d.exposureMode = .locked }
                if d.isFocusModeSupported(.locked) { d.focusMode = .locked }
                if d.isWhiteBalanceModeSupported(.locked) { d.whiteBalanceMode = .locked }
                d.unlockForConfiguration()
                let decoder = Decoder(symbol: symbol)
                decoder.onPacket = { [weak self] packet in
                    DispatchQueue.main.async {
                        self?.packet = packet
                        self?.received = String(decoding: packet.bytes, as: UTF8.self)
                        self?.checksum = packet.checksumOK ? "Checksum passed" : "Checksum failed: message contains errors"
                        self?.status = "Packet received. Listening for another…"
                    }
                }
                self.decoder = decoder
                DispatchQueue.main.async { self.packet = nil; self.received = ""; self.checksum = ""; self.recording = true; self.status = "Listening. Send from the computer now." }
            } catch { DispatchQueue.main.async { self.status = error.localizedDescription } }
        }
    }
    func stop() {
        queue.async {
            self.decoder = nil
            if let d = self.device, (try? d.lockForConfiguration()) != nil {
                if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
                if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
                if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
                d.unlockForConfiguration()
            }
            DispatchQueue.main.async { self.recording = false; self.status = "Stopped. Camera is adjusting automatically." }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
        guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(pixels, 0), h = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let strideBytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let data = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0, count = 0.0
        for y in stride(from: h*2/5, to: h*3/5, by: 3) {
            for x in stride(from: w*2/5, to: w*3/5, by: 3) { sum += Double(data[y*strideBytes+x]); count += 1 }
        }
        decoder?.append(LightSample(time: t, value: sum / max(count, 1) / 255))
        if t-lastUI > 0.5 {
            let rate = previousTime.map { 1 / max(t-$0, 0.001) } ?? 0
            lastUI = t
            DispatchQueue.main.async { self.fps = rate }
        }
        previousTime = t
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    }
    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        let layer = view.layer as! AVCaptureVideoPreviewLayer
        layer.session = session; layer.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ uiView: Preview, context: Context) {}
}
