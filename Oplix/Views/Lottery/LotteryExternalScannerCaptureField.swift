//
//  LotteryExternalScannerCaptureField.swift
//  Oplix
//

import SwiftUI
import UIKit

/// Always-focused text field for Bluetooth HID / keyboard-wedge barcode scanners.
/// Submits on Return/Enter (what most scanners send after the code).
struct LotteryExternalScannerCaptureField: UIViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool = true
    var onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.keyboardType = .asciiCapable
        field.returnKeyType = .done
        field.borderStyle = .roundedRect
        field.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        field.placeholder = "Waiting for scanner…"
        field.clearButtonMode = .whileEditing
        field.textContentType = nil
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isEnabled = isEnabled
        if isEnabled, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LotteryExternalScannerCaptureField
        weak var field: UITextField?

        init(_ parent: LotteryExternalScannerCaptureField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            let value = textField.text ?? ""
            if parent.text != value {
                parent.text = value
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            submit(textField)
            return false
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            // Some wedges append \n / \r without going through shouldReturn.
            if string.contains("\n") || string.contains("\r") {
                let cleaned = string
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                if let text = textField.text,
                   let swiftRange = Range(range, in: text) {
                    textField.text = text.replacingCharacters(in: swiftRange, with: cleaned)
                } else if !cleaned.isEmpty {
                    textField.text = (textField.text ?? "") + cleaned
                }
                parent.text = textField.text ?? ""
                submit(textField)
                return false
            }
            return true
        }

        private func submit(_ textField: UITextField) {
            let raw = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }
            parent.onSubmit(raw)
            textField.text = ""
            parent.text = ""
            DispatchQueue.main.async {
                textField.becomeFirstResponder()
            }
        }
    }
}
