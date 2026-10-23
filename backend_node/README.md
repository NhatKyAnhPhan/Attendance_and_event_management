# Event attendance certificates

The event QR flow uses the existing student QR scanner. An event organizer opens
the event details and selects **Mở phiên điểm danh**. Each activation creates a
separate QR session; organizers can close a session without closing the event,
then open another session later. Students must be registered for the event and
scan that session's QR while both the event and session are active. Attendance
is recorded once per student per session in `event_attendance_records`, so a
student can be present in one session and absent in another. The
`event_attendance` table remains the event-level attendance summary used for
rosters and certificates.

After the event ends or it has been closed, select **Gửi chứng nhận** in the
event details. The API creates a personalized landscape PDF from
`certificate-template.png` and emails it only to students with a recorded event
check-in. A successfully delivered certificate is marked **Đã cấp** in the
existing `chungnhan` table and is not sent again on later attempts. Failed
deliveries remain eligible for retry; students who have already received their
certificate are skipped. If no checked-in students remain eligible, the API
reports that no certificate can be issued. Failed email addresses are reported
so the organizer can correct the account and retry.

Configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_FROM` and, when required
by the provider, `SMTP_USER` / `SMTP_PASSWORD` in `backend_node/.env`. Do not
commit actual SMTP credentials. Set `PUBLIC_API_BASE_URL` to the externally
reachable API base URL so the certificate QR code can open its verification
endpoint. On Windows the API uses Arial by default; on Linux/macOS set
`CERTIFICATE_FONT_PATH` to a Vietnamese-capable TTF font if the system default
font candidates are unavailable.

## Password recovery

The login page sends a six-digit, single-use code to the account email. Codes
expire after 10 minutes, allow at most five verification attempts, and can be
requested once per minute. A verified code grants a separate, short-lived
single-use reset token; the password is hashed by the API and never sent by
email.

Configure the SMTP variables above and set `PASSWORD_RESET_SECRET` in
`backend_node/.env` to an independent random value of at least 32 bytes. Replace
the example secrets in `.env.example` before use; do not commit `.env` or real
SMTP credentials. Restart the backend after changing environment settings.

Recovery uses the email currently stored for the account. Profile email edits
are not verified yet, so users should use an email they can access; before
production, add email verification (or have an administrator confirm school
addresses) and require verification when an email is changed.

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
authenticated account. Students can select an eligible open class session or
event before scanning; class sessions must allow `Face` or `Both`, and an event
must have an active organizer-generated attendance session. The selected session ID
is checked by the API along with enrollment/registration, duplicate attendance,
device, and location. Event attendance records are scoped to the selected
session, while class attendance keeps its existing class-session behavior. Face
matching remains on-device and the API
does not independently verify the face image or provide liveness detection, so
client recognition is suitable for the test app only, not as a production
security boundary.

## Login page statistics

The login page loads aggregate counts from the unauthenticated
`GET /api/public/stats` endpoint. It returns student, lecturer, class, and event
counts from the database without exposing user records.
