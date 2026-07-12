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

import Cocoa
import IOHIDKit
import SMCKit

/// Periodically polls the machine's hardware sensors and maintains an
/// observable history of their readings.
///
/// On initialization the object starts a background run loop that samples the
/// IOHID and SMC sensors once per second. Each sample is accumulated into a
/// ``SensorHistoryData`` instance, and the aggregated list is republished on
/// the main queue through the key-value-observable ``data`` property. Call
/// ``stop(completion:)`` to end the polling loop.
@objc
public class Sensors: NSObject
{
    /// Whether the initial set of sensor readings has not been produced yet.
    ///
    /// Starts as `true` and becomes `false` after the first polling pass
    /// completes.
    @objc public private( set ) dynamic var loading = true

    /// The current list of sensor histories, republished on the main queue
    /// after every polling pass.
    @objc public private( set ) dynamic var data = [ SensorHistoryData ]()

    /// The sensor histories keyed by a unique identifier derived from source,
    /// kind and sensor name, used to accumulate samples across polling passes.
    @objc private dynamic var sensors = [ String: SensorHistoryData ]()

    /// Whether the background polling loop should keep running.
    private var shouldRun = true

    /// A closure to invoke once the polling loop has fully stopped.
    private var completion: ( () -> Void )?

    /// Creates the object and immediately starts polling sensors on a
    /// background queue.
    @objc
    public override init()
    {
        super.init()

        DispatchQueue.global( qos: .background ).async
        {
            self.run()
        }
    }

    /// Requests that the background polling loop stop.
    ///
    /// If polling has already stopped the call is a no-op and `completion` is
    /// not invoked. Otherwise the loop finishes its current cycle, clears the
    /// published ``data`` and invokes `completion`.
    ///
    /// - Parameter completion: A closure invoked once the loop has stopped.
    @objc
    public func stop( completion: ( () -> Void )? )
    {
        if self.shouldRun == false
        {
            return
        }

        self.completion = completion
        self.shouldRun  = false
    }

    /// Runs the polling loop until ``stop(completion:)`` is called.
    ///
    /// Schedules a repeating timer that samples the sensors every second while
    /// driving the current run loop. Once stopped, it invalidates the timer,
    /// clears the published ``data`` on the main queue and invokes the pending
    /// completion closure.
    private func run()
    {
        let timer = Timer.scheduledTimer( withTimeInterval: 1, repeats: true )
        {
            _ in self.readSensors()
        }

        self.readSensors()
        RunLoop.current.add( timer, forMode: .default )

        while self.shouldRun
        {
            RunLoop.current.run( until: Date( timeIntervalSinceNow: 5 ) )
        }

        timer.invalidate()

        let completion  = self.completion
        self.completion = nil

        DispatchQueue.main.async
        {
            self.data = []
        }

        completion?()
    }

    /// Performs a single polling pass over every sensor source.
    ///
    /// Reads the IOHID and SMC sensors, then republishes the aggregated
    /// histories through ``data`` and clears ``loading`` on the main queue.
    private func readSensors()
    {
        self.readIOHIDSensors()
        self.readSMCSensors()

        let sensors = self.sensors

        DispatchQueue.main.async
        {
            self.data    = [ SensorHistoryData ]( sensors.values )
            self.loading = false
        }
    }

    /// Reads the temperature, voltage, current and ambient light sensors
    /// exposed through the IOHID subsystem and records their values.
    private func readIOHIDSensors()
    {
        IOHID.shared.readTemperatureSensors().forEach  { self.addSensorHistoryData( data: $0, kind: .thermal ) }
        IOHID.shared.readVoltageSensors().forEach      { self.addSensorHistoryData( data: $0, kind: .voltage ) }
        IOHID.shared.readCurrentSensors().forEach      { self.addSensorHistoryData( data: $0, kind: .current ) }
        IOHID.shared.readAmbientLightSensors().forEach { self.addSensorHistoryData( data: $0, kind: .ambientLight ) }
    }

    /// Reads all SMC keys and records them, classifying each as thermal,
    /// voltage or current based on its key name prefix (`T`, `V` or `I`).
    private func readSMCSensors()
    {
        let all = SMC.shared.readAllKeys()

        all.filter { $0.keyName.hasPrefix( "T" ) }.forEach { self.addSensorHistoryData( data: $0, kind: .thermal ) }
        all.filter { $0.keyName.hasPrefix( "V" ) }.forEach { self.addSensorHistoryData( data: $0, kind: .voltage ) }
        all.filter { $0.keyName.hasPrefix( "I" ) }.forEach { self.addSensorHistoryData( data: $0, kind: .current ) }
    }

    /// Records a reading coming from the IOHID subsystem.
    ///
    /// Looks up (or lazily creates) the ``SensorHistoryData`` matching the
    /// reading's kind and name, then appends the new value.
    ///
    /// - Parameters:
    ///   - data: The IOHID reading to record.
    ///   - kind: The physical quantity the reading represents.
    private func addSensorHistoryData( data: IOHIDData, kind: SensorHistoryData.Kind )
    {
        let key = String( format: "IOHID.%llu.%@", kind.rawValue, data.name )

        if self.sensors[ key ] == nil
        {
            self.sensors[ key ] = SensorHistoryData( source: .hid, kind: kind, name: data.name )
        }

        self.sensors[ key ]?.add( value: data.value )
    }

    /// Records a reading coming from the SMC subsystem.
    ///
    /// Readings whose value is neither a `Double` nor a `Float32` are ignored.
    /// Otherwise the value is looked up (or lazily created) by kind and key
    /// name and the new value is appended.
    ///
    /// - Parameters:
    ///   - data: The SMC reading to record.
    ///   - kind: The physical quantity the reading represents.
    private func addSensorHistoryData( data: SMCData, kind: SensorHistoryData.Kind )
    {
        let value: Double

        if let f = data.value as? Double
        {
            value = f
        }
        else if let f = data.value as? Float32
        {
            value = Double( f )
        }
        else
        {
            return
        }

        let key = String( format: "SMC.%llu.%@", kind.rawValue, data.keyName )

        if self.sensors[ key ] == nil
        {
            self.sensors[ key ] = SensorHistoryData( source: .smc, kind: kind, name: data.keyName )
        }

        self.sensors[ key ]?.add( value: value )
    }
}
