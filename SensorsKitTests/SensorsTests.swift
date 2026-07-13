/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2026, Jean-David Gadina - www.xs-labs.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the Software), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 ******************************************************************************/

import Foundation
import Testing
@testable import SensorsKit

/// Lifecycle tests for ``Sensors``.
///
/// These tests intentionally make no assertions about actual sensor readings,
/// which depend on the host hardware and are therefore nondeterministic. They
/// only exercise the observable object's own state machine.
@Suite( "Sensors" )
struct SensorsTests
{
    /// A newly created object reports its initial, pre-polling state.
    ///
    /// The test runs on the main actor so that the first background polling
    /// pass — which republishes ``Sensors/data`` and clears ``Sensors/loading``
    /// through `DispatchQueue.main.async` — cannot run before the assertions,
    /// keeping the initial state deterministic.
    @Test
    @MainActor
    func newlyCreatedSensorsIsLoading()
    {
        let sensors = Sensors()

        #expect( sensors.loading )
        #expect( sensors.data.isEmpty )

        sensors.stop( completion: nil )
    }

    /// Stopping the object eventually invokes the completion closure.
    @Test( .timeLimit( .minutes( 1 ) ) )
    func stopInvokesCompletion() async
    {
        let sensors = Sensors()

        await withCheckedContinuation
        {
            continuation in sensors.stop { continuation.resume() }
        }
    }

    /// The ordering helper produces a stable, deterministic order regardless of
    /// the input order.
    ///
    /// Histories are sorted by the composite key
    /// `(source.rawValue, kind.rawValue, name)`, so the same set always yields
    /// the same order — even when the source dictionary enumerates its values
    /// differently between polling passes.
    @Test
    func sortedProducesDeterministicOrder()
    {
        let a = SensorHistoryData( source: .hid, kind: .thermal, name: "A" )
        let b = SensorHistoryData( source: .hid, kind: .thermal, name: "B" )
        let c = SensorHistoryData( source: .hid, kind: .voltage, name: "A" )
        let d = SensorHistoryData( source: .smc, kind: .thermal, name: "A" )

        let expected = [ a, b, c, d ]

        let firstPass  = Sensors.sorted( [ d, b, a, c ] )
        let secondPass = Sensors.sorted( [ c, a, d, b ] )

        #expect( firstPass == expected )
        #expect( secondPass == expected )
        #expect( firstPass == secondPass )
    }

    /// Names are ordered case-insensitively and with numeric awareness.
    ///
    /// Within a single source and kind, `name` is compared using a fixed
    /// `en_US` locale with the numeric and case-insensitive options, so
    /// `"Core 2"` precedes `"Core 10"` (numeric, not lexicographic) and
    /// `"apple"`/`"Zebra"` interleave by letter rather than by case.
    @Test
    func sortedUsesCaseInsensitiveNaturalOrdering()
    {
        let apple  = SensorHistoryData( source: .hid, kind: .thermal, name: "apple" )
        let core2  = SensorHistoryData( source: .hid, kind: .thermal, name: "Core 2" )
        let core10 = SensorHistoryData( source: .hid, kind: .thermal, name: "Core 10" )
        let zebra  = SensorHistoryData( source: .hid, kind: .thermal, name: "Zebra" )

        let expected = [ apple, core2, core10, zebra ]
        let sorted   = Sensors.sorted( [ core10, zebra, core2, apple ] )

        #expect( sorted == expected )
    }

    /// Names that the locale-aware comparison treats as equal are still ordered
    /// deterministically.
    ///
    /// `"TC0P"` and `"tc0p"` compare as equal under the case-insensitive
    /// comparison, so the helper falls back to a plain code-point tie-break to
    /// keep the overall order a total order — the same input set always yields
    /// the same sequence regardless of the input order.
    @Test
    func sortedIsDeterministicForCollationEquivalentNames()
    {
        let upper = SensorHistoryData( source: .smc, kind: .thermal, name: "TC0P" )
        let lower = SensorHistoryData( source: .smc, kind: .thermal, name: "tc0p" )

        let firstPass  = Sensors.sorted( [ upper, lower ] )
        let secondPass = Sensors.sorted( [ lower, upper ] )

        #expect( firstPass == secondPass )
    }

    /// Calling ``Sensors/stop(completion:)`` invokes its completion exactly
    /// once.
    @Test( .timeLimit( .minutes( 1 ) ) )
    func stopInvokesCompletionExactlyOnce() async
    {
        let sensors = Sensors()
        let counter = CallCounter()

        await withCheckedContinuation
        {
            continuation in sensors.stop { counter.increment(); continuation.resume() }
        }

        try? await Task.sleep( nanoseconds: 300_000_000 )

        #expect( counter.value == 1 )
    }

    /// A second ``Sensors/stop(completion:)`` still invokes its completion.
    ///
    /// The first call stops the loop; the second is made once the loop has
    /// already stopped and must still invoke its completion rather than
    /// discarding it, so an awaiting caller never hangs.
    @Test( .timeLimit( .minutes( 1 ) ) )
    func secondStopStillInvokesCompletion() async
    {
        let sensors = Sensors()

        await withCheckedContinuation
        {
            continuation in sensors.stop { continuation.resume() }
        }

        await withCheckedContinuation
        {
            continuation in sensors.stop { continuation.resume() }
        }
    }

    /// Releasing a ``Sensors`` without calling ``Sensors/stop(completion:)``
    /// lets it deallocate.
    ///
    /// The polling loop holds only a weak reference to the object, so dropping
    /// the last external reference must let it deallocate rather than leak.
    @Test( .timeLimit( .minutes( 1 ) ) )
    func deallocatesWhenReleasedWithoutStop() async
    {
        weak var weakSensors: Sensors?

        do
        {
            let sensors = Sensors()
            weakSensors = sensors

            #expect( weakSensors != nil )
        }

        for _ in 0 ..< 100
        {
            if weakSensors == nil
            {
                break
            }

            try? await Task.sleep( nanoseconds: 50_000_000 )
        }

        #expect( weakSensors == nil )
    }

    /// Stopping an already-stopped object invokes its completion promptly.
    ///
    /// Once the loop has fully stopped, a further ``Sensors/stop(completion:)``
    /// takes the immediate path — it does not wait on the polling loop — so its
    /// completion fires near-instantly, independent of the hardware polling
    /// duration. (The teardown of a *running* loop is instead bounded by the
    /// in-flight polling pass, so it is not asserted here with a wall-clock
    /// bound.)
    @Test( .timeLimit( .minutes( 1 ) ) )
    func repeatStopCompletesPromptly() async
    {
        let sensors = Sensors()

        await withCheckedContinuation
        {
            continuation in sensors.stop { continuation.resume() }
        }

        let start = Date()

        await withCheckedContinuation
        {
            continuation in sensors.stop { continuation.resume() }
        }

        #expect( Date().timeIntervalSince( start ) < 0.5 )
    }
}

/// A thread-safe counter used to assert how many times a closure runs.
private final class CallCounter: @unchecked Sendable
{
    /// The lock serializing access to ``count``.
    private let lock = NSLock()

    /// The number of recorded calls.
    private var count = 0

    /// Records one call.
    func increment()
    {
        self.lock.lock()

        self.count += 1

        self.lock.unlock()
    }

    /// The number of recorded calls.
    var value: Int
    {
        self.lock.lock()

        defer
        {
            self.lock.unlock()
        }

        return self.count
    }
}
