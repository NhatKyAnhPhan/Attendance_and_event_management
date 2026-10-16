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

## Face attendance test

The Flutter app bundles the consented `facedataset/Dieu/`,
`facedataset/Tam/`, and `facedataset/KyAnh/` samples and matches a captured
image against all three profiles on-device with a pretrained MobileFaceNet
model. It computes embeddings for up to 12 evenly-spaced sample images per
person on first use; it does not train or fine-tune the model. Face images and
embeddings are not sent to this API. The test database script adds students
`2001230097` (Dieu), `2001230787` (Tam), and `2001230014` (KyAnh).
Initialize the schema with `../database/QL_SuKienDA.sql`, then load data with
`../database/DuLieuTest_QLSK.sql`. The latter also adds a demo attendance
records for Dieu and Tam for the ended `SK003` event, which has a certificate
benefit, so certificate delivery to either test email can be tested. The test
account password is `123456`.

The face endpoint checks that the recognized student ID matches the
authenticated account, then applies the same open-session, enrollment, device,
duplicate-attendance, and location checks as QR attendance. It does not
independently verify the face image or provide liveness detection, so client
recognition is suitable for the test app only, not as a production security
boundary.
