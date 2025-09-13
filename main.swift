import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct NewGameResponse: Decodable {
    let id: String
    enum CodingKeys: String, CodingKey {
        case id = "game_id"
    }
}

struct GuessResult: Decodable {
    let black: Int
    let white: Int
}

class MMClient {
    private let serverURL = "https://mastermind.darkube.app"
    private var currentGameID: String?

    func initiateGame(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(serverURL)/game") else {
            completion(false)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { data, _, error in
            guard let data = data, error == nil else { completion(false); return }
            if let game = try? JSONDecoder().decode(NewGameResponse.self, from: data) {
                self.currentGameID = game.id
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }

    func submitGuess(_ guess: String, completion: @escaping (GuessResult?) -> Void) {
        guard let gameID = currentGameID, let url = URL(string: "\(serverURL)/guess") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["game_id": gameID, "guess": guess]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, _, error in
            guard let data = data, error == nil else { completion(nil); return }
            let result = try? JSONDecoder().decode(GuessResult.self, from: data)
            completion(result)
        }.resume()
    }

    func terminateGame(completion: @escaping () -> Void) {
        guard let gameID = currentGameID, let url = URL(string: "\(serverURL)/game/\(gameID)") else {
            completion()
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: req) { _, _, _ in
            completion()
        }.resume()
    }
}

let client = MMClient()
let sema = DispatchSemaphore(value: 0)
print("🔹 Starting Mastermind session...")
client.initiateGame { success in
    if success { print("Game started!") }
    else { print("Failed to start game"); exit(0) }
    sema.signal()
}
sema.wait()

var finished = false
while !finished {
    print("Enter 4-digit guess (1-6) or 'exit': ", terminator: "")
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
    if input.lowercased() == "exit" {
        finished = true
        client.terminateGame { print("Game ended."); exit(0) }
    }
    guard input.count == 4 && input.allSatisfy({ "123456".contains($0) }) else {
        print("Invalid input!"); continue
    }
    let guessSema = DispatchSemaphore(value: 0)
    client.submitGuess(input) { result in
        if let r = result {
            print("Result: \(String(repeating: "B", count: r.black))\(String(repeating: "W", count: r.white))")
            if r.black == 4 {
                print("🎉 You guessed the code!")
                finished = true
                client.terminateGame { exit(0) }
            }
        } else {
            print("Error contacting server")
        }
        guessSema.signal()
    }
    guessSema.wait()
}