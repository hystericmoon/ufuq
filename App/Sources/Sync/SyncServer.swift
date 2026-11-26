import Foundation
import Network
import UfuqCore

/// A tiny HTTP/1.1 server on the LAN (Network.framework), advertised over Bonjour as
/// `_ufuq._tcp`. It only frames requests and writes responses; `SyncRouter` decides everything.
final class SyncServer {
    private let router: SyncRouter
    private let serviceName: String
    private let queue = DispatchQueue(label: "app.ufuq.sync.server")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private static let maxConnections = 16
    private static let headTimeout: TimeInterval = 10

    /// Called on the main queue when the listener is ready (with its port) or stops (nil).
    var onPortChange: ((UInt16?) -> Void)?

    init(router: SyncRouter, serviceName: String) {
        self.router = router
        self.serviceName = serviceName
    }

    func start() throws {
        guard listener == nil else { return }
        let listener = try NWListener(using: .tcp)
        listener.service = NWListener.Service(name: serviceName, type: SyncProtocol.bonjourType)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                let port = listener?.port?.rawValue
                DispatchQueue.main.async { self?.onPortChange?(port) }
            case .failed(let error):
                NSLog("Ufuq sync: listener failed: \(error)")
                self?.stop()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [self] in
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
        }
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async { [weak self] in self?.onPortChange?(nil) }
    }

    // MARK: - Connections (all on `queue`)

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections[id] = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        // A client that never finishes its request head is dropped.
        queue.asyncAfter(deadline: .now() + Self.headTimeout) { [weak connection] in
            if let connection, self.connections[id] != nil, !self.handled.contains(id) { connection.cancel() }
        }
        receive(on: connection, buffer: Data())
    }

    private var handled: Set<ObjectIdentifier> = []

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if error != nil { connection.cancel(); return }

            switch HTTPRequestParser.parse(buffer) {
            case .incomplete:
                if isComplete { connection.cancel() } else { self.receive(on: connection, buffer: buffer) }
            case .invalid(let status):
                self.handled.insert(ObjectIdentifier(connection))
                self.send(HTTPResponse(status: status), on: connection)
            case .request(let request):
                self.handled.insert(ObjectIdentifier(connection))
                Task {
                    let response = await self.router.handle(request)
                    self.queue.async { self.send(response, on: connection) }
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
            self?.handled.remove(ObjectIdentifier(connection))
            connection.cancel()
        })
    }
}
