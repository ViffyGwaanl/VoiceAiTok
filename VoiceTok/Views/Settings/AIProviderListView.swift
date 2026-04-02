// AIProviderListView.swift
// Multi-provider management — list, add, select, delete

import SwiftUI

struct AIProviderListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddSheet = false

    private var service: AIProviderService { appState.aiProviderService }

    var body: some View {
        List {
            // Built-in providers
            Section {
                ForEach(service.providers.filter(\.isBuiltIn)) { provider in
                    providerRow(provider)
                }
            } header: {
                Label("Built-in Providers", systemImage: "cube.box")
            }

            // Custom providers
            if service.providers.contains(where: { !$0.isBuiltIn }) {
                Section {
                    ForEach(service.providers.filter { !$0.isBuiltIn }) { provider in
                        providerRow(provider)
                    }
                    .onDelete { indexSet in
                        let custom = service.providers.filter { !$0.isBuiltIn }
                        for i in indexSet {
                            service.deleteProvider(custom[i])
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
            AddProviderSheet(service: service)
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: AIProvider) -> some View {
        NavigationLink {
            AIProviderDetailView(provider: provider)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider.type.icon)
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .fontWeight(service.selectedProviderID == provider.id ? .semibold : .regular)
                    Text(provider.modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if service.selectedProviderID == provider.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                if !provider.isEnabled {
                    Text("Disabled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                service.selectProvider(provider)
            } label: {
                Label("Set Default", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
    }
}

// MARK: - Add Provider Sheet

struct AddProviderSheet: View {
    let service: AIProviderService
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
                        let provider = service.addProvider(
                            name: name.isEmpty ? type.displayName : name,
                            type: type
                        )
                        service.selectProvider(provider)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
