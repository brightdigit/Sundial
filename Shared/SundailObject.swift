//
//  SundailObject.swift
//  WatchConnectivityTest
//
//  Created by Leo Dion on 4/5/22.
//

import Foundation
import SwiftUI
import WatchConnectivity
import Combine


struct MissingCompanionError : Error {
  
}
extension Publisher {
  func assignOnMain(to published: inout Published<Self.Output>.Publisher) where Self.Failure == Never {
    self.receive(on: DispatchQueue.main).assign(to: &published)
  }
  
  func assignOnMain<OutputType>(_ keyPath: KeyPath<Self.Output, OutputType>, to published: inout Published<OutputType>.Publisher) where Self.Failure == Never {
    self.map(keyPath).assign(to: &published)
  }
  
  func neverPublishers() -> (AnyPublisher<Output, Never>, AnyPublisher<Failure, Never>) {
    let failurePublisher = self.share().map{ _ in nil as Failure? }.catch { error in
      return Just(error)
    }.compactMap{$0}.eraseToAnyPublisher()
    
    let successPublisher = self.share().map{$0 as Output?}.replaceError(with: nil).compactMap{$0}.eraseToAnyPublisher()
    
    return (successPublisher, failurePublisher)
  }
  
  
}

class SundailObject : ObservableObject {
   
  #if os(iOS)
  static let isCompanionAppInstalledKeyPath : KeyPath<WCSession, Bool> = \.isWatchAppInstalled
  #elseif os(watchOS)
  static let isCompanionAppInstalledKeyPath : KeyPath<WCSession, Bool> = \.isCompanionAppInstalled
  #endif
  
  let lastColorSendingSubject = PassthroughSubject<Color, Never>()
  
  @Published var lastColorReceived: Color = .secondary
  @Published var lastColorSent: Color = .secondary
  @Published var lastColorReply: Color = .secondary
  @Published var wcObject = WCObject()
  
#if os(iOS)
  @Published var isPaired = false
#endif
  
  @Published var isReachable = false
  @Published var isCompanionAppInstalled = false
  @Published var activationState = WCSessionActivationState.notActivated
  @Published var lastError: Error?
  
  var cancellables = [AnyCancellable]()
  
  public func forceActivate() {
    try! wcObject.activate()
  }
  
  func sendColor(_ color: Color) {
    self.lastColorSendingSubject.send(color)
  }
  
  init () {
    self.wcObject.activationStateSubject.assignOnMain(\.activationState, to: &$activationState)
    self.wcObject.isReachableSubject.assignOnMain(\.isReachable, to: &$isReachable)
    


    self.wcObject.isCompanionInstalledSubject.assignOnMain(Self.isCompanionAppInstalledKeyPath, to: &$isCompanionAppInstalled)
    
    #if os(iOS)
    self.wcObject.isPairedSubject.assignOnMain(\.isPaired, to: &$isPaired)
    #endif
    
    self.lastColorSendingSubject.share().compactMap(WCMessage.message(fromColor:)).subscribe(self.wcObject.sendingMessageSubject).store(in: &self.cancellables)
    
    self.wcObject.messageReceivedSubject.compactMap(self.receivedMessage(_:)).assignOnMain(to: &self.$lastColorReceived)
    
    let replyReceived = self.wcObject.replyMessageSubject.tryCompactMap(self.receivedReply(_:))
    
    let (replyReceivedValue, replyReceivedError) = replyReceived.neverPublishers()
    
    replyReceivedError.map{$0 as Error?}.assignOnMain(to: &self.$lastError)
        
    replyReceivedValue.share().map{$0.0}.assignOnMain(to: &self.$lastColorSent)
    replyReceivedValue.share().compactMap{$0.1}.assignOnMain(to: &self.$lastColorReply)
    
    
  }
  
  func receivedReply(_ messageResult: WCMessageResult) throws -> (Color, Color?)? {
    let (sent, context) = messageResult
    let reply : WCMessage?
    switch context {
      
    case .applicationContext:
      reply = nil
    case .reply(let messageReply):
      reply = messageReply
    case .failure(let error):
      throw error
    case .noCompanion:
      throw MissingCompanionError()
    }
    guard let sentColor = sent.color else {
      return nil
    }
    
    let replyColor = reply?.color
    return (sentColor, replyColor)
  }
  
  func receivedMessage(_ messageAcceptance: WCMessageAcceptance) -> Color?{
    let (message, context) = messageAcceptance
    let replyHandler = context.replyHandler
    guard let color = message.color else {
      return nil
    }
      replyHandler?(message)
      //print("Recv Updated: \(String(colorValue, radix: 16, uppercase: true))")
      //lastColorReceivedSubject.send(color)
      return color
  }
}
