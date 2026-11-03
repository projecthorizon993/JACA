import SwiftUI

/// App settings view — camera preferences and configuration.
struct SettingsView: View {
    @AppStorage("watermarkEnabled") private var watermarkEnabled = false
    @AppStorage("watermarkOpacity") private var watermarkOpacity: Double = 0.8
    @AppStorage("watermarkScale") private var watermarkScale: Double = 0.15
    @AppStorage("histogramEnabled") private var histogramEnabled = false
    @AppStorage("gridEnabled") private var gridEnabled = true
    @AppStorage("filmGrainEnabled") private var filmGrainEnabled = false

    var body: some View {
        NavigationView {
            Form {
                Section("Camera") {
                    Toggle("Show Histogram", isOn: $histogramEnabled)
                    Toggle("Show Grid Overlay", isOn: $gridEnabled)
                    Toggle("Film Grain", isOn: $filmGrainEnabled)
                }

                Section("Watermark") {
                    Toggle("Enable Watermark", isOn: $watermarkEnabled)
                    if watermarkEnabled {
                        Slider(value: $watermarkOpacity, in: 0...1, step: 0.1) {
                            Text("Opacity")
                        }
                        Slider(value: $watermarkScale, in: 0.05...0.5, step: 0.05) {
                            Text("Scale")
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
