const crypto = require('crypto');
const fs = require('fs');
const admin = require('firebase-admin');

let messaging = null;

function getMessaging() {
  if (messaging) return messaging;
  let rawCredentials = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const credentialsFile = process.env.FIREBASE_SERVICE_ACCOUNT_FILE;
  if (!rawCredentials && credentialsFile) {
    try {
      rawCredentials = fs.readFileSync(credentialsFile, 'utf8');
    } catch (error) {
      console.error('Firebase service account file could not be read:', error.message);
      return null;
    }
  }
  if (!rawCredentials) return null;
  try {
    const credentials = JSON.parse(rawCredentials);
    const app = admin.apps.length
      ? admin.app()
      : admin.initializeApp({ credential: admin.credential.cert(credentials) });
    messaging = admin.messaging(app);
    return messaging;
  } catch (error) {
    console.error('Firebase Admin initialization failed:', error.message);
    return null;
  }
}

function tokenHash(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

async function sendClassAttendancePush(pool, { classId, sessionId, method, closesAt }) {
  const fcm = getMessaging();
  if (!fcm) return;
  const [rows] = await pool.execute(
    `SELECT DISTINCT t.token_hash AS tokenHash, t.token
     FROM user_fcm_tokens t
     INNER JOIN ThanhVienLop tvl ON tvl.Masv = t.user_id
     WHERE tvl.Malop = ? AND tvl.TrangThaiThanhVien <> 'Đã rút'`,
    [classId],
  );
  const tokens = rows.map((row) => row.token).filter(Boolean);
  for (let offset = 0; offset < tokens.length; offset += 500) {
    const batch = tokens.slice(offset, offset + 500);
    const response = await fcm.sendEachForMulticast({
      tokens: batch,
      notification: {
        title: `Điểm danh lớp ${classId} đã mở`,
        body: `Phiên điểm danh ${method} đã bắt đầu. Hãy mở ứng dụng để điểm danh.`,
      },
      data: {
        type: 'class_attendance_opened',
        classId: String(classId),
        sessionId: String(sessionId),
        closesAt: new Date(closesAt).toISOString(),
      },
      android: { priority: 'high' },
    });
    const staleHashes = [];
    response.responses.forEach((item, index) => {
      if (!item.success && [
        'messaging/invalid-registration-token',
        'messaging/registration-token-not-registered',
      ].includes(item.error?.code)) {
        staleHashes.push(tokenHash(batch[index]));
      }
    });
    if (staleHashes.length) {
      await pool.query(
        `DELETE FROM user_fcm_tokens WHERE token_hash IN (${staleHashes.map(() => '?').join(',')})`,
        staleHashes,
      );
    }
  }
}

module.exports = { sendClassAttendancePush, tokenHash };
