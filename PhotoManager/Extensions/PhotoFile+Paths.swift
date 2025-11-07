import Foundation

extension PhotoFile {
    /// Returns the ABSOLUTE full path to the file, including filename
    /// Never returns a relative path - throws error if root directory not found
    func getAbsoluteFullPath(rootDirectories: [RootDirectory]) -> String? {
        guard let rootDir = rootDirectories.first(where: { $0.id == self.rootDirectoryId }) else {
            print("❌ ERROR: No root directory found for rootDirectoryId: \(self.rootDirectoryId)")
            print("   Available roots: \(rootDirectories.map { "ID \($0.id): \($0.path)" }.joined(separator: ", "))")
            print("   File: \(self.fileName)")
            return nil
        }
        
        let fullPath = (rootDir.path as NSString).appendingPathComponent(self.relativePath)
        
        // Verify it's an absolute path
        guard fullPath.hasPrefix("/") else {
            print("❌ ERROR: Generated path is not absolute: \(fullPath)")
            return nil
        }
        
        return fullPath
    }
    
    /// Returns the ABSOLUTE directory path (without filename)
    /// Never returns a relative path - throws error if root directory not found
    func getAbsoluteDirectoryPath(rootDirectories: [RootDirectory]) -> String? {
        guard let rootDir = rootDirectories.first(where: { $0.id == self.rootDirectoryId }) else {
            print("❌ ERROR: No root directory found for rootDirectoryId: \(self.rootDirectoryId)")
            print("   Available roots: \(rootDirectories.map { "ID \($0.id): \($0.path)" }.joined(separator: ", "))")
            return nil
        }
        
        let directoryPath = (self.relativePath as NSString).deletingLastPathComponent
        let fullDirPath = (rootDir.path as NSString).appendingPathComponent(directoryPath)
        
        // Verify it's an absolute path
        guard fullDirPath.hasPrefix("/") else {
            print("❌ ERROR: Generated directory path is not absolute: \(fullDirPath)")
            return nil
        }
        
        return fullDirPath
    }
}
