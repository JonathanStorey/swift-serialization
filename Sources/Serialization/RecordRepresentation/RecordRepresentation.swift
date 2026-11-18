/// The namespace for CloudKit record values that need a type of their own,
/// such as ``Reference``, independent of the CloudKit framework.
public enum RecordRepresentation {}

extension RecordRepresentation {
    /// A reference to another record in the same zone, as CloudKit's
    /// `CKRecord.Reference` stores it.
    ///
    /// CloudKit requires a reference to point into the zone of the record
    /// that holds it, so the zone is not stored here.
    public struct Reference: Codable, Hashable, Sendable {
        /// What CloudKit does to the record holding the reference when the
        /// target record is deleted. The cases match `CKRecord.ReferenceAction`.
        public enum Action: String, CaseIterable, Codable, Hashable, Sendable {
            /// Nothing. The reference is left pointing at a missing record.
            case none
            /// The record holding the reference is deleted too.
            case deleteSelf
        }

        /// The target record's name.
        public var recordName: String
        public var action: Action

        public init(recordName: String, action: Action = .none) {
            self.recordName = recordName
            self.action = action
        }
    }
}
