import Foundation

/// Fichier son WAV construit en mémoire : PCM 16 bits, mono, petit boutiste.
public enum WAV {
    public static func encode(samples: [Int16], sampleRate: Int = 16_000) -> Data {
        let dataBytes = samples.count * 2
        var d = Data(capacity: 44 + dataBytes)
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + dataBytes))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1)                              // PCM
        u16(1)                              // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))         // octets par seconde
        u16(2)                              // octets par échantillon
        u16(16)                             // bits
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(dataBytes))
        samples.withUnsafeBufferPointer { p in
            if CFByteOrderGetCurrent() == Int(CFByteOrderLittleEndian.rawValue) {
                d.append(UnsafeBufferPointer(start: UnsafeRawPointer(p.baseAddress)?.assumingMemoryBound(to: UInt8.self), count: dataBytes))
            } else {
                for s in p { u16(UInt16(bitPattern: s)) }
            }
        }
        return d
    }
}
