//
//  SafariView.swift
//  Huiyijilu
//
//  In-app Safari browser using SFSafariViewController

import SwiftUI
import SafariServices

/// A SwiftUI wrapper around SFSafariViewController for in-app web browsing
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = .systemPurple
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
