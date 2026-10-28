import Foundation
import CoreAudio
import AVFoundation
import os

extension AudioDeviceManager {
    func loadPrioritizedDevices() {
        if let data = UserDefaults.standard.prioritizedDevicesData,
           let devices = try? JSONDecoder().decode([PrioritizedDevice].self, from: data) {
            prioritizedDevices = devices
        }
    }
    
    func savePrioritizedDevices() {
        if let data = try? JSONEncoder().encode(prioritizedDevices) {
            UserDefaults.standard.prioritizedDevicesData = data
        }
    }
    
    func addPrioritizedDevice(uid: String, name: String) {
        guard !prioritizedDevices.contains(where: { $0.id == uid }) else { return }
        let modelUID = availableDevices.first(where: { $0.uid == uid })
            .flatMap { getDeviceModelUID(deviceID: $0.id) }
        let nextPriority = (prioritizedDevices.map { $0.priority }.max() ?? -1) + 1
        let device = PrioritizedDevice(id: uid, name: name, priority: nextPriority, modelUID: modelUID)
        prioritizedDevices.append(device)
        savePrioritizedDevices()
    }

    func removePrioritizedDevice(id: String) {
        let wasSelected = selectedDeviceID == availableDevices.first(where: { $0.uid == id })?.id
        prioritizedDevices.removeAll { $0.id == id }

        let updatedDevices = prioritizedDevices.enumerated().map { index, device in
            PrioritizedDevice(id: device.id, name: device.name, priority: index, modelUID: device.modelUID)
        }

        prioritizedDevices = updatedDevices
        savePrioritizedDevices()
        
        if wasSelected && inputMode == .prioritized {
            selectHighestPriorityAvailableDevice()
        }
    }
    
    func updatePriorities(devices: [PrioritizedDevice]) {
        prioritizedDevices = devices
        savePrioritizedDevices()
        
        if inputMode == .prioritized {
            selectHighestPriorityAvailableDevice()
        }
        
        notifyDeviceChange()
    }
    
    func selectHighestPriorityAvailableDevice() {
        let sortedDevices = prioritizedDevices.sorted { $0.priority < $1.priority }

        for saved in sortedDevices {
            guard let found = findAvailableDevice(uid: saved.id, modelUID: saved.modelUID) else {
                continue
            }
            selectedDeviceID = found.id
            if found.uid != saved.id || saved.modelUID == nil {
                rebindPrioritizedDevice(savedUID: saved.id, newUID: found.uid, newModelUID: getDeviceModelUID(deviceID: found.id))
            }
            notifyDeviceChange()
            return
        }

        fallbackToDefaultDevice()
    }
}
