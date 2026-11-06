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

The staff certificate list displays only **Đã cấp** and **Chưa cấp**. Staff
can preview an issued certificate as a PDF from the list; the preview endpoint
only serves certificates for events within the staff member's unit (admins can
preview all certificates).

Admins and staff can open **Xem mẫu** from the certificate list to preview the
certificate template and independently upload or draw signatures and set names
for both the organizer and dean. Confirmed signatures and names are applied to
certificates generated afterward. Each issued certificate stores its own
signature and name snapshots, so changing or resetting the template never
changes previously issued PDFs. Existing certificates retain their saved dean
signature during migration; the current template is used to initialize the
organizer signature and signer names. **Đặt lại cả hai** removes both saved
signatures and names without changing issued certificates.

For SMTP, configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_FROM` and,
when required by the provider, `SMTP_USER` / `SMTP_PASSWORD`. On hosts that
block SMTP egress, use an HTTPS email API. For Resend, set `MAIL_PROVIDER=resend`,
`RESEND_API_KEY`, and `MAIL_FROM` to an address on a verified Resend domain,
for example `HUIT <chungnhan@your-verified-domain.com>`. `MAIL_FROM` must be an
email address, not just a domain name; verify the sending domain in Resend and
publish its required DNS records before sending.
For Brevo, set `MAIL_PROVIDER=brevo`, `BREVO_API_KEY`, and `MAIL_FROM` to the
sender email configured and verified in Brevo, optionally with its display name
(for example `HUIT <chungnhan@your-domain.com>`). The API sends transactional
emails over HTTPS and supports the certificate PDF attachment.
Both password recovery messages and certificate PDFs use the selected provider.
Do not commit actual API keys or SMTP credentials. Set `PUBLIC_API_BASE_URL` to
the externally reachable API base URL so the certificate QR code can open its
verification endpoint. On Windows the API uses Arial by default; on Linux/macOS set
`CERTIFICATE_FONT_PATH` to a Vietnamese-capable TTF font if the system default
font candidates are unavailable.

## Password recovery

The login page sends a six-digit, single-use code to the account email. Codes
expire after 10 minutes, allow at most five verification attempts, and can be
requested once per minute. A verified code grants a separate, short-lived
single-use reset token; the password is hashed by the API and never sent by
email.

Configure the SMTP variables above and set `PASSWORD_RESET_SECRET` in
the backend environment (or `backend_node/.env` locally) to an independent
random value of at least 32 bytes. The password reset flow uses the same
`MAIL_PROVIDER`, `MAIL_FROM`, and provider credentials configured above; both
the Flutter app and student web client use the same backend endpoints and do
not need provider keys in the client. Replace the example secrets in
`.env.example` before use; do not commit `.env` or real email credentials.
Restart or redeploy the backend after changing environment settings.

Recovery uses the email currently stored for the account. Profile email edits
are not verified yet, so users should use an email they can access; before
production, add email verification (or have an administrator confirm school
addresses) and require verification when an email is changed.

## Firebase push notifications

The Flutter Android app registers its FCM token after a student signs in. The
API stores device tokens in `user_fcm_tokens` and sends a push to a class's
active members when a lecturer opens an attendance session. The table is created
automatically when the API starts.

Create a Firebase service account for the same Firebase project as the mobile
app. In Render, upload its JSON key under **Environment → Secret Files**, then
set `FIREBASE_SERVICE_ACCOUNT_FILE` to `/etc/secrets/<uploaded-filename>`.
Alternatively, set `FIREBASE_SERVICE_ACCOUNT_JSON` to the full JSON value in
Environment Variables. Keep the key private and never put it in the Flutter app
or commit it. Without either setting, token registration still works, but the
backend skips sending pushes. Redeploy the API after configuring it.

Android 13+ asks the student for notification permission. Push delivery should
be checked on a physical Android device with Google Play services, with the app
both in the foreground and in the background.

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

## Event cover photos

On startup, the API adds the nullable `HinhAnh` column to `SuKien` if needed and
fills events without a photo with a topic-matched Unsplash image URL. Existing
photo URLs are preserved. In the event create/edit form, organizers can upload
a JPEG, PNG, or WebP file up to 5 MB, or provide an HTTP(S) image URL. Uploaded
files are stored under `backend_node/uploads/events` by default; set
`EVENT_IMAGES_DIRECTORY` to use a persistent storage directory on a hosted
deployment. Leaving both image inputs empty selects an Unsplash image based on
the event name and description. The student event cards and details load the
saved image URL, so clients need internet access to display remote photos.

## Event registration forms

The API adds the nullable `DonDangKy` column to `SuKien` on startup. Organizers
can upload a signed PDF registration form up to 10 MB when creating an event;
the management and student event details open the saved PDF in a new tab.
Uploaded files are stored under
`backend_node/uploads/event-registration-forms` by default; set
`EVENT_REGISTRATION_FORMS_DIRECTORY` to use persistent storage on a hosted
deployment. Older events without a form display “Không có đơn đăng ký.”
