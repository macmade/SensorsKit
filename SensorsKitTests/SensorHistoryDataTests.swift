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

/// Unit tests for ``SensorHistoryData``.
@Suite( "SensorHistoryData" )
struct SensorHistoryDataTests
{
    /// Returns the boxed `values` of a history as an array of `Double`.
    ///
    /// - Parameter data: The history whose values are read.
    /// - Returns:        The recorded values, unboxed from `NSNumber`.
    private func values( of data: SensorHistoryData ) -> [ Double ]
    {
        return data.values.map { $0.doubleValue }
    }

    /// A freshly created history exposes its metadata and starts empty.
    @Test
    func newHistoryIsEmpty()
    {
        let data = SensorHistoryData( source: .smc, kind: .thermal, name: "CPU" )

        #expect( data.source == .smc )
        #expect( data.kind   == .thermal )
        #expect( data.name   == "CPU" )
        #expect( self.values( of: data ).isEmpty )
        #expect( data.min  == nil )
        #expect( data.max  == nil )
        #expect( data.last == nil )
    }

    /// Adding a single value populates every derived statistic.
    @Test
    func addingSingleValue()
    {
        let data = SensorHistoryData( source: .hid, kind: .voltage, name: "V" )

        data.add( value: 3.5 )

        #expect( self.values( of: data ) == [ 3.5 ] )
        #expect( data.min?.doubleValue  == 3.5 )
        #expect( data.max?.doubleValue  == 3.5 )
        #expect( data.last?.doubleValue == 3.5 )
    }

    /// The minimum, maximum and last statistics reflect the recorded samples,
    /// regardless of the order in which they were added.
    @Test
    func statisticsReflectRecordedValues()
    {
        let data = SensorHistoryData( source: .hid, kind: .current, name: "I" )

        [ 5.0, 1.0, 9.0, 3.0 ].forEach { data.add( value: $0 ) }

        #expect( self.values( of: data ) == [ 5.0, 1.0, 9.0, 3.0 ] )
        #expect( data.min?.doubleValue  == 1.0 )
        #expect( data.max?.doubleValue  == 9.0 )
        #expect( data.last?.doubleValue == 3.0 )
    }

    /// The history keeps only its 50 most recent samples.
    @Test
    func historyIsCappedAtFiftySamples()
    {
        let data = SensorHistoryData( source: .smc, kind: .thermal, name: "CPU" )

        ( 0 ..< 60 ).forEach { data.add( value: Double( $0 ) ) }

        let values = self.values( of: data )

        #expect( values.count == 50 )
        #expect( values.first == 10.0 )
        #expect( values.last  == 59.0 )
        #expect( data.min?.doubleValue  == 10.0 )
        #expect( data.max?.doubleValue  == 59.0 )
        #expect( data.last?.doubleValue == 59.0 )
    }

    /// Each ``SensorHistoryData/Kind`` maps to its expected description.
    @Test
    func kindDescriptions()
    {
        #expect( SensorHistoryData.Kind.thermal.description      == "thermal" )
        #expect( SensorHistoryData.Kind.voltage.description      == "voltage" )
        #expect( SensorHistoryData.Kind.current.description      == "current" )
        #expect( SensorHistoryData.Kind.ambientLight.description == "ambientLight" )
    }

    /// Each ``SensorHistoryData/Source`` maps to its expected description.
    @Test
    func sourceDescriptions()
    {
        #expect( SensorHistoryData.Source.hid.description == "IOHID" )
        #expect( SensorHistoryData.Source.smc.description == "SMC" )
    }

    /// The textual description mentions the sensor name and kind.
    @Test
    func descriptionMentionsNameAndKind()
    {
        let data = SensorHistoryData( source: .smc, kind: .thermal, name: "CPU" )

        data.add( value: 42.0 )

        #expect( data.description.contains( "CPU" ) )
        #expect( data.description.contains( "thermal" ) )
    }
}
