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

/// Stores a rolling history of readings for a single hardware sensor.
///
/// An instance keeps the most recent samples (capped at 50) reported by a
/// sensor and exposes derived, key-value-observable statistics such as the
/// minimum, maximum and last recorded value. Access to the underlying sample
/// buffer is serialized through ``Synchronizable`` so values can be added from
/// a background queue while observers read from the main queue.
@objc
public class SensorHistoryData: NSObject, Synchronizable
{
    /// The physical quantity measured by a sensor.
    @objc( SensorHistoryDataKind )
    public enum Kind: Int, CustomStringConvertible
    {
        /// A temperature reading.
        case thermal

        /// A voltage reading.
        case voltage

        /// An electrical current reading.
        case current

        /// An ambient light reading.
        case ambientLight

        /// A lowercase, human-readable name for the kind.
        public var description: String
        {
            switch self
            {
                case .thermal:      return "thermal"
                case .voltage:      return "voltage"
                case .current:      return "current"
                case .ambientLight: return "ambientLight"
            }
        }
    }

    /// The subsystem a sensor reading originates from.
    @objc( SensorHistoryDataSource )
    public enum Source: Int, CustomStringConvertible
    {
        /// The IOHID subsystem.
        case hid

        /// The System Management Controller (SMC).
        case smc

        /// A human-readable name for the source.
        public var description: String
        {
            switch self
            {
                case .hid: return "IOHID"
                case .smc: return "SMC"
            }
        }
    }

    /// The subsystem the sensor readings originate from.
    @objc public private( set ) dynamic var source: Source

    /// The physical quantity the sensor measures.
    @objc public private( set ) dynamic var kind: Kind

    /// The name identifying the sensor.
    @objc public private( set ) dynamic var name: String

    /// The recorded samples, kept as a rolling window of the 50 most recent
    /// values. Always accessed inside a ``synchronized(closure:)`` block.
    private var data: [ Double ] = []

    /// The recorded samples, boxed as `NSNumber` values for Objective-C and
    /// key-value observing interoperability.
    @objc public dynamic var values: [ NSNumber ]
    {
        return self.synchronized
        {
            return self.data.map { NSNumber( floatLiteral: $0 ) }
        }
    }

    /// The smallest recorded value, or `nil` when no sample has been recorded
    /// yet.
    @objc public dynamic var min: NSNumber?
    {
        return self.synchronized
        {
            guard let value = self.data.min()
            else
            {
                return nil
            }

            return NSNumber( floatLiteral: value )
        }
    }

    /// The largest recorded value, or `nil` when no sample has been recorded
    /// yet.
    @objc public dynamic var max: NSNumber?
    {
        return self.synchronized
        {
            guard let value = self.data.max()
            else
            {
                return nil
            }

            return NSNumber( floatLiteral: value )
        }
    }

    /// The most recently recorded value, or `nil` when no sample has been
    /// recorded yet.
    @objc public dynamic var last: NSNumber?
    {
        return self.synchronized
        {
            guard let last = self.data.last
            else
            {
                return nil
            }

            return NSNumber( floatLiteral: last )
        }
    }

    /// Creates a history container for a sensor.
    ///
    /// - Parameters:
    ///   - source: The subsystem the readings originate from.
    ///   - kind:   The physical quantity the sensor measures.
    ///   - name:   The name identifying the sensor.
    @objc
    public init( source: Source, kind: Kind, name: String )
    {
        self.source = source
        self.kind   = kind
        self.name   = name
    }

    /// Records a new sample.
    ///
    /// The value is appended to the history, which is then trimmed to its 50
    /// most recent samples. Key-value-observing change notifications for the
    /// derived ``values``, ``min``, ``max`` and ``last`` properties are posted
    /// asynchronously on the main queue, after the sample has already been
    /// stored. Because the buffer is updated synchronously but the notifications
    /// are delivered asynchronously, an observer that re-reads the state when
    /// notified sees the latest samples and may not observe every intermediate
    /// value individually.
    ///
    /// - Parameter value: The value to record.
    @objc( addValue: )
    public func add( value: Double )
    {
        self.synchronized
        {
            var data = self.data

            data.append( value )

            self.data = data.suffix( 50 )

            DispatchQueue.main.async
            {
                self.willChangeValue( for: \.values )
                self.willChangeValue( for: \.min )
                self.willChangeValue( for: \.max )
                self.willChangeValue( for: \.last )

                self.didChangeValue( for: \.values )
                self.didChangeValue( for: \.min )
                self.didChangeValue( for: \.max )
                self.didChangeValue( for: \.last )
            }
        }
    }

    /// A textual description including the sensor name, kind and the current
    /// minimum and maximum recorded values.
    ///
    /// The minimum and maximum are read from a single ``synchronized(closure:)``
    /// snapshot of the samples, so they always reflect the same state rather
    /// than two separately locked reads.
    public override var description: String
    {
        let bounds  = self.synchronized { ( minimum: self.data.min(), maximum: self.data.max() ) }
        let minimum = String( format: "%.2f", bounds.minimum ?? 0 )
        let maximum = String( format: "%.2f", bounds.maximum ?? 0 )

        return "\( super.description ): \( self.name ) (\( self.kind ), min: \( minimum ), max: \( maximum ))"
    }
}
