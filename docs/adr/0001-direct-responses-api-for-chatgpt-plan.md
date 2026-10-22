# Use the direct Responses API for ChatGPT Plan translation

MangaTranslator will use a dedicated SSE client to call the Responses API with
the user-authorized ChatGPT Plan token. We rejected Codex app-server because
its child-process, JSON-RPC, packaging, and token-refresh lifecycle costs add
no value for a text translation engine.
