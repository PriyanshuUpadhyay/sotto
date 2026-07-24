import Testing
import Foundation
@testable import Sotto

struct BundledManifestTests {
    @Test func bundledManifestExistsAndDecodes() throws {
        let url = try BundledManifest.url()
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(TranscriptionModelManifest.self, from: data)
        #expect(manifest.schema_version == 1)
        #expect(manifest.models.count == 11)
    }

    @Test func bundledResourceIsAccessibleFromAppBundle() throws {
        let url = try BundledManifest.url()
        #expect(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        #expect(data.count > 0, "bundled manifest must not be empty")
    }
}
