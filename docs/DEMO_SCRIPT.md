# LingCode vs Cursor: Demo Script

A step-by-step guide to demonstrating LingCode's advantages over Cursor.

---

## Pre-Demo Setup

### Requirements
- [ ] MacBook Pro with ProMotion display (120Hz) - optional but recommended
- [ ] LingCode installed and configured
- [ ] Cursor installed and configured
- [ ] Ollama installed with a local model (e.g., `ollama pull llama3.1:70b` or `codellama:34b`)
- [ ] A sample Swift project (can use LingCode's own codebase)
- [ ] Activity Monitor ready to open
- [ ] Stopwatch app or phone timer ready

### Before Starting
1. Quit both LingCode and Cursor completely
2. Clear any caches if needed for fair cold start comparison
3. Prepare a `WORKSPACE.md` file with demo rules
4. Have WiFi toggle ready for offline demo

---

## Demo 1: Performance - Cold Start Race (30 seconds)

### Setup
- Both apps fully quit (not in Dock)
- Activity Monitor closed or minimized

### Script

**Say:** "Let's see how fast each editor launches. I'll start them at the same time."

**Do:**
1. Position both app icons side by side in Finder/Dock
2. Start your timer
3. Double-click both simultaneously
4. Wait for each to be fully ready (file tree loaded, can type)

**Expected Results:**
| App | Time | Notes |
|-----|------|-------|
| LingCode | ~0.8s | Window appears almost instantly |
| Cursor | ~4-5s | Loading spinner, gradual UI assembly |

**Say:** "LingCode is ready in under a second. Cursor is still loading... and now it's ready at about 4 seconds. That's over 5x faster."

---

## Demo 2: Performance - Memory Usage (30 seconds)

### Setup
- Both apps open with the same project
- Activity Monitor ready

### Script

**Say:** "Now let's look at how much memory each uses just sitting idle."

**Do:**
1. Open Activity Monitor
2. Sort by Memory
3. Find "LingCode" and "Cursor" (or "Cursor Helper" processes)
4. Compare total memory

**Expected Results:**
| App | Memory | Notes |
|-----|--------|-------|
| LingCode | ~145MB | Single process |
| Cursor | ~800MB+ | Multiple helper processes |

**Say:** "LingCode uses about 145 megabytes. Cursor uses over 800 megabytes - that's almost 6x more memory. This is because Cursor runs on Electron, which bundles an entire Chrome browser."

---

## Demo 3: Code Safety - Shadow Validation (2 minutes)

### This is your killer demo. Practice it.

### Setup
- LingCode open with a Swift project
- Cursor open with the same project
- Both in Agent/Chat mode

### Script

**Say:** "Here's where LingCode really shines. I'm going to ask both AIs to write code that has a bug - specifically, code that uses a Foundation type without importing Foundation."

**Prompt to use (copy exactly):**
```
Create a new file called NetworkHelper.swift with a function that takes a URL string 
and returns a URL object. Do NOT include any import statements.
```

**In Cursor:**

**Do:**
1. Paste the prompt
2. Let it generate code
3. Observe: Cursor writes the file to disk
4. Show the file in the file tree (it exists)
5. Show the compile error in the editor

**Say:** "Cursor wrote the broken code directly to my project. The file is now on disk with an error. I'd have to manually delete it or fix it."

**In LingCode:**

**Do:**
1. Paste the same prompt
2. Let it generate code
3. Observe: LingCode shows validation status
4. Point to the "Shadow build failed" indicator
5. Show that the file does NOT exist in the real project

**Say:** "LingCode caught this before touching my files. See this? 'Shadow build failed - Missing import Foundation'. The file was never created in my actual project. My codebase is still clean."

**Key Moment:** Open Finder and show the project folder. The file exists in Cursor's project but NOT in LingCode's project.

**Say:** "This is LingCode's tiered validation. Every change goes through a lint check and then a full build in a shadow workspace. Only if both pass does it touch your real files."

---

## Demo 4: Privacy - Offline Mode (1 minute)

### Setup
- Ollama running locally with a model
- WiFi connected initially

### Script

**Say:** "Many developers work with proprietary code that can't leave their machine. Let's see what happens when we go offline."

**Do:**
1. Turn off WiFi (click WiFi icon, turn off)
2. In Cursor: Try to use the AI chat
3. Show error or degraded functionality

**Say:** "Cursor needs the cloud. Without internet, AI features don't work."

**Do:**
4. In LingCode: Show the "Local" badge in the UI
5. Send a coding request
6. Show it working with Ollama

**Say:** "LingCode works fully offline using local models through Ollama. Your code never leaves your machine. This is true local-first development."

**Do:**
7. Turn WiFi back on

---

## Demo 5: Prompt Transparency (1 minute)

### Setup
- Create a `WORKSPACE.md` file in the project root:

```markdown
# WORKSPACE.md

## Code Style Rules
- NEVER use force unwrap (!) in Swift code
- Always use guard let or if let for optionals
- Prefer async/await over completion handlers

## Safety Rules
- NEVER modify .env files
- NEVER delete files without asking first
```

### Script

**Say:** "In Cursor, you don't really know what instructions the AI is following. There's a system prompt somewhere in the cloud, some local rules, and they get merged somehow. In LingCode, it's completely transparent."

**Do:**
1. Show the WORKSPACE.md file
2. Point to where the rules badge appears in LingCode UI

**Say:** "This WORKSPACE.md file contains all my project rules. It's version controlled in git with my code. LingCode shows me exactly which rules are active."

**Do:**
3. Ask LingCode: "Create a function that gets a user's name from UserDefaults"
4. Show the generated code uses `guard let` or `if let`, not `!`

**Say:** "See? It followed my rule - no force unwraps. And I can see exactly why, because I wrote the rules myself in a file I control."

---

## Demo 6: UI Smoothness - 120fps (30 seconds)

### Setup
- MacBook Pro with ProMotion display (120Hz)
- A large file open in both editors (500+ lines)

### Script

**Say:** "If you have a ProMotion display, you'll notice this immediately."

**Do:**
1. In Cursor: Scroll quickly through the file
2. In LingCode: Scroll quickly through the same file
3. Go back and forth a few times

**Say:** "LingCode renders at 120 frames per second using native Metal graphics. Cursor is capped at 60fps because of web rendering limitations. Once you feel the difference, it's hard to go back."

---

## Quick Reference Card

### One-Liners for Each Advantage

| Advantage | One-Liner |
|-----------|-----------|
| **Startup** | "Under 1 second vs over 4 seconds" |
| **Memory** | "145MB vs 800MB - almost 6x less" |
| **Safety** | "Validates before writing; your files stay clean" |
| **Privacy** | "Works fully offline; code never leaves your machine" |
| **Transparency** | "Every AI rule is in WORKSPACE.md, in your git repo" |
| **Smoothness** | "120fps native vs 60fps web" |

### If Asked "Why Should I Switch?"

> "If you're on a Mac and care about any of these: speed, memory usage, keeping your code private, or knowing exactly what rules your AI follows - LingCode is built for you. It's not a web app pretending to be native. It's a real macOS app with real performance."

### If Asked "What About Extensions?"

> "That's Cursor's main advantage - VS Code extension compatibility. If you rely heavily on specific extensions, that's a real consideration. But if you mostly need AI coding assistance with a fast, private, safe editor - LingCode gives you that without the Electron overhead."

---

## Troubleshooting

### LingCode Doesn't Start Fast
- Make sure it was fully quit, not just minimized
- Check if any background processes are running

### Ollama Not Working
- Run `ollama list` to verify models are installed
- Run `ollama serve` if not auto-started
- Check LingCode settings point to correct Ollama endpoint

### Shadow Build Not Triggering
- Ensure the project is a valid Swift project with Package.swift or .xcodeproj
- Check that validation is enabled in settings

### Memory Numbers Different
- Wait 10 seconds after launch for processes to settle
- Sum all Cursor-related processes (main + helpers)

---

## Post-Demo Talking Points

1. **"This is just the beginning"** - MCP support, Skills, CLI agent coming soon
2. **"Open source friendly"** - Local models mean no API costs for personal projects
3. **"Enterprise ready"** - Audit trails, no data leaving the network
4. **"macOS optimized"** - We build for Mac first, not as an afterthought

---

*Last updated: February 2026*
