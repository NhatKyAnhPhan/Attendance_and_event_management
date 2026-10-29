# HUIT web portal

The React portal is a separate web client with a role-selection landing page
and role-specific workspaces for students, lecturers, employees, and
administrators. It uses the existing API and leaves the Flutter app unchanged.
Lecturers and event organizers can create attendance QR codes from the web;
the backend signs those tokens, and the Flutter mobile app scans the same QR
format and records check-in. Student check-in remains on Android so the app can
capture device location, device identity, and (when selected) face attendance.

Both clients must use the same API host for a QR issued on the web to be valid
in Flutter. Set `VITE_API_BASE_URL` for React and configure the Flutter API URL
to that same host. The default production API URL is shared by both clients.
Class/event roster imports accept `.xlsx` files or pasted student IDs, and
attendance reports can be exported to Excel.

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
