# API Route Error Handling Standardization Guide

## CRITICAL RULE: Zero Silent Failures

Every API route MUST:
1. Use `createSuccessResponse()` for success (200-201)
2. Use `createErrorResponse()` for errors (400-500)
3. Wrap ALL logic in try-catch
4. Log errors to system_logs
5. Never return empty response
6. Provide structured error with clear message

---

## Standard Response Format

### SUCCESS (Status 200)
```typescript
{
  success: true,
  data: { /* Your data here */ }
}
```

### ERROR (Status 400/500)
```typescript
{
  success: false,
  error: {
    code: "MISSING_FIELD",
    message: "Email is required",
    details: { /* only in development */ }
  }
}
```

---

## Template for Fixing Routes

### BEFORE (SILENT FAILURE - BAD)
```typescript
import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest) {
  try {
    const data = await req.json();
    // ... some logic
    return NextResponse.json({ success: true, data });
  } catch (error) {
    // ❌ SILENT FAILURE: No error logged, generic message
    return NextResponse.json(
      { error: 'Something went wrong' }, 
      { status: 500 }
    );
  }
}
```

### AFTER (EXPLICIT ERROR HANDLING - GOOD)
```typescript
import { NextRequest, NextResponse } from 'next/server';
import { createSuccessResponse, createErrorResponse, ApiErrorCode } from '@/lib/apiResponse';
import { logSystemError, LogLevel } from '@/lib/systemLogger';
import { logAudit, AuditAction } from '@/lib/audit';
import { getSessionSchoolId } from '@/lib/auth';

export async function POST(req: NextRequest) {
  try {
    // 1. Get session
    const session = await getSessionSchoolId(req);
    if (!session) {
      return createErrorResponse(
        ApiErrorCode.UNAUTHORIZED,
        'Not authenticated',
        401
      );
    }

    // 2. Parse and validate input
    const data = await req.json();
    
    // Validation example
    if (!data.email || !data.name) {
      return createErrorResponse(
        ApiErrorCode.MISSING_FIELD,
        'Email and name are required',
        400
      );
    }

    // 3. Process business logic
    // ... your code

    // 4. Log audit trail for success
    await logAudit({
      schoolId: session.schoolId,
      userId: session.userId,
      action: AuditAction.CREATED_ROLE, // Choose appropriate action
      entityType: 'role',
      entityId: resultId,
      details: { name: data.name }
    }).catch(console.error);

    // 5. Return success
    return createSuccessResponse({ 
      id: resultId,
      message: 'Operation successful'
    }, 201);

  } catch (error: any) {
    // 6. Log error explicitly  
    await logSystemError({
      source: '/api/your-route',
      message: error?.message || 'Unknown error',
      context: {
        code: error?.code,
        message: error?.message
      }
    }).catch(e => console.error('Logging failed:', e));

    console.error('Route error:', error);

    // 7. Return structured error
    if (error?.code === 'ER_DUP_ENTRY') {
      return createErrorResponse(
        ApiErrorCode.DUPLICATE_ENTRY,
        'This record already exists',
        409
      );
    }

    return createErrorResponse(
      ApiErrorCode.INTERNAL_ERROR,
      'Failed to process request',
      500,
      process.env.NODE_ENV === 'development' ? { message: error.message } : undefined
    );
  }
}
```

---

## Quick Fix Checklist

For EACH API route:

- [ ] Add imports: `createSuccessResponse`, `createErrorResponse`, `ApiErrorCode`, `logSystemError`
- [ ] Verify auth check exists and uses proper error response
- [ ] Add try-catch wrapper around entire handler
- [ ] Replace all `NextResponse.json()` with proper response functions
- [ ] Log all errors with detailed context
- [ ] Log successful audit-worthy actions with `logAudit()`
- [ ] Never return object without `success` field
- [ ] All errors must have `.error.message` (not generic 'Failed')

---

## Common Error Codes

```typescript
ApiErrorCode.UNAUTHORIZED      // 401 - Not authenticated
ApiErrorCode.FORBIDDEN         // 403 - No permission
ApiErrorCode.MISSING_FIELD     // 400 - Required field missing
ApiErrorCode.INVALID_INPUT     // 400 - Invalid data format
ApiErrorCode.NOT_FOUND         // 404 - Resource not found
ApiErrorCode.DUPLICATE_ENTRY   // 409 - Record already exists
ApiErrorCode.DATABASE_ERROR    // 500 - DB operation failed
ApiErrorCode.INTERNAL_ERROR    // 500 - Unexpected error
```

---

## Database Error Handling

```typescript
// Detect and handle specific DB errors
if (error?.code === 'ER_NO_REFERENCED_ROW' || error?.errno === 1452) {
  return createErrorResponse(
    ApiErrorCode.DATABASE_ERROR,
    'Invalid reference: related record not found',
    400
  );
}

if (error?.code === 'ER_DUP_ENTRY' || error?.errno === 1062) {
  return createErrorResponse(
    ApiErrorCode.DUPLICATE_ENTRY,
    'This record already exists',
    409
  );
}

if (error?.code === 'ER_BAD_NULL_ERROR' || error?.errno === 1048) {
  return createErrorResponse(
    ApiErrorCode.MISSING_FIELD,
    'Required field is missing',
    400
  );
}
```

---

## Notification on Errors (Optional)

For critical operations, notify admins:

```typescript
import { notifyErrorOccurred } from '@/lib/notificationTrigger';

// After logging error
await notifyErrorOccurred(
  session.schoolId,
  {
    operation: 'Staff Creation',
    errorMessage: 'Database constraint failed',
    severity: 'error',
    context: { error: error.message }
  },
  [/* admin user IDs */]
).catch(console.error);
```

---

## Manual Testing Checklist

Test each route with:

1. **Happy path**: Valid data → Success response
2. **Missing required fields**: Empty data → 400 with clear message
3. **Duplicate entry**: Existing data → 409 with clear message
4. **Missing auth**: No session → 401 response
5. **Network error**: Database down → 500 with log
6. **Check logs**: All errors appear in `system_logs` table
7. **Check audit**: Success actions appear in `audit_logs` table
8. **Frontend toast**: Error message displays clearly

---

## Coverage

Routes that MUST be fixed:
- `/api/staff/*` (in progress)
- `/api/roles/*` (CREATE, UPDATE, DELETE)
- `/api/departments/*` (CREATE, UPDATE, DELETE)
- `/api/users/*` (CREATE, UPDATE, DELETE)
- `/api/results/*` (CREATE, UPDATE, APPROVE)
- All other `/api/**` routes

Priority order:
1. Staff operations (admin workflow)
2. Role/permission operations (RBAC)
3. User account operations (auth)
4. All others
