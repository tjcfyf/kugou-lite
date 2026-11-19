import Foundation

final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var token: String?
    @Published private(set) var userid: Int = 0

    var isLoggedIn: Bool { token != nil && userid != 0 }

    private let tokenKey = "kg.token"
    private let useridKey = "kg.userid"

    private init() {
        let defaults = UserDefaults.standard
        let savedToken = defaults.string(forKey: tokenKey)
        let savedUserid = defaults.integer(forKey: useridKey)
        token = savedToken
        userid = savedUserid
        KGApi.shared.token = savedToken
        KGApi.shared.userid = savedUserid
    }

    func signIn(token: String, userid: Int) {
        self.token = token
        self.userid = userid
        let defaults = UserDefaults.standard
        defaults.set(token, forKey: tokenKey)
        defaults.set(userid, forKey: useridKey)
        KGApi.shared.token = token
        KGApi.shared.userid = userid
    }

    func signOut() {
        token = nil
        userid = 0
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: useridKey)
        KGApi.shared.token = nil
        KGApi.shared.userid = 0
    }
}
