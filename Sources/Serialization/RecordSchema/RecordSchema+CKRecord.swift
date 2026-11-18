#if canImport(CloudKit)
import CloudKit
import CoreLocation

extension RecordSchema {
    /// Whether the type behind the schema can read `record`, as
    /// ``JSONSchema/contains(_:)`` asks of a JSON value.
    ///
    /// ```swift
    /// let schema = try RecordSchema(for: Note.self)
    /// schema.contains(record)   // Note can read this CKRecord
    /// ```
    ///
    /// The record type must match, every required field must be present,
    /// and each field's value must have the field's CloudKit type, in
    /// `encryptedValues` when the field is encrypted. A `String` or `Int`
    /// raw-value enum must hold one of its cases, and a `Bool` must be 0 or
    /// 1. Fields the type does not declare are ignored. A nested value
    /// stored as bytes is checked only as `Data`.
    public func contains(_ record: CKRecord) -> Bool {
        record.recordType == recordType && fields.allSatisfy { key, field in
            let value: CKRecordValue? = field.isEncrypted ? record.encryptedValues[key] : record[key]
            guard let value else { return field.schema.isOptional }
            return field.type.accepts(value, as: field.schema)
        }
    }
}

private extension RecordSchema.FieldType {
    func accepts(_ value: Any, as schema: JSONSchema) -> Bool {
        let schema = schema.unwrapped
        switch self {
        case .string:
            guard let text = value as? String else { return false }
            if case .string(let cases?) = schema { return cases.contains(text) }
            return true
        case .int64:
            guard let number = value as? Int64 else { return false }
            switch schema {
            case .boolean: return number == 0 || number == 1
            case .integer(let cases?): return cases.contains(number)
            default: return true
            }
        case .double: return value as? Double != nil
        case .timestamp: return value as? Date != nil
        case .bytes: return value as? Data != nil
        case .location: return value as? CLLocation != nil
        case .reference: return value as? CKRecord.Reference != nil
        case .asset: return value as? CKAsset != nil
        case .list(let element):
            guard let items = value as? [Any] else { return false }
            let elementSchema: JSONSchema = if case .array(let elementSchema) = schema { elementSchema } else { schema }
            return items.allSatisfy { element.accepts($0, as: elementSchema) }
        }
    }
}
#endif
