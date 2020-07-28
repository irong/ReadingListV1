import Foundation
import Promises

public extension URLSession {

    /**
     Starts and returns a Data task
    */
    @discardableResult
    func startedDataTask(with url: URL, callback: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let task = dataTask(with: url, completionHandler: callback)
        task.resume()
        return task
    }

    func data(url: URL) -> Promise<Data> {
        return Promise<Data> { fulfill, reject in
            self.startedDataTask(with: url) { data, _, error in
                if let error = error {
                    reject(error)
                } else if let data = data {
                    fulfill(data)
                }
            }
        }
    }
}
