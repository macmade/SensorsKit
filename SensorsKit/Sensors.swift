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
/// On initialization the object starts a dedicated background thread whose run
/// loop samples the IOHID and SMC sensors once per second. Each sample is
/// accumulated into a ``SensorHistoryData`` instance, and the aggregated list
/// is republished on the main queue through the key-value-observable ``data``
/// property.
///
/// SMC readings are classified into their kind heuristically, from the sensor
/// key's name prefix, so their kind and labeling should be treated as
/// best-effort: some values may be mislabeled and some sensors omitted.
///
/// Call ``stop(completion:)`` to end the polling loop, or simply release the
/// object — the loop holds only a weak reference to it, so dropping the last
/// reference stops the loop and deallocates the object rather than leaking.
@objc
public class Sensors: NSObject, Synchronizable
{
    /// The interval, in seconds, between polling passes.
    ///
    /// It is also the maximum time the run loop blocks before re-checking
    /// whether it should keep running, so a lost wake-up delays teardown by at
    /// most this interval instead of hanging.
    private static let pollInterval: TimeInterval = 1

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
    ///
    /// Read from the polling thread and written by ``stop(completion:)`` and
    /// `deinit`, so it is only accessed inside ``synchronized(closure:)``.
    private var shouldRun = true

    /// Whether the polling loop has fully stopped and torn down.
    ///
    /// Once `true`, ``stop(completion:)`` invokes its completion immediately
    /// rather than queuing it. Only accessed inside ``synchronized(closure:)``.
    private var stopped = false

    /// The completion closures awaiting the polling loop's full stop.
    ///
    /// Only accessed inside ``synchronized(closure:)``.
    private var completions = [ () -> Void ]()

    /// The Core Foundation run loop driving the dedicated polling thread.
    ///
    /// Captured once the thread starts so ``stop(completion:)`` and `deinit`
    /// can wake it for prompt teardown. Only accessed inside
    /// ``synchronized(closure:)``.
    private var runLoop: CFRunLoop?

    /// Creates the object and immediately starts polling sensors on a dedicated
    /// background thread.
    ///
    /// The thread owns a run loop that fires a repeating timer every
    /// ``pollInterval`` seconds. Both the thread body and the timer hold only a
    /// weak reference to the object, so it can be released and torn down through
    /// `deinit` even if ``stop(completion:)`` is never called.
    @objc
    public override init()
    {
        super.init()

        let thread = Thread
        {
            [ weak self ] in

            let runLoop = RunLoop.current
            let timer   = Timer( timeInterval: Sensors.pollInterval, repeats: true )
            {
                [ weak self ] _ in self?.readSensors()
            }

            self?.pollingLoopDidStart( runLoop: runLoop.getCFRunLoop() )
            runLoop.add( timer, forMode: .default )
            self?.readSensors()

            while self?.shouldKeepPolling() ?? false
            {
                CFRunLoopRunInMode( CFRunLoopMode.defaultMode, Sensors.pollInterval, false )
            }

            timer.invalidate()
            self?.pollingLoopDidStop()
        }

        thread.name             = "com.xs-labs.SensorsKit.Sensors.polling"
        thread.qualityOfService = .background

        thread.start()
    }

    /// Stops the polling loop when the object is released.
    ///
    /// Requests the loop to end and wakes its run loop so the dedicated thread
    /// exits promptly, then invokes any completion closures still awaiting the
    /// stop. Because the running loop holds only a weak reference to the object,
    /// dropping the last external reference reaches this `deinit` rather than
    /// leaking.
    deinit
    {
        let completions = self.takePendingCompletions()

        self.synchronized { self.shouldRun = false }
        self.wakeRunLoop()

        completions.forEach { $0() }
    }

    /// Requests that the background polling loop stop.
    ///
    /// If the loop is still running, `completion` is queued and invoked once the
    /// loop has fully stopped; the published ``data`` is cleared asynchronously
    /// on the main queue, so it may still be non-empty when `completion` runs.
    /// If the loop has already stopped, `completion` is invoked immediately.
    /// Calling this method more than once is safe: each call's `completion` is
    /// invoked exactly once.
    ///
    /// The completion may run on an arbitrary thread — the polling thread, or
    /// the thread that releases the object — so dispatch to the main queue
    /// yourself if it touches the UI.
    ///
    /// - Parameter completion: A closure invoked once the loop has stopped.
    @objc
    public func stop( completion: ( () -> Void )? )
    {
        let alreadyStopped = self.synchronized
        {
            () -> Bool in

            if self.stopped
            {
                return true
            }

            if let completion = completion
            {
                self.completions.append( completion )
            }

            self.shouldRun = false

            return false
        }

        if alreadyStopped
        {
            completion?()

            return
        }

        self.wakeRunLoop()
    }

    /// Records the run loop of the dedicated polling thread.
    ///
    /// - Parameter runLoop: The Core Foundation run loop to wake on stop.
    private func pollingLoopDidStart( runLoop: CFRunLoop )
    {
        self.synchronized { self.runLoop = runLoop }
    }

    /// Whether the polling loop should perform another pass.
    ///
    /// - Returns: `true` while polling should continue.
    private func shouldKeepPolling() -> Bool
    {
        return self.synchronized { self.shouldRun }
    }

    /// Finalizes the polling loop once it has stopped.
    ///
    /// Clears the published ``data`` on the main queue and invokes any
    /// completion closures awaiting the stop.
    private func pollingLoopDidStop()
    {
        let completions = self.takePendingCompletions()

        DispatchQueue.main.async
        {
            self.data = []
        }

        completions.forEach { $0() }
    }

    /// Marks the loop as stopped and returns the pending completion closures.
    ///
    /// Returns an empty array if the loop was already marked stopped, so the
    /// completions are invoked exactly once even when both the polling thread
    /// and `deinit` reach this point.
    ///
    /// - Returns: The completion closures to invoke.
    private func takePendingCompletions() -> [ () -> Void ]
    {
        return self.synchronized
        {
            if self.stopped
            {
                return []
            }

            self.stopped = true

            let completions  = self.completions
            self.completions = []

            return completions
        }
    }

    /// Wakes the polling run loop so it re-checks whether to keep running.
    ///
    /// Called after ``shouldRun`` is cleared so a blocked run loop returns
    /// promptly instead of waiting for its backstop timeout.
    private func wakeRunLoop()
    {
        let runLoop = self.synchronized { self.runLoop }

        if let runLoop = runLoop
        {
            CFRunLoopStop( runLoop )
        }
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
        let sorted  = Sensors.sorted( [ SensorHistoryData ]( sensors.values ) )

        DispatchQueue.main.async
        {
            self.data    = sorted
            self.loading = false
        }
    }

    /// The fixed locale used to order sensor names.
    ///
    /// A specific, host-independent locale (`en_US`) is used so the name
    /// ordering does not vary with the machine's current locale, keeping the
    /// published order deterministic across machines.
    private static let sortLocale = Locale( identifier: "en_US" )

    /// Sorts sensor histories into a stable, deterministic order.
    ///
    /// The histories are ordered by `source`, then `kind`, then `name`. The
    /// `name` comparison uses the fixed ``sortLocale`` with the numeric and
    /// case-insensitive options, so names sort the way a person reads them:
    /// case is ignored (`"apple"` interleaves with `"Zebra"`) and embedded
    /// numbers compare by value (`"Core 2"` precedes `"Core 10"`). When the
    /// locale-aware comparison treats two names as equal, a plain code-point
    /// comparison breaks the tie so the result stays a total order.
    ///
    /// Because a source, kind and name triple uniquely identifies a history,
    /// this ordering is total and the same set of histories always produces the
    /// same sequence — so a consumer binding ``data`` to a table or list no
    /// longer sees its rows shuffle arbitrarily between polling passes.
    ///
    /// - Parameter sensors: The histories to order.
    ///
    /// - Returns: The histories sorted by their composite key.
    static func sorted( _ sensors: [ SensorHistoryData ] ) -> [ SensorHistoryData ]
    {
        return sensors.sorted
        {
            lhs, rhs in

            if lhs.source.rawValue != rhs.source.rawValue
            {
                return lhs.source.rawValue < rhs.source.rawValue
            }

            if lhs.kind.rawValue != rhs.kind.rawValue
            {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }

            let order = lhs.name.compare( rhs.name, options: [ .numeric, .caseInsensitive ], range: nil, locale: Sensors.sortLocale )

            if order != .orderedSame
            {
                return order == .orderedAscending
            }

            return lhs.name < rhs.name
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

    /// Reads all SMC keys and records those with a floating-point value,
    /// classifying each by its key-name prefix: `T` as thermal, `V` as voltage
    /// and `I` as current.
    ///
    /// This prefix classification is a **best-effort heuristic**, not an exact
    /// mapping — the SMC exposes no type metadata for its keys:
    ///
    /// - Not every `T`, `V` or `I` key is actually a temperature, voltage or
    ///   current reading; a key may carry the prefix by coincidence and still be
    ///   surfaced under that kind.
    /// - A non-sensor key whose value is a `Double` or `Float32` is recorded,
    ///   and may therefore be mislabeled; keys of any other value type (integers,
    ///   booleans, strings, and so on) are ignored.
    /// - Keys whose name does not start with `T`, `V` or `I` are dropped, so
    ///   some genuine sensors may be omitted.
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
