#if canImport(CloudKit)
import CloudKit

extension RecordRepresentation.RecordID {
    /// The name and zone of `id`.
    public init(_ id: CKRecord.ID) {
        self.init(recordName: id.recordName, zoneName: id.zoneID.zoneName, ownerName: id.zoneID.ownerName)
    }

    /// This id as CloudKit holds it.
    public var ckRecordID: CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName))
    }
}
#endif
