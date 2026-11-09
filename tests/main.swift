import Foundation
func bits(_ value: UInt8) -> [Int] { (0..<8).map { Int((value >> (7-$0)) & 1) } }
func simulate(symbol: Double, offset: Double, corrupt: Bool = false, message: String = "Hello", realistic: Bool = false) {
    let bytes = Array(message.utf8)
    var payload = bytes.flatMap(bits)
    if corrupt { payload[9] ^= 1 }
    let wire = Decoder.sync + bits(UInt8(bytes.count)) + payload + bits(bytes.reduce(0, ^))
    let decoder = Decoder(symbol: symbol)
    var received: [Packet] = []
    decoder.onPacket = { received.append($0) }
    let origin = 12000.0, start = origin + offset
    let end = offset + Double(wire.count)*symbol + 1
    for n in 0..<Int(end*30) {
        let t = origin + Double(n)/30
        var value = 0.0
        // Model 60 Hz display sample-and-hold and a 1/60 s exposure.
        let integrationCount = realistic ? 12 : 1
        for sub in 0..<integrationCount {
        let cameraTime = t - (realistic ? Double(sub) / 720 : 0)
        let opticalTime = realistic ? floor(cameraTime * 60) / 60 : cameraTime
        let elapsed = opticalTime-start
        let index = Int(floor(elapsed/symbol))
        var level = 0.7
        if index >= 0 && index < wire.count {
            let cycles = wire[index] == 0 ? 2.0 : 3.0
            level -= sin(2 * .pi * cycles * elapsed/symbol) >= 0 ? 0.07 : 0
        }
        value += level / Double(integrationCount)
        }
        value += 0.001*sin(Double(n)*1.789)
        decoder.append(LightSample(time:t, value:value))
    }
    precondition(received.count == 1, "Missing/extra packet T=\(symbol), offset=\(offset): \(received.count)")
    precondition(received[0].checksumOK != corrupt, "Checksum mismatch")
    if !corrupt { precondition(received[0].bytes == bytes, "Payload mismatch") }
}
for symbol in [1.0, 0.75, 0.5, 0.25] {
    for offset in [0.37, 1.013] { simulate(symbol:symbol, offset:offset) }
}
simulate(symbol:0.5, offset:0.37, corrupt:true)
for symbol in [1.0, 0.75, 0.5, 0.25] {
    for offset in [0.37, 1.013] { simulate(symbol: symbol, offset: offset, message: "hi", realistic: true) }
}
let quiet = Decoder(symbol:0.5)
quiet.onPacket = { _ in fatalError("Decoded static light as packet") }
for n in 0..<1200 { quiet.append(LightSample(time:Double(n)/30, value:0.5)) }
print("Passed: 16 message/timing cases (including display refresh and camera exposure), corrupted payload checksum, static-light rejection.")
