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
import SensorsKit

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
}
