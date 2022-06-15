//
//  main.swift
//  ChatServer
//
//  Created by JK on 2022/06/15.
//

import Foundation


let server = ChatServer(with: .init(integerLiteral: 9090))
server?.run()

RunLoop.main.run()
