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
import SensorsKit

/// Unit tests for ``Synchronizable``.
@Suite( "Synchronizable" )
struct SynchronizableTests
{
    /// A minimal ``Synchronizable`` conformer whose mutable state is only ever
    /// touched from inside a synchronized block.
    private final class Counter: Synchronizable
    {
        /// The backing value, guarded by ``Synchronizable/synchronized(closure:)``.
        private var value = 0

        /// The current value, read inside a synchronized block.
        var current: Int
        {
            return self.synchronized { self.value }
        }

        /// Atomically increments the value.
        func increment()
        {
            self.synchronized { self.value += 1 }
        }
    }

    /// The instance-level helper returns the value produced by its closure.
    @Test
    func instanceSynchronizedReturnsClosureValue()
    {
        let counter = Counter()
        let result  = counter.synchronized { 42 }

        #expect( result == 42 )
    }

    /// The instance-level helper actually executes its closure.
    @Test
    func instanceSynchronizedRunsClosure()
    {
        let counter = Counter()

        counter.increment()

        #expect( counter.current == 1 )
    }

    /// The type-level helper returns the value produced by its closure.
    @Test
    func staticSynchronizedReturnsClosureValue()
    {
        let result = Counter.synchronized { "value" }

        #expect( result == "value" )
    }

    /// Concurrent access serialized through the helper never loses an update.
    @Test
    func synchronizedSerializesConcurrentAccess()
    {
        let counter    = Counter()
        let iterations = 10_000

        DispatchQueue.concurrentPerform( iterations: iterations )
        {
            _ in counter.increment()
        }

        #expect( counter.current == iterations )
    }
}
