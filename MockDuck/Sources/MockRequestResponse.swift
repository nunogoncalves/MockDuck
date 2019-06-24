//
//  MockRequestResponse.swift
//  MockDuck
//
//  Created by Peter Walters on 3/22/18.
//  Copyright © 2018 BuzzFeed, Inc. All rights reserved.
//

import Foundation

/// A basic container for holding a request, a response, and any associated data.
final class MockRequestResponse: Codable {

    enum MockFileTarget {
        case request
        case requestBody
        case responseData
    }

    // MARK: - Properties

    var request: URLRequest {
        get {
            return requestWrapper.request
        }
        set {
            requestWrapper.request = newValue
        }
    }

    var response: URLResponse? {
        return responseWrapper?.response
    }

    var responseData: Data? {
        get {
            return responseWrapper?.responseData
        }
        set {
            responseWrapper?.responseData = newValue
        }
    }

    private(set) lazy var normalizedRequest: URLRequest = {
        return MockDuck.delegate?.normalizedRequest(for: request) ?? request
    }()

    let requestWrapper: MockRequest
    var responseWrapper: MockResponse?

    // MARK: - Initializers

    init(request: URLRequest) {
        self.requestWrapper = MockRequest(request: request)
        self.responseWrapper = nil
    }

    init(request: URLRequest, mockResponse: MockResponse) {
        self.requestWrapper = MockRequest(request: request)
        self.responseWrapper = mockResponse
    }

    init(request: URLRequest, response: URLResponse, responseData: Data?) {
        self.requestWrapper = MockRequest(request: request)
        self.responseWrapper = MockResponse(response: response, responseData: responseData)
    }

    // MARK: - Disk Utilities

    func fileName(for type: MockFileTarget) -> String? {
        guard let baseName = serializedBaseName else { return nil }
        let hashValue = serializedHashValue
        var componentSuffix = ""
        var pathExtension: String?

        switch type {
        case .request:
            pathExtension = "json"
        case .requestBody:
            componentSuffix = "-request"
            pathExtension = request.dataSuffix
        case .responseData:
            componentSuffix = "-response"
            pathExtension = response?.dataSuffix
        }

        // We only construct a fileName if there is a valid path extension. The only way
        // pathExtension can be nil here is if this is a data blob that we do not support writing as
        // an associated file. In this scenario, this data is encoded and stored in the JSON itself
        // instead of as a separate, associated file.
        var fileName: String?
        if let pathExtension = pathExtension {
            fileName = "\(baseName)-\(hashValue)\(componentSuffix).\(pathExtension)"
        }

        return fileName
    }

    var serializedHashValue: String {
        var hashData = Data()

        if let urlData = normalizedRequest.url?.absoluteString.data(using: .utf8) {
            hashData.append(urlData)
        }

        if let body = normalizedRequest.httpBody ?? normalizedRequest.bodyStreamData {
            if let json = try? JSONSerialization.jsonObject(with: body, options: []) as! [String: Any]{
                hashData.append(sort(dictionary: json).data(using: .utf8)!)
            } else {

                hashData.append(body)
            }
        }

        if !hashData.isEmpty {
            return String(CryptoUtils.md5(hashData).prefix(8))
        } else {
            return ""
        }
    }

    private var serializedBaseName: String? {
        guard
            let url = normalizedRequest.url,
            let host = url.host else
        {
            return nil
        }

        if url.path.count > 0 {
            return host.appending(url.path)
        } else {
            return host
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case requestWrapper = "request"
        case responseWrapper = "response"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestWrapper = try container.decode(MockRequest.self, forKey: .requestWrapper)
        responseWrapper = try container.decodeIfPresent(MockResponse.self, forKey: .responseWrapper)
    }
}

internal extension URLRequest {

    var bodyStreamData: Data? {

        guard let bodyStream = self.httpBodyStream else { return nil }

        bodyStream.open()

        // Will read 16 chars per iteration. Can use bigger buffer if needed
        let bufferSize: Int = 16

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

        var dat = Data()

        while bodyStream.hasBytesAvailable {

            let readDat = bodyStream.read(buffer, maxLength: bufferSize)
            dat.append(buffer, count: readDat)
        }

        buffer.deallocate()

        bodyStream.close()

        return dat
    }
}

func sort(dictionary: [String: Any]) -> String {
    let sorted = dictionary.keys.sorted().reduce("") { (acc, iteration) -> String in
        if let json = dictionary[iteration] as? [String: Any] {
            return acc.appending("\(iteration):\(sort(dictionary: json)),")
        } else {
            return acc.appending("\(iteration):\(dictionary[iteration]!),")
        }
    }
    return String(sorted.dropLast())
}
