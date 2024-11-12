import Combine
import Foundation
import Dispatch
//
//let sub = Timer.publish(every: 0.1, on: .current, in: .common)
//
//var count = 0
//
//func delayedPublisher<Value>(_ value: Value, delay after: TimeInterval) -> AnyPublisher<Value, Never> {
//    Just(value)
//        .delay(for: .seconds(after), scheduler: RunLoop.current)
//        .eraseToAnyPublisher()
//}
//
//let cancel = sub
//    .autoconnect()
//    .buffer(size: 10, prefetch: .keepFull, whenFull: .dropOldest)
//    .flatMap(maxPublishers: .max(1), { delayedPublisher($0, delay: 1) })
////    .flatMap { delayedPublisher($0, delay: 3) }
//    .sink { result in
//        print("now:", result)
//    }


protocol Resumable {
    func resume()
}

extension Subscribers {
    class ResumableSink<Input, Failure: Error>: Subscriber, Cancellable, Resumable {
        let receiveCompletion: (Subscribers.Completion<Failure>) -> Void
        let receiveValue: (Input) -> Bool
        
        var shouldPullNewValue: Bool = false
        
        var subscription: Subscription?
        
        init(
            receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
            receiveValue: @escaping (Input) -> Bool
        )
        {
            self.receiveCompletion = receiveCompletion
            self.receiveValue = receiveValue
        }
        
        func receive(subscription: Subscription) {
            self.subscription = subscription
            resume()
        }
        
        func receive(_ input: Input) -> Subscribers.Demand {
            shouldPullNewValue = receiveValue(input)
            return shouldPullNewValue ? .max(1) : .none
        }
        
        func receive(completion: Subscribers.Completion<Failure>) {
            receiveCompletion(completion)
            subscription = nil
        }
        
        func cancel() {
            subscription?.cancel()
            subscription = nil
        }
        
        func resume() {
            guard !shouldPullNewValue else {
                return
            }
            shouldPullNewValue = true
            subscription?.request(.max(1))
        }
    }
}

extension Publisher {
    func resumableSink(
        receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
        receiveValue: @escaping (Output) -> Bool
    ) -> Cancellable & Resumable
    {
        let sink = Subscribers.ResumableSink<Output, Failure>(
            receiveCompletion: receiveCompletion,
            receiveValue: receiveValue
        )
        self.subscribe(sink)
        return sink
    }
}


var buffer = [Int]()
let subscriber = (1...).publisher.resumableSink(
    receiveCompletion: { completion in
        print("Completion: \(completion)")
    },
    receiveValue: { value in
        print("Receive value: \(value)")
        buffer.append(value)
        return buffer.count < 5
//        return true
    }
)

let cancellable  = Timer.publish(every: 1/60, on: .main, in: .default)
    .autoconnect()
    .sink { _ in
        buffer.removeAll()
        subscriber.resume()
    }
