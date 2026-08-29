#!/usr/bin/env swift

import Foundation
import ImageIO
import Vision

let imagePaths = Array(CommandLine.arguments.dropFirst())
guard !imagePaths.isEmpty else {
    fputs("No image paths were supplied.\n", stderr)
    exit(64)
}

for (index, imagePath) in imagePaths.enumerated() {
    let output: String
    if let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL, nil),
       let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            output = text
        } catch {
            output = "OCR_ERROR"
        }
    } else {
        output = "IMAGE_READ_ERROR"
    }
    print("\(index)\t\(output)")
}
