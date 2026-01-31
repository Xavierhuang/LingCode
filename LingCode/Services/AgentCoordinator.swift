//
//  AgentCoordinator.swift
//  LingCode
//
//  Manages multiple AgentService instances so multiple agents can run simultaneously.
//

import Foundation
import Combine

@MainActor
class AgentCoordinator: ObservableObject {
    static let shared = AgentCoordinator()
    
    @Published private(set) var agents: [AgentService] = []
    /// Published so the view updates when an agent needs approval (agent.pendingApproval is not observed by the view otherwise).
    @Published private(set) var agentNeedingApprovalId: UUID?
    
    private init() {
        agents = [AgentService(agentName: "Assistant")]
    }
    
    func addAgent(name: String? = nil) -> AgentService {
        let count = agents.count + 1
        let agentName = name ?? "Agent \(count)"
        let agent = AgentService(agentName: agentName)
        agents.append(agent)
        return agent
    }
    
    func agent(for id: UUID?) -> AgentService? {
        guard let id = id else { return nil }
        return agents.first { $0.id == id }
    }
    
    var agentNeedingApproval: AgentService? {
        guard let id = agentNeedingApprovalId else { return nil }
        return agents.first { $0.id == id }
    }
    
    func notifyNeedsApproval(agentId: UUID) {
        agentNeedingApprovalId = agentId
    }
    
    func clearApproval(agentId: UUID) {
        if agentNeedingApprovalId == agentId {
            agentNeedingApprovalId = nil
        }
    }
    
    var anyRunning: Bool {
        agents.contains { $0.isRunning }
    }
}
