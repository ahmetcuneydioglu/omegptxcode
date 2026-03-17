import Foundation

struct FakeUser: Identifiable, Equatable {
    let id: UUID
    let name: String
    let countryFlag: String

    init(id: UUID = UUID(), name: String, countryFlag: String) {
        self.id = id
        self.name = name
        self.countryFlag = countryFlag
    }
}

enum FakeUserData {
    static let globalUsers: [FakeUser] = [
        FakeUser(name: "James", countryFlag: "🇺🇸"),
        FakeUser(name: "Olivia", countryFlag: "🇺🇸"),
        FakeUser(name: "Noah", countryFlag: "🇨🇦"),
        FakeUser(name: "Emma", countryFlag: "🇨🇦"),
        FakeUser(name: "Isabella", countryFlag: "🇧🇷"),
        FakeUser(name: "Ricardo", countryFlag: "🇧🇷"),
        FakeUser(name: "Haruto", countryFlag: "🇯🇵"),
        FakeUser(name: "Yui", countryFlag: "🇯🇵"),
        FakeUser(name: "Kerem", countryFlag: "🇹🇷"),
        FakeUser(name: "Selin", countryFlag: "🇹🇷"),
        FakeUser(name: "Lukas", countryFlag: "🇩🇪"),
        FakeUser(name: "Hannah", countryFlag: "🇩🇪"),
        FakeUser(name: "Chloe", countryFlag: "🇫🇷"),
        FakeUser(name: "Lucas", countryFlag: "🇫🇷"),
        FakeUser(name: "Priya", countryFlag: "🇮🇳"),
        FakeUser(name: "Arjun", countryFlag: "🇮🇳"),
        FakeUser(name: "Mateo", countryFlag: "🇪🇸"),
        FakeUser(name: "Sofia", countryFlag: "🇪🇸"),
        FakeUser(name: "Liam", countryFlag: "🇦🇺"),
        FakeUser(name: "Mia", countryFlag: "🇦🇺"),
        FakeUser(name: "Ethan", countryFlag: "🇬🇧"),
        FakeUser(name: "Amelia", countryFlag: "🇬🇧"),
        FakeUser(name: "Daniel", countryFlag: "🇲🇽"),
        FakeUser(name: "Valentina", countryFlag: "🇲🇽"),
        FakeUser(name: "Leon", countryFlag: "🇳🇱"),
        FakeUser(name: "Eva", countryFlag: "🇳🇱"),
        FakeUser(name: "Rayan", countryFlag: "🇲🇦"),
        FakeUser(name: "Ines", countryFlag: "🇲🇦"),
        FakeUser(name: "Youssef", countryFlag: "🇪🇬"),
        FakeUser(name: "Nour", countryFlag: "🇪🇬"),
        FakeUser(name: "Ahmed", countryFlag: "🇸🇦"),
        FakeUser(name: "Layan", countryFlag: "🇸🇦"),
        FakeUser(name: "Ava", countryFlag: "🇳🇿"),
        FakeUser(name: "Oliver", countryFlag: "🇳🇿"),
        FakeUser(name: "Theo", countryFlag: "🇸🇪"),
        FakeUser(name: "Elsa", countryFlag: "🇸🇪"),
        FakeUser(name: "Mikkel", countryFlag: "🇩🇰"),
        FakeUser(name: "Freja", countryFlag: "🇩🇰"),
        FakeUser(name: "Joon", countryFlag: "🇰🇷"),
        FakeUser(name: "Minji", countryFlag: "🇰🇷"),
        FakeUser(name: "Wei", countryFlag: "🇨🇳"),
        FakeUser(name: "Xinyi", countryFlag: "🇨🇳"),
        FakeUser(name: "Andrei", countryFlag: "🇷🇴"),
        FakeUser(name: "Elena", countryFlag: "🇷🇴"),
        FakeUser(name: "Nikola", countryFlag: "🇷🇸"),
        FakeUser(name: "Mila", countryFlag: "🇷🇸"),
        FakeUser(name: "Joao", countryFlag: "🇵🇹"),
        FakeUser(name: "Beatriz", countryFlag: "🇵🇹"),
        FakeUser(name: "Kofi", countryFlag: "🇬🇭"),
        FakeUser(name: "Ama", countryFlag: "🇬🇭")
    ]
}
