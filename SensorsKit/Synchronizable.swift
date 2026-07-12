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

/// A type that can serialize access to critical sections using the
/// Objective-C synchronization primitives.
///
/// Conforming types gain a type-level and an instance-level
/// ``synchronized(closure:)`` helper. Each wraps a closure between
/// `objc_sync_enter` and `objc_sync_exit`, guaranteeing that closures
/// synchronized on the same token never run concurrently.
public protocol Synchronizable
{
    /// Runs a closure while holding the lock associated with the conforming
    /// type.
    ///
    /// - Parameter closure: The work to perform inside the critical section.
    /// - Returns:           The value returned by `closure`.
    static func synchronized< T >( closure: () -> T ) -> T

    /// Runs a closure while holding the lock associated with the conforming
    /// instance.
    ///
    /// - Parameter closure: The work to perform inside the critical section.
    /// - Returns:           The value returned by `closure`.
    func synchronized< T >( closure: () -> T ) -> T
}

/// Default implementations of ``Synchronizable`` backed by
/// `objc_sync_enter` / `objc_sync_exit`.
public extension Synchronizable
{
    /// Runs a closure while holding the lock associated with the conforming
    /// type, using the type itself as the synchronization token.
    ///
    /// - Parameter closure: The work to perform inside the critical section.
    /// - Returns:           The value returned by `closure`.
    static func synchronized< T >( closure: () -> T ) -> T
    {
        objc_sync_enter( self )

        let r = closure()

        objc_sync_exit( self )

        return r
    }

    /// Runs a closure while holding the lock associated with the conforming
    /// instance, using the instance itself as the synchronization token.
    ///
    /// - Parameter closure: The work to perform inside the critical section.
    /// - Returns:           The value returned by `closure`.
    func synchronized< T >( closure: () -> T ) -> T
    {
        objc_sync_enter( self )

        let r = closure()

        objc_sync_exit( self )

        return r
    }
}
