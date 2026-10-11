# BookBridge | Kitaab Dost Network 📚🇵🇰

> Direct textbook & library bridge linking under-resourced Pakistani schools with verified education NGOs and donors.

---

## 🌟 Live Deployment
- **Live Website**: [https://richbrokie.github.io/kitaab-dost/](https://richbrokie.github.io/kitaab-dost/)
- **Hosting**: 100% Free on GitHub Pages (Zero ongoing hosting cost)
- **Cloud Backend**: Supabase PostgreSQL with Realtime multi-client syncing

---

## 🌟 Overview
Many schools across Pakistan face severe textbook shortages, where 3 to 4 students are forced to share a single book or lack reading material entirely. 

**BookBridge** provides a direct, transparent dual-portal web application:
1. **School Portal**: Teachers and headmasters submit specific curriculum requests (subject, grade level, textbook edition, quantity needed, urgency, and classroom context).
2. **NGO Donor Dashboard**: Verified education NGOs and book donors discover verified requests, filter by need and region, pledge books, and provide courier/tracking notes.
3. **Delivery & Acknowledgment Loop**: Once shipped, schools confirm receipt directly in the classroom with a note back to donors.
4. **Impact Overview**: Real-time transparency metrics showing books pledged, students impacted, and fulfillment rates by subject.

---

## 🚀 Key Production Features

### 1. 🛡️ Official EMIS Verification
- Schools can specify their official provincial **EMIS / SEMIS Code** (e.g., `35210049` for Punjab, `40108821` for Sindh).
- Request cards showcase an official verified badge (`EMIS #35210049 (Verified)`), allowing NGOs to verify schools directly against government records.

### 2. 🔒 Contact Privacy & Scraper Protection
- Anonymous public visitors see masked phone numbers (`+92 ••• ••••••• [Sign in to view]`) to protect school teachers and principals against automated web scrapers.
- Authenticated schools and NGOs have instant access to direct phone & WhatsApp communication.

### 3. 🖨️ Printable Courier Packing & Dispatch Dockets
- One-click **Courier Slip** generator formatted for Pakistani parcel couriers: **TCS Express, Leopards Courier, Trax, and Pakistan Post**.
- Generates a clean A4/thermal printable document (`window.print()`) with:
  - Consignor (Sender NGO) and Consignee (School) details.
  - Campus delivery gate instructions & contact phone numbers.
  - Tracking barcode visualization & reference number (`KD-PK-REQ...`).
  - Handling instructions for fragile educational material.
  - POD (Proof of Delivery) stamps & signature blocks.

### 4. 📲 WhatsApp Direct Share
- Pre-formatted 1-click sharing buttons to broadcast school book needs to WhatsApp groups, donors, and alumni networks.

### 5. ⚡ Real-Time Cloud Sync (Supabase)
- Dual client syncing using `@supabase/supabase-js@2` and PostgreSQL Realtime changes. When an NGO pledges books, any open school screen updates instantly without refreshing.

---

## 🛠️ Production Database Setup (Supabase)

To deploy or reset the production cloud database:
1. Open your Supabase Dashboard: [https://supabase.com/dashboard/project/uqotflogqjlkhozhrpdd/sql](https://supabase.com/dashboard/project/uqotflogqjlkhozhrpdd/sql)
2. Click **New Query**.
3. Copy the entire contents of [`production-schema.sql`](./production-schema.sql) and paste it into the SQL editor.
4. Click **Run**. This will:
   - Create tables `book_requests` and `pledges`.
   - Setup indexes for high-speed search and filtering.
   - Enable Supabase Realtime replication on both tables.
   - Configure Row-Level Security (RLS) policies for secure access.
   - Seed initial verified requests and pledges across Lahore, Karachi, Multan, Swat, and Quetta.

---

## 💻 Local Development & Testing

```bash
# Start local HTTP server
py -m http.server 3000

# Open in browser
http://localhost:3000/index.html
```

---

## 📄 Documentation
- Detailed User Guide for Schools & NGOs: [`MANUAL.md`](./MANUAL.md)
- Production Database Schema: [`production-schema.sql`](./production-schema.sql)
