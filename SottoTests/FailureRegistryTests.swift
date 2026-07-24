import Testing
import Foundation
import Combine
@testable import Sotto

@MainActor
struct FailureRegistryTests {

    @Test func publishIncrementsUnresolvedAndSetsCurrent() async throws {
        let registry = FailureRegistry()
        #expect(registry.unresolvedCount == 0)
        #expect(registry.current == nil)

        registry.publish(reason: "First")
        #expect(registry.unresolvedCount == 1)
        #expect(registry.current?.reason == "First")

        registry.publish(reason: "Second")
        #expect(registry.unresolvedCount == 2)
        #expect(registry.current?.reason == "Second")
    }

    @Test func acknowledgeMatchingIdClearsCurrent() async throws {
        let registry = FailureRegistry()
        registry.publish(reason: "Boom")
        let id = try #require(registry.current?.id)

        registry.acknowledge(id)
        #expect(registry.current == nil)
        #expect(registry.unresolvedCount == 0)
    }

    @Test func acknowledgeNonMatchingIdLeavesCurrentButDecrements() async throws {
        let registry = FailureRegistry()
        registry.publish(reason: "Boom")
        let foreignId = UUID()

        registry.acknowledge(foreignId)
        // current stays — id didn't match the latest event
        #expect(registry.current?.reason == "Boom")
        // unresolvedCount still decrements; ack semantics are "user saw something"
        #expect(registry.unresolvedCount == 0)
    }

    @Test func clearAllResetsBoth() async throws {
        let registry = FailureRegistry()
        registry.publish(reason: "A")
        registry.publish(reason: "B")
        registry.publish(reason: "C")
        #expect(registry.unresolvedCount == 3)

        registry.clearAll()
        #expect(registry.current == nil)
        #expect(registry.unresolvedCount == 0)
    }

    @Test func attachToPublisherRoutesEvents() async throws {
        let registry = FailureRegistry()
        let subject = PassthroughSubject<FailureEvent, Never>()
        registry.attach(to: subject.eraseToAnyPublisher())

        subject.send(FailureEvent(reason: "From publisher"))
        // Allow the receive(on: DispatchQueue.main) hop to land.
        await Task.yield()

        #expect(registry.current?.reason == "From publisher")
        #expect(registry.unresolvedCount == 1)
    }
}
