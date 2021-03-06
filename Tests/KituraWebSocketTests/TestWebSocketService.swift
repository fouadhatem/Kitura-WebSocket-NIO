/**
 * Copyright IBM Corporation 2016-2017
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import XCTest
import Foundation

@testable import KituraWebSocket
import KituraNet

class TestWebSocketService: WebSocketService {
    private var _connectionId = ""
    private var _disconnectClientId = [String]()
    let closeReason: WebSocketCloseReasonCode
    let pingMessage: String?
    let testServerRequest: Bool
    let testQueryParams: Bool
    var queryParams: [String: String] = [:]
    let connectionIDAccessQueue: DispatchQueue = DispatchQueue(label: "Connection ID Access Queue")

    public init(closeReason: WebSocketCloseReasonCode, testServerRequest: Bool, pingMessage: String?, testQueryParams: Bool = false, connectionTimeout: Int? = nil) {
        self.closeReason = closeReason
        self.testServerRequest = testServerRequest
        self.pingMessage = pingMessage
        self.testQueryParams = testQueryParams
        self.connectionTimeout = connectionTimeout
    }

    public let connectionTimeout: Int?

    var connectionId: String {
        get {
            return connectionIDAccessQueue.sync {
                return _connectionId
            }
        }
        set {
            connectionIDAccessQueue.sync {
                _connectionId = newValue
            }
        }
    }

    internal let queue = DispatchQueue(label: "ClientIDArrayQueue")
    public var connectClientId = [String]()
    public func connected(connection: WebSocketConnection) {
        connectionId = connection.id
        queue.sync {
            self.connectClientId.append(self.connectionId)
        }
        if let pingMessage = pingMessage {
            if pingMessage.count > 0 {
                connection.ping(withMessage: pingMessage)
            } else {
                connection.ping()
            }
        }

        if testServerRequest {
            performServerRequestTests(request: connection.request)

            sleep(2)

            performServerRequestTests(request: connection.request)
        }

        if testQueryParams {
            let parsedURL = URLParser(url: connection.request.url, isConnect: false)
            self.queryParams = parsedURL.queryParameters.mapValues({ $0.removingPercentEncoding ?? $0 })
        }
    }

    private func performServerRequestTests(request: ServerRequest) {
        XCTAssertEqual(request.method, "GET", "The method of the request should be GET, it was \(request.method))")
        XCTAssertEqual(request.httpVersionMajor, 1, "HTTP version major should be 1, it was \(String(describing: request.httpVersionMajor))")
        XCTAssertEqual(request.httpVersionMinor, 1, "HTTP version major should be 1, it was \(String(describing: request.httpVersionMinor))")
        XCTAssertEqual(request.urlURL.pathComponents[1], "wstester", "Path of the request should be /wstester, it was /\(request.urlURL.pathComponents[1])")
        XCTAssertEqual(request.url, "/wstester".data(using: .utf8)!, "Path of the request should be /wstester, it was \(String(data: request.url, encoding: .utf8) ?? "Not UTF-8")")
        let protocolVersion = request.headers["Sec-WebSocket-Version"]
        XCTAssertNotNil(protocolVersion, "The Sec-WebSocket-Version header wasn't in the headers")
        XCTAssertEqual(protocolVersion!.count, 1, "The Sec-WebSocket-Version header should have one value")
        XCTAssertEqual(protocolVersion![0], "13", "The Sec-WebSocket-Version header value should be 13, it was \(protocolVersion![0])")

        do {
            let bodyString = try request.readString()
            XCTAssertNil(bodyString, "Read of body should have returned nil, it returned \"\(String(describing: bodyString))\"")
            var body = Data()
            var count = try request.read(into: &body)
            XCTAssertEqual(count, 0, "Read of body into a Data should have returned 0, it returned \(count)")
            count = try request.readAllData(into: &body)
            XCTAssertEqual(count, 0, "Read of entire body into a Data should have returned 0, it returned \(count)")
        } catch {
            XCTFail("Failed to read from the body. Error=\(error)")
        }
    }
    public var disconnectClientId = [String]()
    public func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode) {
        queue.sync {
            self.disconnectClientId.append(connection.id)
        }
        XCTAssertEqual(Int(closeReason.code()), Int(reason.code()), "Expected close reason code of \(closeReason) received \(reason)")
    }

    public func received(message: Data, from: WebSocketConnection) {
        from.send(message: message)
    }

    public func received(message: String, from: WebSocketConnection) {
        if self.testQueryParams {
            let keys = queryParams.keys.sorted().joined(separator: ",")
            let values = queryParams.values.sorted().joined(separator: ",")
            from.send(message: "\(message)\(keys) and \(values)")
        } else {
            from.send(message: message)
        }

        if message == "close" {
            from.close(reason: .goingAway, description: "Going away...")
        } else if message == "drop" {
            from.drop(reason: .policyViolation, description: "Droping...")
        } else if message == "ping" {
            from.ping(withMessage: "Hello")
        }
    }
}

extension TestWebSocketService: CustomStringConvertible {
    /// Generate a printable version of this enum.
    public var description: String {
        return "TestWebSocketService(closeReason: \(closeReason))"
    }
}
