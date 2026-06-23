import Foundation

struct LLMProviderChain: LLMProvider, Sendable {
    private let providers: [any LLMProvider]

    init(providers: [any LLMProvider]) {
        self.providers = providers
    }

    static func make(
        settings: AIMetadataSettings,
        secretsStore: SecretsStore = KeychainSecretsStore()
    ) -> LLMProviderChain {
        var providers: [any LLMProvider] = []

        if let apiKey = try? secretsStore.read(key: SecretsStoreKey.groqAPIKey),
           !apiKey.isEmpty
        {
            providers.append(GroqChatProvider(apiKey: apiKey, model: settings.groqModel))
        }

        providers.append(
            OllamaChatProvider(baseURL: settings.ollamaURL, model: settings.ollamaChatModel)
        )

        return LLMProviderChain(providers: providers)
    }

    func complete(prompt: String) async throws -> String {
        var lastError: Error?
        for provider in providers {
            do {
                return try await provider.complete(prompt: prompt)
            } catch {
                lastError = error
            }
        }
        if let lastError {
            throw lastError
        }
        throw LLMProviderError.unavailable
    }
}
