import Foundation

enum ProxyRestoration {
    static func restored(current: [String: Any], original: [String: Any], port: Int) -> [String: Any]? {
        var result = current, owned = false
        for prefix in ["HTTP", "HTTPS", "SOCKS"] {
            if current[prefix + "Port"] as? Int == port && current[prefix + "Proxy"] as? String == "127.0.0.1" {
                owned = true
                for key in [prefix + "Enable", prefix + "Proxy", prefix + "Port"] { result[key] = original[key] }
            }
        }
        guard owned else { return nil }
        for key in ["ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"] where current[key] as? Int == 0 { result[key] = original[key] }
        return result
    }
}
