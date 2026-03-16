import Foundation

struct MyTool: Tool {
    func invoke(args: [String]) -> String {
        return "Hello from MyTool!";
    }
}
