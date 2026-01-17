# Why Regex Indexing for Non-Swift Languages is Fragile

## The Problem

Regex-based symbol extraction (used for JavaScript, TypeScript, Python, etc.) is **fragile** and will miss or incorrectly identify symbols in many common scenarios.

## Why Regex Fails

### 1. **Multi-line Declarations**

Regex patterns like `^function\s+(\w+)` only match single-line patterns. They fail on:

```javascript
// ❌ Regex MISSES this:
function 
    calculateTotal(
        items,
        tax
    ) {
    // ...
}

// ❌ Regex MISSES this:
const myFunction = 
    async function() {
        // ...
    };
```

### 2. **Comments and Strings**

Regex can't distinguish between actual code and code-like text in comments/strings:

```javascript
// ❌ Regex INCORRECTLY matches this comment:
// function oldFunction() { ... }

// ❌ Regex INCORRECTLY matches this string:
const example = "function fake() { return true; }";
```

### 3. **Nested Structures**

Regex can't understand scope or nesting:

```javascript
// ❌ Regex can't tell this is INSIDE a class:
class MyClass {
    method() {
        function innerFunction() {  // Regex might miss this
            // ...
        }
    }
}
```

### 4. **Complex Syntax**

Modern language features break regex patterns:

```typescript
// ❌ Regex can't handle decorators:
@Injectable()
export class MyService { }

// ❌ Regex can't handle generics properly:
function process<T extends Base>(item: T): T { }

// ❌ Regex can't handle arrow functions with complex signatures:
const handler = (event: MouseEvent): void => { };
```

### 5. **Context-Aware Parsing**

Regex doesn't understand context:

```python
# ❌ Regex can't distinguish:
def method(self):  # Is this a method or function?
    pass

class MyClass:
    def method(self):  # This is a method
        pass

def function():  # This is a function
    pass
```

### 6. **Template Literals and String Interpolation**

```javascript
// ❌ Regex gets confused by template literals:
const code = `
    function generated() {
        return true;
    }
`;
```

## Real-World Impact

### Example: Missing Symbols

```javascript
// File: utils.js
export const helpers = {
    // Regex MISSES this arrow function:
    calculate: (x, y) => x + y,
    
    // Regex MISSES this method:
    process(items) {
        return items.map(item => item.value);
    }
};

// Regex might only catch:
// - Nothing (if pattern doesn't match object methods)
// - Or incorrectly identify "helpers" as a function
```

### Example: False Positives

```javascript
// File: test.js
describe('MyComponent', () => {
    // Regex might INCORRECTLY match "function" in this string:
    it('should call function when clicked', () => {
        // ...
    });
    
    // Regex might match this comment:
    // function oldImplementation() { ... }
});
```

## The Solution: Tree-sitter Parsers

Tree-sitter provides:
- ✅ **Real AST parsing** - Understands language structure
- ✅ **Multi-line support** - Handles declarations spanning lines
- ✅ **Context awareness** - Knows if something is in a class, function, etc.
- ✅ **Comment/string filtering** - Ignores code-like text in strings/comments
- ✅ **Modern syntax** - Handles decorators, generics, arrow functions, etc.

## Current State

- ✅ **Swift**: Uses SwiftSyntax (AST-based, perfect)
- ❌ **JavaScript/TypeScript**: Uses regex (fragile)
- ❌ **Python**: Uses regex (fragile)
- ❌ **Other languages**: Uses regex (fragile)

## Recommendation

Integrate Tree-sitter parsers for JavaScript, TypeScript, and Python to match Cursor's robustness. This will:
1. Extract symbols accurately (no false positives/negatives)
2. Handle modern language features
3. Provide better context for AI code understanding
4. Match Cursor's indexing quality
