//
//  ChatServer.swift
//  ChatServer
//
//  Created by JK on 2022/06/15.
//

import Foundation
import Network

struct Command : Decodable {
    let header : String
    let id : String
    let length : Int?
    let data : Data?
}

struct CommandResponse : Encodable {
    let header : String
    let id : String
}


enum Request {
    static let Login = "0x10"
    static let Chat = "0x20"
}

enum Response {
    static let Login = "0x11"
    static let Chat = "0x21"
}

class ChatServer {
    let networkQueue = DispatchQueue.init(label: "chat.codesquad.kr")
    var listener : NWListener
    var connections = [NWConnection]()
    var threads = [Thread]()
    
    init?(with port: NWEndpoint.Port) {
        let options = NWProtocolTCP.Options()
        let params = NWParameters.init(tls: .none, tcp: options)
        params.allowLocalEndpointReuse = true
        let binding = try? NWListener(using: params, on: port)
        guard binding != nil else { return nil }
        listener = binding!
    }
    
    func run() {
        setupListener()
        print("Chat Server is running...")
    }
 
    private func setupListener() {
        listener.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                print("Listener ready on \(String(describing: self.listener.port))")
            case .failed(let error):
                print("Listener failed with \(error), restarting")
                self.listener.cancel()
            default:
                break
            }
        }
        listener.newConnectionHandler = setup(connection:)
        listener.start(queue: networkQueue)
    }
    
    private func setup(connection: NWConnection) {
        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                print("ready.. \(connection)")
                self.setupReceiverFromClient(of: connection)
            case .failed(_):
                connection.cancel()
                guard let index = self.connections.firstIndex(where: { $0.endpoint == connection.endpoint }) else {
                    return
                }
                self.connections.remove(at: index)
                print("\(connection) failed")
            case .cancelled:
                print("\(connection) cancelled")
            default:
                print("\(connection) others")
                break
            }
        }
        connection.start(queue: self.networkQueue)
    }
    
    private func receive(from connection : NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 1024) { (content, context, isComplete, error) in
            if let data = content, !data.isEmpty {
                guard let command = try? JSONDecoder().decode(Command.self, from: data) else {
                    print("\(connection) unknown command")
                    connection.cancel()
                    return
                }
                switch command.header {
                    case "0x10": //Login
                        let response = CommandResponse(header: Response.Login, id: command.id)
                        let responseData = try? JSONEncoder().encode(response)
                        connection.send(content: responseData, completion: NWConnection.SendCompletion.contentProcessed({_ in}))
                        self.connections.append(connection)
                    case "0x20": //Chat
                        let response = CommandResponse(header: Response.Chat, id: command.id)
                        let responseData = try? JSONEncoder().encode(response)
                        connection.send(content: responseData, completion: NWConnection.SendCompletion.contentProcessed({_ in}))
                        for client in self.connections {
                            if client.endpoint == connection.endpoint { continue }
                            client.send(content: data, completion: NWConnection.SendCompletion.contentProcessed({_ in}))
                        }
                    default:
                        break
                }
            }
            if let error = error {
                print("\(connection) error - ", error.localizedDescription)
            }
        }
    }
    
    private func setupReceiverFromClient(of connection: NWConnection) {
        let thread = Thread {
            while connection.state == .ready {
                Thread.sleep(forTimeInterval: 0.5)
                self.networkQueue.async {
                    self.receive(from: connection)
                }
            }
        }
        thread.start()
        threads.append(thread)
    }
}
