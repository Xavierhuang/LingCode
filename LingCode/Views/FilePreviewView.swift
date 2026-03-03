//
//  FilePreviewView.swift
//  LingCode
//
//  Preview for image and PDF files in the main editor.
//

import SwiftUI
import AppKit
import PDFKit

struct FilePreviewView: View {
    let fileURL: URL

    var body: some View {
        Group {
            if fileURL.pathExtension.lowercased() == "pdf" {
                PDFPreviewRepresentable(url: fileURL)
            } else {
                ImagePreviewRepresentable(url: fileURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.primaryBackground)
    }
}

private struct ImagePreviewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageFrameStyle = .none
        if let image = NSImage(contentsOf: url) {
            imageView.image = image
        }
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image == nil, let image = NSImage(contentsOf: url) {
            nsView.image = image
        }
    }
}

private struct PDFPreviewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document == nil, let document = PDFDocument(url: url) {
            nsView.document = document
        }
    }
}
