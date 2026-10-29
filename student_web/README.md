# HUIT web portal

The React portal is a separate web client with a role-selection landing page
and role-specific workspaces for students, lecturers, employees, and
administrators. It uses the existing API and leaves the Flutter app unchanged.
Attendance check-in is intentionally unavailable in the React student portal;
students are directed to Android to scan QR codes or use face attendance.

## Run locally

1. Install Node.js 20.19+.
2. From this folder, run `npm install`.
3. Copy `.env.example` to `.env.local` and set `VITE_API_BASE_URL` to the API
   base URL (for example `http://localhost:3000`).
4. Run `npm run dev` and open the URL printed by Vite.

For production, run `npm run build` and deploy the generated `dist/` folder as
a static site. Configure the API's CORS allowlist for the deployed web origin.
The API base URL is public client configuration; never put API secrets in
`VITE_*` variables.
