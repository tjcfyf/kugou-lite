import Foundation

final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var token: String?
    @Published private(set) var userid: Int = 0
    @Published private(set) var vipToken: String?

    var isLoggedIn: Bool { token != nil && userid != 0 }

    private let tokenKey = "kg.token"
    private let useridKey = "kg.userid"
    private let vipTokenKey = "kg.vipToken"

    private init() {
        let defaults = UserDefaults.standard
        let savedToken = defaults.string(forKey: tokenKey)
        let savedUserid = defaults.integer(forKey: useridKey)
        token = savedToken
        userid = savedUserid
        vipToken = defaults.string(forKey: vipTokenKey)
        KGApi.shared.token = savedToken
        KGApi.shared.userid = savedUserid
        KGApi.shared.vipToken = defaults.string(forKey: vipTokenKey)
    }

    func signIn(token: String, userid: Int, vipToken: String? = nil) {
        self.token = token
        self.userid = userid
        if let vipToken = vipToken, !vipToken.isEmpty { self.vipToken = vipToken }
        let defaults = UserDefaults.standard
        defaults.set(token, forKey: tokenKey)
        defaults.set(userid, forKey: useridKey)
        if let vipToken = vipToken, !vipToken.isEmpty {
            defaults.set(vipToken, forKey: vipTokenKey)
            KGApi.shared.vipToken = vipToken
        }
        KGApi.shared.token = token
        KGApi.shared.userid = userid
    }

    func signOut() {
        token = nil
        userid = 0
        vipToken = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: useridKey)
        UserDefaults.standard.removeObject(forKey: vipTokenKey)
        KGApi.shared.token = nil
        KGApi.shared.userid = 0
        KGApi.shared.vipToken = nil
    }
}
