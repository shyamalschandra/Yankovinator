> **Current status (2026):** Yankovinator ships with **Ollama** (`llama3.2:3b`), not Apple Foundation Models. Treat the Foundation Models content below as historical / aspirational. Use [README.md](README.md) and [QUICK_START.md](QUICK_START.md) for accurate instructions.

# Foundation Models API Implementation Notes

## Current Status

The FoundationModels framework has been integrated to replace Ollama, but the exact API structure needs to be verified and adjusted based on the actual FoundationModels framework API.

## Known Issues

1. **SystemLanguageModel Availability**: The compiler reports that `SystemLanguageModel` requires macOS 26.0+, which suggests either:
   - The API structure is different than expected
   - A different class/API should be used
   - The framework may not be fully available yet

2. **API Method Names**: The actual method to generate text may be:
   - `prompt(_:)` 
   - `generate(_:)`
   - `complete(_:)`
   - Or another method name

3. **GeneratedContent Structure**: The `GeneratedContent` type may have different properties:
   - `string`
   - `text`
   - `content`
   - `segments`
   - Or other property names

## What Needs to Be Done

1. **Verify FoundationModels API**: Check Apple's documentation at https://developer.apple.com/documentation/FoundationModels to confirm:
   - Correct class names (SystemLanguageModel vs LanguageModel)
   - Correct initialization parameters
   - Correct method names for text generation
   - Correct response structure

2. **Update FoundationModelsClient.swift**: Adjust the implementation based on the actual API:
   - Fix the SystemLanguageModel initialization
   - Fix the text generation method call
   - Fix the response parsing

3. **Test and Benchmark**: Once the API is correct:
   - Run all tests
   - Create benchmarks comparing Foundation Models vs Ollama
   - Update documentation

## Current Implementation

The current implementation in `FoundationModelsClient.swift` uses:
- `SystemLanguageModel()` for initialization
- `languageModel.prompt(prompt)` for text generation
- `GeneratedContent.string` or `GeneratedContent.segments` for response extraction

These may need to be adjusted based on the actual API.

## Platform Requirements

- macOS 15.0+ (Sequoia) or iOS 18.0+
- FoundationModels framework must be available

## Next Steps

1. Review Apple's FoundationModels documentation
2. Test the actual API in a simple Swift project
3. Update FoundationModelsClient.swift with correct API calls
4. Test compilation and functionality
5. Run benchmarks
6. Update all documentation
