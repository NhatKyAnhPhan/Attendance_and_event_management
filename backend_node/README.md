# Event attendance certificates

The event QR flow uses the existing student QR scanner. An event organizer opens
the event details and selects **QR điểm danh**; students must be registered for
the event and scan the QR while the event is active. A scan is recorded once
per student and event in the `event_attendance` table, which the API creates
when it starts.

After the event ends, select **Gửi chứng nhận** in the event details. The API
creates a personalized landscape PDF from `certificate-template.png` and emails
it only to students with a recorded event check-in. Certificate rows are stored
in the existing `chungnhan` table. Failed email addresses are reported so the
organizer can correct the account and retry.

Configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_FROM` and, when required
by the provider, `SMTP_USER` / `SMTP_PASSWORD` in `backend_node/.env`. Do not
commit actual SMTP credentials. Set `PUBLIC_API_BASE_URL` to the externally
reachable API base URL so the certificate QR code can open its verification
endpoint. On Windows the API uses Arial by default; on Linux/macOS set
`CERTIFICATE_FONT_PATH` to a Vietnamese-capable TTF font if the system default
font candidates are unavailable.
