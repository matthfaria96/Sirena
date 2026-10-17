// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted for Sirena: the pieces of Vorssaint's mixer that the island's live
// equalizer reads (IslandMixerRender.swift, IslandResponsibleProcess.swift and parts of
// IslandAudioOutput.swift / MixerRoutingSupport.swift).

import Accelerate
import AppKit
import CoreAudio
import Darwin

enum IslandAudioObjects {
    /// Every process object the audio HAL knows about.
    static func audioProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let object = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size).filter { $0 != 0 }
    }

    static let owningAppSearchDepth = 6

    static func owningRegularAppPid(responsiblePid: pid_t,
                                    isRegularApp: (pid_t) -> Bool,
                                    parentPid: (pid_t) -> pid_t) -> pid_t? {
        guard responsiblePid > 0 else { return nil }
        if isRegularApp(responsiblePid) { return responsiblePid }
        var current = responsiblePid
        for _ in 0..<owningAppSearchDepth {
            current = parentPid(current)
            guard current > 1 else { return nil }
            if isRegularApp(current) { return current }
        }
        return nil
    }
}

/// Vorssaint corrects a tap's level for outputs with more than two channels.
/// Sirena has no mixer to share that work with, so the equalizer reads the
/// tap as it comes: the bars only move a little less on such outputs.
final class IslandLevelCompensationWatch {
    static func started(objects: [AudioObjectID], store: @escaping (Float) -> Void) -> IslandLevelCompensationWatch {
        store(1)
        return IslandLevelCompensationWatch()
    }

    func stop() {}
}

enum IslandMixerRender {
    /// How many frames a buffer holds.
    static func frames(bytes: UInt32, channels: UInt32) -> Int {
        guard channels > 0 else { return 0 }
        return Int(bytes) / (MemoryLayout<Float>.size * Int(channels))
    }

    /// Which input buffer carries the tap.
    ///
    /// An aggregate presents what its sub-device records first and the tap
    /// after it, so on an output device that also has a microphone the tap is
    /// not buffer zero: rendering that one plays the microphone's silence and
    /// the app goes quiet. The tap is the last buffer with the shape the tap
    /// announced.
    ///
    /// With nothing matching that shape, the tap can still be claimed when the
    /// device brings no input of its own: a single buffer has nowhere else to
    /// come from. Guessing among several would mean playing the device's own
    /// microphone out of its speakers, so the app stays silent instead.
    static func tapBufferIndex(in buffers: UnsafeMutableAudioBufferListPointer,
                               tapChannels: Int) -> Int? {
        var lone: Int?
        for index in stride(from: buffers.count - 1, through: 0, by: -1)
        where buffers[index].mData != nil && buffers[index].mNumberChannels > 0 {
            if Int(buffers[index].mNumberChannels) == tapChannels { return index }
            if buffers.count == 1 { lone = index }
        }
        return lone
    }

    /// Which source channel feeds one output channel, or nil when the device
    /// has more channels than the tap can fill and the rest must stay silent.
    static func sourceChannel(for outputChannel: Int, sourceChannels: Int) -> Int? {
        if outputChannel < sourceChannels { return outputChannel }
        // A single-channel source belongs in both front channels, not just
        // the left one.
        if sourceChannels == 1, outputChannel == 1 { return 0 }
        return nil
    }

    /// Silences every output frame from `frame` on.
    ///
    /// The output buffer is handed over dirty: it holds whatever CoreAudio
    /// last put in that memory. Frames the tap cannot fill — the tail of a
    /// buffer longer than the tap's, or the whole buffer on a cycle with no
    /// tap to read — used to be left as they were found and played back as a
    /// fragment of older audio (issue #326). Silence is the right content for
    /// a frame with no samples behind it.
    static func silence(_ output: UnsafeMutableAudioBufferListPointer, from frame: Int = 0) {
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0,
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let unwritten = frames(bytes: buffer.mDataByteSize,
                                   channels: buffer.mNumberChannels) - frame
            guard unwritten > 0 else { continue }
            vDSP_vclr(destination + frame * channels, 1, vDSP_Length(unwritten * channels))
        }
    }

    /// Renders one interleaved source buffer onto the output, scaled by
    /// `gain`, and answers how many frames it wrote. Whatever it does not
    /// write it silences, so the caller never has to think about the tail.
    @discardableResult
    static func render(source: AudioBuffer,
                       into output: UnsafeMutableAudioBufferListPointer,
                       gain: Float) -> Int {
        var written = 0
        defer { silence(output, from: written) }
        let sourceChannels = Int(source.mNumberChannels)
        guard sourceChannels > 0,
              let samples = source.mData?.assumingMemoryBound(to: Float.self) else { return 0 }

        var frames = self.frames(bytes: source.mDataByteSize, channels: source.mNumberChannels)
        var outputChannels = 0
        var hasWritableOutput = false
        for buffer in output where buffer.mNumberChannels > 0 {
            outputChannels += Int(buffer.mNumberChannels)
            guard buffer.mData != nil else { continue }
            hasWritableOutput = true
            frames = min(frames, self.frames(bytes: buffer.mDataByteSize,
                                             channels: buffer.mNumberChannels))
        }
        guard frames > 0, outputChannels > 0, hasWritableOutput else { return 0 }
        var gain = gain

        // The usual shape: one interleaved buffer wanting exactly what the
        // tap produced. One pass, nothing to map.
        if output.count == 1, Int(output[0].mNumberChannels) == sourceChannels,
           let destination = output[0].mData?.assumingMemoryBound(to: Float.self) {
            vDSP_vsmul(samples, 1, &gain, destination, 1, vDSP_Length(frames * sourceChannels))
            written = frames
            return written
        }

        // One channel to play with: fold the source into it instead of
        // handing over every other sample.
        if outputChannels == 1, sourceChannels > 1 {
            guard let buffer = output.first(where: { $0.mNumberChannels == 1 && $0.mData != nil }),
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
            var scale = gain / Float(sourceChannels)
            vDSP_vsmul(samples, vDSP_Stride(sourceChannels), &scale,
                       destination, 1, vDSP_Length(frames))
            for channel in 1..<sourceChannels {
                vDSP_vsma(samples + channel, vDSP_Stride(sourceChannels), &scale,
                          destination, 1, destination, 1, vDSP_Length(frames))
            }
            written = frames
            return written
        }

        var firstOutputChannel = 0
        var didWriteSourceChannel = false
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            defer { firstOutputChannel += channels }
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for channel in 0..<channels {
                guard let sourceChannel = sourceChannel(for: firstOutputChannel + channel,
                                                        sourceChannels: sourceChannels) else {
                    vDSP_vclr(destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
                    continue
                }
                didWriteSourceChannel = true
                vDSP_vsmul(samples + sourceChannel, vDSP_Stride(sourceChannels), &gain,
                           destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
            }
        }
        written = didWriteSourceChannel ? frames : 0
        return written
    }
}

enum IslandResponsibleProcess {
    /// `responsibility_get_pid_responsible_for_pid`, exported by libsystem and
    /// used by the system for the same grouping; resolved at runtime so a
    /// missing symbol degrades to per-process rows instead of breaking.
    private static let resolve: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */,
                                 "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    static func owner(of pid: pid_t) -> pid_t {
        guard let resolve else { return pid }
        let owner = resolve(pid)
        return owner > 0 ? owner : pid
    }

    /// The regular app to bill the process to, following the parent chain
    /// when the responsibility API dead-ends on a helper that answers for
    /// itself (browser audio helpers, issue #256). Nil when no ancestor is
    /// a regular app — daemons and login items stay unlisted.
    static func regularAppOwner(of pid: pid_t) -> NSRunningApplication? {
        let responsible = owner(of: pid)
        let isRegular: (pid_t) -> Bool = { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular }
        let parent: (pid_t) -> pid_t = parent(of:)
        let resolved = IslandAudioObjects.owningRegularAppPid(
            responsiblePid: responsible,
            isRegularApp: isRegular,
            parentPid: parent
        ) ?? (responsible != pid ? IslandAudioObjects.owningRegularAppPid(
            responsiblePid: pid,
            isRegularApp: isRegular,
            parentPid: parent
        ) : nil)
        return resolved.flatMap(NSRunningApplication.init(processIdentifier:))
    }

    private static func parent(of pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return pid_t(info.pbi_ppid)
    }
}
