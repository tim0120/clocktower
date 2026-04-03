import Darwin
import Foundation

final class ProcessSingleton {
    private var fileDescriptor: Int32 = -1

    func acquireLock(at url: URL) -> Bool {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        fileDescriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            logAsync("singleton lock-open failed path=\(url.path)")
            return false
        }

        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            logAsync("singleton lock-acquired path=\(url.path)")
            return true
        }

        logAsync("singleton lock-denied path=\(url.path)")
        close(fileDescriptor)
        fileDescriptor = -1
        return false
    }

    deinit {
        guard fileDescriptor >= 0 else { return }
        logAsync("singleton lock-released")
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}
