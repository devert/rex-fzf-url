// capture.swift: record one window with ScreenCaptureKit, for record.sh.
//
//   capture WINDOW_ID FPS > frames.raw
//
// Writes the window as raw BGRA frames to stdout, FPS frames each second,
// at the full pixel size of the screen. The colors are sRGB, the corners
// outside the window are transparent, and the mouse pointer is hidden.
// When the window does not change, the last frame repeats.
//
// macOS puts a screen sharing badge over the window buttons of a window that
// a program records on its own. So the stream records the display, cut to
// the window rectangle. A display has no transparent corners, so one window
// screenshot before the stream gives the shape of the window. Each frame
// then gets the pixels at the edge of that shape from the screenshot, and
// the badge of the screenshot goes away before the stream starts.
//
// Prints "size WIDTHxHEIGHT" to stderr when the capture starts, and "ready"
// when it writes the first frame. Stops on SIGINT or SIGTERM.
//
// The ffmpeg avfoundation input is not used, because it makes the colors
// darker than they are on the screen.
import AppKit
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("capture: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// ScreenCaptureKit needs a connection to the window server.
_ = NSApplication.shared

let args = CommandLine.arguments
guard args.count == 3, let windowID = UInt32(args[1]), let fps = Int(args[2]), fps > 0 else {
    fail("usage: capture WINDOW_ID FPS")
}

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    let width: Int
    let height: Int
    // The window screenshot, and the byte offsets of its pixels that are not
    // fully opaque: the corners and the edge of the window.
    let edge: [UInt8]
    let edgeOffsets: [Int]
    private let lock = NSLock()
    private var latest: Data?

    init(width: Int, height: Int, edge: [UInt8]) {
        self.width = width
        self.height = height
        self.edge = edge
        self.edgeOffsets = stride(from: 0, to: edge.count, by: 4).filter { edge[$0 + 3] < 255 }
    }

    // Keep a copy of each complete frame. The timer writes the newest copy.
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let info = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = info.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let pixels = buffer.imageBuffer else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard CVPixelBufferGetWidth(pixels) == width, CVPixelBufferGetHeight(pixels) == height,
              let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        let row = width * 4
        var frame = Data(count: row * height)
        frame.withUnsafeMutableBytes { out in
            for y in 0..<height {
                memcpy(out.baseAddress! + y * row, base + y * stride, row)
            }
            let bytes = out.bindMemory(to: UInt8.self)
            for i in edgeOffsets {
                bytes[i] = edge[i]
                bytes[i + 1] = edge[i + 1]
                bytes[i + 2] = edge[i + 2]
                bytes[i + 3] = edge[i + 3]
            }
        }
        lock.lock()
        latest = frame
        lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fail("the capture stopped: \(error.localizedDescription)")
    }

    func newest() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}

var stream: SCStream?
var recorder: Recorder?
var timer: DispatchSourceTimer?
var signals: [DispatchSourceSignal] = []
let writer = DispatchQueue(label: "capture.writer")

for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        // The timer writes on the writer queue, so this waits until the
        // frame that it writes now is complete. ffmpeg then gets no partial
        // frame at the end.
        writer.sync { timer?.cancel() }
        stream?.stopCapture { _ in exit(0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
    }
    source.resume()
    signals.append(source)
}
// ffmpeg closes the pipe when it stops. Exit then, without an error.
signal(SIGPIPE, SIG_IGN)

// Take one screenshot of the window alone, as BGRA with straight alpha.
func windowImage(_ window: SCWindow, width: Int, height: Int) async throws -> [UInt8] {
    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.colorSpaceName = CGColorSpace.sRGB
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    config.shouldBeOpaque = false
    let image = try await SCScreenshotManager.captureImage(
        contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
    var data = [UInt8](repeating: 0, count: width * height * 4)
    data.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    for i in stride(from: 0, to: data.count, by: 4) {
        let a = Int(data[i + 3])
        guard a > 0, a < 255 else { continue }
        for c in 0..<3 {
            data[i + c] = UInt8(min(255, (Int(data[i + c]) * 255 + a / 2) / a))
        }
    }
    return data
}

Task {
    let content: SCShareableContent
    do {
        content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    } catch {
        fail("no permission to record the screen: \(error.localizedDescription)")
    }
    guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
        fail("window \(windowID) is not on the screen")
    }
    let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
    guard let display = content.displays.first(where: { $0.frame.contains(center) }) else {
        fail("no display shows window \(windowID)")
    }
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let scale = CGFloat(filter.pointPixelScale)
    let source = window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    let width = Int((source.width * scale).rounded())
    let height = Int((source.height * scale).rounded())

    let edge: [UInt8]
    do {
        edge = try await windowImage(window, width: width, height: height)
    } catch {
        fail("no permission to record the screen: \(error.localizedDescription)")
    }
    // Wait until the screen sharing badge of the screenshot is gone.
    try? await Task.sleep(nanoseconds: 2_000_000_000)

    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.sourceRect = source
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.colorSpaceName = CGColorSpace.sRGB
    config.showsCursor = false
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    config.queueDepth = 8

    let rec = Recorder(width: width, height: height, edge: edge)
    let s = SCStream(filter: filter, configuration: config, delegate: rec)
    do {
        try s.addStreamOutput(rec, type: .screen,
                              sampleHandlerQueue: DispatchQueue(label: "capture.frames"))
        try await s.startCapture()
    } catch {
        fail("the capture did not start: \(error.localizedDescription)")
    }
    stream = s
    recorder = rec
    FileHandle.standardError.write("size \(width)x\(height)\n".data(using: .utf8)!)

    // Write one frame each 1/fps seconds, so the video has a constant frame
    // rate. Wait for the first frame before the timer starts.
    let out = FileHandle.standardOutput
    var ready = false
    let t = DispatchSource.makeTimerSource(queue: writer)
    t.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / fps), leeway: .milliseconds(1))
    t.setEventHandler {
        guard let frame = rec.newest() else { return }
        if !ready {
            ready = true
            FileHandle.standardError.write("ready\n".data(using: .utf8)!)
        }
        do {
            try out.write(contentsOf: frame)
        } catch {
            exit(0)
        }
    }
    timer = t
    t.resume()
}

dispatchMain()
