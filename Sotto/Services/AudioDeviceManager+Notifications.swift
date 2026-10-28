import Foundation
import CoreAudio
import AVFoundation
import os

extension AudioDeviceManager {
    func setupDeviceChangeNotifications() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        
        let status = AudioObjectAddPropertyListener(
            systemObjectID,
            &address,
            { (_, _, _, userData) -> OSStatus in
                let manager = Unmanaged<AudioDeviceManager>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handleDeviceListChange()
                }
                return noErr
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        if status != noErr {
            logger.error("Failed to add device change listener: \(status, privacy: .public)")
        }
    }
    
    private func handleDeviceListChange() {
        loadAvailableDevices { [weak self] in
            guard let self = self else { return }

            if self.inputMode == .systemDefault {
                self.notifyDeviceChange()
                return
            }

            if self.isRecordingActive {
                guard let currentID = self.selectedDeviceID else { return }

                if !self.isDeviceAvailable(currentID) {
                    self.logger.warning("🎙️ Recording device \(currentID, privacy: .public) no longer available - requesting switch")

                    let newDeviceID: AudioDeviceID?
                    if self.inputMode == .prioritized {
                        let sortedDevices = self.prioritizedDevices.sorted { $0.priority < $1.priority }
                        let priorityDeviceID = sortedDevices.compactMap { device in
                            self.availableDevices.first(where: { $0.uid == device.id })?.id
                        }.first

                        if let deviceID = priorityDeviceID {
                            newDeviceID = deviceID
                        } else {
                            newDeviceID = self.findBestAvailableDevice()
                        }
                    } else {
                        newDeviceID = self.findBestAvailableDevice()
                    }

                    if let deviceID = newDeviceID {
                        self.selectedDeviceID = deviceID
                        NotificationCenter.default.post(
                            name: .audioDeviceSwitchRequired,
                            object: nil,
                            userInfo: ["newDeviceID": deviceID]
                        )
                    } else {
                        self.logger.error("No audio input devices available!")
                        NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
                    }
                }
                return
            }

            if self.inputMode == .prioritized {
                self.selectHighestPriorityAvailableDevice()
            } else if self.inputMode == .custom {
                self.reconcileCustomDeviceAfterListChange()
            }
        }
    }
    
    func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        let uid: CFString? = getDeviceProperty(deviceID: deviceID,
                                             selector: kAudioDevicePropertyDeviceUID)
        return uid as String?
    }

    func getDeviceModelUID(deviceID: AudioDeviceID) -> String? {
        let uid: CFString? = getDeviceProperty(deviceID: deviceID,
                                              selector: kAudioDevicePropertyModelUID)
        return uid as String?
    }

    func findAvailableDevice(uid: String, modelUID: String?) -> (id: AudioDeviceID, uid: String, name: String)? {
        if !uid.isEmpty, let found = availableDevices.first(where: { $0.uid == uid }) {
            return found
        }
        if let modelUID, !modelUID.isEmpty,
           let found = availableDevices.first(where: { getDeviceModelUID(deviceID: $0.id) == modelUID }) {
            return found
        }
        return nil
    }

    func rebindPrioritizedDevice(savedUID: String, newUID: String, newModelUID: String?) {
        prioritizedDevices.removeAll { $0.id == newUID && $0.id != savedUID }
        prioritizedDevices = prioritizedDevices.map { device in
            guard device.id == savedUID else { return device }
            return PrioritizedDevice(id: newUID, name: device.name, priority: device.priority, modelUID: newModelUID ?? device.modelUID)
        }
        savePrioritizedDevices()
    }

    func updateCustomDeviceHints(deviceID: AudioDeviceID, uid: String, modelUID: String? = nil) {
        UserDefaults.standard.selectedAudioDeviceUID = uid
        UserDefaults.standard.selectedAudioDeviceModelUID = modelUID ?? getDeviceModelUID(deviceID: deviceID)
    }

    private func reconcileCustomDeviceAfterListChange() {
        let savedUID = UserDefaults.standard.selectedAudioDeviceUID ?? ""
        let savedModelUID = UserDefaults.standard.selectedAudioDeviceModelUID

        if let desired = findAvailableDevice(uid: savedUID, modelUID: savedModelUID) {
            if selectedDeviceID != desired.id {
                selectedDeviceID = desired.id
                if desired.uid != savedUID || savedModelUID == nil {
                    updateCustomDeviceHints(deviceID: desired.id, uid: desired.uid)
                }
                notifyDeviceChange()
            } else if savedModelUID == nil {
                updateCustomDeviceHints(deviceID: desired.id, uid: desired.uid)
            }
        } else if let currentID = selectedDeviceID, !isDeviceAvailable(currentID) {
            fallbackToDefaultDevice()
        }
    }

    
    private func createPropertyAddress(selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }
    
    func getDeviceProperty<T>(deviceID: AudioDeviceID,
                                    selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        guard deviceID != 0 else { return nil }
        
        var address = createPropertyAddress(selector: selector, scope: scope)
        var propertySize = UInt32(MemoryLayout<T>.size)
        var property: T? = nil
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &property
        )
        
        if status != noErr {
            logger.error("Failed to get device property \(selector, privacy: .public) for device \(deviceID, privacy: .public): \(status, privacy: .public)")
            return nil
        }
        
        return property
    }
    
    func notifyDeviceChange() {
        NotificationCenter.default.post(name: NSNotification.Name("AudioDeviceChanged"), object: nil)
    }
}
