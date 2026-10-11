-- ==============================================================================
-- KITAAB DOST NETWORK | BOOKBRIDGE — SUPABASE PRODUCTION DATABASE SCHEMA
-- Project: https://uqotflogqjlkhozhrpdd.supabase.co
-- ==============================================================================
-- Instructions:
-- 1. Open your Supabase Dashboard: https://supabase.com/dashboard/project/uqotflogqjlkhozhrpdd/sql
-- 2. Click "New Query" and paste the entire contents of this file.
-- 3. Click "Run" (or Ctrl+Enter) to initialize tables, indexes, realtime, and RLS.
-- ==============================================================================

-- 1. Create book_requests table
CREATE TABLE IF NOT EXISTS public.book_requests (
    id TEXT PRIMARY KEY,
    school_name TEXT NOT NULL,
    emis_code TEXT,
    location TEXT NOT NULL,
    delivery_address TEXT,
    grade_level TEXT NOT NULL,
    subject TEXT NOT NULL,
    book_title TEXT NOT NULL,
    description TEXT,
    quantity_needed INTEGER NOT NULL DEFAULT 1,
    quantity_pledged INTEGER NOT NULL DEFAULT 0,
    urgency TEXT NOT NULL DEFAULT 'Medium' CHECK (urgency IN ('Critical', 'High', 'Medium')),
    contact_person TEXT NOT NULL,
    contact_phone TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending', 'Partially Funded', 'Fulfilled', 'Shipped', 'Delivered')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Create pledges table
CREATE TABLE IF NOT EXISTS public.pledges (
    id TEXT PRIMARY KEY,
    request_id TEXT NOT NULL REFERENCES public.book_requests(id) ON DELETE CASCADE,
    ngo_name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Indexes for fast search and filtering
CREATE INDEX IF NOT EXISTS idx_book_requests_status ON public.book_requests(status);
CREATE INDEX IF NOT EXISTS idx_book_requests_subject ON public.book_requests(subject);
CREATE INDEX IF NOT EXISTS idx_book_requests_grade ON public.book_requests(grade_level);
CREATE INDEX IF NOT EXISTS idx_book_requests_urgency ON public.book_requests(urgency);
CREATE INDEX IF NOT EXISTS idx_book_requests_created ON public.book_requests(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pledges_request_id ON public.pledges(request_id);

-- 4. Enable Supabase Realtime for instant multi-user updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.book_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE public.pledges;

-- 5. Row-Level Security (RLS) Setup
ALTER TABLE public.book_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pledges ENABLE ROW LEVEL SECURITY;

-- 5a. Public read access (Allows anonymous visitors & NGOs to discover book needs)
CREATE POLICY "Allow public read access to book_requests"
    ON public.book_requests FOR SELECT
    USING (true);

CREATE POLICY "Allow public read access to pledges"
    ON public.pledges FOR SELECT
    USING (true);

-- 5b. Write policies (Allows authenticated or demo users to publish requests and pledges)
CREATE POLICY "Allow insert to book_requests"
    ON public.book_requests FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Allow update to book_requests"
    ON public.book_requests FOR UPDATE
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Allow insert to pledges"
    ON public.pledges FOR INSERT
    WITH CHECK (true);

-- 6. Initial Seed Data (Pakistani Under-Resourced Schools)
INSERT INTO public.book_requests (
    id, school_name, emis_code, location, delivery_address, grade_level, subject,
    book_title, description, quantity_needed, quantity_pledged, urgency,
    contact_person, contact_phone, status
) VALUES
(
    'req-101',
    'Al-Noor Community Model School',
    '35210049',
    'Lahore, Punjab',
    'Main Gate, Plot 14-B, Sector 4, Near Grid Station, Lahore',
    'Grades 6-8 (Middle)',
    'Science',
    'General Science & Lab Experiments (PTB Illustrated Edition)',
    'Our middle school students are currently sharing 1 textbook among 4 students. Having individual books will allow them to study diagrams and complete homework assignments.',
    60,
    40,
    'High',
    'Mrs. Tahira Perveen (Principal)',
    '+92 300 4128901',
    'Partially Funded'
),
(
    'req-102',
    'Roshni Primary Government School',
    '21094012',
    'Multan, South Punjab',
    'Government Primary School Campus, Bosan Road, Multan',
    'Grades 1-5 (Primary)',
    'Urdu & Regional',
    'Nardban-e-Urdu & Illustrated Storybooks Set',
    'Looking for foundational Urdu phonics and early reading storybooks to establish our first classroom reading corner for 120 first-generation learners.',
    80,
    0,
    'Critical',
    'Mr. Sajjad Hussain (Headmaster)',
    '+92 321 6781122',
    'Pending'
),
(
    'req-103',
    'Umeed Welfare Girls High School',
    '40108821',
    'Karachi, Sindh',
    'Umeed Welfare Campus, Street 9, Sector 11-A, Orangi Town, Karachi',
    'Grades 9-10 (Matric)',
    'Mathematics',
    'Secondary Stage Mathematics Class 9 & 10 + Geometry Kits',
    'Board examinations are approaching in 3 months and 45 of our 9th & 10th grade girls lack updated textbooks and past paper workbooks.',
    45,
    45,
    'High',
    'Ms. Sadia Qureshi (Coordinator)',
    '+92 333 2190445',
    'Fulfilled'
),
(
    'req-104',
    'Kohsar Valley Rural Elementary',
    '15302910',
    'Swat, KP',
    'Kohsar Model School, Mingora Bazar Bypass, Swat',
    'Grades 6-8 (Middle)',
    'English Literature',
    'Oxford Progressive English Readers & Pocket Dictionaries',
    'Students have strong enthusiasm for learning English vocabulary, but our library lost most books during last season’s heavy rains.',
    50,
    15,
    'Medium',
    'Mr. Kamran Khattak (Senior Teacher)',
    '+92 345 9012388',
    'Partially Funded'
),
(
    'req-105',
    'Chiltan Community School',
    '61092833',
    'Quetta, Balochistan',
    'Brewery Road near Western Bypass, Quetta',
    'Grades 9-10 (Matric)',
    'Computer Science',
    'Fundamentals of Computer Science & IT Basics',
    'We recently received 5 donated desktop computers, and now we need textbooks so students can study programming logic and hardware fundamentals.',
    35,
    0,
    'Critical',
    'Mr. Mirwais Baloch (Administrator)',
    '+92 312 8834901',
    'Pending'
),
(
    'req-106',
    'Al-Noor Community Model School',
    '35210049',
    'Lahore, Punjab',
    'Main Gate, Plot 14-B, Sector 4, Near Grid Station, Lahore',
    'Grades 1-5 (Primary)',
    'Mathematics',
    'Primary Countdown Mathematics Workbooks (Level 3 & 4)',
    'Activity-based math books with visual number puzzles for our Grade 3 and Grade 4 classrooms.',
    50,
    50,
    'Medium',
    'Mrs. Tahira Perveen (Principal)',
    '+92 300 4128901',
    'Shipped'
)
ON CONFLICT (id) DO NOTHING;

-- Seed Pledges
INSERT INTO public.pledges (id, request_id, ngo_name, quantity, note) VALUES
(
    'p-1',
    'req-101',
    'Read Pakistan Foundation',
    40,
    'Dispatched via courier from our Lahore Gulberg warehouse. Expected arrival by Thursday.'
),
(
    'p-2',
    'req-103',
    'Zindagi Trust Book Drive',
    25,
    'Delivering 25 new copies Monday morning.'
),
(
    'p-3',
    'req-103',
    'Citizens Education Alliance',
    20,
    'Remaining 20 copies + geometry sets packed and ready.'
),
(
    'p-4',
    'req-104',
    'Kitaab Dost Initiative',
    15,
    'Sending 15 Oxford English dictionaries and graded readers.'
),
(
    'p-5',
    'req-106',
    'Ilm-o-Amal Foundation',
    50,
    'Full batch shipped via TCS (Tracking #8891204).'
)
ON CONFLICT (id) DO NOTHING;
