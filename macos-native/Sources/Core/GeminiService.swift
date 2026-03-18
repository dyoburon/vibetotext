import Foundation

/// URLSession REST client for Gemini API.
/// Ports cleanup and plan prompts from llm.py.
final class GeminiService {
    private let model = "gemini-3-flash-preview"

    // MARK: - Cleanup mode

    func cleanup(text: String) async throws -> String? {
        guard let apiKey = ConfigStore.shared.geminiAPIKey else {
            print("[Gemini] No API key configured")
            return nil
        }

        let prompt = Self.cleanupPrompt.replacingOccurrences(of: "{text}", with: text)
        return try await generateContent(prompt: prompt, apiKey: apiKey, temperature: 0.3, maxTokens: 2048)
    }

    // MARK: - Plan mode

    func generatePlan(text: String) async throws -> String? {
        guard let apiKey = ConfigStore.shared.geminiAPIKey else {
            print("[Gemini] No API key configured")
            return nil
        }

        let prompt = Self.planPrompt.replacingOccurrences(of: "{text}", with: text)
        return try await generateContent(prompt: prompt, apiKey: apiKey, temperature: 0.4, maxTokens: 4096)
    }

    // MARK: - Feedback mode

    func feedback(text: String) async throws -> String? {
        guard let apiKey = ConfigStore.shared.geminiAPIKey else {
            print("[Gemini] No API key configured")
            return nil
        }

        let prompt = Self.feedbackPrompt.replacingOccurrences(of: "{text}", with: text)
        return try await generateContent(prompt: prompt, apiKey: apiKey, temperature: 0.5, maxTokens: 256)
    }

    // MARK: - REST API call

    private func generateContent(prompt: String, apiKey: String, temperature: Double, maxTokens: Int) async throws -> String? {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": maxTokens,
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[Gemini] API error: status \(statusCode)")
            return nil
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String

        return text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompts (from llm.py)

    static let cleanupPrompt = """
    You are an expert prompt optimizer and thought clarifier. The user has recorded a rambling voice message and needs you to transform it into a clear, well-structured prompt or request.

    Your task:
    1. **Extract the core intent** - What is the user actually trying to accomplish? Cut through the rambling to find their real goal.
    2. **Resolve contradictions** - If they say conflicting things, use context to determine what they most likely meant.
    3. **Apply expert knowledge** - The user may not know the correct terminology. As an expert in whatever domain they're discussing, use precise technical terms and concepts.
    4. **Optimize for LLM consumption** - Structure the output so an AI assistant can best understand and act on it.
    5. **Be concise but complete** - Remove filler words and repetition, but keep all important details.

    Rules:
    - Output ONLY the refined prompt/request. No explanations, no "Here's what you meant", just the clean output.
    - Preserve the user's voice and intent - don't add requirements they didn't mention.
    - If they're asking a question, make it a clear question. If they're giving instructions, make them clear instructions.
    - Use markdown formatting if it helps clarity (bullet points, headers, etc.)

    User's rambling input:
    {text}

    Refined output:
    """

    static let feedbackPrompt = """
    You are JARVIS, a calm and concise AI assistant. The user has spoken to you and needs a brief verbal response.

    Rules:
    - Respond in 1-3 short sentences MAX. This will be spoken aloud via TTS.
    - Be direct and helpful. No filler, no "I think", no hedging.
    - Use natural spoken English — contractions, simple words. No markdown, no bullet points.
    - If they asked a question, answer it. If they described something, give concise feedback.
    - Address the user as "sir" occasionally but not every sentence.
    - Sound like a knowledgeable, confident AI assistant.

    User said:
    {text}

    Your spoken response:
    """

    static let planPrompt = """
    You are a senior software architect. Transform a rambling voice description into a concise implementation plan.

    ## Output Format (keep it SHORT)

    ```markdown
    # [Feature Name]

    ## Problem
    [1-2 sentences: what problem are we solving]

    ## Solution
    [2-3 sentences: high-level approach]

    ---

    ## Implementation

    ### Step 1: [Name]
    **Files:** `path/to/file.py`
    ```python
    # Key code snippet or interface
    ```

    ### Step 2: [Name]
    **Files:** `path/to/file.py`
    ```python
    # Key code snippet
    ```

    ---

    ## Files Changed
    - `new/file.py` - [purpose]
    - `modified/file.py` - [what changes]
    ```

    ## Rules
    - **Be concise** - No fluff, no explanations, just the plan
    - **2-4 steps max** - Break into logical chunks
    - **Show key code** - Interfaces, function signatures, not full implementations
    - **No time estimates** - Never include "2-3 days" or timelines
    - **Real file paths** - Based on typical project structure

    User's voice request:
    {text}

    Plan:
    """
}
