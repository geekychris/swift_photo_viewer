import Foundation

extension PhotoFile {
    /// Returns the ABSOLUTE full path to the file, including filename
    /// Never returns a relative path - throws error if root directory not found
    func getAbsoluteFullPath(rootDirectories: [RootDirectory]) -> String? {
        guard let rootDir = rootDirectories.first(where: { $0.id == self.rootDirectoryId }) else {
            return nil
        }
        
        let fullPath = (rootDir.path as NSString).appendingPathComponent(self.relativePath)
        
        // Verify it's an absolute path
        guard fullPath.hasPrefix("/") else {
            return nil
        }
        
        return fullPath
    }
    
    /// Returns the ABSOLUTE directory path (without filename)
    /// Never returns a relative path - throws error if root directory not found
    func getAbsoluteDirectoryPath(rootDirectories: [RootDirectory]) -> String? {
        guard let rootDir = rootDirectories.first(where: { $0.id == self.rootDirectoryId }) else {
            return nil
        }
        
        let directoryPath = (self.relativePath as NSString).deletingLastPathComponent
        let fullDirPath = (rootDir.path as NSString).appendingPathComponent(directoryPath)
        
        // Verify it's an absolute path
        guard fullDirPath.hasPrefix("/") else {
            return nil
        }
        
        return fullDirPath
    }
}
