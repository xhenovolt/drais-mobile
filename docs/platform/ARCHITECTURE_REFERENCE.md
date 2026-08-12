# 🏗️ DRAIS CORE SYSTEMS - ARCHITECTURE REFERENCE

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    DRAIS PLATFORM V2                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  LIFECYCLE   │  │   PROFILE    │  │   IMPORT     │      │
│  │  MANAGEMENT  │  │   SYSTEM     │  │   ENGINE     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│        ↓                 ↓                  ↓               │
│  Status Tracking   Unified View      Bulk Onboarding       │
│  (Active/Left/...)  (All Student     (CSV/Excel)          │
│  with Reasons       Data)            Auto-create cls      │
│                                       Duplicate chk       │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              DATABASE LAYER (TiDB)                      ││
│  ├─────────────────────────────────────────────────────────┤│
│  │ students (NEW: status, left_at, left_reason)            ││
│  │ people, enrollments, results, classes, streams           ││
│  │ ✅ All with school_id isolation                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 1️⃣ STUDENT LIFECYCLE MANAGEMENT

### Database Schema
```sql
-- Added to students table (migration 021)
ALTER TABLE students ADD COLUMN status ENUM(
  'active',        -- Currently enrolled
  'left',          -- Departed (archived)
  'graduated',     -- Completed program
  'suspended'      -- Temporarily inactive
) DEFAULT 'active';

ALTER TABLE students ADD COLUMN left_at DATETIME;
ALTER TABLE students ADD COLUMN left_reason TEXT;

-- Indexes for performance
CREATE INDEX idx_students_status ON students(school_id, status);
CREATE INDEX idx_students_left_at ON students(left_at);
```

### API Flow

```
┌─────────────────────────────────────────┐
│  UI: Click Status Dropdown               │
│  → Select "Mark as Left"                 │
└──────────────┬──────────────────────────┘
               │
               ↓
┌─────────────────────────────────────────┐
│  Modal: Prompt for Reason                │
│  (Why is student leaving?)               │
└──────────────┬──────────────────────────┘
               │
               ↓
┌─────────────────────────────────────────┐
│  PATCH /api/students/:id/status          │
│  {                                       │
│    "status": "left",                     │
│    "left_reason": "Transferred schools"  │
│  }                                       │
└──────────────┬──────────────────────────┘
               │
               ↓
┌─────────────────────────────────────────┐
│  Server Logic:                           │
│  1. Auth check (session.schoolId)        │
│  2. Verify student owns school_id        │
│  3. Set left_at = NOW()                  │
│  4. Update status + left_reason          │
│  5. Return updated student               │
└──────────────┬──────────────────────────┘
               │
               ↓
┌─────────────────────────────────────────┐
│  UI: Show confirmation                   │
│  Student marked as left                  │
│  Status badge changes color              │
└─────────────────────────────────────────┘
```

### Query Examples

```sql
-- Find all active students in a school
SELECT * FROM students 
WHERE school_id = 6 AND status = 'active';

-- Find students who left
SELECT * FROM students 
WHERE school_id = 6 AND status = 'left' 
ORDER BY left_at DESC;

-- Students graduated this year
SELECT * FROM students 
WHERE school_id = 6 
  AND status = 'graduated' 
  AND YEAR(left_at) = 2026;

-- Find students with specific left reason
SELECT * FROM students 
WHERE school_id = 6 
  AND status = 'left' 
  AND left_reason LIKE '%expelled%';
```

---

## 2️⃣ STUDENT PROFILE SYSTEM

### Data Structure

```
GET /api/students/:id/profile

Response:
{
  "student": {
    id, admission_no, status, left_at, left_reason,
    first_name, last_name, gender, date_of_birth,
    photo_url, email, phone, admission_date, notes
  },
  "enrollments": [
    {
      id, class_id, class_name, stream_id, stream_name,
      term_id, term_name, academic_year_id, academic_year_name,
      status, enrollment_date
    }
  ],
  "results": [
    {
      id, exam_name, subject_name, score, grade,
      term_name, academic_year_name, exam_date, remarks
    }
  ],
  "guardian": {
    id, first_name, last_name, email, phone, address
  },
  "stats": {
    totalResults: 45,
    examsPassed: 42,
    averageScore: "87.5",
    currentClass: "Primary 3",
    status: "active"
  }
}
```

### UI Tabs

| Tab | Shows |
|-----|-------|
| **Overview** | Name, photo, DOB, gender, contact, admission date, status |
| **Academics** | Enrollment history, classes, streams, terms |
| **Results** | All exam results with scores and grades |
| **Finance** | Fee balance and payment history |
| **Documents** | Certificates, transcripts, etc. |

### Component Hierarchy

```
/students/[id]
├─ Header (Photo, Name, Status, Quick Actions)
├─ Tab Navigation
└─ Tab Panels
   ├─ OverviewTab (Personal Info, Enrollment Info)
   ├─ AcademicsTab (Enrollments Table)
   ├─ ResultsTab (Results Table with color-coded grades)
   ├─ FinanceTab (Fee Balance Widget)
   └─ DocumentsTab (Document Upload/View)
```

---

## 3️⃣ BULK IMPORT ENGINE

### Architecture

```
┌──────────────────────────────────────────────────┐
│  User: Upload CSV/XLSX                           │
└────────────────┬─────────────────────────────────┘
                 │
                 ↓
┌──────────────────────────────────────────────────┐
│  PHASE 1: Preview (Validation Only)              │
│  ────────────────────────────────────────────    │
│  • Parse file                                    │
│  • Validate required columns                     │
│  • Check for duplicates (admission_no)           │
│  • Show sample 5 rows                            │
│  • Report any warnings/errors                    │
│  • Do NOT insert anything                        │
└────────────────┬─────────────────────────────────┘
                 │
                 ↓
┌──────────────────────────────────────────────────┐
│  UI: Review Preview                              │
│  ├─ Show first 5 sample rows                     │
│  ├─ Display any warnings                         │
│  ├─ Show import count                            │
│  └─ [Import] button (ready to go)                │
└────────────────┬─────────────────────────────────┘
                 │
                 ↓
┌──────────────────────────────────────────────────┐
│  PHASE 2: Import (Actual Insert)                 │
│  ──────────────────────────────────────────      │
│  For each row:                                   │
│    1. Validate fields                            │
│    2. Get/Create class (auto-create if needed)   │
│    3. Get/Create stream (auto-create if needed)  │
│    4. Check for duplicate (admission_no)         │
│    5. Insert person                              │
│    6. Insert student                             │
│    7. Insert enrollment                          │
│    8. Rollback if any error                      │
└────────────────┬─────────────────────────────────┘
                 │
                 ↓
┌──────────────────────────────────────────────────┐
│  UI: Import Results                              │
│  ├─ Imported: X students ✅                      │
│  ├─ Skipped: Y students (duplicates)             │
│  ├─ Errors: Z students (detail list)             │
│  └─ [Import Another File] button                 │
└──────────────────────────────────────────────────┘
```

### CSV Format

```
REQUIRED COLUMNS:
- name: "FirstName LastName"
- reg_no: "ADM-001"
- class: "Primary 1"

OPTIONAL COLUMNS:
- section: "A"
- stream: "Standard"
- balance_fees: "500.00"

EXAMPLE FILE:
───────────────────────────────────────────
name,reg_no,class,stream,balance_fees
John Doe,ADM-001,Primary 1,Standard,0
Jane Smith,ADM-002,Primary 1,Standard,500
Ahmed Hassan,ADM-003,Primary 2,Hebrew,1000
───────────────────────────────────────────
```

### Transaction Flow

```
BEGIN TRANSACTION
├─ [Row 1] John Doe
│  ├─ Create person
│  ├─ Create student (ADM-001)
│  ├─ Create enrollment
│  └─ ✅ Committed
├─ [Row 2] Jane Smith
│  ├─ Create person
│  ├─ Create student (ADM-002)
│  ├─ Create enrollment
│  └─ ✅ Committed
└─ [Row 3] Duplicate ADM-001
   ├─ Validate... DUPLICATE FOUND
   └─ ❌ SKIPPED (not inserted)

RESULT:
Imported: 2
Skipped: 1
```

### Automatic Class/Stream Creation

```
If class "Primary 1" doesn't exist:
↓
INSERT INTO classes (school_id, name, description)
VALUES (6, 'Primary 1', 'Auto-created from import')

If stream "Hebrew" doesn't exist:
↓
INSERT INTO streams (school_id, name)
VALUES (6, 'Hebrew')
```

---

## 🔒 SECURITY MODEL

### Multi-Tenant Isolation

```
LIFECYCLE STATUS:
PATCH /api/students/:id/status
├─ Check session.schoolId (e.g., 6)
├─ Check student.school_id (e.g., 6)
├─ If mismatch: 403 Forbidden
└─ Only allow update if match ✅

PROFILE FETCH:
GET /api/students/:id/profile
├─ Get session.schoolId (e.g., 6)
├─ WHERE student WHERE id = :id AND school_id = 6
├─ Only return if school matches
└─ 404 if accessed from wrong school

BULK IMPORT:
POST /api/students/import
├─ Get session.schoolId (e.g., 6)
├─ Tag all new records with school_id = 6
├─ Check for duplicates ONLY within school 6
├─ admission_no must be unique PER SCHOOL
└─ Never reveal other schools' conflicts
```

### Authorization Rules

```
STUDENT LIST (active):
  ✅ Teacher: Can see all students in their school
  ✅ Admin: Can see all students in their school
  ❌ Teacher: Cannot see other school's students
  ❌ Student: Cannot see other students

STUDENT PROFILE:
  ✅ Teacher: Can view any student in school
  ✅ Admin: Can view any student in school
  ✅ Parent: Can view only own child
  ❌ Teacher: Cannot view other school's students

BULK IMPORT:
  ✅ Headmaster: Can import for school
  ✅ Admin: Can import for school
  ❌ Teacher: Cannot import (permission denied)
  ❌ Anyone: Cannot import to other school
```

---

## 📊 PERFORMANCE QUERIES

### Optimized Queries

```sql
-- Get all active students (indexed)
SELECT * FROM students
WHERE school_id = ? AND status = 'active'
  AND deleted_at IS NULL
ORDER BY last_name, first_name;
-- Uses: idx_students_status, idx_students_status_deleted

-- Get students who left this year (indexed)
SELECT * FROM students
WHERE school_id = ? AND status = 'left'
  AND YEAR(left_at) = ?;
-- Uses: idx_students_left_at

-- Profile fetch (optimized)
SELECT s.*, p.*, 
  COUNT(DISTINCT r.id) as result_count
FROM students s
JOIN people p ON s.person_id = p.id
LEFT JOIN results r ON r.student_id = s.id
WHERE s.id = ? AND s.school_id = ?
GROUP BY s.id;
-- Single query with all data

-- Bulk list with enrollments
SELECT s.*, c.name as class_name, 
  COUNT(r.id) as result_count
FROM students s
LEFT JOIN enrollments e ON e.student_id = s.id 
  AND e.status = 'active'
LEFT JOIN classes c ON c.id = e.class_id
LEFT JOIN results r ON r.student_id = s.id
WHERE s.school_id = ? AND s.status = 'active'
GROUP BY s.id;
-- Efficient table scan with aggregates
```

### Index Strategy

```sql
-- Existing indexes
✅ idx_students_school_id
✅ idx_students_deleted_at

-- New indexes (migration 021)
✅ idx_students_status (school_id, status)
✅ idx_students_left_at (left_at)

-- Proposed future indexes
⏳ idx_students_admission_no (school_id, admission_no) UNIQUE
⏳ idx_results_school_id (for results table filtering)
```

---

## 🧪 TESTING SCENARIOS

### Lifecycle Management

```
Test 1: Mark student as left with reason
  Input: status="left", left_reason="Expelled due to behavior"
  Expected: Student marked, timestamp set, status visible
  
Test 2: Suspend student temporarily
  Input: status="suspended"
  Expected: Student marked suspended, can be reactivated
  
Test 3: Mark graduated
  Input: status="graduated"
  Expected: Archive student, move to completed
  
Test 4: No permission to update another school
  Input: LoggedIn as School A, update School B student
  Expected: 403 Forbidden
```

### Bulk Import

```
Test 1: Import 100 valid students
  Expected: 100 imported, 0 skipped
  
Test 2: Import with 5 duplicates
  Expected: 95 imported, 5 skipped (duplicates)
  
Test 3: Import with missing class
  Expected: Class auto-created, students enrolled
  
Test 4: Import with invalid fee format
  Expected: Row error, skipped, others imported
  
Test 5: Two schools import same reg_no
  Expected: Both allowed (unique per school, not global)
```

### Profile View

```
Test 1: View complete student profile
  Expected: All tabs load (Overview, Academics, Results, Finance)
  
Test 2: View student who left
  Expected: Show "left" status, left_at date, left_reason
  
Test 3: Profile with 100 exam results
  Expected: Load fast, paginate if needed
  
Test 4: Cross-school profile access
  Expected: 404 Not Found (forbidden access)
```

---

## 🚀 DEPLOYMENT STEPS

### 1. Database Preparation
```bash
# Connect to TiDB. Take the values from your own `drais.env` — the live
# username and password were written out here in full, which is exactly how
# credentials end up in a public repository.
mysql -h "$TIDB_HOST" \
  -u "$TIDB_USER" \
  -p"$TIDB_PASSWORD" \
  -D "$TIDB_DB"

# Run migration
SOURCE database/migrations/021_add_student_lifecycle.sql;

# Verify
DESCRIBE students;
-- Should show: status, left_at, left_reason columns
```

### 2. API Deployment
```bash
# Files already in place:
- src/app/api/students/[id]/status/route.ts
- src/app/api/students/[id]/profile/route.ts (enhanced)
- src/app/api/students/import/route.ts (enhanced)

# Just need to deploy Next.js app
npm run build
npm run start
```

### 3. UI Deployment
```bash
# Files already in place:
- src/app/students/[id]/page.tsx (enhanced with tabs)
- src/app/students/import/page.tsx (new UI)
- src/app/students/list/page.tsx (add dropdown actions)

# Test URLs:
http://localhost:3000/students/1 (profile)
http://localhost:3000/students/import (bulk import)
http://localhost:3000/students/list (lifecycle management)
```

### 4. Testing
```bash
# Test each endpoint
curl -X PATCH http://localhost:3000/api/students/1/status \
  -H "Authorization: Bearer token" \
  -d '{"status": "left", "left_reason": "Transferred"}'

# Test bulk import
curl -X POST http://localhost:3000/api/students/import \
  -H "Authorization: Bearer token" \
  -F "file=@data.csv" \
  -F "mode=preview"

# Test profile
curl http://localhost:3000/api/students/1/profile \
  -H "Authorization: Bearer token"
```

---

## 📈 BUSINESS METRICS

```
ADOPTION SUCCESS METRICS:
- Schools importing >10 students/month
- Average import time <5 minutes 
- Status tracking usage >80% of schools
- Profile views >50% of student interactions
- Duplicate detection preventing 5% of imports

PERFORMANCE METRICS:
- Status update <100ms
- Profile load <300ms
- Bulk import 100 students <30 seconds
- Query response <50ms with proper indexing
```

---

**Version**: 1.0
**Last Updated**: 2026-03-24
**Status**: 🟢 READY FOR PRODUCTION
