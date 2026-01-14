# Local Models Setup Guide

This guide will help you set up and use local AI models in LingCode.

## Overview

LingCode supports running AI models locally on your Mac, which provides:
- **Privacy**: Your code never leaves your machine
- **No API costs**: Free to use after initial setup
- **Offline capability**: Works without internet connection
- **Fast responses**: No network latency

## Step 1: Install Ollama

Ollama is the easiest way to run local models on macOS.

### Option A: Using Homebrew (Recommended)
```bash
brew install ollama
```

### Option B: Direct Download
1. Visit https://ollama.ai
2. Download the macOS installer
3. Run the installer

### Option C: Using curl
```bash
curl -fsSL https://ollama.ai/install.sh | sh
```

## Step 2: Start Ollama

After installation, start the Ollama service:

```bash
ollama serve
```

This will start a local server at `http://localhost:11434`

## Step 3: Download Models

You need to download the models you want to use. Here are recommended models for coding:

### For Code Generation (Recommended)
```bash
# DeepSeek Coder 6.7B - Best for code generation
ollama pull deepseek-coder:6.7b

# Or smaller alternative (faster, less memory)
ollama pull deepseek-coder:1.3b
```

### For Code Completion
```bash
# StarCoder2 - Fast and efficient
ollama pull starcoder2:15b

# Or smaller version
ollama pull starcoder2:7b
```

### For General Coding Tasks
```bash
# Qwen 2.5 Coder - Good balance
ollama pull qwen2.5-coder:7b

# Or smaller version
ollama pull qwen2.5-coder:1.5b
```

### For Lightweight Tasks
```bash
# Phi-3 - Very fast, good for simple tasks
ollama pull phi3:mini
```

## Step 4: Verify Installation

Test that Ollama is working:

```bash
ollama run deepseek-coder:6.7b "Write a hello world in Python"
```

If you see a response, Ollama is working correctly!

## Step 5: Configure LingCode

1. Open LingCode
2. Go to Settings (⌘,)
3. Navigate to "AI Configuration"
4. Select "Local Models" as your provider
5. The app will automatically detect Ollama if it's running

## Step 6: Test Local Models

1. In LingCode, open the AI chat
2. Type a simple request like "Write a function to calculate factorial"
3. The app should use your local model

## Model Recommendations by Task

| Task | Recommended Model | Memory Required |
|------|------------------|-----------------|
| Code Generation | `deepseek-coder:6.7b` | ~8GB RAM |
| Code Completion | `starcoder2:7b` | ~6GB RAM |
| Quick Edits | `qwen2.5-coder:1.5b` | ~3GB RAM |
| Simple Tasks | `phi3:mini` | ~2GB RAM |

## Troubleshooting

### Ollama not detected
- Make sure Ollama is running: `ollama serve`
- Check if it's accessible: `curl http://localhost:11434/api/tags`
- Restart LingCode after starting Ollama

### Out of Memory
- Use smaller models (1.3b, 1.5b, or mini versions)
- Close other applications
- Consider upgrading your Mac's RAM

### Slow Responses
- Use smaller/faster models
- Ensure you have enough RAM
- Close other applications

## Advanced: Using Multiple Models

You can have multiple models installed and switch between them:

```bash
# List installed models
ollama list

# Use specific model
ollama run <model-name> "your prompt"
```

## Next Steps

After setup, you can:
- Use local models for all AI features
- Enable "Offline Mode" in settings
- Switch between local and cloud models as needed

## Support

If you encounter issues:
1. Check Ollama logs: `ollama logs`
2. Verify model is downloaded: `ollama list`
3. Test Ollama directly: `ollama run <model> "test"`