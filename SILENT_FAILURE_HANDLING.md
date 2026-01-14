# Silent Failure Detection & Handling

This document describes improvements to detect and handle "silent failures" where HTTP 200 is received but no content arrives.

## Problem: The "Empty Response" Paradox

**Symptoms**:
- HTTP Status Code: 200 (success)
- But IDE shows: "AI service returned an empty response"
- No actual content chunks received

**Root Causes**:
1. Server sent success signal but failed to generate text
2. IDE's parser failed to read incoming stream
3. ViewBridge/UI crash interrupted response rendering
4. Context length/timeout - request too large or took too long

## Solutions Implemented

### 1. Timeout Detection

**Feature**: Automatic timeout detection for silent failures

**Implementation**:
- Starts a 30-second timer when HTTP 200 is received
- If no chunks arrive within timeout period, treats as failure
- Provides specific error message explaining the issue

**Code Location**: `LingCode/Services/AIService.swift` - `StreamingDelegate.urlSession(_:dataTask:didReceive:)`

### 2. Enhanced Empty Response Detection

**Feature**: Better detection of different failure modes

**Failure Types Detected**:
- `empty_response`: Truly empty response body
- `encoding_error`: Data received but can't be decoded as UTF-8
- `parse_error`: Data received but no parseable SSE chunks
- `silent_failure`: HTTP 200 but no chunks within timeout

**Code Location**: `LingCode/Services/AIService.swift` - `StreamingDelegate.urlSession(_:task:didCompleteWithError:)`

### 3. Improved Error Messages

**Feature**: Context-aware error messages with actionable suggestions

**Error Messages**:
- Distinguish between network failures, empty responses, and silent failures
- Include failure type, HTTP status, and received bytes in error info
- Suggest breaking request into smaller parts for large contexts

**Code Locations**:
- `LingCode/Services/AIService.swift` - Error handling
- `LingCode/Views/EditorView.swift` - Error display

### 4. Enhanced Logging

**Feature**: Detailed telemetry for debugging

**Logs Include**:
- HTTP status code
- Response data length
- Chunk reception status
- First/last chunk timestamps
- Failure type classification
- Possible causes and suggestions

**Code Location**: `LingCode/Services/AIService.swift` - All error paths

## User-Facing Improvements

### Better Error Messages

**Before**:
```
AI service returned an empty response. Please retry.
```

**After**:
```
Connection successful (HTTP 200) but no content was received. 
This may be a transient server issue or UI rendering problem. 
Please retry, or try breaking the request into smaller parts.
```

### Actionable Suggestions

Error messages now include:
- Explanation of what went wrong
- Possible causes
- Suggested actions (retry, break into smaller parts, restart IDE)

## Technical Details

### Timeout Configuration

- **Timeout Duration**: 30 seconds
- **Trigger**: HTTP 200 received but no chunks
- **Action**: Cancel timer once first chunk arrives

### Chunk Tracking

- Tracks `firstChunkTime` and `lastChunkTime` for diagnostics
- Validates that chunks contain non-empty text
- Distinguishes between empty chunks and no chunks

### Error Classification

Errors are classified with:
- `failure_type`: Type of failure (empty_response, encoding_error, parse_error, silent_failure)
- `http_status`: HTTP status code
- `received_bytes`: Number of bytes received

## Testing Scenarios

### Scenario 1: HTTP 200 with No Chunks
- **Expected**: Timeout after 30s, error with "silent_failure" type
- **User Action**: Retry or break request into smaller parts

### Scenario 2: HTTP 200 with Malformed SSE
- **Expected**: Error with "parse_error" type, includes raw response preview
- **User Action**: Retry (likely transient server issue)

### Scenario 3: HTTP 200 with Encoding Issues
- **Expected**: Error with "encoding_error" type
- **User Action**: Retry (server encoding issue)

### Scenario 4: HTTP 200 with Empty Response Body
- **Expected**: Error with "empty_response" type
- **User Action**: Retry or restart IDE (ViewBridge crash)

## Future Improvements

Potential enhancements:
1. Automatic retry with exponential backoff
2. Request size warnings before sending
3. Progress indicators during long requests
4. Context size optimization suggestions
