import Foundation
import Swifter
import ReadingList_Foundation

class MockServer {
    let server = HttpServer()

    init() {
        server.get["/"] = { request in
            guard let urlQueryParam = request.queryParams.first(where: { $0.0 == "url" })?.1 else { preconditionFailure() }
            guard let realUrl = urlQueryParam.removingPercentEncoding else { preconditionFailure() }
            
            let path = NSTemporaryDirectory() + "/" + urlQueryParam
            FileManager.default.createFile(atPath: path, contents: Data(base64Encoded: "hello")!, attributes: nil)
            return .internalServerError
        }

        /*for path in mockedApiCalls.map { $0.request.path }.distinct() {
            server.get[path] = { incomingRequest in
                guard let mockedRequest = mockedApiCalls.first(where: { mockRequest in
                    // The incoming request path starts with a '/' - drop this.
                    mockRequest.request.pathAndQuery == String(incomingRequest.path.dropFirst())
                }) else { preconditionFailure("No mocked request matching '\(incomingRequest.path)' found") }
                return .ok(.json(mockedRequest.response))
            }
            print("Registered responder to URL \(path)")
        }*/
    }
}

extension String {
    func regex(_ regex: String) -> [(match: String, groups: [String])] {
        let regex = try! NSRegularExpression(pattern: regex)
        return regex.matches(in: self, range: NSRange(location: 0, length: self.count)).map { match in
            (self[match.range], (1..<match.numberOfRanges).map { self[match.range(at: $0)] })
        }
    }

    subscript(range: NSRange) -> String {
        return String(self[Range(range, in: self)!])
    }
}
