import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        DictionarySync.shared.start()
        DictionaryDownloads.shared.start()
    }

    func applicationDidBecomeActive() {
        Task { await DictionarySync.shared.refreshLocal() }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let downloadTask = task as? WKURLSessionRefreshBackgroundTask {
                if downloadTask.sessionIdentifier == DictionaryDownloads.sessionIdentifier {
                    DictionaryDownloads.shared.handleBackgroundEvents {
                        downloadTask.setTaskCompletedWithSnapshot(false)
                    }
                } else { downloadTask.setTaskCompletedWithSnapshot(false) }
                continue
            }
            guard let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }
            DictionarySync.shared.finishBackgroundTransfer(connectivityTask)
        }
    }
}
