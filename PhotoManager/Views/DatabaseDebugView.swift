import SwiftUI
import SQLite

struct DatabaseDebugView: SwiftUI.View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @State private var sqlQuery: String = "SELECT * FROM photo_files LIMIT 10"
    @State private var queryResults: [[String: String]] = []
    @State private var columnNames: [String] = []
    @State private var errorMessage: String?
    @State private var isExecuting = false
    
    var body: some SwiftUI.View {
        VStack(spacing: 0) {
            // SQL Input Area
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SQL Query")
                        .font(.headline)
                    Spacer()
                    Button("Execute") {
                        executeQuery()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExecuting || sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.top)
                
                TextEditor(text: $sqlQuery)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .padding(.horizontal)
                
                // Quick Query Buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        QuickQueryButton(title: "All Tables", query: "SELECT name FROM sqlite_master WHERE type='table'") {
                            sqlQuery = $0
                        }
                        QuickQueryButton(title: "Photo Count", query: "SELECT COUNT(*) as count FROM photo_files") {
                            sqlQuery = $0
                        }
                        QuickQueryButton(title: "Directories", query: "SELECT * FROM root_directories") {
                            sqlQuery = $0
                        }
                        QuickQueryButton(title: "Recent Photos", query: "SELECT id, file_name, created_at FROM photo_files ORDER BY created_at DESC LIMIT 20") {
                            sqlQuery = $0
                        }
                        QuickQueryButton(title: "Schema: Photos", query: "PRAGMA table_info(photo_files)") {
                            sqlQuery = $0
                        }
                        QuickQueryButton(title: "Duplicates", query: "SELECT file_hash, COUNT(*) as count FROM photo_files GROUP BY file_hash HAVING count > 1") {
                            sqlQuery = $0
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
            }
            
            Divider()
            
            // Results Area
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Results")
                        .font(.headline)
                    if !queryResults.isEmpty {
                        Text("(\(queryResults.count) rows)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !queryResults.isEmpty {
                        Button("Clear") {
                            clearResults()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                if let error = errorMessage {
                    // Error Display
                    ScrollView {
                        Text(error)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color.red.opacity(0.1))
                    .border(Color.red.opacity(0.3), width: 1)
                    .padding(.horizontal)
                } else if isExecuting {
                    // Loading Indicator
                    ProgressView("Executing query...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if queryResults.isEmpty {
                    // Empty State
                    VStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Execute a query to see results")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Results Table
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header Row
                            HStack(spacing: 0) {
                                ForEach(columnNames, id: \.self) { column in
                                    Text(column)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.bold)
                                        .padding(8)
                                        .frame(minWidth: 120, alignment: .leading)
                                        .background(Color.gray.opacity(0.2))
                                        .border(Color.gray.opacity(0.3), width: 0.5)
                                }
                            }
                            
                            // Data Rows
                            ForEach(Array(queryResults.enumerated()), id: \.offset) { index, row in
                                HStack(spacing: 0) {
                                    ForEach(columnNames, id: \.self) { column in
                                        Text(row[column] ?? "NULL")
                                            .font(.system(.caption, design: .monospaced))
                                            .padding(8)
                                            .frame(minWidth: 120, alignment: .leading)
                                            .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
                                            .border(Color.gray.opacity(0.2), width: 0.5)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Footer with tips
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Tip: Use read-only SELECT queries. Modification queries (INSERT, UPDATE, DELETE) will execute but use with caution.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    private func executeQuery() {
        isExecuting = true
        errorMessage = nil
        
        Task {
            do {
                let (columns, results) = try await databaseManager.executeRawSQL(sqlQuery)
                
                await MainActor.run {
                    self.columnNames = columns
                    self.queryResults = results
                    self.isExecuting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    self.queryResults = []
                    self.columnNames = []
                    self.isExecuting = false
                }
            }
        }
    }
    
    private func clearResults() {
        queryResults = []
        columnNames = []
        errorMessage = nil
    }
}

struct QuickQueryButton: SwiftUI.View {
    let title: String
    let query: String
    let action: (String) -> Void
    
    var body: some SwiftUI.View {
        Button(title) {
            action(query)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

#Preview {
    DatabaseDebugView()
        .environmentObject(DatabaseManager.shared)
}
