// Prints the text visible in an image (macOS Vision OCR). Used by the CI UI smoke test.
import AppKit
import Vision

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: url) else { print("cannot read \(url.path)"); exit(1) }
var rect = CGRect(origin: .zero, size: image.size)
guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { exit(1) }
print("image \(cg.width)x\(cg.height)")
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
try VNImageRequestHandler(cgImage: cg).perform([request])
let lines = (request.results ?? []).map { o -> (CGFloat, CGFloat, String) in
    (1 - o.boundingBox.maxY, o.boundingBox.minX, o.topCandidates(1).first?.string ?? "")
}.sorted { ($0.0 * 50).rounded() == ($1.0 * 50).rounded() ? $0.1 < $1.1 : $0.0 < $1.0 }
for (y, x, text) in lines { print(String(format: "y=%.2f x=%.2f  ", y, x) + text) }
