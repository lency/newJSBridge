//
//  WebApiBridge.swift
//  webapiDemo
//
//  Created by jicuhanguo on 2019/8/22.
//  Copyright © 2019 jicg. All rights reserved.
//

import Foundation
import WebKit

struct JsValueReturn<T: Encodable> : Encodable {
    let type = "value"
    let value: T
    init(_ value: T) {
        self.value = value
    }
}

struct JsPromiseReturn : Encodable {
    let type = "promise"
    let promise: String
    init(_ promise: String) {
        self.promise = promise
    }
}

struct JsDone : Encodable {
    let type = "done"
}

struct JSCmdHeader : Codable {
    let `class`: String
    let method: String
    let type: CmdType
}

struct JSCmd<T:Codable> : Codable {
    let `class`: String
    let method: String
    let args: T
}

enum JSCmdError : Error {
    case invalidparameters
    case methodnotfound
}

struct SetVal<T:Codable> : Codable {
    let newVal : T
}

typealias FutureCall = (Data) throws -> EncodableFuture
typealias SyncCall = (Data) throws -> Encodable
typealias SetterCall = (Data) throws -> JsDone
typealias Proc = (Data) throws -> ()

protocol WebCommander {
    func get_sync_pointer(_ method: String) throws -> SyncCall
    func get_setter_pointer(_ method: String) throws -> SetterCall
    func get_future_pointer(_ method: String) throws -> FutureCall
    var jsPiece: String{ get }
}

enum CmdType : String, Codable {
    case AsyncFunction
    case Function
    case Setter
    case Getter
}

extension WebCommander {
    func dispatch_ex(_ method: String, _ type: CmdType, _ json: Data, invoker: @escaping (String) -> ()) throws -> String? {
        var data : Data?

        switch type {
        case .AsyncFunction:
            let ck = "_" + String(format: "%x", json.hashValue)
            data = try JsPromiseReturn( ck ).toJsonData()
            try get_future_pointer(method)(json).then { (ret: Encodable) in
                if let d = try? ret.toWrapperJsonData(),
                  let s = String(data:d, encoding: .utf8) {
                    invoker("\(ck)('\(s)')")
                }
            }
        case .Function:
            data = try get_sync_pointer(method)(json).toJsonData()
        case .Getter:
            data = try getPropertyData(method)
        case .Setter:
            data = try get_setter_pointer(method)(json).toJsonData()
        }
        return data.flatMap { String(data: $0, encoding: .utf8)}
    }

    func getPropertyData(_ name: String) throws -> Data {
        let mirror = Mirror(reflecting: self)
        for prop in mirror.children {
            if prop.label == name {
                if let v = prop.value as? Encodable {
                    return try v.toWrapperJsonData()
                }
                break
            }
        }
        throw JSCmdError.methodnotfound
    }
}

extension PWebView {
    static func bridgeConfiguration() -> WKWebViewConfiguration {
        let x = WKWebViewConfiguration()

        let script = WKUserScript(source: WebCommandRouter.injectScript,
                                  injectionTime: .atDocumentStart,// 在载入时就添加JS
            forMainFrameOnly: false) // 只添加到mainFrame中

        x.userContentController.addUserScript(script)
        return x
    }
    static func createBridgeWebView() -> WKWebView {
        let webView =  PWebView(frame: .zero, configuration: bridgeConfiguration())
        webView.uiDelegate = webView
        NotificationCenter.default.addObserver(webView, selector: #selector(onNoti), name: nil, object: WebapiDemo.share)
        webView.loadapiStub()
        return webView
    }

    @objc
    func onNoti(_ noti: Notification) {
        if let command = noti.object as? BaseCommand {
            let s = "\(command.class).dispatchEvent(new Event('\(noti.name.rawValue)'))"
            evaluateJavaScript(s, completionHandler: nil)
        }
    }
}
