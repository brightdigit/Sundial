import Combine
import Foundation
import SwiftUI
import WatchConnectivity

typealias WCMessage = [String : Any]

enum WCSendMessageResult {
  case applicationContext
  case reply(WCMessage)
  case failure(Error)
  case noCompanion
}

typealias WCMessageResult = (WCMessage, WCSendMessageResult)

enum WCMessageContext {
  case replyWith(WCMessageHandler)
  case applicationContext
  
  var replyHandler : WCMessageHandler? {
    guard case let .replyWith(handler) = self else {
      return nil
    }
    return handler
  }
}

typealias WCMessageHandler = (WCMessage) -> Void


typealias WCMessageAcceptance = (WCMessage, WCMessageContext)
extension WCSession {
  var isPairedAppInstalled : Bool {
    #if os(iOS)
    return self.isWatchAppInstalled
    #else
    return self.isCompanionAppInstalled
    #endif
  }
}

class WCObject: NSObject, WCSessionDelegate, ObservableObject {
  struct NotSupportedError: Error {}
  var cancellable : AnyCancellable!


  public func activate() throws {
    guard WCSession.isSupported() else {
      throw NotSupportedError()
    }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  override init() {
    super.init()
    cancellable = self.sendingMessageSubject.sink(receiveValue: self.sendMessage(_:))
  }

  var _session: WCSession?

  var actualSession: WCSession {
    _session ?? WCSession.default
  }

  let activationStateSubject = PassthroughSubject<WCSession, Never>()
  let isReachableSubject = PassthroughSubject<WCSession, Never>()

  let isCompanionInstalledSubject = PassthroughSubject<WCSession, Never>()
  #if os(iOS)
    let isPairedSubject = PassthroughSubject<WCSession, Never>()
  #endif
  
  
  let messageReceivedSubject = PassthroughSubject<WCMessageAcceptance, Never>()
  let sendingMessageSubject = PassthroughSubject<WCMessage, Never>()
  let replyMessageSubject = PassthroughSubject<WCMessageResult, Never>()

  #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
      activationStateSubject.send(session)
    }

    func sessionDidDeactivate(_ session: WCSession) {
      activationStateSubject.send(session)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
      DispatchQueue.main.async {
        self.isPairedSubject.send(session)
        self.isCompanionInstalledSubject.send(session)
      }
      
    }

  #elseif os(watchOS)

    func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
      isCompanionInstalledSubject.send(session)
    }
  #endif

  func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
    _session = session
    DispatchQueue.main.async {
      
      self.activationStateSubject.send(session)

      self.isReachableSubject.send(session)
      #if os(iOS)
      self.isCompanionInstalledSubject.send(session)
      self.isPairedSubject.send(session)
      #elseif os(watchOS)
      self.isCompanionInstalledSubject.send(session)
      #endif
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async {
      self.isReachableSubject.send(session)
    }
    
  }
  
  
  
  private func sendMessage(_ message: WCMessage) {
    if self.actualSession.isReachable {
      actualSession.sendMessage(message) { reply in
        self.replyMessageSubject.send((message, .reply(reply)))
      } errorHandler: { error in
        self.replyMessageSubject.send((message, .failure(error)))
      }
    } else if self.actualSession.isPairedAppInstalled {
      do {
        try actualSession.updateApplicationContext(message)
      } catch {
        self.replyMessageSubject.send((message, .failure(error)))

        return
      }
                                      self.replyMessageSubject.send((message, .applicationContext))
      
    } else {
          self.replyMessageSubject.send((message, .noCompanion))
    }
  }


  func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    messageReceivedSubject.send((message, .replyWith( replyHandler)))
  }

  func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    messageReceivedSubject.send((applicationContext, .applicationContext))
  }
}
