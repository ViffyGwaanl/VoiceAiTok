// AIProviderListView.swift
// Multi-provider management — list, add, select, delete

import SwiftUI

struct AIProviderListView: View {
    @EnvironmentObject var providerService: AIProviderService
    @State private var showAddSheet = false

    var body: some View {
        List {
            // Built-in providers
            Section {
                ForEach(providerService.providers.filter(\.isBuiltIn)) { provider in
                    providerRow(provider)
                }
            } header: {
                Label("Built-in Providers", systemImage: "cube.box")
            }

            // Custom providers
            let custom = providerService.providers.filter { !$0.isBuiltIn }
            if !custom.isEmpty {
                Section {
                    ForEach(custom) { provider in
                        providerRow(provider)
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            providerService.deleteProvider(custom[i])
                        }
                    }
                } header: {
                    Label("Custom Providers", systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle("AI Providers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddProviderSheet()
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: AIProvider) -> some View {
        NavigationLink {
            AIProviderDetailView(providerID: provider.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider.type.icon)
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .fontWeight(providerService.selectedProviderID == provider.id ? .semibold : .regular)
                    Text(provider.modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if providerService.selectedProviderID == provider.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                if !provider.isEnabled {
                    Text("Disabled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                providerService.selectProvider(provider)
            } label: {
                Label("Set Default", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
    }
}

// MARK: - Add Provider Sheet

struct AddProviderSheet: View {
    @EnvironmentObject var providerService: AIProviderService
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var type: AIProviderType = .openaiCompatible

    var body: some View {
        NavigationStack {
            Form {
                TextField("Provider Name", text: $name)

                Picker("Type", selection: $type) {
                    ForEach(AIProviderType.allCases) { t in
                        Label(t.displayName, systemImage: t.icon).tag(t)
                    }
                }
            }
            .navigationTitle("Add Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let provider = providerService.addProvider(
                            name: name.isEmpty ? type.displayName : name,
                            type: type
                        )
                        providerService.selectProvider(provider)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
