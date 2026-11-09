# ScreenLink: screen-to-iPhone BFSK experiment

A Windows/Mac transmitter webpage and native iPhone receiver for the assignment. This is a single-region, low-rate teaching prototype inspired by HiLight, not a reproduction of its multi-region high-throughput system. Real hardware measurements have not been performed; no experimental results are supplied or implied.

## Run the transmitter

Open `transmitter.html` directly in a desktop browser on Windows or Mac. A static landscape is included; optionally select your own bright picture. Keep the browser visible. Set the message, alpha difference, and seconds per bit. The black overlay alternates between opacity 0 and the selected delta, darkening the picture without changing its underlying pixels.

## Install the iPhone app (requires a Mac with Xcode)

1. Open `ScreenLink/ScreenLink.xcodeproj` in Xcode.
2. Select the ScreenLink target. Under Signing & Capabilities, choose your Apple development team and change `org.example.ScreenLink` to a unique bundle identifier if needed.
3. Connect your iPhone, select it as the run destination, enable Developer Mode if requested, then Run. Allow camera access. Minimum supported iOS: 17.
4. Tap Start camera. Point the rear camera at the computer's picture. The entire central fifth of the camera image must lie inside the picture, preferably a bright region. The yellow box marks its center; it is an aiming guide, not its exact boundary.
5. Give autofocus/exposure a few seconds to settle. Choose the same seconds per bit as on the computer; begin with 0.50. Tap Listen to lock focus, exposure, and white balance.
6. On the computer, Send once. The decoded message appears on the phone without using the expected-message field. That field is for scoring only.
7. Save last packet once per send. For a completed transmission that never decodes, Save missed packet once instead. Stop before changing settings or repositioning, then let the camera adjust and Listen again.

The computer can still be Windows after the iPhone app is installed. Xcode is needed for building/installing the native receiver, not for transmitting.

## Experiment

Test delta alpha 0.1 and 0.5 at 20, 40, 80, and 120 cm. Repeat each condition using the same exact message and multiple trials. Test the four available durations: 1.0, 0.75, 0.5, and 0.25 seconds per bit. Record perceived flicker separately, along with display refresh rate, phone model, ambient light, and screen brightness. Increasing speed does not necessarily make flicker more visible; report your actual observation.

At symbol duration T, 0 uses 2/T Hz and 1 uses 3/T Hz. At T=0.5, these are 4 and 6 Hz, with a gross payload speed of 2 bits/s. At T=0.25, the frequencies are 8 and 12 Hz, with a gross payload speed of 4 bits/s. This fastest preset leaves less margin at 30 camera fps. Verify reliability on your hardware. These deliberately conservative presets use a requested 30-fps camera; they do not explore the highest possible hardware throughput or guarantee an imperceptible signal. Faster research would require higher camera frame rates and suitable display refresh rates, then new presets and validation.

Export results CSV from the phone. Saved rows persist across app restarts in local app preferences. Stop does not clear them and export does not reset them. There is no explicit row limit or export timer, but export after each set of trials as a backup. Deleting the app deletes its local results. Export in-memory results from older versions before installing this update. Alpha and distance are labels you select manually; the phone does not measure them.

Scoring compares expected UTF-8 bytes with the decoded bytes in order. Missing expected bits count as errors. A missed packet counts all expected payload bits as errors. Extra decoded bytes are not credited. Ensure the expected text exactly matches the transmitted text, including case, spaces, and punctuation. Do not save the same packet twice.

- `ber`: incorrect or missing expected payload bits / transmitted payload bits.
- `payload_correct_bps`: correct payload bits / scheduled payload duration.
- `packet_correct_bps`: correct payload bits / scheduled full packet duration, including 32 framing/checksum bits. Use this latter rate for a full-message communication measurement and state the convention in your report.
- Both rates exclude manual waiting between trials; elapsed duration is derived from the shared symbol setting. Download the transmitter timing log to check actual duration and frame gaps. If actual transmission duration materially differs from the schedule, calculate correct bits / actual duration instead and report the timing discrepancy.

Failed header/sync acquisition will not produce a packet. A plausible corrupted length can delay or prevent reception; score it as a missed packet after the known transmission finishes and restart Listen. Do not omit failed transmissions from your results. The XOR checksum detects many, but not all, corruptions; BER is determined from the reference bytes, not from the checksum.

## Protocol and limitations

MSB-first wire format: sync `1101001110001010`, one-byte payload length (1–128), UTF-8 payload, one-byte XOR of payload bytes. Each symbol resets phase and uses two or three square-wave cycles. The phone samples mean camera luminance in the central fifth of the image. Timestamp-based sinusoidal correlation distinguishes the frequencies, and the preamble recovers symbol timing by choosing the offset with the strongest frequency separation among matching sync patterns. Decoding happens continuously on the camera queue.

There is no error correction, perspective correction, rolling-shutter decoding, adaptive timing recovery, or automatic trial accounting. Keep the devices steady; screen/camera clock drift, long messages, autofocus/exposure mistakes, low brightness, room-light interference, and dropped display/camera frames can cause errors. Try short words first. Display updates use browser animation frames, which are not a precision hardware clock. Do not claim a successful physical link until it has been tested with your actual screen and phone.

The app requests 30 fps when supported and shows an approximate observed instantaneous camera rate. A locked auto-exposure can still be too long for fast modulation; use a brighter screen/room or slower bit duration. Keep the phone and screen brightness settings consistent between comparisons.

## Verification

Build without signing:

```
xcodebuild -project ScreenLink/ScreenLink.xcodeproj -scheme ScreenLink -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/screenlink-build CODE_SIGNING_ALLOWED=NO build
```

Synthetic signal tests (macOS Swift):

```
swiftc -module-cache-path /tmp/screenlink-swift-cache ScreenLink/Sources/Decoder.swift tests/main.swift -o /tmp/screenlink-decoder-tests
/tmp/screenlink-decoder-tests
```

Synthetic tests exercise decoding at all four symbol durations, different start offsets, a corrupted payload, static-light rejection, and lowercase `hi` with simulated 60 Hz display updates and camera exposure. They do not substitute for an optical hardware test.

Reference: https://www.cs.columbia.edu/~xia/publication/mobisys15-hilight/mobisys15-hilight.pdf
