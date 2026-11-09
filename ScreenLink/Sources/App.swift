import SwiftUI

@main struct ScreenLinkApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
struct ContentView: View {
    @StateObject private var camera = Camera()
    @State private var symbol = 0.5
    @State private var delta = "0.1"
    @State private var distance = "20"
    @State private var expected = "Hello"
    @AppStorage("screenlink.resultsCSV") private var rows = "distance_cm,delta_alpha,symbol_seconds,expected_bits,correct_bits,ber,payload_correct_bps,packet_correct_bps,checksum_ok\n"
    @State private var saved = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ScreenLink Receiver").font(.system(size: 24, weight: .semibold))
                CameraPreview(session: camera.session)
                    .frame(height: 260)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay { Rectangle().stroke(.yellow, lineWidth: 2).frame(width: 44, height: 44) }
                Text(camera.status)
                Text(String(format: "Camera: %.1f fps • 0: %.1f Hz • 1: %.1f Hz", camera.fps, 2/symbol, 3/symbol)).font(.caption)
                Picker("Seconds per bit", selection: $symbol) {
                    ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { Text(String(format: "%.3g s / bit", $0)).tag($0) }
                }.disabled(camera.recording)
                HStack {
                    Picker("Δα", selection: $delta) { Text("Δα 0.1").tag("0.1"); Text("Δα 0.5").tag("0.5") }
                    Picker("Distance", selection: $distance) {
                        ForEach(["20","40","80","120"], id: \.self) { Text("\($0) cm").tag($0) }
                    }
                }.disabled(camera.recording)
                TextField("Expected message (for scoring only)", text: $expected)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .disabled(camera.recording)
                HStack {
                    Button("Start camera") { camera.start() }
                    Button("Listen") { camera.listen(symbol: symbol) }.disabled(camera.recording)
                    Button("Stop") { camera.stop() }.disabled(!camera.recording)
                }.buttonStyle(.bordered)
                Text("Received: \(camera.received)").font(.headline).textSelection(.enabled)
                Text(camera.checksum).font(.caption)
                Text("The expected message is used only for scoring, never to decode the signal.").font(.caption)
                HStack {
                    Button("Save last packet") { save(missing: false) }.disabled(camera.packet == nil)
                    Button("Save missed packet") { save(missing: true) }
                }.buttonStyle(.bordered)
                Text(saved).font(.caption)
                ShareLink("Export results CSV", item: csvURL())
                Text("Aim the yellow center box entirely inside the picture. Start at 0.50 seconds per bit on both devices. Stop before changing settings. Save one row per transmitted packet, including missed packets.").font(.footnote)
            }.padding(24)
        }
        .background(Color(red: 1, green: 240.0/255, blue: 245.0/255).ignoresSafeArea())
        .foregroundStyle(Color(red: 34.0/255, green: 34.0/255, blue: 34.0/255))
        .tint(Color(red: 143.0/255, green: 63.0/255, blue: 94.0/255))
        .preferredColorScheme(.light)
    }
    func csvURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("screenlink-results.csv")
        try? rows.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func save(missing: Bool) {
        let reference = Array(expected.utf8)
        guard !reference.isEmpty else { saved = "Enter the exact transmitted message first."; return }
        let packet = missing ? nil : camera.packet
        let actual = packet?.bytes ?? []
        var errors = 0
        for (i, value) in reference.enumerated() {
            if i < actual.count { errors += (value ^ actual[i]).nonzeroBitCount }
            else { errors += 8 }
        }
        let total = reference.count*8, correct = total-errors
        let ber = Double(errors)/Double(total)
        let payloadRate = Double(correct)/(Double(total)*symbol)
        // Include framing overhead in the second rate. A missed packet scores zero.
        let fullTime = Double(32+total)*symbol
        let rate = Double(correct)/fullTime
        rows += "\(distance),\(delta),\(symbol),\(total),\(correct),\(ber),\(payloadRate),\(rate),\(packet?.checksumOK ?? false)\n"
        saved = String(format: "Saved: BER %.2f%% • %.2f correct payload bits/s (%.2f including framing)", ber*100, payloadRate, rate)
        _ = csvURL()
    }
}
