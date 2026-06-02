//
//  LocalModelDiscovery.swift
//  Hover
//
//  Created by Hover Contributors on 2026-05-26.
//  Detects local LM Studio and Ollama model servers without sending secrets.
//

import Darwin
import Foundation

struct LocalModelProvider: Equatable, Identifiable {
    let preset: EndpointPreset
    let displayName: String
    let baseURL: String
    let models: [String]
    let isInstalled: Bool
    let isReachable: Bool

    var id: String {
        preset.rawValue
    }

    var preferredModel: String? {
        models.first
    }
}

final class LocalModelDiscovery {
    private enum Ports {
        static let lmStudio: UInt16 = 1234
        static let ollama: UInt16 = 11434
    }

    private let session: URLSession
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.25
        configuration.timeoutIntervalForResource = 2.5
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil

        self.session = URLSession(configuration: configuration)
        self.fileManager = fileManager
    }

    func discoverLocalProviders() async -> [LocalModelProvider] {
        async let lmStudio = discoverLMStudio()
        async let ollama = discoverOllama()

        return await [lmStudio, ollama]
    }

    private func discoverLMStudio() async -> LocalModelProvider {
        let baseURL = EndpointPreset.lmStudio.baseURL
        let models = await fetchOpenAICompatibleModels()

        return LocalModelProvider(
            preset: .lmStudio,
            displayName: EndpointPreset.lmStudio.title,
            baseURL: baseURL,
            models: models,
            isInstalled: appExists(named: "LM Studio"),
            isReachable: !models.isEmpty
        )
    }

    private func discoverOllama() async -> LocalModelProvider {
        let baseURL = EndpointPreset.ollama.baseURL
        let models = await fetchOllamaModels()

        return LocalModelProvider(
            preset: .ollama,
            displayName: EndpointPreset.ollama.title,
            baseURL: baseURL,
            models: models,
            isInstalled: appExists(named: "Ollama") || commandExists(named: "ollama"),
            isReachable: !models.isEmpty
        )
    }

    private func fetchOpenAICompatibleModels() async -> [String] {
        guard isLocalPortAcceptingConnections(Ports.lmStudio),
              let baseURL = URL(string: "http://127.0.0.1:\(Ports.lmStudio)/v1") else {
            return []
        }

        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.25)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return []
            }

            let payload = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            return sortedModelNames(payload.data.map(\.id))
        } catch {
            return []
        }
    }

    private func fetchOllamaModels() async -> [String] {
        guard isLocalPortAcceptingConnections(Ports.ollama),
              let url = URL(string: "http://127.0.0.1:\(Ports.ollama)/api/tags") else {
            return []
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.25)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return []
            }

            let payload = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return sortedModelNames(payload.models.map(\.name))
        } catch {
            return []
        }
    }

    private func sortedModelNames(_ names: [String]) -> [String] {
        let cleanNames = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(Set(cleanNames))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func appExists(named appName: String) -> Bool {
        [
            "/Applications/\(appName).app",
            "\(NSHomeDirectory())/Applications/\(appName).app"
        ].contains { path in
            fileManager.fileExists(atPath: path)
        }
    }

    private func commandExists(named commandName: String) -> Bool {
        [
            "/opt/homebrew/bin/\(commandName)",
            "/usr/local/bin/\(commandName)",
            "/usr/bin/\(commandName)"
        ].contains { path in
            fileManager.fileExists(atPath: path)
        }
    }

    private func isLocalPortAcceptingConnections(_ port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }

        defer {
            close(descriptor)
        }

        let currentFlags = fcntl(descriptor, F_GETFL, 0)
        guard currentFlags >= 0,
              fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) >= 0 else {
            return false
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian

        guard inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1 else {
            return false
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return true
        }

        guard errno == EINPROGRESS else {
            return false
        }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pollDescriptor, 1, 120)
        guard pollResult > 0 else {
            return false
        }

        var socketError: Int32 = 0
        var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
        let status = getsockopt(
            descriptor,
            SOL_SOCKET,
            SO_ERROR,
            &socketError,
            &socketErrorLength
        )

        return status == 0 && socketError == 0
    }
}

private struct OpenAIModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
    }
}
