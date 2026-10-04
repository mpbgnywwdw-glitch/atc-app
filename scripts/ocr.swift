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
struct Line { let y: Double; let x: Double; let text: String }
var lines: [Line] = []
for o in request.results ?? [] {
    let box = o.boundingBox
    let text = o.topCandidates(1).first?.string ?? ""
    lines.append(Line(y: Double(1 - box.maxY), x: Double(box.minX), text: text))
}
lines.sort { a, b in
    let ya = (a.y * 50).rounded(), yb = (b.y * 50).rounded()
    return ya == yb ? a.x < b.x : a.y < b.y
}
for l in lines { print(String(format: "y=%.2f x=%.2f  ", l.y, l.x) + l.text) }
