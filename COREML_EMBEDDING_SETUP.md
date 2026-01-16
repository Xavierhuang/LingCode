# CoreML Embedding Model Setup

## Overview

LingCode now uses **real embeddings** instead of pseudo-embeddings for semantic search. The system supports two embedding methods:

1. **NLEmbedding** (Built-in, always available) - Apple's sentence embeddings
2. **Custom CoreML Model** (Optional, higher quality) - Your own sentence-transformer model

## Current Implementation

The `VectorDB` class automatically:
- Uses NLEmbedding by default (good quality, always available)
- Falls back to NLEmbedding if no CoreML model is found
- Supports loading a custom CoreML model for better semantic understanding

## Adding a Custom CoreML Embedding Model

### Step 1: Convert a Sentence-Transformer Model to CoreML

You can use models like:
- `all-MiniLM-L6-v2` (384 dimensions, fast)
- `bge-small-en-v1.5` (384 dimensions, high quality)
- `sentence-transformers/all-mpnet-base-v2` (768 dimensions, best quality)

**Conversion Tool**: Use `coremltools` Python package:

```python
from sentence_transformers import SentenceTransformer
import coremltools as ct

# Load the model
model = SentenceTransformer('all-MiniLM-L6-v2')

# Convert to CoreML
coreml_model = ct.converters.sklearn.convert(
    model,
    input_features=[ct.datatypes.Array(shape=(1,))],
    output_names=['embedding']
)

# Save the model
coreml_model.save('EmbeddingModel.mlmodel')
```

### Step 2: Add Model to Xcode Project

1. Drag `EmbeddingModel.mlmodelc` (compiled model) into your Xcode project
2. Ensure it's added to the LingCode target
3. The model will be automatically loaded at runtime

### Step 3: Customize Integration (Optional)

If your CoreML model has a different input/output format, update `generateEmbeddingWithCoreML` in `VectorDB.swift`:

```swift
private func generateEmbeddingWithCoreML(text: String, model: MLModel) -> [Float]? {
    // 1. Preprocess text (tokenization, etc.)
    // 2. Create MLMultiArray with proper shape
    // 3. Run prediction
    // 4. Extract output vector
}
```

## Benefits of Real Embeddings

✅ **True Semantic Understanding**: Finds "login" when searching for "authentication"  
✅ **Better Context Ranking**: Understands code relationships beyond keywords  
✅ **Cursor-Level Intelligence**: Matches Cursor's semantic search capabilities  

## Current Status

- ✅ NLEmbedding integration (working)
- ✅ CoreML model loading infrastructure (ready)
- ⚠️ Custom CoreML model integration (needs model-specific code)

The system works well with NLEmbedding, but adding a custom CoreML model will provide even better semantic understanding.
