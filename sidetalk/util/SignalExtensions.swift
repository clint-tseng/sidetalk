
import Foundation
import ReactiveSwift
import enum Result.NoError

extension Signal {
    // HACK: this causes observation to happen! careful with use on cold signals.
    func combineWithDefault<U>(_ other: Signal<U, Error>, defaultValue: U) -> Signal<(Value, U), Error> {
        let (signal, observer) = Signal<U, Error>.pipe();
        let result = self.combineLatest(with: signal);
        other.observe(observer);
        observer.send(value: defaultValue);

        return result;
    }

    // HACK: same problem!
    func merge(_ other: Signal<Value, Error>) -> Signal<Value, Error> {
        let (signal, observer) = Signal<Value, Error>.pipe();

        self.observe { value in observer.send(value); }
        other.observe { value in observer.send(value); }

        return signal;
    }

    func downcastToOptional() -> Signal<Value?, Error> {
        return self.map({ value in value as Value? });
    }

    func always<U>(value: U) -> Signal<U, Error> {
        return self.map({ _ in value });
    }
}
