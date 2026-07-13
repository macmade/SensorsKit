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
}
