import Foundation
import Testing
@testable import LeewayCore

@Test func missingPolicyUsesDefaults() throws {
    let policy = try Policy.load(URL(fileURLWithPath: "/nonexistent/leeway-policy.toml"), home: URL(fileURLWithPath: "/example"))
    #expect(policy.port == 8799)
    #expect(policy.pollMinutes == 15)
    #expect(policy.accounts.isEmpty)
}

@Test func policyReadsProjectsAccountsAndRoleOverrides() throws {
    let text = """
    port = 9000
    codex_model = "codex-x"
    poll_minutes = 5
    [roles]
    planner = "sonnet:high" # user rule
    [[accounts]]
    id = "first"
    provider = "claude"
    label = "First"
    config_dir = "~/first"
    target_high = 95
    reserve_account = "second"
    [[accounts]]
    id = "second"
    provider = "claude"
    config_dir = "~/second"
    [[projects]]
    name = "app"
    paths = ["~/work/app", "/srv/other"]
    claude = ["first", "second"]
    codex = []
    [default]
    claude = ["second"]
    """
    let policy = try Policy.parse(text, home: URL(fileURLWithPath: "/example"))
    #expect(policy.port == 9000)
    #expect(policy.pollMinutes == 5)
    #expect(policy.roles[.planner] == "sonnet:high")
    try #require(policy.accounts.count == 2)
    #expect(policy.accounts[0].configDir.path == "/example/first")
    #expect(policy.accounts[0].targetHigh == 95)
    #expect(policy.accounts[0].reserveAccount == "second")
    #expect(policy.allowed(for: "/example/work/app/tree").claude == ["first", "second"])
    #expect(policy.allowed(for: "/example/work/app2").claude == ["second"])
    #expect(policy.codexModel == "codex-x")
}

@Test(arguments: ["port = 0", "port = true", "port = 65536", "bogus = 1",
    "poll_minutes = 7", "[roles]\nboss = \"x\"", "[[projects]]\nname = \"a\"",
    "[default]\nclaude = \"first\"", "port = 4\nport = 5",
    "[[accounts]]\nid = \"x\"\nprovider = \"claude\"\nconfig_dir = \"/x\"\ntarget_high = 101"])
func malformedPolicyFails(_ text: String) {
    #expect(throws: PolicyError.self) { try Policy.parse(text, home: URL(fileURLWithPath: "/example")) }
}

@Test func routingCoversEveryRoleTierAndCodexEffort() {
    let policy = Policy()
    #expect(ModelRouter.choose(.claude, role: .builder, task: .mechanical, policy: policy).model == "haiku")
    #expect(ModelRouter.choose(.claude, role: .builder, task: .design, policy: policy).effort == "high")
    #expect(ModelRouter.choose(.claude, role: .reviewer, task: .design, policy: policy).model == "sonnet")
    #expect(ModelRouter.choose(.claude, role: .explorer, task: .mechanical, policy: policy).model == "haiku")
    #expect(ModelRouter.choose(.claude, role: .explorer, task: .design, policy: policy).model == "sonnet")
    for role in [Role.planner, .evaluator] {
        #expect(ModelRouter.choose(.claude, role: role, task: .integration, policy: policy).model == "opus")
    }
    #expect(ModelRouter.choose(.codex, role: .builder, task: .design, policy: policy).model == "")
    #expect(ModelRouter.choose(.codex, role: .explorer, task: .mechanical, policy: policy).effort == "medium")
    let custom = Policy(codexModel: "x", roles: [.planner: "sonnet:high"])
    #expect(ModelRouter.choose(.claude, role: .planner, task: .integration, policy: custom).model == "sonnet")
    #expect(ModelRouter.choose(.codex, role: .planner, task: .integration, policy: custom).model == "x")
}

@Test func policyQuotedBracketsAndCommentsAreScalarText() throws {
    let text = """
    codex_model = "model[variant]#tag"
    [[accounts]]
    id = 'first'
    provider = 'claude'
    label = 'First [main]'
    config_dir = '/example/first'
    [default]
    claude = [
      'first', # preferred
    ]
    """
    let policy = try Policy.parse(text, home: URL(fileURLWithPath: "/example"))
    #expect(policy.codexModel == "model[variant]#tag")
    #expect(policy.accounts.first?.label == "First [main]")
    #expect(policy.defaultAllowed.claude == ["first"])
}
