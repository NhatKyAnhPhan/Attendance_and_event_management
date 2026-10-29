# HUIT web portal

The React portal is a separate web client with a role-selection landing page
and distinct sign-in screens for students, lecturers, and employees. It uses
the existing Node.js API and leaves the Flutter Android app unchanged. The
student workspace is implemented in React. Lecturer and employee credentials
are role-checked, then directed to the existing application because their web
workspaces are not part of this portal yet. Attendance check-in is intentionally
unavailable on the web; students are directed to Android to scan QR codes or
use face attendance.

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
