require('dotenv').config();

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const multer = require('multer');
const mysql = require('mysql2/promise');
const { createUpdateProfileHandler } = require('./profile_handler');
const {
  createCertificatePdf,
  createMailTransport,
  isMailConfigured,
} = require('./certificate_mailer');
const { createPasswordResetHandlers } = require('./password_reset_handler');
const { sendClassAttendancePush, tokenHash } = require('./push_notifications');
const { isValidEventAttendanceThreshold } = require('./event_attendance_threshold');

const app = express();
const port = Number(process.env.PORT || 3000);
const jwtSecret = process.env.JWT_SECRET || 'change-this-development-secret';
const eventImagesDirectory = path.resolve(
  process.env.EVENT_IMAGES_DIRECTORY || path.join(__dirname, 'uploads', 'events'),
);
const eventRegistrationFormsDirectory = path.resolve(
  process.env.EVENT_REGISTRATION_FORMS_DIRECTORY
    || path.join(__dirname, 'uploads', 'event-registration-forms'),
);
const eventImageExtensions = new Map([
  ['image/jpeg', '.jpg'],
  ['image/png', '.png'],
  ['image/webp', '.webp'],
]);
fs.mkdirSync(eventImagesDirectory, { recursive: true });
fs.mkdirSync(eventRegistrationFormsDirectory, { recursive: true });

const eventImageUpload = multer({
  storage: multer.diskStorage({
    destination: eventImagesDirectory,
    filename: (_request, file, callback) => {
      callback(null, `${crypto.randomUUID()}${eventImageExtensions.get(file.mimetype)}`);
    },
  }),
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
  fileFilter: (_request, file, callback) => {
    if (!eventImageExtensions.has(file.mimetype)) {
      callback(new Error('Chỉ chấp nhận ảnh JPEG, PNG hoặc WebP.'));
      return;
    }
    callback(null, true);
  },
});
const eventRegistrationFormUpload = multer({
  storage: multer.diskStorage({
    destination: eventRegistrationFormsDirectory,
    filename: (_request, file, callback) => {
      callback(null, `${crypto.randomUUID()}.pdf`);
    },
  }),
  limits: { fileSize: 10 * 1024 * 1024, files: 1 },
  fileFilter: (_request, file, callback) => {
    if (file.mimetype !== 'application/pdf' || path.extname(file.originalname).toLowerCase() !== '.pdf') {
      callback(new Error('Chỉ chấp nhận tệp PDF.'));
      return;
    }
    callback(null, true);
  },
});

const dbSslCaPath = process.env.DB_SSL_CA?.trim();
const dbSsl = dbSslCaPath
  ? { ca: fs.readFileSync(path.resolve(__dirname, dbSslCaPath)) }
  : undefined;

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'QL_SuKienDA',
  waitForConnections: true,
  connectionLimit: 10,
  charset: 'utf8mb4',
  ssl: dbSsl,
});

function createCertificatePdfForRequest(request, certificate) {
  const publicBaseUrl = (
    process.env.PUBLIC_API_BASE_URL
    || `${request.protocol}://${request.get('host')}`
  ).replace(/\/+$/, '');
  const verificationUrl =
    `${publicBaseUrl}/certificates/${encodeURIComponent(certificate.certificateId)}`;

  return createCertificatePdf({
    studentName: certificate.studentName,
    studentId: certificate.studentId,
    eventName: certificate.eventName,
    startTime: certificate.startTime,
    endTime: certificate.endTime,
    location: certificate.location || '',
    certificateId: certificate.certificateId,
    issuedAt: certificate.endTime,
    verificationUrl,
    isSample: String(certificate.content || '').startsWith(
      '[MẪU KIỂM THỬ]',
    ),
    organizerSignatureImage: certificate.organizerSignatureImage
      ? Buffer.from(certificate.organizerSignatureImage)
      : null,
    organizerName: certificate.organizerName || '',
    deanSignatureImage: certificate.signatureImage
      ? Buffer.from(certificate.signatureImage)
      : null,
    deanName: certificate.deanName || '',
  });
}

async function findPublicCertificate(certificateId) {
  const [[certificate]] = await pool.execute(
    `SELECT cn.Machungnhan AS certificateId,
            COALESCE(nd.Hoten, cn.Masv) AS studentName,
            cn.Masv AS studentId, sk.Tensukien AS eventName,
            sk.Thoigianbatdau AS startTime,
            sk.Thoigianketthuc AS endTime, sk.Diadiem AS location,
            cn.Ngaycap AS issuedAt, cn.Noidung AS content,
            cn.SignatureSnapshot AS signatureImage,
            cn.OrganizerSignatureSnapshot AS organizerSignatureImage,
            cn.SignatureNameSnapshot AS signatureName,
            cn.OrganizerSignatureNameSnapshot AS organizerSignatureName,
            CASE
              WHEN cn.Trangthaichungnhan = 'Đã cấp' AND cn.Ngaycap IS NOT NULL THEN 'Đã cấp'
              WHEN cn.EmailTrangthai = 'Đã gửi' THEN 'Đã gửi qua email'
              ELSE cn.Trangthaichungnhan
            END AS status
     FROM ChungNhan cn
     INNER JOIN SuKien sk ON sk.Masukien = cn.Masukien
     LEFT JOIN NguoiDung nd ON nd.Mand = cn.Masv
     WHERE cn.Machungnhan = ?
       AND ((cn.Trangthaichungnhan = 'Đã cấp' AND cn.Ngaycap IS NOT NULL)
         OR cn.EmailTrangthai = 'Đã gửi')
     LIMIT 1`,
    [certificateId],
  );
  return certificate;
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[character]);
}

function formatCertificateDate(value) {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return '';
  return new Intl.DateTimeFormat('vi-VN', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: 'Asia/Ho_Chi_Minh',
  }).format(date);
}

function renderCertificatePage(certificate) {
  const certificateId = encodeURIComponent(certificate.certificateId);
  const pdfUrl = `/api/certificates/${certificateId}/pdf`;
  const details = [
    ['Người nhận', certificate.studentName],
    ['Mã sinh viên', certificate.studentId],
    ['Sự kiện', certificate.eventName],
    ['Thời gian', [
      formatCertificateDate(certificate.startTime),
      formatCertificateDate(certificate.endTime),
    ].filter(Boolean).join(' - ')],
    ['Địa điểm', certificate.location],
    ['Mã chứng nhận', certificate.certificateId],
    ['Ngày cấp', formatCertificateDate(certificate.issuedAt)],
    ['Trạng thái', certificate.status],
  ].filter(([, value]) => value);
  const detailRows = details.map(([label, value]) => (
    `<div class="detail"><dt>${escapeHtml(label)}</dt><dd>${escapeHtml(value)}</dd></div>`
  )).join('');

  return `<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>Xác minh chứng nhận ${escapeHtml(certificate.certificateId)}</title>
  <style>
    :root { color-scheme: light; font-family: Arial, sans-serif; color: #172b3a; background: #f3f6f5; }
    * { box-sizing: border-box; }
    body { margin: 0; padding: 28px 16px; }
    main { max-width: 900px; margin: 0 auto; }
    header { padding: 22px 24px; background: #176b58; color: white; border-radius: 8px 8px 0 0; }
    h1 { margin: 0; font-size: 24px; }
    .status { margin: 8px 0 0; }
    section { padding: 20px 24px; background: white; border: 1px solid #dce5e1; border-top: 0; }
    dl { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px 24px; margin: 0; }
    .detail { min-width: 0; }
    dt { color: #5c7069; font-size: 13px; }
    dd { margin: 4px 0 0; overflow-wrap: anywhere; font-weight: 600; }
    .pdf-heading { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
    h2 { margin: 0; font-size: 19px; }
    a { color: #075e9b; font-weight: 600; }
    iframe { display: block; width: 100%; height: min(72vh, 850px); min-height: 480px; margin-top: 16px; border: 1px solid #dce5e1; }
    @media (max-width: 600px) {
      body { padding: 12px 8px; }
      header, section { padding: 18px 16px; }
      h1 { font-size: 21px; }
      dl { grid-template-columns: 1fr; gap: 12px; }
      .pdf-heading { align-items: flex-start; flex-direction: column; }
      iframe { min-height: 55vh; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Chứng nhận hợp lệ</h1>
      <p class="status">${escapeHtml(certificate.status)}</p>
    </header>
    <section aria-label="Thông tin chứng nhận"><dl>${detailRows}</dl></section>
    <section>
      <div class="pdf-heading">
        <h2>Chứng nhận PDF</h2>
        <a href="${pdfUrl}?download=1">Tải PDF</a>
      </div>
      <iframe title="Bản PDF chứng nhận" src="${pdfUrl}"></iframe>
    </section>
  </main>
</body>
</html>`;
}

function certificateSignatureSnapshot(certificate) {
  return {
    signatureImage: certificate.signatureImage
      ? Buffer.from(certificate.signatureImage)
      : null,
    signatureName: certificate.signatureName || '',
    organizerSignatureImage: certificate.organizerSignatureImage
      ? Buffer.from(certificate.organizerSignatureImage)
      : null,
    organizerSignatureName: certificate.organizerSignatureName || '',
  };
}

async function getCertificateSignatureSettings(database = pool) {
  const [[settings]] = await database.query(
    `SELECT signature_image, signature_mime, signature_name,
            organizer_signature_image, organizer_signature_mime,
            organizer_signature_name
     FROM certificate_signature_settings WHERE setting_id = 1`,
  );
  return {
    signatureImage: settings?.signature_image ? Buffer.from(settings.signature_image) : null,
    signatureName: settings?.signature_name || '',
    organizerSignatureImage: settings?.organizer_signature_image
      ? Buffer.from(settings.organizer_signature_image)
      : null,
    organizerSignatureName: settings?.organizer_signature_name || '',
  };
}

function decodeCertificateSignature(imageData) {
  const match = /^data:image\/(png|jpe?g)(?:;[a-z0-9!#$&^_.+-]+=[^;,]*)*;base64,([A-Za-z0-9+/=\s]+)$/i.exec(
    String(imageData || '').trim(),
  );
  if (!match) {
    throw new Error('Dữ liệu chữ ký không phải ảnh PNG hoặc JPEG hợp lệ.');
  }
  const encodedImage = match[2].replace(/\s/g, '');
  const image = Buffer.from(encodedImage, 'base64');
  if (
    image.length === 0
    || image.length > 1024 * 1024
    || image.toString('base64') !== encodedImage
  ) {
    throw new Error('Ảnh chữ ký không hợp lệ hoặc vượt quá 1 MB.');
  }
  const mimeType = match[1].toLowerCase();
  const isPng = mimeType === 'png'
    && image.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const isJpeg = (mimeType === 'jpeg' || mimeType === 'jpg')
    && image[0] === 0xff
    && image[1] === 0xd8
    && image[image.length - 2] === 0xff
    && image[image.length - 1] === 0xd9;
  if (!isPng && !isJpeg) {
    throw new Error('Nội dung ảnh chữ ký không đúng định dạng PNG hoặc JPEG.');
  }
  return image;
}
const passwordResetHandlers = createPasswordResetHandlers({
  pool,
  secret: process.env.PASSWORD_RESET_SECRET,
  mailTransportFactory: createMailTransport,
  mailConfigured: isMailConfigured,
});

const eventStatusSql = `CASE
  WHEN sk.Trangthaisukien = 'Đã đóng' THEN 'Đã đóng'
  WHEN NOW() < sk.Thoigianbatdau THEN 'Sắp diễn ra'
  WHEN NOW() < sk.Thoigianketthuc THEN 'Đang diễn ra'
  ELSE 'Đã kết thúc'
END`;

const eventImageRules = [
  { keywords: ['hiến máu', 'donation'], photoId: '1615461066841-6116e61058f4' },
  { keywords: ['lập trình', 'it contest', 'coding', 'hackathon', 'công nghệ'], photoId: '1516321318423-f06f85e504b3' },
  { keywords: ['kỹ năng mềm', 'tập huấn', 'workshop', 'đào tạo'], photoId: '1521737711867-e3b97375f902' },
  { keywords: ['câu lạc bộ', 'clb', 'đoàn hội'], photoId: '1523240795612-9a054b0db644' },
  { keywords: ['hướng nghiệp', 'tư vấn nghề', 'career'], photoId: '1551836022-d5d88e9218df' },
  { keywords: ['đổi mới sáng tạo', 'innovation', 'sáng tạo'], photoId: '1531058020387-3be344556be6' },
];

function getEventImageUrl(name, description = '') {
  const searchText = `${name || ''} ${description || ''}`
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[đĐ]/g, 'd')
    .toLowerCase();
  const rule = eventImageRules.find(({ keywords }) => keywords.some((keyword) => {
    const normalizedKeyword = keyword
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[đĐ]/g, 'd')
      .toLowerCase();
    return searchText.includes(normalizedKeyword);
  }));
  const photoId = rule?.photoId || '1503676260728-1c00da094a0b';
  return `https://images.unsplash.com/photo-${photoId}?auto=format&fit=crop&w=1400&q=85`;
}

function validateEventImageUrl(value) {
  if (value === undefined || value === null || value === '') {
    return { value: '' };
  }
  if (typeof value !== 'string' || value.trim().length > 1000) {
    return { message: 'Đường dẫn ảnh không hợp lệ (tối đa 1000 ký tự).' };
  }
  const imageUrl = value.trim();
  try {
    const parsedUrl = new URL(imageUrl);
    if (!['http:', 'https:'].includes(parsedUrl.protocol) || !parsedUrl.hostname) {
      return { message: 'Ảnh phải dùng đường dẫn HTTP hoặc HTTPS hợp lệ.' };
    }
  } catch {
    return { message: 'Đường dẫn ảnh không hợp lệ.' };
  }
  return { value: imageUrl };
}

function validateEventRegistrationFormUrl(value) {
  if (value === undefined || value === null || value === '') {
    return { value: '' };
  }
  if (typeof value !== 'string' || value.trim().length > 1000) {
    return { message: 'Đường dẫn đơn đăng ký không hợp lệ (tối đa 1000 ký tự).' };
  }
  const formUrl = value.trim();
  try {
    const parsedUrl = new URL(formUrl);
    if (!['http:', 'https:'].includes(parsedUrl.protocol) || !parsedUrl.hostname) {
      return { message: 'Đơn đăng ký phải dùng đường dẫn HTTP hoặc HTTPS hợp lệ.' };
    }
  } catch {
    return { message: 'Đường dẫn đơn đăng ký không hợp lệ.' };
  }
  return { value: formUrl };
}

async function ensureEventImageColumn() {
  const [columns] = await pool.query("SHOW COLUMNS FROM SuKien LIKE 'HinhAnh'");
  if (!columns.length) {
    try {
      await pool.query('ALTER TABLE SuKien ADD COLUMN HinhAnh VARCHAR(1000) NULL');
    } catch (error) {
      if (error.code !== 'ER_DUP_FIELDNAME') throw error;
    }
  }

  const [eventsWithoutImages] = await pool.query(
    `SELECT Masukien AS id, Tensukien AS name, Mota AS description
     FROM SuKien
     WHERE HinhAnh IS NULL OR TRIM(HinhAnh) = ''`,
  );
  for (const event of eventsWithoutImages) {
    await pool.execute(
      `UPDATE SuKien SET HinhAnh = ?
       WHERE Masukien = ? AND (HinhAnh IS NULL OR TRIM(HinhAnh) = '')`,
      [getEventImageUrl(event.name, event.description), event.id],
    );
  }
}

async function ensureEventRegistrationFormColumn() {
  const [columns] = await pool.query(
    "SHOW COLUMNS FROM SuKien LIKE 'DonDangKy'",
  );
  if (columns.length) return;
  try {
    await pool.query(
      'ALTER TABLE SuKien ADD COLUMN DonDangKy VARCHAR(1000) NULL',
    );
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
}

async function ensureEventCertificateColumn() {
  const [columns] = await pool.query(
    "SHOW COLUMNS FROM SuKien LIKE 'Capchungnhan'",
  );
  if (columns.length) return;
  try {
    await pool.query(
      'ALTER TABLE SuKien ADD COLUMN Capchungnhan TINYINT(1) NOT NULL DEFAULT 0',
    );
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
}

async function ensureEventAttendanceThresholdColumn() {
  const [columns] = await pool.query(
    "SHOW COLUMNS FROM SuKien LIKE 'attendance_threshold_percent'",
  );
  if (columns.length) return;
  await pool.query(
    'ALTER TABLE SuKien ADD COLUMN attendance_threshold_percent INT NOT NULL DEFAULT 100',
  );
  await pool.query(
    `UPDATE SuKien sk
     LEFT JOIN system_parameters event_parameters
       ON event_parameters.scope_type = 'event'
     AND BINARY event_parameters.scope_id = BINARY sk.Masukien
     LEFT JOIN system_parameters group_parameters
       ON group_parameters.scope_type = 'all_events'
      AND group_parameters.scope_id = ''
     LEFT JOIN system_parameters global_parameters
       ON global_parameters.scope_type = 'global'
      AND global_parameters.scope_id = ''
     SET sk.attendance_threshold_percent = COALESCE(
       event_parameters.attendance_threshold_percent,
       group_parameters.attendance_threshold_percent,
       global_parameters.attendance_threshold_percent,
       100
     )`,
  );
}

async function ensureCertificateEmailColumns() {
  const [statusColumns] = await pool.query(
    "SHOW COLUMNS FROM ChungNhan LIKE 'EmailTrangthai'",
  );
  const isNewEmailStatus = statusColumns.length === 0;
  if (isNewEmailStatus) {
    await pool.query(
      "ALTER TABLE ChungNhan ADD COLUMN EmailTrangthai VARCHAR(20) NOT NULL DEFAULT 'Chưa gửi'",
    );
  }
  const [sentAtColumns] = await pool.query(
    "SHOW COLUMNS FROM ChungNhan LIKE 'EmailNgaygui'",
  );
  if (sentAtColumns.length === 0) {
    await pool.query(
      'ALTER TABLE ChungNhan ADD COLUMN EmailNgaygui DATETIME NULL',
    );
  }
  // Các chứng nhận cũ được cấp qua luồng Gmail gộp trước đây.
  if (isNewEmailStatus) {
    await pool.query(
      `UPDATE ChungNhan
       SET EmailTrangthai = 'Đã gửi', EmailNgaygui = COALESCE(Ngaycap, NOW())
       WHERE Trangthaichungnhan = 'Đã cấp' AND Ngaycap IS NOT NULL`,
    );
  }
}

async function ensureEventStatusColumn() {
  const [columns] = await pool.query(
    "SHOW COLUMNS FROM SuKien LIKE 'Trangthaisukien'",
  );
  if (columns.length) return;
  try {
    await pool.query(
      `ALTER TABLE SuKien
       ADD COLUMN Trangthaisukien VARCHAR(30) NOT NULL DEFAULT 'Sắp diễn ra'`,
    );
  } catch (error) {
    if (error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
}

async function synchronizeEventStatuses() {
  await pool.query(
    `UPDATE SuKien sk
     SET Trangthaisukien = ${eventStatusSql}
     WHERE Trangthaisukien <> 'Đã đóng'
       AND NOT (Trangthaisukien <=> ${eventStatusSql})`,
  );
}

async function recordExpiredClassAbsences() {
  const [sessions] = await pool.execute(
    `SELECT Mabuoidiemdanh AS id
     FROM BuoiDiemDanh bpd
     WHERE (bpd.Trangthaidiemdanh <> 'Đang mở'
        OR bpd.Thoigiandong <= NOW())
       AND EXISTS (
         SELECT 1
         FROM Buoi b
         INNER JOIN ThanhVienLop tvl ON tvl.Malop = b.Malop
         LEFT JOIN KetQuaDiemDanh kd
           ON kd.Mabuoidiemdanh = bpd.Mabuoidiemdanh
          AND kd.Masv = tvl.Masv
         WHERE b.Mabuoi = bpd.Mabuoi
           AND kd.Maketqua IS NULL
       )
     ORDER BY Mabuoidiemdanh`,
  );
  for (const session of sessions) {
    let connection;
    try {
      connection = await pool.getConnection();
      await connection.beginTransaction();
      const [[lockedSession]] = await connection.execute(
        `SELECT Mabuoidiemdanh AS id
         FROM BuoiDiemDanh
         WHERE Mabuoidiemdanh = ?
           AND (Trangthaidiemdanh <> 'Đang mở' OR Thoigiandong <= NOW())
         FOR UPDATE`,
        [session.id],
      );
      if (!lockedSession) {
        await connection.rollback();
        continue;
      }
      await connection.execute(
        `INSERT INTO KetQuaDiemDanh
         (Maketqua, Thoigiandiemdanh, Trangthaiketqua, Mabuoidiemdanh, Masv)
         SELECT CONCAT('RS', UPPER(SUBSTRING(REPLACE(UUID(), '-', ''), 1, 20))),
                COALESCE(bpd.Thoigiandong, NOW()),
                'Vắng mặt', bpd.Mabuoidiemdanh, tvl.Masv
         FROM BuoiDiemDanh bpd
         INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
         INNER JOIN ThanhVienLop tvl ON tvl.Malop = b.Malop
         LEFT JOIN KetQuaDiemDanh kd
           ON kd.Mabuoidiemdanh = bpd.Mabuoidiemdanh
          AND kd.Masv = tvl.Masv
         WHERE bpd.Mabuoidiemdanh = ?
           AND kd.Maketqua IS NULL`,
        [session.id],
      );
      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }
  }
}

async function closeExpiredClassAttendanceSessions() {
  await pool.execute(
    `UPDATE BuoiDiemDanh
     SET Trangthaidiemdanh = 'Đã đóng'
     WHERE Trangthaidiemdanh = 'Đang mở'
       AND Thoigiandong <= NOW()`,
  );
}

// Sinh mã sự kiện ngẫu nhiên; khóa duy nhất của cơ sở dữ liệu ngăn mã trùng.
function generateRecordId(prefix) {
  return `${prefix}${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
}

// Kiểm tra khoảng thời gian sự kiện; cho phép sự kiện kéo dài nhiều ngày.
function isValidEventTimeRange(startTime, endTime, { requireNonPastStart = false, requireFutureEnd = false } = {}) {
  const start = startTime.valueOf();
  const end = endTime.valueOf();
  // datetime-local and the mobile picker have minute precision.
  const now = Date.now();
  const currentMinuteStart = Math.floor(now / 60000) * 60000;
  return Number.isFinite(start)
    && Number.isFinite(end)
    && end > start
    && (!requireNonPastStart || start >= currentMinuteStart)
    && (!requireFutureEnd || end > now);
}

function validateEventAttendancePeriods(periods, eventStart, eventEnd) {
  if (!Array.isArray(periods) || periods.length > 12) {
    return { message: 'Sự kiện có thể có tối đa 12 khung điểm danh.' };
  }
  const parsed = [];
  for (const period of periods) {
    if (!period || typeof period !== 'object'
        || typeof period.name !== 'string'
        || !period.name.trim()
        || period.name.trim().length > 60) {
      return { message: 'Tên khung điểm danh không hợp lệ (tối đa 60 ký tự).' };
    }
    const startTime = new Date(period.startTime);
    const endTime = new Date(period.endTime);
    if (!Number.isFinite(startTime.valueOf())
        || !Number.isFinite(endTime.valueOf())
        || startTime < eventStart || endTime > eventEnd
        || endTime <= startTime) {
      return {
        message: 'Khung điểm danh phải nằm trong thời gian sự kiện và có giờ kết thúc sau giờ bắt đầu.',
      };
    }
    parsed.push({
      name: period.name.trim(),
      startTime,
      endTime,
    });
  }
  parsed.sort((left, right) => left.startTime - right.startTime);
  for (let index = 1; index < parsed.length; index += 1) {
    if (parsed[index].startTime < parsed[index - 1].endTime) {
      return { message: 'Các khung điểm danh không được chồng lấn nhau.' };
    }
  }
  return { value: parsed };
}

const eventBenefitTypes = new Set([
  'Điểm rèn luyện',
  'Điểm công tác xã hội',
  'Chứng nhận',
  'Khác',
]);

function validateEventContent(body) {
  const description = typeof body.description === 'string' ? body.description.trim() : '';
  const benefits = body.benefits === undefined ? [] : body.benefits;
  const rules = body.rules === undefined ? [] : body.rules;
  if (description.length > 1000) {
    return { message: 'Mô tả sự kiện không được vượt quá 1.000 ký tự.' };
  }
  if (!Array.isArray(benefits) || benefits.length > 20) {
    return { message: 'Sự kiện có thể có tối đa 20 quyền lợi.' };
  }
  if (benefits.some((benefit) => !benefit || typeof benefit !== 'object'
    || !eventBenefitTypes.has(benefit.type)
    || !Number.isInteger(Number(benefit.points))
    || Number(benefit.points) < 0
    || typeof benefit.content !== 'string'
    || !benefit.content.trim()
    || benefit.content.trim().length > 500)) {
    return { message: 'Thông tin quyền lợi không hợp lệ.' };
  }
  if (!Array.isArray(rules) || rules.length > 30
    || rules.some((rule) => typeof rule !== 'string'
      || !rule.trim()
      || rule.trim().length > 500)) {
    return { message: 'Nội quy không hợp lệ (tối đa 30 nội dung, mỗi nội dung 500 ký tự).' };
  }
  return {
    value: {
      description,
      benefits: benefits.map((benefit) => ({
        type: benefit.type,
        points: Number(benefit.points),
        content: benefit.content.trim(),
      })),
      rules: rules.map((rule) => rule.trim()),
    },
  };
}

async function replaceEventContent(connection, eventId, content) {
  await connection.execute(
    'UPDATE SuKien SET Mota = ? WHERE Masukien = ?',
    [content.description, eventId],
  );
  await connection.execute('DELETE FROM QuyenLoi WHERE Masukien = ?', [eventId]);
  await connection.execute('DELETE FROM NoiQuy WHERE Masukien = ?', [eventId]);

  for (const benefit of content.benefits) {
    await connection.execute(
      `INSERT INTO QuyenLoi (Maquyenloi, Masukien, Loaiquyenloi, Sodiem, Noidung)
       VALUES (?, ?, ?, ?, ?)`,
      [generateRecordId('QL'), eventId, benefit.type, benefit.points, benefit.content],
    );
  }
  for (const [index, rule] of content.rules.entries()) {
    await connection.execute(
      `INSERT INTO NoiQuy (Manoiquy, Masukien, Thutu, Noidung)
       VALUES (?, ?, ?, ?)`,
      [generateRecordId('NQ'), eventId, index + 1, rule],
    );
  }
}

function normalizeDateTime(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const [, year, month, day, hour, minute, second] = match;
  const parsed = new Date(Date.UTC(
    Number(year), Number(month) - 1, Number(day),
    Number(hour), Number(minute), Number(second),
  ));
  if (parsed.getUTCFullYear() !== Number(year)
      || parsed.getUTCMonth() !== Number(month) - 1
      || parsed.getUTCDate() !== Number(day)
      || parsed.getUTCHours() !== Number(hour)
      || parsed.getUTCMinutes() !== Number(minute)
      || parsed.getUTCSeconds() !== Number(second)) {
    return null;
  }
  return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
}

function academicYearFromDateTime(value) {
  const match = /^(\d{4})-(\d{2})-/.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const firstYear = Number(match[2]) >= 8 ? year : year - 1;
  return `${firstYear}-${firstYear + 1}`;
}

// Bổ sung cột tọa độ nếu cơ sở dữ liệu cũ chưa có thông tin vị trí.
async function ensureAttendanceLocationColumns() {
  for (const [column, definition] of [
    ['latitude', 'DECIMAL(10, 7) NULL'],
    ['longitude', 'DECIMAL(10, 7) NULL'],
    ['radius_meters', 'INT NOT NULL DEFAULT 150'],
    ['accuracy_meters', 'DOUBLE NOT NULL DEFAULT 0'],
  ]) {
    try {
      await pool.query(`ALTER TABLE \`BuoiDiemDanh\` ADD COLUMN \`${column}\` ${definition}`);
    } catch (error) {
      if (error.code !== 'ER_DUP_FIELDNAME') throw error;
    }
  }
}

async function ensureSystemParametersTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS system_parameters (
       scope_type VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       scope_id VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
       gps_radius_meters INT NULL,
       event_registration_lock_hours INT NULL,
       qr_duration_minutes INT NULL,
       attendance_threshold_percent INT NULL,
       allow_early_attendance TINYINT(1) NOT NULL DEFAULT 0,
       allow_overlapping_event_attendance TINYINT(1) NOT NULL DEFAULT 0,
       updated_by VARCHAR(30) NULL,
       updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
         ON UPDATE CURRENT_TIMESTAMP,
       PRIMARY KEY (scope_type, scope_id)
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
  const [columns] = await pool.query('SHOW COLUMNS FROM system_parameters');
  if (!columns.some((column) => column.Field === 'attendance_threshold_percent')) {
    await pool.query('ALTER TABLE system_parameters ADD COLUMN attendance_threshold_percent INT NULL AFTER qr_duration_minutes');
  }
  if (!columns.some((column) => column.Field === 'allow_early_attendance')) {
    await pool.query(
      'ALTER TABLE system_parameters ADD COLUMN allow_early_attendance TINYINT(1) NOT NULL DEFAULT 0 AFTER attendance_threshold_percent',
    );
  }
  if (!columns.some((column) => column.Field === 'allow_overlapping_event_attendance')) {
    await pool.query(
      'ALTER TABLE system_parameters ADD COLUMN allow_overlapping_event_attendance TINYINT(1) NOT NULL DEFAULT 0 AFTER allow_early_attendance',
    );
  }
  await pool.execute(
    `INSERT IGNORE INTO system_parameters
       (scope_type, scope_id, gps_radius_meters,
        event_registration_lock_hours, qr_duration_minutes,
        attendance_threshold_percent, allow_early_attendance)
     VALUES ('global', '', 100, 0, 15, 100, 0)`,
  );
  await pool.execute(
    `UPDATE system_parameters
     SET event_registration_lock_hours = 0
     WHERE scope_type = 'global' AND scope_id = ''
       AND event_registration_lock_hours = 24 AND updated_by IS NULL`,
  );
}

async function ensureCertificateSignatureTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS certificate_signature_settings (
       setting_id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
       signature_image MEDIUMBLOB NULL,
       signature_mime VARCHAR(16) NULL,
       signature_name VARCHAR(120) NOT NULL DEFAULT '',
       organizer_signature_image MEDIUMBLOB NULL,
       organizer_signature_mime VARCHAR(16) NULL,
       organizer_signature_name VARCHAR(120) NOT NULL DEFAULT '',
       updated_by VARCHAR(30) NULL,
       updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
         ON UPDATE CURRENT_TIMESTAMP
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
  const [columns] = await pool.query(
    `SELECT COLUMN_NAME AS name, IS_NULLABLE AS isNullable
     FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'certificate_signature_settings'`,
  );
  const existingColumns = new Set(columns.map((column) => column.name));
  const additions = [
    ['signature_name', "VARCHAR(120) NOT NULL DEFAULT ''"],
    ['organizer_signature_image', 'MEDIUMBLOB NULL'],
    ['organizer_signature_mime', 'VARCHAR(16) NULL'],
    ['organizer_signature_name', "VARCHAR(120) NOT NULL DEFAULT ''"],
  ];
  for (const [name, definition] of additions) {
    if (!existingColumns.has(name)) {
      await pool.query(
        `ALTER TABLE certificate_signature_settings ADD COLUMN ${name} ${definition}`,
      );
    }
  }
  const deanImage = columns.find((column) => column.name === 'signature_image');
  const deanMime = columns.find((column) => column.name === 'signature_mime');
  if (deanImage?.isNullable === 'NO' || deanMime?.isNullable === 'NO') {
    await pool.query(
      `ALTER TABLE certificate_signature_settings
         MODIFY signature_image MEDIUMBLOB NULL,
         MODIFY signature_mime VARCHAR(16) NULL`,
    );
  }
}

async function ensureCertificateSignatureSnapshots() {
  const [columns] = await pool.query(
    `SELECT COLUMN_NAME AS name
     FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ChungNhan'`,
  );
  const existingColumns = new Set(columns.map((column) => column.name));
  const additions = [
    ['SignatureSnapshot', 'MEDIUMBLOB NULL'],
    ['SignatureSnapshotCaptured', 'TINYINT(1) NOT NULL DEFAULT 0'],
    ['OrganizerSignatureSnapshot', 'MEDIUMBLOB NULL'],
    ['SignatureNameSnapshot', "VARCHAR(120) NOT NULL DEFAULT ''"],
    ['OrganizerSignatureNameSnapshot', "VARCHAR(120) NOT NULL DEFAULT ''"],
    ['SignatureSnapshotVersion', 'TINYINT UNSIGNED NOT NULL DEFAULT 0'],
  ];
  for (const [name, definition] of additions) {
    if (!existingColumns.has(name)) {
      await pool.query(
        `ALTER TABLE ChungNhan ADD COLUMN ${name} ${definition}`,
      );
    }
  }
  await pool.query(
    `UPDATE ChungNhan cn
     INNER JOIN certificate_signature_settings settings
       ON settings.setting_id = 1
     SET cn.SignatureSnapshot = CASE
           WHEN cn.SignatureSnapshotCaptured = 1 THEN cn.SignatureSnapshot
           ELSE settings.signature_image
         END,
         cn.OrganizerSignatureSnapshot = settings.organizer_signature_image,
         cn.SignatureNameSnapshot = settings.signature_name,
         cn.OrganizerSignatureNameSnapshot = settings.organizer_signature_name,
         cn.SignatureSnapshotCaptured = 1,
         cn.SignatureSnapshotVersion = 1
     WHERE cn.SignatureSnapshotVersion = 0
       AND (
         (cn.Trangthaichungnhan = 'Đã cấp' AND cn.Ngaycap IS NOT NULL)
         OR cn.EmailTrangthai = 'Đã gửi'
       )`,
  );
  await pool.query(
    `UPDATE ChungNhan
     SET SignatureSnapshotVersion = 1
     WHERE SignatureSnapshotVersion = 0
       AND (
         (Trangthaichungnhan = 'Đã cấp' AND Ngaycap IS NOT NULL)
         OR EmailTrangthai = 'Đã gửi'
       )`,
  );
}

async function ensureAttendanceDeviceClaimsTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS attendance_device_claims (
       device_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       attendance_date DATE NOT NULL,
       student_id VARCHAR(30) NOT NULL,
       attendance_session_id VARCHAR(30) NOT NULL,
       created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
       PRIMARY KEY (device_id, attendance_session_id),
       INDEX idx_attendance_device_claims_student (student_id),
       INDEX idx_attendance_device_claims_session (attendance_session_id),
       CONSTRAINT fk_attendance_device_claims_student
         FOREIGN KEY (student_id) REFERENCES SinhVien (MaSV)
         ON UPDATE CASCADE ON DELETE CASCADE,
       CONSTRAINT fk_attendance_device_claims_session
         FOREIGN KEY (attendance_session_id)
         REFERENCES BuoiDiemDanh (MabuoiDiemdanh)
         ON UPDATE CASCADE ON DELETE CASCADE
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );

  const [[primaryKey]] = await pool.query(
    `SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns
     FROM INFORMATION_SCHEMA.STATISTICS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'attendance_device_claims'
       AND INDEX_NAME = 'PRIMARY'`,
  );
  if (primaryKey.columns !== 'device_id,attendance_session_id') {
    await pool.query(
      `ALTER TABLE attendance_device_claims
       DROP PRIMARY KEY,
       ADD PRIMARY KEY (device_id, attendance_session_id)`,
    );
  }
}

async function ensurePasswordResetChallengesTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS password_reset_challenges (
       user_id VARCHAR(30) NOT NULL,
       email VARCHAR(150) NOT NULL,
       code_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
       reset_token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
       expires_at DATETIME NOT NULL,
       requested_at DATETIME NOT NULL,
       attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
       PRIMARY KEY (user_id),
       INDEX idx_password_reset_challenges_email (email),
       CONSTRAINT fk_password_reset_challenges_user
         FOREIGN KEY (user_id) REFERENCES NguoiDung (MaND)
         ON UPDATE CASCADE ON DELETE CASCADE
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
}

async function ensureUserFcmTokensTable() {
  const [[userIdDefinition]] = await pool.query(
    `SELECT COLUMN_TYPE AS columnType,
            CHARACTER_SET_NAME AS characterSet,
            COLLATION_NAME AS collation
     FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'NguoiDung'
       AND COLUMN_NAME = 'MaND'`,
  );
  if (
    !userIdDefinition
    || !/^(?:varchar|char)\(\d+\)$/i.test(userIdDefinition.columnType)
    || !/^[a-z0-9_]+$/i.test(userIdDefinition.characterSet || '')
    || !/^[a-z0-9_]+$/i.test(userIdDefinition.collation || '')
  ) {
    throw new Error('Không thể xác định kiểu dữ liệu tương thích cho NguoiDung.MaND.');
  }
  const userIdColumn = `${userIdDefinition.columnType} CHARACTER SET ${userIdDefinition.characterSet} COLLATE ${userIdDefinition.collation}`;
  await pool.query(
    `CREATE TABLE IF NOT EXISTS user_fcm_tokens (
       token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       user_id ${userIdColumn} NOT NULL,
       token TEXT NOT NULL,
       updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
         ON UPDATE CURRENT_TIMESTAMP,
       PRIMARY KEY (token_hash),
       INDEX idx_user_fcm_tokens_user (user_id),
       CONSTRAINT fk_user_fcm_tokens_user
         FOREIGN KEY (user_id) REFERENCES NguoiDung (MaND)
         ON UPDATE CASCADE ON DELETE CASCADE
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
}

async function ensureEventAttendancePeriodsTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS event_attendance_periods (
       period_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       event_id VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
       name VARCHAR(60) NOT NULL,
       starts_at DATETIME NOT NULL,
       ends_at DATETIME NOT NULL,
       display_order INT NOT NULL DEFAULT 0,
       PRIMARY KEY (period_id),
       INDEX idx_event_attendance_periods_event (event_id),
       CONSTRAINT fk_event_attendance_periods_event
         FOREIGN KEY (event_id) REFERENCES SuKien (MaSuKien)
         ON UPDATE CASCADE ON DELETE CASCADE
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
}

async function replaceEventAttendancePeriods(connection, eventId, periods) {
  await connection.execute(
    'DELETE FROM event_attendance_periods WHERE event_id = ?',
    [eventId],
  );
  for (const [index, period] of periods.entries()) {
    await connection.execute(
      `INSERT INTO event_attendance_periods
       (period_id, event_id, name, starts_at, ends_at, display_order)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        crypto.randomUUID(),
        eventId,
        period.name,
        period.startTime,
        period.endTime,
        index,
      ],
    );
  }
}

function areEventAttendancePeriodsEqual(existing, proposed) {
  return existing.length === proposed.length
    && existing.every((period, index) => (
      period.name === proposed[index].name
      && new Date(period.startTime).valueOf()
        === proposed[index].startTime.valueOf()
      && new Date(period.endTime).valueOf()
        === proposed[index].endTime.valueOf()
    ));
}

async function ensureEventAttendanceTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS event_attendance (
       event_id VARCHAR(30) NOT NULL,
       student_id VARCHAR(30) NOT NULL,
       device_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       checked_in_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
       PRIMARY KEY (event_id, student_id),
       CONSTRAINT fk_event_attendance_event
         FOREIGN KEY (event_id) REFERENCES SuKien (MaSuKien)
         ON UPDATE CASCADE ON DELETE CASCADE,
       CONSTRAINT fk_event_attendance_student
         FOREIGN KEY (student_id) REFERENCES SinhVien (MaSV)
         ON UPDATE CASCADE ON DELETE CASCADE
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
  const [columns] = await pool.query('SHOW COLUMNS FROM event_attendance');
  if (!columns.some((column) => column.Field === 'checked_in_at')) {
    await pool.query(
      'ALTER TABLE event_attendance ADD COLUMN checked_in_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP',
    );
  }
  const [indexes] = await pool.query('SHOW INDEX FROM event_attendance');
  const uniqueIndexes = new Map();
  for (const index of indexes) {
    if (Number(index.Non_unique) !== 0 || index.Key_name === 'PRIMARY') continue;
    const columns = uniqueIndexes.get(index.Key_name) || [];
    columns[index.Seq_in_index - 1] = index.Column_name;
    uniqueIndexes.set(index.Key_name, columns);
  }
  for (const [name, columns] of uniqueIndexes) {
    if (columns.join(',') === 'event_id,device_id') {
      const escapedName = name.replace(/`/g, '``');
      await pool.query(`ALTER TABLE event_attendance DROP INDEX \`${escapedName}\``);
    }
  }
}

async function ensureEventAttendanceSessionsTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS event_attendance_sessions (
       session_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       event_id VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
         NOT NULL,
       latitude DOUBLE NOT NULL,
       longitude DOUBLE NOT NULL,
       radius_meters INT NOT NULL,
       expires_at DATETIME NOT NULL,
       period_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
       period_name VARCHAR(60) NULL,
       period_start DATETIME NULL,
       period_end DATETIME NULL,
       closed_at DATETIME NULL,
       created_by VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
       opened_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
       PRIMARY KEY (session_id),
       UNIQUE KEY uq_event_attendance_sessions_session_event (session_id, event_id),
       INDEX idx_event_attendance_sessions_event (event_id),
       INDEX idx_event_attendance_sessions_period (period_id),
       INDEX idx_event_attendance_sessions_created_by (created_by),
       CONSTRAINT fk_event_attendance_sessions_event
         FOREIGN KEY (event_id) REFERENCES SuKien (MaSuKien)
         ON UPDATE CASCADE ON DELETE CASCADE,
       CONSTRAINT fk_event_attendance_sessions_period
         FOREIGN KEY (period_id) REFERENCES event_attendance_periods (period_id)
         ON UPDATE CASCADE ON DELETE SET NULL,
       CONSTRAINT fk_event_attendance_sessions_created_by
         FOREIGN KEY (created_by) REFERENCES NguoiDung (MaND)
         ON UPDATE CASCADE ON DELETE SET NULL
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
  const [columns] = await pool.query('SHOW COLUMNS FROM event_attendance_sessions');
  const columnNames = new Set(columns.map((column) => column.Field));
  if (!columnNames.has('session_id')) {
    await pool.query(
      'ALTER TABLE event_attendance_sessions ADD COLUMN session_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL AFTER event_id',
    );
  }
  if (!columnNames.has('closed_at')) {
    await pool.query(
      'ALTER TABLE event_attendance_sessions ADD COLUMN closed_at DATETIME NULL',
    );
  }
  if (!columnNames.has('opened_at')) {
    await pool.query(
      'ALTER TABLE event_attendance_sessions ADD COLUMN opened_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP',
    );
  }
  if (!columnNames.has('period_id')) {
    await pool.query(
      'ALTER TABLE event_attendance_sessions ADD COLUMN period_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL',
    );
  }
  if (!columnNames.has('period_name')) {
    await pool.query(
      'ALTER TABLE event_attendance_sessions ADD COLUMN period_name VARCHAR(60) NULL',
    );
  }
  if (!columnNames.has('period_start')) {
    await pool.query(
      'ALTER TABLE event_attendance_sessions ADD COLUMN period_start DATETIME NULL',
    );
  }
  if (!columnNames.has('period_end')) {
    await pool.query(
      'ALTER TABLE event_attendance_sessions ADD COLUMN period_end DATETIME NULL',
    );
  }
  await pool.query(
    `UPDATE event_attendance_sessions
     SET session_id = UUID()
     WHERE session_id IS NULL OR session_id = ''`,
  );
  const [indexes] = await pool.query('SHOW INDEX FROM event_attendance_sessions');
  const primaryColumns = indexes
    .filter((index) => index.Key_name === 'PRIMARY')
    .sort((left, right) => left.Seq_in_index - right.Seq_in_index)
    .map((index) => index.Column_name);
  const hasEventIndex = indexes.some(
    (index) => index.Key_name === 'idx_event_attendance_sessions_event',
  );
  const alterParts = [];
  if (primaryColumns.length !== 1 || primaryColumns[0] !== 'session_id') {
    alterParts.push('DROP PRIMARY KEY', 'ADD PRIMARY KEY (session_id)');
  }
  if (!hasEventIndex) {
    alterParts.push('ADD INDEX idx_event_attendance_sessions_event (event_id)');
  }
  if (alterParts.length > 0) {
    await pool.query(`ALTER TABLE event_attendance_sessions ${alterParts.join(', ')}`);
  }
  const sessionIdColumn = columns.find((column) => column.Field === 'session_id');
  if (
    sessionIdColumn
    && (
      String(sessionIdColumn.Type).toLowerCase() !== 'char(36)'
      || sessionIdColumn.Null !== 'NO'
      || sessionIdColumn.Collation !== 'ascii_bin'
    )
  ) {
    await pool.query(
      `ALTER TABLE event_attendance_sessions
       MODIFY session_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL`,
    );
  }
  const eventIdColumn = columns.find((column) => column.Field === 'event_id');
  if (
    eventIdColumn
    && (
      String(eventIdColumn.Type).toLowerCase() !== 'varchar(30)'
      || eventIdColumn.Collation !== 'utf8mb4_unicode_ci'
    )
  ) {
    await pool.query(
      `ALTER TABLE event_attendance_sessions
       MODIFY event_id VARCHAR(30) CHARACTER SET utf8mb4
         COLLATE utf8mb4_unicode_ci NOT NULL`,
    );
  }
  const uniqueIndexes = new Map();
  for (const index of indexes) {
    if (Number(index.Non_unique) !== 0) continue;
    const indexColumns = uniqueIndexes.get(index.Key_name) || [];
    indexColumns[index.Seq_in_index - 1] = index.Column_name;
    uniqueIndexes.set(index.Key_name, indexColumns);
  }
  if (
    ![...uniqueIndexes.values()].some(
      (indexColumns) => indexColumns.join(',') === 'session_id,event_id',
    )
  ) {
    await pool.query(
      `ALTER TABLE event_attendance_sessions
       ADD UNIQUE KEY uq_event_attendance_sessions_session_event
         (session_id, event_id)`,
    );
  }
  await pool.query(
    `CREATE TABLE IF NOT EXISTS event_attendance_records (
       event_id VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
       session_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       student_id VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
       device_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       method VARCHAR(16) NOT NULL DEFAULT 'QR',
       checked_in_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
       PRIMARY KEY (session_id, student_id),
       UNIQUE KEY unique_event_session_device (session_id, device_id),
       INDEX idx_event_attendance_records_event (event_id),
       INDEX idx_event_attendance_records_student (student_id),
       INDEX idx_event_attendance_records_session_event (session_id, event_id),
       CONSTRAINT fk_event_attendance_records_session
         FOREIGN KEY (session_id, event_id)
         REFERENCES event_attendance_sessions (session_id, event_id)
         ON UPDATE CASCADE ON DELETE CASCADE,
       CONSTRAINT fk_event_attendance_records_student
         FOREIGN KEY (student_id) REFERENCES SinhVien (MaSV)
         ON UPDATE CASCADE ON DELETE CASCADE
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
  const [recordColumns] = await pool.query(
    'SHOW COLUMNS FROM event_attendance_records',
  );
  const recordColumnNames = new Set(
    recordColumns.map((column) => column.Field),
  );
  if (!recordColumnNames.has('method')) {
    await pool.query(
      "ALTER TABLE event_attendance_records ADD COLUMN method VARCHAR(16) NOT NULL DEFAULT 'QR'",
    );
  }
  if (!recordColumnNames.has('checked_in_at')) {
    await pool.query(
      'ALTER TABLE event_attendance_records ADD COLUMN checked_in_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP',
    );
  }
  const collationMappings = [
    {
      sourceTable: 'SuKien',
      sourceColumn: 'MaSuKien',
      table: 'event_attendance_sessions',
      column: 'event_id',
    },
    {
      sourceTable: 'SuKien',
      sourceColumn: 'MaSuKien',
      table: 'event_attendance_records',
      column: 'event_id',
    },
    {
      sourceTable: 'SinhVien',
      sourceColumn: 'MaSV',
      table: 'event_attendance_records',
      column: 'student_id',
    },
  ];
  for (const mapping of collationMappings) {
    const [[sourceColumn]] = await pool.query(
      `SELECT COLLATION_NAME AS collation
       FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE()
         AND TABLE_NAME = ?
         AND COLUMN_NAME = ?
       LIMIT 1`,
      [mapping.sourceTable, mapping.sourceColumn],
    );
    const collation = sourceColumn?.collation;
    if (typeof collation !== 'string' || !/^[A-Za-z0-9_]+$/.test(collation)) {
      throw new Error(
        `Unable to determine collation for ${mapping.sourceTable}.${mapping.sourceColumn}.`,
      );
    }
    const [[column]] = await pool.query(
      `SELECT COLLATION_NAME AS collation
       FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE()
         AND TABLE_NAME = ?
         AND COLUMN_NAME = ?
       LIMIT 1`,
      [mapping.table, mapping.column],
    );
    if (!column) {
      throw new Error(`Missing ${mapping.column} column in ${mapping.table}.`);
    }
    if (column.collation !== collation) {
      await pool.query(
        `ALTER TABLE ${mapping.table}
         MODIFY ${mapping.column} VARCHAR(30) CHARACTER SET utf8mb4
           COLLATE ${collation} NOT NULL`,
      );
    }
  }
}

app.use(cors());
app.use('/uploads/events', express.static(eventImagesDirectory, {
  dotfiles: 'deny',
  fallthrough: false,
  index: false,
  maxAge: '1y',
  setHeaders: (response) => response.setHeader('X-Content-Type-Options', 'nosniff'),
}));
app.use('/uploads/event-registration-forms', express.static(eventRegistrationFormsDirectory, {
  dotfiles: 'deny',
  fallthrough: false,
  index: false,
  maxAge: '1y',
  setHeaders: (response) => {
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Content-Disposition', 'inline');
  },
}));
app.use(express.json({ limit: '4mb' }));

app.get('/', (_request, response) => {
  response.json({
    name: 'Attendance and Event Management API',
    status: 'running',
    health: '/health',
  });
});

// Quy đổi các tên vai trò đồng nghĩa trong CSDL về tên mà các route đang kiểm tra.
function normalizeRole(role) {
  const value = String(role || '').trim();
  if (value.toLowerCase() === 'công nhân viên') return 'Nhân viên';
  return value;
}

function requireAuth(request, response, next) {
  const header = request.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';

  if (!token) {
    return response.status(401).json({ message: 'Bạn chưa đăng nhập.' });
  }

  try {
    request.auth = jwt.verify(token, jwtSecret);
    request.auth.role = normalizeRole(request.auth.role);
    return next();
  } catch (_error) {
    return response.status(401).json({ message: 'Phiên đăng nhập đã hết hạn.' });
  }
}

// Kiểm tra vai trò trong token trước khi cho phép truy cập route quản trị.
function requireRole(...roles) {
  const allowedRoles = new Set(
    roles.map((role) => String(role).trim().toLowerCase()),
  );
  return (request, response, next) => {
    const currentRole = String(request.auth.role || '').trim().toLowerCase();
    if (!allowedRoles.has(currentRole)) {
      return response.status(403).json({ message: 'Bạn không có quyền truy cập.' });
    }
    return next();
  };
}

// Vai trò được quản lý sự kiện; người không phải admin chỉ thao tác trên đơn vị mình phụ trách.
const eventManagerRoles = ['Quản trị viên', 'admin', 'Ban tổ chức', 'event_organizer', 'Cán bộ', 'Nhân viên'];

async function isValidEventImageFile(file) {
  const handle = await fs.promises.open(file.path, 'r');
  try {
    const header = Buffer.alloc(12);
    const { bytesRead } = await handle.read(header, 0, header.length, 0);
    if (file.mimetype === 'image/jpeg') {
      return bytesRead >= 3 && header[0] === 0xff && header[1] === 0xd8 && header[2] === 0xff;
    }
    if (file.mimetype === 'image/png') {
      return header.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
    }
    return file.mimetype === 'image/webp'
      && header.toString('ascii', 0, 4) === 'RIFF'
      && header.toString('ascii', 8, 12) === 'WEBP'
      && bytesRead === 12;
  } finally {
    await handle.close();
  }
}

async function isValidEventRegistrationFormFile(file) {
  const handle = await fs.promises.open(file.path, 'r');
  try {
    const header = Buffer.alloc(5);
    const { bytesRead } = await handle.read(header, 0, header.length, 0);
    return bytesRead === header.length && header.toString('ascii') === '%PDF-';
  } finally {
    await handle.close();
  }
}

async function removeUploadedEventFile(filePath) {
  try {
    await fs.promises.unlink(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') {
      console.error('Event upload cleanup failed:', error.message);
    }
  }
}

app.post(
  '/api/organizer/event-images',
  requireAuth,
  requireRole(...eventManagerRoles),
  (request, response, next) => {
    eventImageUpload.single('image')(request, response, (error) => {
      if (!error) return next();
      const status = error instanceof multer.MulterError && error.code === 'LIMIT_FILE_SIZE'
        ? 413
        : 400;
      return response.status(status).json({ message: error.message || 'Không thể tải ảnh lên.' });
    });
  },
  async (request, response) => {
    if (!request.file) {
      return response.status(400).json({ message: 'Vui lòng chọn ảnh sự kiện.' });
    }
    try {
      if (!await isValidEventImageFile(request.file)) {
        await removeUploadedEventFile(request.file.path);
        return response.status(400).json({
          message: 'Nội dung tệp không khớp với ảnh JPEG, PNG hoặc WebP.',
        });
      }
      const publicBaseUrl = (
        process.env.PUBLIC_API_BASE_URL || `${request.protocol}://${request.get('host')}`
      ).replace(/\/+$/, '');
      return response.status(201).json({
        imageUrl: `${publicBaseUrl}/uploads/events/${encodeURIComponent(request.file.filename)}`,
      });
    } catch (error) {
      await removeUploadedEventFile(request.file.path);
      console.error('Event image upload failed:', error.message);
      return response.status(500).json({ message: 'Không thể lưu ảnh sự kiện.' });
    }
  },
);

app.post(
  '/api/organizer/event-registration-forms',
  requireAuth,
  requireRole(...eventManagerRoles),
  (request, response, next) => {
    eventRegistrationFormUpload.single('registrationForm')(request, response, (error) => {
      if (!error) return next();
      const status = error instanceof multer.MulterError && error.code === 'LIMIT_FILE_SIZE'
        ? 413
        : 400;
      return response.status(status).json({
        message: error.message || 'Không thể tải đơn đăng ký lên.',
      });
    });
  },
  async (request, response) => {
    if (!request.file) {
      return response.status(400).json({ message: 'Vui lòng chọn tệp đơn đăng ký PDF.' });
    }
    try {
      if (!await isValidEventRegistrationFormFile(request.file)) {
        await removeUploadedEventFile(request.file.path);
        return response.status(400).json({
          message: 'Nội dung tệp không đúng định dạng PDF.',
        });
      }
      const publicBaseUrl = (
        process.env.PUBLIC_API_BASE_URL || `${request.protocol}://${request.get('host')}`
      ).replace(/\/+$/, '');
      return response.status(201).json({
        registrationFormUrl: `${publicBaseUrl}/uploads/event-registration-forms/${encodeURIComponent(request.file.filename)}`,
      });
    } catch (error) {
      await removeUploadedEventFile(request.file.path);
      console.error('Event registration form upload failed:', error.message);
      return response.status(500).json({ message: 'Không thể lưu đơn đăng ký PDF.' });
    }
  },
);

function isAdminAuth(auth) {
  return ['quản trị viên', 'admin'].includes(String(auth.role || '').trim().toLowerCase());
}

// Kiểm tra người dùng có phụ trách đơn vị tổ chức (DonVi.MaNV) hay không.
async function managesUnit(executor, auth, unitId) {
  if (isAdminAuth(auth)) return true;
  const [[unit]] = await executor.execute(
    'SELECT 1 AS ok FROM DonVi WHERE Madv = ? AND Manv = ? LIMIT 1',
    [unitId, auth.sub],
  );
  return Boolean(unit);
}

// Kiểm tra nhanh trạng thái kết nối giữa API và cơ sở dữ liệu.
app.get('/health', async (_request, response) => {
  try {
    await pool.query('SELECT 1');
    response.json({ ok: true, database: 'connected' });
  } catch (error) {
    response.status(503).json({ ok: false, database: 'disconnected' });
  }
});

function passwordsMatch(password, storedPassword) {
  if (storedPassword.startsWith('$2')) {
    return bcrypt.compareSync(password, storedPassword);
  }

  if (Buffer.byteLength(password) !== Buffer.byteLength(storedPassword)) {
    return false;
  }

  return crypto.timingSafeEqual(
    Buffer.from(password),
    Buffer.from(storedPassword),
  );
}

// Xác thực tài khoản, tạo JWT và trả thông tin người dùng cho ứng dụng.
app.post('/api/auth/login', async (request, response) => {
  const { identifier, password } = request.body || {};

  if (!identifier || !password) {
    return response.status(400).json({ message: 'Vui lòng nhập tài khoản và mật khẩu.' });
  }

  try {
    const [rows] = await pool.execute(
            `SELECT Mand AS id, Hoten AS name, Email AS email, Matkhau AS password,
              Vaitro AS role, Trangthaind AS status
             FROM NguoiDung
             WHERE Mand = ? OR Email = ?
       LIMIT 1`,
      [identifier, identifier],
    );
    const user = rows[0];

    if (!user || user.status !== 'Đang hoạt động'
      || !passwordsMatch(password, user.password)) {
      return response.status(401).json({ message: 'Tài khoản hoặc mật khẩu không đúng.' });
    }

    const token = jwt.sign(
      { sub: user.id, role: user.role },
      jwtSecret,
      { expiresIn: '8h' },
    );

    return response.json({
      token,
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role,
      },
    });
  } catch (error) {
    console.error('Login error:', error.message);
    return response.status(500).json({ message: 'Không thể kết nối cơ sở dữ liệu.' });
  }
});

app.post('/api/auth/password-reset/request', passwordResetHandlers.requestCode);
app.post('/api/auth/password-reset/verify', passwordResetHandlers.verifyCode);
app.post('/api/auth/password-reset/complete', passwordResetHandlers.resetPassword);

// Lấy hồ sơ người dùng hiện tại từ token đăng nhập.
app.get('/api/me', requireAuth, async (request, response) => {
  try {
    const [rows] = await pool.execute(
            `SELECT nd.Mand AS id, nd.Hoten AS name,
                    nd.Email AS email, nd.Vaitro AS role, nd.SDT AS phone,
                    nd.DiaChi AS address, nd.NgaySinh AS birthDate,
                    nd.GioiTinh AS gender, nd.QueQuan AS hometown,
                    nd.Trangthaind AS status,
                    sv.Lop AS className, sv.Chuyennganh AS major,
              gv.BoMon AS subjectDepartment, cnv.Chucvu AS position
             FROM NguoiDung nd
             LEFT JOIN SinhVien sv ON sv.Masv = nd.Mand
             LEFT JOIN GiangVien gv ON gv.Magv = nd.Mand
              LEFT JOIN CongNhanVien cnv ON cnv.Manv = nd.Mand
             WHERE nd.Mand = ?
       LIMIT 1`,
      [request.auth.sub],
    );
    if (!rows[0]) return response.status(404).json({ message: 'Không tìm thấy người dùng.' });
    return response.json({ user: rows[0] });
  } catch (error) {
    console.error('Me error:', error.message);
    return response.status(500).json({ message: 'Không thể tải thông tin người dùng.' });
  }
});
app.put('/api/me', requireAuth, createUpdateProfileHandler(pool));
app.post('/api/me/fcm-token', requireAuth, async (request, response) => {
  const token = typeof request.body?.token === 'string' ? request.body.token.trim() : '';
  if (!token || token.length > 4096) {
    return response.status(400).json({ message: 'FCM token không hợp lệ.' });
  }
  try {
    await pool.execute(
      `INSERT INTO user_fcm_tokens (token_hash, user_id, token)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), token = VALUES(token)`,
      [tokenHash(token), request.auth.sub, token],
    );
    return response.json({ ok: true });
  } catch (error) {
    console.error('FCM token registration failed:', error.message);
    return response.status(500).json({ message: 'Không thể đăng ký thiết bị nhận thông báo.' });
  }
});
app.post('/api/me/fcm-token/unregister', requireAuth, async (request, response) => {
  const token = typeof request.body?.token === 'string' ? request.body.token.trim() : '';
  if (!token) return response.status(400).json({ message: 'FCM token không hợp lệ.' });
  try {
    await pool.execute(
      'DELETE FROM user_fcm_tokens WHERE token_hash = ? AND user_id = ?',
      [tokenHash(token), request.auth.sub],
    );
    return response.json({ ok: true });
  } catch (error) {
    console.error('FCM token removal failed:', error.message);
    return response.status(500).json({ message: 'Không thể hủy đăng ký thiết bị.' });
  }
});
/*
/*
app.get('/api/notifications', requireAuth, async (request, response) => {
  if (!['student', 'sinh viên'].includes(String(request.auth.role).toLowerCase())) {
    return response.json({ items: [] });
  }

  try {
    const [result] = await pool.execute(
      `SELECT DISTINCT bpd.[[0m[K`Mã buổi điểm danh[0m[K` AS sessionId,
              b.[[0m[K`Mã lớp[0m[K` AS classId,
              COALESCE(b.[[0m[K`Nội dung[0m[K`, '') AS content,
              bpd.[[0m[K`Phương thức[0m[K` AS method,
              bpd.[[0m[K`Thời gian mở[0m[K` AS createdAt,
              bpd.[[0m[K`Thời gian đóng[0m[K` AS closesAt
       FROM [[0m[K`buổi điểm danh[0m[K` bpd
       INNER JOIN [[0m[K`buổi[0m[K` b ON b.[[0m[K`Mã buổi[0m[K` = bpd.[[0m[K`Mã buổi[0m[K`
       INNER JOIN [[0m[K`Thành viên lớp[0m[K` tvl ON tvl.[[0m[K`Mã lớp[0m[K` = b.[[0m[K`Mã lớp[0m[K`
       WHERE tvl.[[0m[K`Mã sinh viên[0m[K` = ?
         AND bpd.[[0m[K`Trạng thái điểm danh[0m[K` = 'Đang mở'
         AND bpd.[[0m[K`Thời gian đóng[0m[K` > NOW()
       ORDER BY bpd.[[0m[K`Thời gian mở[0m[K` DESC
       LIMIT 50`,
      [request.auth.sub],
    );
    return response.json({ items: result });
  } catch (error) {
    console.error('Notifications error:', error.message);
    return response.status(500).json({ message: 'Không thể tải thông báo.' });
  }
});

*/
// Trả về các phiên điểm danh đang mở mà sinh viên hiện tại có thể tham gia.
app.get('/api/notifications', requireAuth, async (request, response) => {
  if (!['student', 'sinh viên'].includes(String(request.auth.role).toLowerCase())) {
    return response.json({ items: [] });
  }

  try {
    const [rows] = await pool.execute(
      [
        "SELECT DISTINCT bpd.Mabuoidiemdanh AS sessionId,",
        "b.Malop AS classId, COALESCE(b.Noidung, '') AS content,",
        "bpd.Phuongthuc AS method, bpd.Thoigianmo AS createdAt,",
        "bpd.Thoigiandong AS closesAt",
        "FROM BuoiDiemDanh bpd",
        "INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi",
        "INNER JOIN ThanhVienLop tvl ON tvl.Malop = b.Malop",
        "WHERE tvl.Masv = ?",
        "AND bpd.Trangthaidiemdanh = 'Đang mở'",
        "AND bpd.Thoigiandong > NOW()",
        "ORDER BY bpd.Thoigianmo DESC LIMIT 50",
      ].join(' '),
      [request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Notifications error:', error.message);
    return response.status(500).json({ message: 'Không thể tải thông báo.' });
  }
});
// Lấy các lớp học phần mà sinh viên hiện tại đang tham gia.
app.get('/api/classes', requireAuth, async (request, response) => {
  try {
    await recordExpiredClassAbsences();
    const [rows] = await pool.execute(
      `SELECT lhp.Malop AS id, lhp.Malop AS code,
              lhp.Tenlop AS name, lhp.Hocky AS semester,
              lhp.Thoigianbatdau AS startTime, lhp.Magv AS lecturerId,
              lhp.Tinchi AS credits, lhp.Soluongtoida AS capacity,
              COALESCE((
                SELECT GROUP_CONCAT(
                  CONCAT(
                    CASE lh.ThuTrongTuan
                      WHEN 7 THEN 'Chủ nhật'
                      ELSE CONCAT('Thứ ', lh.ThuTrongTuan + 1)
                    END,
                    ', ', TIME_FORMAT(lh.GioBatDau, '%H:%i'),
                    '–', TIME_FORMAT(lh.GioKetThuc, '%H:%i')
                  )
                  ORDER BY lh.ThuTrongTuan, lh.GioBatDau SEPARATOR ' · '
                )
                FROM LichHocPhan lh WHERE lh.Malop = lhp.Malop
              ), '') AS schedule,
              COALESCE((
                SELECT GROUP_CONCAT(DISTINCT lh.PhongHoc
                  ORDER BY lh.PhongHoc SEPARATOR ', ')
                FROM LichHocPhan lh WHERE lh.Malop = lhp.Malop
              ), '') AS room,
              COALESCE((
                SELECT GROUP_CONCAT(
                  CONCAT(
                    TIME_FORMAT(lh.GioBatDau, '%H:%i'),
                    '–', TIME_FORMAT(lh.GioKetThuc, '%H:%i'),
                    ' · Phòng ', lh.PhongHoc
                  )
                  ORDER BY lh.GioBatDau SEPARATOR ' | '
                )
                FROM LichHocPhan lh
                WHERE lh.Malop = lhp.Malop
                  AND lh.ThuTrongTuan = WEEKDAY(CURDATE()) + 1
                  AND (lh.NgayBatDau IS NULL OR lh.NgayBatDau <= CURDATE())
                  AND (lh.NgayKetThuc IS NULL OR lh.NgayKetThuc >= CURDATE())
                  AND lh.GioKetThuc >= CURTIME()
              ), '') AS todaySchedule,
              COALESCE(nd.Hoten, '') AS lecturerName,
              COUNT(DISTINCT tvl.Masv) AS studentCount,
              COALESCE(attendance.present, 0) AS present,
              COALESCE(attendance.late, 0) AS late,
              COALESCE(attendance.absent, 0) AS absent,
              COALESCE(attendance.sessions, 0) AS sessions,
              CASE WHEN COALESCE(attendance.present, 0)
                    + COALESCE(attendance.late, 0)
                    + COALESCE(attendance.absent, 0) = 0 THEN 0
                   ELSE ROUND(100 * COALESCE(attendance.present, 0)
                    / (attendance.present + attendance.late + attendance.absent))
              END AS rate
       FROM LopHocPhan lhp
       LEFT JOIN GiangVien gv ON gv.Magv = lhp.Magv
       LEFT JOIN NguoiDung nd ON nd.Mand = gv.Magv
       LEFT JOIN ThanhVienLop tvl ON tvl.Malop = lhp.Malop
            LEFT JOIN (
              SELECT b.Malop, kd.Masv,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent,
                COUNT(DISTINCT bpd.Mabuoidiemdanh) AS sessions
              FROM KetQuaDiemDanh kd
              INNER JOIN BuoiDiemDanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
              INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
              GROUP BY b.Malop, kd.Masv
            ) attendance ON attendance.Malop = lhp.Malop
                   AND attendance.Masv = ?
       WHERE EXISTS (
         SELECT 1 FROM ThanhVienLop mine
         WHERE mine.Malop = lhp.Malop
           AND mine.Masv = ?
       )
      GROUP BY lhp.Malop, lhp.Tenlop, lhp.Hocky,
          lhp.Thoigianbatdau, lhp.Magv, lhp.Tinchi, lhp.Soluongtoida,
          nd.Hoten, attendance.present,
                attendance.late, attendance.absent, attendance.sessions
       ORDER BY lhp.Malop`,
      [request.auth.sub, request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Classes error:', error.message);
    return response.status(500).json({ message: 'Không thể tải danh sách lớp.' });
  }
});

app.post('/api/classes/join', requireAuth, requireRole('Sinh viên', 'student'), async (request, response) => {
  const classCode = typeof request.body?.classCode === 'string'
    ? request.body.classCode.trim()
    : '';
  if (!classCode || classCode.length > 64) {
    return response.status(400).json({ message: 'Mã lớp không hợp lệ.' });
  }

  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[classInfo]] = await connection.execute(
      `SELECT Malop, Trangthailop AS status, Soluongtoida AS capacity,
              (Thoigianbatdau < DATE_SUB(NOW(), INTERVAL 1 YEAR)) AS isArchived
       FROM LopHocPhan WHERE Malop = ? FOR UPDATE`,
      [classCode],
    );
    if (!classInfo) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy lớp theo mã đã nhập.' });
    }
    if (classInfo.status === 'Đã đóng' || Number(classInfo.isArchived)) {
      await connection.rollback();
      return response.status(409).json({ message: 'Lớp đã đóng hoặc đã lưu trữ.' });
    }

    const [[membership]] = await connection.execute(
      'SELECT 1 AS isMember FROM ThanhVienLop WHERE Malop = ? AND Masv = ? LIMIT 1',
      [classInfo.Malop, request.auth.sub],
    );
    if (membership) {
      await connection.rollback();
      return response.status(409).json({ message: 'Bạn đã tham gia lớp này.' });
    }

    const [[count]] = await connection.execute(
      'SELECT COUNT(*) AS total FROM ThanhVienLop WHERE Malop = ?',
      [classInfo.Malop],
    );
    if (Number(count.total) >= Number(classInfo.capacity)) {
      await connection.rollback();
      return response.status(409).json({ message: 'Lớp đã đủ số lượng sinh viên.' });
    }

    await connection.execute(
      `INSERT INTO ThanhVienLop (Malop, Masv, NgayThamGia, TrangThaiThanhVien)
       VALUES (?, ?, CURRENT_DATE, 'Đang tham gia')`,
      [classInfo.Malop, request.auth.sub],
    );
    await connection.commit();
    return response.status(201).json({ message: 'Tham gia lớp thành công.' });
  } catch (error) {
    if (connection) await connection.rollback();
    if (error.code === 'ER_DUP_ENTRY') {
      return response.status(409).json({ message: 'Bạn đã tham gia lớp này.' });
    }
    console.error('Join class error:', error.message);
    return response.status(500).json({ message: 'Không thể tham gia lớp học.' });
  } finally {
    if (connection) connection.release();
  }
});

app.get(
  '/api/calendar/classes',
  requireAuth,
  requireRole('Sinh viên', 'student', 'Giảng viên', 'lecturer'),
  async (request, response) => {
    const role = String(request.auth.role || '').trim().toLowerCase();
    const isStudent = role === 'sinh viên' || role === 'student';
    try {
      const [rows] = await pool.execute(
        `SELECT lhp.Malop AS id, lhp.Tenlop AS name,
                COALESCE(mh.Tenmon, '') AS subjectName,
                COALESCE(nd.Hoten, '') AS lecturerName,
                lh.Malich AS scheduleId, lh.ThuTrongTuan AS weekday,
                TIME_FORMAT(lh.GioBatDau, '%H:%i') AS startTime,
                TIME_FORMAT(lh.GioKetThuc, '%H:%i') AS endTime,
                COALESCE(lh.PhongHoc, '') AS room,
                DATE_FORMAT(lh.NgayBatDau, '%Y-%m-%d') AS startsOn,
                DATE_FORMAT(lh.NgayKetThuc, '%Y-%m-%d') AS endsOn
         FROM LopHocPhan lhp
         LEFT JOIN MonHoc mh ON mh.Mamon = lhp.Mamon
         LEFT JOIN GiangVien gv ON gv.Magv = lhp.Magv
         LEFT JOIN NguoiDung nd ON nd.Mand = gv.Magv
         LEFT JOIN LichHocPhan lh ON lh.Malop = lhp.Malop
         WHERE COALESCE(lhp.Trangthailop, '') <> 'Đã đóng'
           AND ${
             isStudent
               ? `EXISTS (
                    SELECT 1 FROM ThanhVienLop tvl
                    WHERE tvl.Malop = lhp.Malop AND tvl.Masv = ?
                  )`
               : 'lhp.Magv = ?'
           }
         ORDER BY lhp.Malop, lh.ThuTrongTuan, lh.GioBatDau`,
        [request.auth.sub],
      );
      const classes = new Map();
      for (const row of rows) {
        let classItem = classes.get(String(row.id));
        if (!classItem) {
          classItem = {
            id: String(row.id),
            name: row.name || '',
            subjectName: row.subjectName || '',
            lecturerName: row.lecturerName || '',
            schedules: [],
          };
          classes.set(String(row.id), classItem);
        }
        if (row.scheduleId != null) {
          classItem.schedules.push({
            weekday: Number(row.weekday),
            startTime: row.startTime || '',
            endTime: row.endTime || '',
            room: row.room || '',
            startsOn: row.startsOn || '',
            endsOn: row.endsOn || '',
          });
        }
      }
      return response.json({ items: [...classes.values()] });
    } catch (error) {
      console.error('Calendar classes error:', error.message);
      return response.status(500).json({
        message: 'Không thể tải lịch học.',
      });
    }
  },
);

// Sinh viên chỉ được xem chi tiết và danh sách thành viên của lớp mình tham gia.
app.get('/api/classes/:classId/detail', requireAuth, requireRole('Sinh viên', 'student'), async (request, response) => {
  try {
    const [[classInfo]] = await pool.execute(
      `SELECT lhp.Malop AS id, lhp.Tenlop AS name,
              lhp.Makhoa AS cohortCode, lhp.Hocky AS semester,
              lhp.Namhoc AS academicYear, lhp.Thoigianbatdau AS startTime,
              lhp.Magv AS lecturerId, lhp.Tinchi AS credits,
              lhp.Soluongtoida AS capacity, lhp.Trangthailop AS status,
              lhp.Mamon AS subjectId, mh.Tenmon AS subjectName,
              lhp.Madv AS departmentId, COALESCE(dv.Tendv, '') AS departmentName,
              COALESCE(nd.Hoten, '') AS lecturerName,
              (SELECT COUNT(*) FROM ThanhVienLop tvl
               WHERE tvl.Malop = lhp.Malop) AS studentCount
       FROM LopHocPhan lhp
       INNER JOIN MonHoc mh ON mh.Mamon = lhp.Mamon
       LEFT JOIN DonVi dv ON dv.Madv = lhp.Madv
       LEFT JOIN GiangVien gv ON gv.Magv = lhp.Magv
       LEFT JOIN NguoiDung nd ON nd.Mand = gv.Magv
       WHERE lhp.Malop = ?
         AND EXISTS (
           SELECT 1 FROM ThanhVienLop mine
           WHERE mine.Malop = lhp.Malop AND mine.Masv = ?
         )
       LIMIT 1`,
      [request.params.classId, request.auth.sub],
    );
    if (!classInfo) {
      return response.status(404).json({
        message: 'Không tìm thấy lớp hoặc bạn không tham gia lớp này.',
      });
    }
    const [schedules] = await pool.execute(
      `SELECT Malich AS id, ThuTrongTuan AS weekday,
              TIME_FORMAT(GioBatDau, '%H:%i') AS startTime,
              TIME_FORMAT(GioKetThuc, '%H:%i') AS endTime,
              PhongHoc AS room,
              DATE_FORMAT(NgayBatDau, '%d/%m/%Y') AS startsOn,
              DATE_FORMAT(NgayKetThuc, '%d/%m/%Y') AS endsOn
       FROM LichHocPhan
       WHERE Malop = ?
       ORDER BY ThuTrongTuan, GioBatDau`,
      [request.params.classId],
    );
    const [students] = await pool.execute(
      `SELECT tvl.Masv AS studentId,
              COALESCE(nd.Hoten, tvl.Masv) AS studentName,
              COALESCE(tvl.TrangThaiThanhVien, '') AS status,
              DATE_FORMAT(tvl.NgayThamGia, '%d/%m/%Y') AS dateLabel
       FROM ThanhVienLop tvl
       LEFT JOIN NguoiDung nd ON nd.Mand = tvl.Masv
       WHERE tvl.Malop = ?
       ORDER BY nd.Hoten, tvl.Masv`,
      [request.params.classId],
    );
    const [attendanceSessions] = await pool.execute(
      `SELECT bpd.Mabuoidiemdanh AS id,
              COALESCE(b.Noidung, '') AS name,
              DATE_FORMAT(b.Thoigianbatdau, '%d/%m/%Y %H:%i') AS startTime,
              DATE_FORMAT(kd.Thoigiandiemdanh, '%d/%m/%Y %H:%i') AS checkedInAt,
              COALESCE(
                kd.Trangthaiketqua,
                CASE
                  WHEN bpd.Trangthaidiemdanh <> 'Đang mở'
                    OR bpd.Thoigiandong <= NOW() THEN 'Vắng mặt'
                  ELSE 'Chưa điểm danh'
                END
              ) AS status,
              COALESCE(bpd.Phuongthuc, '') AS method
       FROM BuoiDiemDanh bpd
       INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
       LEFT JOIN KetQuaDiemDanh kd
         ON kd.Mabuoidiemdanh = bpd.Mabuoidiemdanh
        AND kd.Masv = ?
       WHERE b.Malop = ?
       ORDER BY b.Thoigianbatdau DESC, bpd.Thoigianmo DESC`,
      [request.auth.sub, request.params.classId],
    );
    return response.json({ class: classInfo, schedules, attendanceSessions, students });
  } catch (error) {
    console.error('Student class detail error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải chi tiết lớp học.',
    });
  }
});

// Lấy danh sách sự kiện và trạng thái đăng ký của sinh viên hiện tại.
app.get('/api/events', requireAuth, async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              COALESCE(sk.HinhAnh, '') AS imageUrl,
              sk.Madv AS organizerId, COALESCE(dv.Tendv, '') AS organizerName,
              sk.Thoigianbatdau AS startTime, sk.Thoigianketthuc AS endTime,
              ${eventStatusSql} AS status,
              COALESCE(sk.Diadiem, '') AS location,
              COALESCE(sk.Soluongtoida, 0) AS capacity,
              COALESCE(sk.Capchungnhan, 0) AS certificateEnabled,
              COUNT(DISTINCT dkAll.Masv) AS registeredCount,
              dkMine.Ngaydangky AS registeredAt,
              CASE WHEN dkMine.Masv IS NULL THEN 'notRegistered'
                   ELSE LOWER(REPLACE(dkMine.Trangthaidangky, ' ', '')) END AS registrationStatus,
              CASE
                WHEN dkMine.Masv IS NULL THEN ''
                WHEN EXISTS (
                  SELECT 1 FROM event_attendance ea
                  WHERE ea.event_id = sk.Masukien
                    AND ea.student_id = dkMine.Masv
                ) OR EXISTS (
                  SELECT 1 FROM event_attendance_records ear
                  WHERE ear.event_id = sk.Masukien
                    AND ear.student_id = dkMine.Masv
                ) THEN 'Có mặt'
                WHEN sk.Trangthaisukien = 'Đã đóng'
                  OR NOW() >= sk.Thoigianketthuc THEN 'Vắng mặt'
                ELSE 'Chưa điểm danh'
              END AS attendanceStatus
       FROM SuKien sk
       LEFT JOIN DonVi dv ON dv.Madv = sk.Madv
       LEFT JOIN DangKySuKien dkAll ON dkAll.Masukien = sk.Masukien
       LEFT JOIN DangKySuKien dkMine
         ON dkMine.Masukien = sk.Masukien
        AND dkMine.Masv = ?
       GROUP BY sk.Masukien, sk.Tensukien, sk.Madv, dv.Tendv,
                sk.Thoigianbatdau, sk.Thoigianketthuc, sk.Trangthaisukien,
                sk.Diadiem, sk.HinhAnh,
                sk.Soluongtoida, sk.Capchungnhan,
                dkMine.Masv, dkMine.Trangthaidangky,
                dkMine.Ngaydangky
       ORDER BY sk.Thoigianbatdau`,
      [request.auth.sub],
    );
    const { effective: globalParameters } = await getEffectiveAttendanceParameters();
    const [[allEventParameters]] = await pool.execute(
      `SELECT event_registration_lock_hours AS eventRegistrationLockHours
       FROM system_parameters WHERE scope_type = 'all_events' AND scope_id = '' LIMIT 1`,
    );
    const eventParameterRows = rows.length > 0
      ? (await pool.execute(
        `SELECT scope_id AS scopeId,
                event_registration_lock_hours AS eventRegistrationLockHours
         FROM system_parameters
         WHERE scope_type = 'event' AND scope_id IN (${rows.map(() => '?').join(', ')})`,
        rows.map((row) => row.id),
      ))[0]
      : [];
    const eventLockOverrides = new Map(
      eventParameterRows.map((item) => [String(item.scopeId), item.eventRegistrationLockHours]),
    );
    for (const row of rows) {
      const lockHours = eventLockOverrides.get(String(row.id))
        ?? allEventParameters?.eventRegistrationLockHours
        ?? globalParameters.eventRegistrationLockHours;
      const registrationLockAt = new Date(row.startTime).getTime()
        - Number(lockHours) * 60 * 60 * 1000;
      row.registrationLockHours = Number(lockHours);
      row.registrationLocked = Date.now() >= registrationLockAt
        || row.status === 'Đã đóng'
        || new Date(row.endTime) <= new Date();
    }
    return response.json({ items: rows });
  } catch (error) {
    console.error('Events error:', error.message);
    return response.status(500).json({ message: 'Không thể tải danh sách sự kiện.' });
  }
});

// Lấy thông tin chi tiết, quyền lợi và nội quy của một sự kiện.
app.get('/api/events/:eventId', requireAuth, async (request, response) => {
  try {
    const [[event]] = await pool.execute(
      [
        "SELECT sk.Masukien AS id, sk.Tensukien AS name,",
        "COALESCE(sk.HinhAnh, '') AS imageUrl,",
        "COALESCE(sk.DonDangKy, '') AS registrationFormUrl,",
        "sk.Mota AS description, COALESCE(sk.Diadiem, '') AS location,",
        "sk.Thoigianbatdau AS startTime, sk.Thoigianketthuc AS endTime,",
        "COALESCE(sk.Soluongtoida, 0) AS capacity,",
        "COALESCE(sk.Capchungnhan, 0) AS certificateEnabled,",
        "COALESCE(sk.attendance_threshold_percent, 100) AS attendanceThresholdPercent,",
        "dv.Tendv AS organizerName,",
        "(SELECT COUNT(*) FROM DangKySuKien allRegs",
        "WHERE allRegs.Masukien = sk.Masukien) AS registeredCount,",
        "(SELECT COUNT(*) FROM DangKySuKien myRegistration",
        "WHERE myRegistration.Masukien = sk.Masukien AND myRegistration.Masv = ?) AS isRegistered,",
        "(SELECT myRegistration.Ngaydangky FROM DangKySuKien myRegistration",
        "WHERE myRegistration.Masukien = sk.Masukien AND myRegistration.Masv = ? LIMIT 1) AS registeredAt",
        "FROM SuKien sk INNER JOIN DonVi dv ON dv.Madv = sk.Madv",
        "WHERE sk.Masukien = ? LIMIT 1",
      ].join(' '),
      [request.auth.sub, request.auth.sub, request.params.eventId],
    );
    if (!event) return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });

    let benefits = [];
    try {
      [benefits] = await pool.execute(
      [
        "SELECT Loaiquyenloi AS type, Sodiem AS points, Noidung AS content",
        "FROM QuyenLoi WHERE Masukien = ? ORDER BY Maquyenloi",
      ].join(' '),
      [event.id],
      );
    } catch (error) {
      if (error.code !== 'ER_NO_SUCH_TABLE') throw error;
    }
    let rules = [];
    try {
      [rules] = await pool.execute(
      [
        "SELECT Thutu AS sortOrder, Noidung AS text",
        "FROM NoiQuy WHERE Masukien = ? ORDER BY Thutu",
      ].join(' '),
      [event.id],
      );
    } catch (error) {
      if (error.code !== 'ER_NO_SUCH_TABLE') throw error;
    }
    const [attendancePeriods] = await pool.execute(
      `SELECT period_id AS id, name, starts_at AS startTime,
              ends_at AS endTime
       FROM event_attendance_periods
       WHERE event_id = ?
       ORDER BY display_order, starts_at`,
      [event.id],
    );
    return response.json({ ...event, benefits, rules, attendancePeriods });
  } catch (error) {
    console.error('Event details error:', error.message);
    return response.status(500).json({ message: 'Không thể tải chi tiết sự kiện.' });
  }
});

// Trả lịch sử phản hồi và đánh giá của chính sinh viên đang đăng nhập.
app.get('/api/student/my-feedback', requireAuth, requireRole('Sinh viên', 'student'), async (request, response) => {
  try {
    const [feedbackItems] = await pool.execute(
      `SELECT ph.Maphanhoi AS id,
              CASE
                WHEN ph.Masukien IS NOT NULL THEN 'event'
                WHEN ph.Malop IS NOT NULL THEN 'class'
                ELSE NULL
              END AS targetType,
              COALESCE(sk.Tensukien, lhp.Tenlop, '') AS targetName,
              ph.Masukien AS eventId, ph.Malop AS classId,
              ph.Noidung AS content, ph.Thoigiangui AS createdAt
       FROM PhanHoi ph
       LEFT JOIN SuKien sk ON sk.Masukien = ph.Masukien
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = ph.Malop
       WHERE ph.Masv = ?
       ORDER BY ph.Thoigiangui DESC, ph.Maphanhoi DESC`,
      [request.auth.sub],
    );
    const [ratingItems] = await pool.execute(
      `SELECT dg.Madanhgia AS id,
              CASE
                WHEN dg.Masukien IS NOT NULL THEN 'event'
                WHEN dg.Malop IS NOT NULL THEN 'class'
                ELSE NULL
              END AS targetType,
              COALESCE(sk.Tensukien, lhp.Tenlop, '') AS targetName,
              dg.Masukien AS eventId, dg.Malop AS classId,
              dg.Sosao AS rating, COALESCE(dg.Noidung, '') AS content,
              dg.Thoigiandanhgia AS createdAt
       FROM DanhGia dg
       LEFT JOIN SuKien sk ON sk.Masukien = dg.Masukien
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = dg.Malop
       WHERE dg.Masv = ?
       ORDER BY dg.Thoigiandanhgia DESC, dg.Madanhgia DESC`,
      [request.auth.sub],
    );
    return response.json({ feedbackItems, ratingItems });
  } catch (error) {
    console.error('Student feedback history error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải lịch sử phản hồi và đánh giá.',
    });
  }
});

app.get('/api/events/:eventId/feedback', requireAuth, async (request, response) => {
  try {
    const [[summary]] = await pool.execute(
      `SELECT COALESCE(AVG(SoSao), 0) AS averageRating,
              COUNT(*) AS ratingCount
       FROM DanhGia WHERE Masukien = ?`,
      [request.params.eventId],
    );
    const [items] = await pool.execute(
      `SELECT dg.SoSao AS rating,
              COALESCE(NULLIF(dg.Noidung, ''), ph.Noidung, '') AS comment,
              COALESCE(dg.Thoigiandanhgia, ph.Thoigiangui) AS createdAt
       FROM PhanHoi ph
       LEFT JOIN DanhGia dg
         ON dg.Masv = ph.Masv AND dg.Masukien = ph.Masukien
       WHERE ph.Masukien = ?
       UNION ALL
       SELECT dg.SoSao AS rating, COALESCE(dg.Noidung, '') AS comment,
              dg.Thoigiandanhgia AS createdAt
       FROM DanhGia dg
       WHERE dg.Masukien = ?
         AND NOT EXISTS (
           SELECT 1 FROM PhanHoi ph
           WHERE ph.Masv = dg.Masv AND ph.Masukien = dg.Masukien
         )
       ORDER BY createdAt DESC`,
      [request.params.eventId, request.params.eventId],
    );
    return response.json({
      averageRating: Number(summary.averageRating),
      ratingCount: Number(summary.ratingCount),
      items,
    });
  } catch (error) {
    console.error('Event feedback error:', error.message);
    return response.status(500).json({ message: 'Không thể tải phản hồi sự kiện.' });
  }
});

app.post('/api/events/:eventId/feedback', requireAuth, async (request, response) => {
  const { rating, comment } = request.body || {};
  const hasRating = rating !== undefined && rating !== null;
  const hasComment = comment !== undefined && comment !== null;
  if (!['student', 'sinh viên'].includes(String(request.auth.role).toLowerCase())) {
    return response.status(403).json({ message: 'Chỉ sinh viên mới được gửi đánh giá.' });
  }
  if ((!hasRating && !hasComment)
    || (hasRating && (!Number.isInteger(Number(rating))
      || Number(rating) < 1 || Number(rating) > 5))
    || (hasComment && (typeof comment !== 'string' || comment.trim().length > 2000))
    || (!hasRating && (!hasComment || !comment.trim()))) {
    return response.status(400).json({
      message: 'Vui lòng chọn từ 1 đến 5 sao hoặc nhập phản hồi tối đa 2.000 ký tự.',
    });
  }

  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[event]] = await connection.execute(
      `SELECT Masukien AS id FROM SuKien
       WHERE Masukien = ? AND (Thoigianketthuc <= NOW() OR Trangthaisukien = 'Đã đóng')
       FOR UPDATE`,
      [request.params.eventId],
    );
    if (!event) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Chỉ có thể đánh giá sự kiện đã kết thúc hoặc đã đóng.',
      });
    }
    const [[registration]] = await connection.execute(
      `SELECT Masv FROM DangKySuKien
       WHERE Masukien = ? AND Masv = ?
         AND Trangthaidangky NOT IN ('Đã hủy', 'Từ chối')
       LIMIT 1`,
      [event.id, request.auth.sub],
    );
    if (!registration) {
      await connection.rollback();
      return response.status(403).json({
        message: 'Bạn cần đăng ký sự kiện trước khi gửi đánh giá.',
      });
    }

    const normalizedComment = hasComment ? comment.trim() : '';
    if (hasRating) {
      await connection.execute(
        `INSERT INTO DanhGia (Madanhgia, Sosao, Noidung, Masv, Masukien)
         VALUES (?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           Sosao = VALUES(Sosao), Noidung = VALUES(Noidung),
           Thoigiandanhgia = CURRENT_TIMESTAMP`,
        [generateRecordId('DG'), Number(rating), normalizedComment, request.auth.sub, event.id],
      );
    }
    if (normalizedComment) {
      await connection.execute(
        `INSERT INTO PhanHoi (Maphanhoi, Noidung, Masv, Masukien)
         VALUES (?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           Noidung = VALUES(Noidung), Thoigiangui = CURRENT_TIMESTAMP`,
        [generateRecordId('PH'), normalizedComment, request.auth.sub, event.id],
      );
    }
    await connection.commit();
    return response.json({ message: 'Gửi đánh giá thành công.' });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Submit event feedback error:', error.message);
    return response.status(500).json({ message: 'Không thể gửi đánh giá sự kiện.' });
  } finally {
    if (connection) connection.release();
  }
});

app.get('/api/classes/:classId/feedback', requireAuth, async (request, response) => {
  try {
    const [[classInfo]] = await pool.execute(
      'SELECT Malop FROM LopHocPhan WHERE Malop = ? LIMIT 1',
      [request.params.classId],
    );
    if (!classInfo) {
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    const [[summary]] = await pool.execute(
      `SELECT COALESCE(AVG(SoSao), 0) AS averageRating,
              COUNT(*) AS ratingCount
       FROM DanhGia WHERE Malop = ?`,
      [request.params.classId],
    );
    const [items] = await pool.execute(
      `SELECT dg.SoSao AS rating,
              COALESCE(NULLIF(dg.Noidung, ''), ph.Noidung, '') AS comment,
              COALESCE(dg.Thoigiandanhgia, ph.Thoigiangui) AS createdAt
       FROM PhanHoi ph
       LEFT JOIN DanhGia dg
         ON dg.Masv = ph.Masv AND dg.Malop = ph.Malop
       WHERE ph.Malop = ?
       UNION ALL
       SELECT dg.SoSao AS rating, COALESCE(dg.Noidung, '') AS comment,
              dg.Thoigiandanhgia AS createdAt
       FROM DanhGia dg
       WHERE dg.Malop = ?
         AND NOT EXISTS (
           SELECT 1 FROM PhanHoi ph
           WHERE ph.Masv = dg.Masv AND ph.Malop = dg.Malop
         )
       ORDER BY createdAt DESC`,
      [request.params.classId, request.params.classId],
    );
    return response.json({
      averageRating: Number(summary.averageRating),
      ratingCount: Number(summary.ratingCount),
      items,
    });
  } catch (error) {
    console.error('Class feedback error:', error.message);
    return response.status(500).json({ message: 'Không thể tải phản hồi lớp học.' });
  }
});

app.post('/api/classes/:classId/feedback', requireAuth, async (request, response) => {
  const { rating, comment } = request.body || {};
  const hasRating = rating !== undefined && rating !== null;
  const hasComment = comment !== undefined && comment !== null;
  if (!['student', 'sinh viên'].includes(String(request.auth.role).toLowerCase())) {
    return response.status(403).json({ message: 'Chỉ sinh viên mới được gửi đánh giá.' });
  }
  if ((!hasRating && !hasComment)
    || (hasRating && (!Number.isInteger(Number(rating))
      || Number(rating) < 1 || Number(rating) > 5))
    || (hasComment && (typeof comment !== 'string' || comment.trim().length > 2000))
    || (!hasRating && (!hasComment || !comment.trim()))) {
    return response.status(400).json({
      message: 'Vui lòng chọn từ 1 đến 5 sao hoặc nhập phản hồi tối đa 2.000 ký tự.',
    });
  }

  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[classInfo]] = await connection.execute(
      'SELECT Malop AS id FROM LopHocPhan WHERE Malop = ? FOR UPDATE',
      [request.params.classId],
    );
    if (!classInfo) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    const [[membership]] = await connection.execute(
      `SELECT Masv FROM ThanhVienLop
       WHERE Malop = ? AND Masv = ? AND TrangThaiThanhVien <> 'Đã rút'
       LIMIT 1`,
      [classInfo.id, request.auth.sub],
    );
    if (!membership) {
      await connection.rollback();
      return response.status(403).json({
        message: 'Bạn cần là thành viên của lớp trước khi gửi đánh giá.',
      });
    }

    const normalizedComment = hasComment ? comment.trim() : '';
    if (hasRating) {
      await connection.execute(
        `INSERT INTO DanhGia (Madanhgia, Sosao, Noidung, Masv, Malop)
         VALUES (?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           Sosao = VALUES(Sosao), Noidung = VALUES(Noidung),
           Thoigiandanhgia = CURRENT_TIMESTAMP`,
        [generateRecordId('DG'), Number(rating), normalizedComment, request.auth.sub, classInfo.id],
      );
    }
    if (normalizedComment) {
      await connection.execute(
        `INSERT INTO PhanHoi (Maphanhoi, Noidung, Masv, Malop)
         VALUES (?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           Noidung = VALUES(Noidung), Thoigiangui = CURRENT_TIMESTAMP`,
        [generateRecordId('PH'), normalizedComment, request.auth.sub, classInfo.id],
      );
    }
    await connection.commit();
    return response.json({ message: 'Gửi đánh giá lớp học thành công.' });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Submit class feedback error:', error.message);
    return response.status(500).json({ message: 'Không thể gửi đánh giá lớp học.' });
  } finally {
    if (connection) connection.release();
  }
});

// Ghi nhận đăng ký tham gia sự kiện cho sinh viên hiện tại.
app.post('/api/events/:eventId/register', requireAuth, async (request, response) => {
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[event]] = await connection.execute(
    `SELECT Thoigianbatdau AS startTime, Thoigianketthuc AS endTime,
              Soluongtoida AS capacity, Trangthaisukien AS status
       FROM SuKien WHERE Masukien = ? FOR UPDATE`,
      [request.params.eventId],
    );
    if (!event) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    if (event.status === 'Đã đóng') {
      await connection.rollback();
      return response.status(409).json({
        message: 'Sự kiện đã đóng, không thể đăng ký.',
      });
    }
    if (new Date(event.endTime) <= new Date()) {
      await connection.rollback();
      return response.status(409).json({ message: 'Sự kiện đã kết thúc, không thể đăng ký.' });
    }
    const { effective: eventParameters } = await getEffectiveAttendanceParameters(
      'event', request.params.eventId, connection,
    );
    const registrationLockAt = new Date(event.startTime).getTime()
      - Number(eventParameters.eventRegistrationLockHours) * 60 * 60 * 1000;
    if (Date.now() >= registrationLockAt) {
      await connection.rollback();
      return response.status(409).json({
        message: `Đã đến thời gian khóa đăng ký trước sự kiện ${eventParameters.eventRegistrationLockHours} giờ. Không thể đăng ký mới.`,
      });
    }
    const [[registrationCount]] = await connection.execute(
      'SELECT COUNT(*) AS total FROM DangKySuKien WHERE Masukien = ?',
      [request.params.eventId],
    );
    if (Number(registrationCount.total) >= Number(event.capacity)) {
      await connection.rollback();
      return response.status(409).json({ message: 'Sự kiện đã đủ số lượng đăng ký.' });
    }

    const { global: globalAttendanceParameters } =
      await getEffectiveAttendanceParameters('global', '', connection);
    const [eventConflicts] = globalAttendanceParameters.allowOverlappingEventAttendance
      ? [[]]
      : await connection.execute(
      `SELECT sk.Tensukien AS name
       FROM DangKySuKien dk
       INNER JOIN SuKien sk ON sk.Masukien = dk.Masukien
       WHERE dk.Masv = ? AND dk.Masukien <> ?
         AND dk.Trangthaidangky NOT IN ('Từ chối', 'Đã hủy', 'Hủy')
         AND sk.Thoigianbatdau < ? AND sk.Thoigianketthuc > ?
       LIMIT 1`,
      [request.auth.sub, request.params.eventId, event.endTime, event.startTime],
    );
    if (eventConflicts[0]) {
      await connection.rollback();
      return response.status(409).json({
        type: 'event_schedule_conflict',
        message: `Sự kiện bị trùng lịch với "${eventConflicts[0].name}". Vui lòng hủy sự kiện trùng lịch trước khi đăng ký.`,
      });
    }

    const [classConflicts] = await connection.execute(
      `SELECT lhp.Tenlop AS name, b.Noidung AS content
       FROM ThanhVienLop tvl
       INNER JOIN Buoi b ON b.Malop = tvl.Malop
       INNER JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
       WHERE tvl.Masv = ?
         AND b.Thoigianbatdau < ? AND b.Thoigianketthuc > ?
       LIMIT 1`,
      [request.auth.sub, event.endTime, event.startTime],
    );
    if (classConflicts[0] && request.body?.allowClassConflict !== true) {
      await connection.rollback();
      return response.status(409).json({
        type: 'class_schedule_conflict',
        className: classConflicts[0].name,
        message: `Sự kiện trùng lịch học ${classConflicts[0].name}${classConflicts[0].content ? ` - ${classConflicts[0].content}` : ''}. Bạn có chắc chắn muốn đăng ký không?`,
      });
    }

    await connection.execute(
      `INSERT INTO DangKySuKien
       (Masukien, Masv, Ngaydangky, Trangthaidangky)
       VALUES (?, ?, NOW(), 'Chờ duyệt')`,
      [request.params.eventId, request.auth.sub],
    );
    await connection.commit();
    return response.status(201).json({
      message: 'Đăng ký sự kiện thành công.',
      registeredAt: new Date().toISOString(),
    });
  } catch (error) {
    if (connection) await connection.rollback();
    if (error.code === 'ER_DUP_ENTRY') {
      return response.status(409).json({ message: 'Bạn đã đăng ký sự kiện này.' });
    }
    console.error('Event registration error:', error.message);
    return response.status(500).json({ message: 'Không thể đăng ký sự kiện.' });
  } finally {
    connection?.release();
  }
});

// Hủy đăng ký khi còn trước mốc khóa đăng ký của sự kiện.
app.delete('/api/events/:eventId/register', requireAuth, async (request, response) => {
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[event]] = await connection.execute(
      `SELECT Thoigianbatdau AS startTime,
              CASE WHEN Thoigianketthuc <= NOW() THEN 1 ELSE 0 END AS ended
       FROM SuKien WHERE Masukien = ? LIMIT 1 FOR UPDATE`,
      [request.params.eventId],
    );
    if (!event) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    if (Number(event.ended) === 1) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Sự kiện đã kết thúc, không thể hủy đăng ký.',
      });
    }
    const [[registration]] = await connection.execute(
      `SELECT Ngaydangky AS registeredAt
       FROM DangKySuKien
       WHERE Masukien = ? AND Masv = ?
       LIMIT 1 FOR UPDATE`,
      [request.params.eventId, request.auth.sub],
    );
    if (!registration) {
      await connection.rollback();
      return response.status(404).json({ message: 'Bạn chưa đăng ký sự kiện này.' });
    }
    const [[attendance]] = await connection.execute(
      `SELECT (
         EXISTS (
           SELECT 1 FROM event_attendance ea
           WHERE ea.event_id = ? AND ea.student_id = ?
         ) OR EXISTS (
           SELECT 1 FROM event_attendance_records ear
           WHERE ear.event_id = ? AND ear.student_id = ?
         )
       ) AS attended`,
      [request.params.eventId, request.auth.sub, request.params.eventId, request.auth.sub],
    );
    if (Number(attendance.attended) === 1) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Bạn đã điểm danh sự kiện này nên không thể hủy đăng ký.',
      });
    }
    const { effective: eventParameters } = await getEffectiveAttendanceParameters(
      'event', request.params.eventId, connection,
    );
    const registrationLockAt = new Date(event.startTime).getTime()
      - Number(eventParameters.eventRegistrationLockHours) * 60 * 60 * 1000;
    if (Date.now() >= registrationLockAt) {
      await connection.rollback();
      return response.status(403).json({
        message: `Đã đến thời gian khóa đăng ký trước sự kiện ${eventParameters.eventRegistrationLockHours} giờ. Không thể hủy đăng ký.`,
      });
    }
    await connection.execute(
      `DELETE FROM DangKySuKien WHERE Masukien = ? AND Masv = ?`,
      [request.params.eventId, request.auth.sub],
    );
    await connection.commit();
    return response.json({ message: 'Đã hủy đăng ký sự kiện.' });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Event cancellation error:', error.message);
    return response.status(500).json({ message: 'Không thể hủy đăng ký sự kiện.' });
  } finally {
    connection?.release();
  }
});

// Cung cấp số liệu tổng quan không nhạy cảm cho màn hình đăng nhập.
app.get('/api/public/stats', async (_request, response) => {
  try {
    const [[counts]] = await pool.query(
      `SELECT
         (SELECT COUNT(*) FROM SinhVien) AS students,
         (SELECT COUNT(*) FROM GiangVien) AS lecturers,
         (SELECT COUNT(*) FROM LopHocPhan) AS classes,
         (SELECT COUNT(*) FROM SuKien) AS events`,
    );
    return response.json({
      students: Number(counts.students || 0),
      lecturers: Number(counts.lecturers || 0),
      classes: Number(counts.classes || 0),
      events: Number(counts.events || 0),
    });
  } catch (error) {
    console.error('Public stats error:', error.message);
    return response.status(500).json({ message: 'Không thể tải số liệu hệ thống.' });
  }
});

// Tổng hợp số lớp, sự kiện và kết quả điểm danh của sinh viên.
app.get('/api/dashboard', requireAuth, async (request, response) => {
  try {
    const semesterParam = request.query.semester;
    const validSemesters = ['HK1', 'HK2', 'HK3'];
    if (
      semesterParam !== undefined
      && (typeof semesterParam !== 'string'
        || !validSemesters.includes(semesterParam.trim()))
    ) {
      return response.status(400).json({ message: 'Học kỳ không hợp lệ.' });
    }
    const semester = typeof semesterParam === 'string'
      ? semesterParam.trim()
      : '';
    await recordExpiredClassAbsences();
    const currentRole = String(request.auth.role || '').trim().toLowerCase();
    const userId = request.auth.sub;

    if (['quản trị viên', 'admin'].includes(currentRole)) {
      const [[users]] = await pool.query(
        'SELECT COUNT(*) AS total FROM NguoiDung',
      );
      const [[students]] = await pool.query(
        'SELECT COUNT(*) AS total FROM SinhVien',
      );
      const [[classes]] = await pool.query(
        'SELECT COUNT(*) AS total FROM LopHocPhan',
      );
      const [[events]] = await pool.query(
        'SELECT COUNT(*) AS total FROM SuKien',
      );
      const [[sessions]] = await pool.query(
        'SELECT COUNT(*) AS total FROM BuoiDiemDanh',
      );
      const [[attendance]] = await pool.query(
        `SELECT COUNT(*) AS total,
                SUM(CASE WHEN Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
                SUM(CASE WHEN Trangthaiketqua IN ('Đi trễ', 'Đi muộn') THEN 1 ELSE 0 END) AS late,
                SUM(CASE WHEN Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
         FROM KetQuaDiemDanh`,
      );
      let semesterAttendance = attendance;
      if (semester) {
        [[semesterAttendance]] = await pool.execute(
          `SELECT SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
                  SUM(CASE WHEN kd.Trangthaiketqua IN ('Đi trễ', 'Đi muộn') THEN 1 ELSE 0 END) AS late,
                  SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
           FROM KetQuaDiemDanh kd
           WHERE EXISTS (
             SELECT 1
             FROM BuoiDiemDanh bpd
             INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
             INNER JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
             WHERE bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
               AND lhp.Hocky = ?
           )`,
          [semester],
        );
      }
      const rate = Number(attendance.total || 0) === 0
        ? 0
        : Math.round(Number(attendance.present || 0) * 100 / Number(attendance.total));
      return response.json({
        metrics: [
          { label: 'Tổng người dùng', value: Number(users.total || 0) },
          { label: 'Sinh viên', value: Number(students.total || 0) },
          { label: 'Lớp học phần', value: Number(classes.total || 0) },
          { label: 'Sự kiện', value: Number(events.total || 0) },
          { label: 'Phiên điểm danh', value: Number(sessions.total || 0) },
          { label: 'Tỷ lệ có mặt', value: `${rate}%` },
        ],
        attendanceBreakdown: {
          present: Number(semesterAttendance.present || 0),
          late: Number(semesterAttendance.late || 0),
          absent: Number(semesterAttendance.absent || 0),
        },
      });
    }

    if (['cán bộ', 'nhân viên', 'ban tổ chức', 'organizer', 'staff', 'employee'].includes(currentRole)) {
      const [[events]] = await pool.execute(
        `SELECT COUNT(DISTINCT sk.Masukien) AS total,
                COUNT(DISTINCT dk.Masv, dk.Masukien) AS registrations
         FROM DonVi dv
         LEFT JOIN SuKien sk ON sk.Madv = dv.Madv
         LEFT JOIN DangKySuKien dk ON dk.Masukien = sk.Masukien
         WHERE dv.Manv = ?`,
        [userId],
      );
      const [[certificates]] = await pool.execute(
        `SELECT COUNT(*) AS total
         FROM ChungNhan cn
         INNER JOIN SuKien sk ON sk.Masukien = cn.Masukien
         INNER JOIN DonVi dv ON dv.Madv = sk.Madv
         WHERE dv.Manv = ?`,
        [userId],
      );
      return response.json({
        metrics: [
          { label: 'Sự kiện phụ trách', value: Number(events.total || 0) },
          { label: 'Lượt đăng ký', value: Number(events.registrations || 0) },
          { label: 'Chứng chỉ đã cấp', value: Number(certificates.total || 0) },
        ],
      });
    }

    if (['giảng viên', 'lecturer', 'teacher'].includes(currentRole)) {
      const [[teaching]] = await pool.execute(
        `SELECT COUNT(DISTINCT lhp.Malop) AS classes,
                COUNT(DISTINCT tvl.Masv) AS students,
                COUNT(DISTINCT b.Mabuoi) AS sessions
         FROM LopHocPhan lhp
         LEFT JOIN ThanhVienLop tvl ON tvl.Malop = lhp.Malop
         LEFT JOIN Buoi b ON b.Malop = lhp.Malop
         WHERE lhp.Magv = ?`,
        [userId],
      );
      const [[attendance]] = await pool.execute(
        `SELECT COUNT(kd.Maketqua) AS total,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
                SUM(CASE WHEN kd.Trangthaiketqua IN ('Đi trễ', 'Đi muộn') THEN 1 ELSE 0 END) AS late,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
         FROM KetQuaDiemDanh kd
         INNER JOIN BuoiDiemDanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
         INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
         INNER JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
         WHERE lhp.Magv = ?`,
        [userId],
      );
      let semesterAttendance = attendance;
      if (semester) {
        [[semesterAttendance]] = await pool.execute(
          `SELECT COUNT(kd.Maketqua) AS total,
                  SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
                  SUM(CASE WHEN kd.Trangthaiketqua IN ('Đi trễ', 'Đi muộn') THEN 1 ELSE 0 END) AS late,
                  SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
           FROM KetQuaDiemDanh kd
           INNER JOIN BuoiDiemDanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
           INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
           INNER JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
           WHERE lhp.Magv = ? AND lhp.Hocky = ?`,
          [userId, semester],
        );
      }
      const rate = Number(attendance.total || 0) === 0
        ? 0
        : Math.round(Number(attendance.present || 0) * 100 / Number(attendance.total));
      return response.json({
        metrics: [
          { label: 'Lớp của tôi', value: Number(teaching.classes || 0) },
          { label: 'Sinh viên', value: Number(teaching.students || 0) },
          { label: 'Buổi học', value: Number(teaching.sessions || 0) },
          { label: 'Tỷ lệ có mặt', value: `${rate}%` },
        ],
        attendanceBreakdown: {
          present: Number(semesterAttendance.present || 0),
          late: Number(semesterAttendance.late || 0),
          absent: Number(semesterAttendance.absent || 0),
        },
      });
    }

    const [[classes]] = await pool.execute(
      'SELECT COUNT(*) AS total FROM ThanhVienLop WHERE Masv = ?',
      [userId],
    );
    const [[events]] = await pool.execute(
      'SELECT COUNT(*) AS total FROM DangKySuKien WHERE Masv = ?',
      [userId],
    );
    const [[attendance]] = await pool.execute(
      `SELECT
         SUM(CASE WHEN Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
         SUM(CASE WHEN Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
         SUM(CASE WHEN Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
      FROM KetQuaDiemDanh WHERE Masv = ?`,
          [userId],
    );
    let semesterAttendance = attendance;
    if (semester) {
      [[semesterAttendance]] = await pool.execute(
        `SELECT SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
         FROM KetQuaDiemDanh kd
         WHERE kd.Masv = ?
           AND EXISTS (
             SELECT 1
             FROM BuoiDiemDanh bpd
             INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
             INNER JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
             WHERE bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
               AND lhp.Hocky = ?
           )`,
        [userId, semester],
      );
    }
    return response.json({
      classes: Number(classes.total || 0),
      events: Number(events.total || 0),
      present: Number(attendance.present || 0),
      late: Number(attendance.late || 0),
      absent: Number(attendance.absent || 0),
      attendanceBreakdown: {
        present: Number(semesterAttendance.present || 0),
        late: Number(semesterAttendance.late || 0),
        absent: Number(semesterAttendance.absent || 0),
      },
    });
  } catch (error) {
    console.error('Dashboard error:', error.message);
    return response.status(500).json({ message: 'Không thể tải dữ liệu tổng quan.' });
  }
});

// Tạo mã định danh ngẫu nhiên theo tiền tố của loại dữ liệu.
function makeId(prefix) {
  return `${prefix}_${crypto.randomBytes(10).toString('hex')}`.slice(0, 30);
}

const classAttendanceRadiusMeters = 100;
const eventAttendanceRadiusMeters = 300;
const defaultAttendanceParameters = {
  gpsRadiusMeters: 100,
  eventRegistrationLockHours: 0,
  qrDurationMinutes: 15,
  attendanceThresholdPercent: 100,
  allowEarlyAttendance: false,
  allowOverlappingEventAttendance: false,
};

async function getEffectiveAttendanceParameters(scopeType = 'global', scopeId = '', executor = pool) {
  const selectParameters = async (type, id) => {
    const [rows] = await executor.execute(
      `SELECT gps_radius_meters AS gpsRadiusMeters,
              event_registration_lock_hours AS eventRegistrationLockHours,
              qr_duration_minutes AS qrDurationMinutes,
              attendance_threshold_percent AS attendanceThresholdPercent,
              allow_early_attendance AS allowEarlyAttendance,
              allow_overlapping_event_attendance AS allowOverlappingEventAttendance
       FROM system_parameters WHERE scope_type = ? AND scope_id = ? LIMIT 1`,
      [type, id],
    );
    return rows[0] || null;
  };
  const globalRow = await selectParameters('global', '');
  const global = {
    ...defaultAttendanceParameters,
    ...(globalRow || {}),
    attendanceThresholdPercent: Number(
      globalRow?.attendanceThresholdPercent ?? defaultAttendanceParameters.attendanceThresholdPercent,
    ),
    allowEarlyAttendance: Boolean(
      Number(globalRow?.allowEarlyAttendance ?? defaultAttendanceParameters.allowEarlyAttendance),
    ),
    allowOverlappingEventAttendance: Boolean(
      Number(globalRow?.allowOverlappingEventAttendance ?? defaultAttendanceParameters.allowOverlappingEventAttendance),
    ),
  };
  const isGroupScope = ['all_classes', 'all_events'].includes(scopeType);
  const entityGroupScope = scopeType === 'class'
    ? 'all_classes'
    : scopeType === 'event'
      ? 'all_events'
      : null;
  const groupRow = isGroupScope
    ? await selectParameters(scopeType, '')
    : entityGroupScope
      ? await selectParameters(entityGroupScope, '')
      : null;
  const override = scopeType === 'global'
    ? global
    : isGroupScope
      ? groupRow
      : await selectParameters(scopeType, scopeId);
  const overrides = scopeType === 'global'
    ? global
    : {
      gpsRadiusMeters: override?.gpsRadiusMeters ?? null,
      eventRegistrationLockHours: override?.eventRegistrationLockHours ?? null,
      qrDurationMinutes: override?.qrDurationMinutes ?? null,
      attendanceThresholdPercent: override?.attendanceThresholdPercent ?? null,
    };
  const effective = scopeType === 'global'
    ? global
    : {
      gpsRadiusMeters: overrides.gpsRadiusMeters
        ?? groupRow?.gpsRadiusMeters ?? global.gpsRadiusMeters,
      eventRegistrationLockHours:
        overrides.eventRegistrationLockHours
          ?? groupRow?.eventRegistrationLockHours ?? global.eventRegistrationLockHours,
      qrDurationMinutes: overrides.qrDurationMinutes
        ?? groupRow?.qrDurationMinutes ?? global.qrDurationMinutes,
      attendanceThresholdPercent:
        overrides.attendanceThresholdPercent
          ?? groupRow?.attendanceThresholdPercent ?? global.attendanceThresholdPercent,
      allowEarlyAttendance: global.allowEarlyAttendance,
    };
  return { global, overrides, effective };
}

async function filterEligibleEventAttendees(eventId, attendees) {
  if (attendees.length === 0) return [];
  const [[event]] = await pool.execute(
    `SELECT attendance_threshold_percent AS attendanceThresholdPercent
     FROM SuKien WHERE Masukien = ? LIMIT 1`,
    [eventId],
  );
  const [[sessionSummary]] = await pool.execute(
    `SELECT COUNT(*) AS totalSessions FROM event_attendance_sessions
     WHERE event_id = ?`,
    [eventId],
  );
  const [[periodSummary]] = await pool.execute(
    `SELECT COUNT(*) AS totalPeriods FROM event_attendance_periods
     WHERE event_id = ?`,
    [eventId],
  );
  const totalPeriods = Number(periodSummary.totalPeriods);
  const [sessionAttendance] = await pool.execute(
    `SELECT ear.student_id AS studentId,
            COUNT(DISTINCT CASE
              WHEN ? > 0 THEN eas.period_id ELSE ear.session_id
            END) AS attendedSessions
     FROM event_attendance_records ear
     INNER JOIN event_attendance_sessions eas
       ON eas.session_id = ear.session_id AND eas.event_id = ear.event_id
     WHERE ear.event_id = ?
     GROUP BY ear.student_id`,
    [totalPeriods, eventId],
  );
  const [legacyAttendance] = Number(sessionSummary.totalSessions) === 0
    ? await pool.execute(
      `SELECT student_id AS studentId FROM event_attendance WHERE event_id = ?`,
      [eventId],
    )
    : [[]];
  const attendedByStudent = new Map(sessionAttendance.map((row) => [
    String(row.studentId), Number(row.attendedSessions),
  ]));
  for (const row of legacyAttendance) attendedByStudent.set(String(row.studentId), 1);
  const totalAttendanceUnits = totalPeriods || Number(sessionSummary.totalSessions);
  const threshold = Number(event?.attendanceThresholdPercent ?? 100);
  return attendees.filter((attendee) => {
    const attended = attendedByStudent.get(String(attendee.studentId)) || 0;
    return totalAttendanceUnits === 0
      ? threshold === 0 || attended > 0
      : attended * 100 >= threshold * totalAttendanceUnits;
  });
}

// Đọc và kiểm tra vĩ độ, kinh độ từ request hoặc payload QR.
function readCoordinates(body) {
  if (body?.latitude === undefined || body.latitude === null
      || body?.longitude === undefined || body.longitude === null) {
    return null;
  }
  const latitude = Number(body?.latitude);
  const longitude = Number(body?.longitude);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90
      || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return null;
  }
  return { latitude, longitude };
}

function readLocationAccuracy(body) {
  if (body?.accuracy === undefined) return 0;
  if (body.accuracy === null) return null;
  const accuracy = Number(body.accuracy);
  return Number.isFinite(accuracy) && accuracy >= 0 ? accuracy : null;
}

const maxGpsAccuracyAllowanceMeters = 20;

function isWithinAttendanceRadius(
  first,
  second,
  radiusMeters,
  firstAccuracyMeters = 0,
  secondAccuracyMeters = 0,
) {
  const accuracyAllowance = Math.min(
    maxGpsAccuracyAllowanceMeters,
    Math.max(0, firstAccuracyMeters) + Math.max(0, secondAccuracyMeters),
  );
  return distanceInMeters(first, second) <= radiusMeters + accuracyAllowance;
}

async function checkInEventAttendance(request, response, payload, deviceId, coordinates) {
  if (typeof payload.eventId !== 'string' || !payload.eventId) {
    return response.status(410).json({ message: 'Mã QR sự kiện không hợp lệ.' });
  }
  const { global: globalParameters } = await getEffectiveAttendanceParameters(
    'global',
  );
  const allowEarlyAttendance = globalParameters.allowEarlyAttendance;
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [[event]] = await connection.execute(
      `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              COALESCE(sk.Diadiem, '') AS location,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              sk.Trangthaisukien AS status,
              CASE
                WHEN (? = 1 OR NOW() >= sk.Thoigianbatdau)
                  AND NOW() < sk.Thoigianketthuc
                  AND sk.Trangthaisukien <> 'Đã đóng' THEN 1
                ELSE 0
              END AS isOpen,
              eas.session_id AS sessionId,
              eas.latitude AS latitude,
              eas.longitude AS longitude,
              eas.radius_meters AS radiusMeters,
              eas.opened_at AS openedAt
       FROM SuKien sk
       JOIN event_attendance_sessions eas ON eas.event_id = sk.Masukien
       WHERE sk.Masukien = ?
         AND (? IS NULL OR eas.session_id = ?)
         AND eas.closed_at IS NULL
         AND eas.expires_at > NOW()
         AND (eas.period_start IS NULL
           OR ? = 1
           OR (NOW() >= eas.period_start AND NOW() < eas.period_end))
       ORDER BY eas.opened_at DESC, eas.session_id DESC
       LIMIT 1
       FOR UPDATE`,
      [
        allowEarlyAttendance ? 1 : 0,
        payload.eventId,
        typeof payload.sessionId === 'string' ? payload.sessionId : null,
        typeof payload.sessionId === 'string' ? payload.sessionId : null,
        allowEarlyAttendance ? 1 : 0,
      ],
    );
    if (!event || Number(event.isOpen) !== 1) {
      await connection.rollback();
      return response.status(410).json({
        message: 'Phiên điểm danh đã đóng, hết hạn hoặc hiện không nằm trong khung giờ điểm danh.',
      });
    }
    const radiusMeters = Number(event.radiusMeters);
    if (distanceInMeters(
      { latitude: Number(event.latitude), longitude: Number(event.longitude) },
      coordinates,
    ) > radiusMeters) {
      await connection.rollback();
      return response.status(403).json({
        message: `Bạn đang cách vị trí sự kiện quá xa (phạm vi ${radiusMeters} m).`,
      });
    }

    const [[registration]] = await connection.execute(
      `SELECT Trangthaidangky AS status
       FROM DangKySuKien
       WHERE Masukien = ? AND Masv = ?
       LIMIT 1
       FOR UPDATE`,
      [event.id, request.auth.sub],
    );
    if (!registration
        || ['từ chối', 'đã hủy', 'hủy'].includes(
          String(registration.status || '').trim().toLowerCase(),
        )) {
      await connection.rollback();
      return response.status(403).json({
        message: 'Bạn cần có đăng ký hợp lệ cho sự kiện mới được điểm danh.',
      });
    }

    await connection.execute(
      `INSERT INTO event_attendance_records
       (event_id, session_id, student_id, device_id, method)
       VALUES (?, ?, ?, ?, 'QR')`,
      [event.id, event.sessionId, request.auth.sub, deviceId],
    );
    await connection.execute(
      `INSERT IGNORE INTO event_attendance (event_id, student_id, device_id)
       VALUES (?, ?, ?)`,
      [event.id, request.auth.sub, deviceId],
    );
    const [[attendee]] = await connection.execute(
      `SELECT sk.Masukien AS eventId, sk.Tensukien AS eventName,
              sk.Diadiem AS location, sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              COALESCE(dv.Tendv, '') AS organizerName,
              ea.checked_in_at AS checkedInAt,
              nd.Mand AS studentId, COALESCE(nd.Hoten, nd.Mand) AS studentName,
              ea.session_id AS attendanceSessionId,
              session.period_name AS periodName,
              session.period_start AS periodStart,
              session.period_end AS periodEnd,
              (SELECT COUNT(*)
               FROM event_attendance_sessions previous
               WHERE previous.event_id = ea.event_id
                 AND (previous.opened_at < session.opened_at
                   OR (previous.opened_at = session.opened_at
                     AND previous.session_id <= session.session_id))) AS sessionNumber
       FROM event_attendance_records ea
       INNER JOIN SuKien sk ON sk.Masukien = ea.event_id
       INNER JOIN event_attendance_sessions session
         ON session.session_id = ea.session_id
       LEFT JOIN DonVi dv ON dv.Madv = sk.Madv
       INNER JOIN NguoiDung nd ON nd.Mand = ea.student_id
       WHERE ea.event_id = ? AND ea.session_id = ? AND ea.student_id = ?
       LIMIT 1`,
      [event.id, event.sessionId, request.auth.sub],
    );
    await connection.commit();
    return response.status(201).json({
      message: 'Điểm danh sự kiện thành công.',
      status: 'Có mặt',
      ...attendee,
    });
  } catch (error) {
    await connection.rollback();
    if (error.code === 'ER_DUP_ENTRY') {
      return response.status(409).json({
        message: 'Bạn đã điểm danh phiên này hoặc thiết bị đã được dùng trong phiên.',
      });
    }
    throw error;
  } finally {
    connection.release();
  }
}

app.post('/api/events/attendance/check-in', requireAuth, async (request, response) => {
  const { qrToken, deviceId } = request.body || {};
  const coordinates = readCoordinates(request.body);
  const previewOnly = request.body?.preview === true;
  if (typeof qrToken !== 'string' || qrToken.length === 0) {
    return response.status(400).json({ message: 'Thiếu mã QR sự kiện.' });
  }
  if (!previewOnly && (typeof deviceId !== 'string' || !/^[a-f0-9]{32}$/.test(deviceId))) {
    return response.status(400).json({ message: 'Không xác định được thiết bị điểm danh.' });
  }
  if (!previewOnly && !coordinates) {
    return response.status(400).json({ message: 'Không lấy được vị trí hiện tại của bạn.' });
  }
  if (!['student', 'sinh viên'].includes(String(request.auth.role).toLowerCase())) {
    return response.status(403).json({
      message: 'Sai tài khoản: hãy đăng nhập bằng tài khoản sinh viên để điểm danh.',
    });
  }

  try {
    const [[student]] = await pool.execute(
      'SELECT Masv AS id FROM SinhVien WHERE Masv = ? LIMIT 1',
      [request.auth.sub],
    );
    if (!student) {
      return response.status(403).json({
        message: 'Sai sinh viên: tài khoản này chưa được liên kết với hồ sơ sinh viên.',
      });
    }

    const payload = jwt.verify(qrToken, jwtSecret);
    if (payload.type !== 'event-attendance') {
      return response.status(410).json({ message: 'Mã QR không phải mã điểm danh sự kiện.' });
    }
    if (previewOnly) {
      const { global: globalParameters } = await getEffectiveAttendanceParameters(
        'global',
      );
      const allowEarlyAttendance = globalParameters.allowEarlyAttendance;
      const [[preview]] = await pool.execute(
        `SELECT sk.Masukien AS eventId, sk.Tensukien AS eventName,
                COALESCE(sk.Diadiem, '') AS location,
                sk.Thoigianbatdau AS startTime,
                sk.Thoigianketthuc AS endTime,
                COALESCE(dv.Tendv, '') AS organizerName,
                eas.session_id AS attendanceSessionId,
                eas.period_name AS periodName,
                eas.period_start AS periodStart,
                eas.period_end AS periodEnd,
                (SELECT COUNT(*)
                 FROM event_attendance_sessions previous
                 WHERE previous.event_id = eas.event_id
                   AND (previous.opened_at < eas.opened_at
                     OR (previous.opened_at = eas.opened_at
                       AND previous.session_id <= eas.session_id))) AS sessionNumber,
                nd.Mand AS studentId,
                COALESCE(nd.Hoten, nd.Mand) AS studentName,
                CASE
                  WHEN (? = 1 OR NOW() >= sk.Thoigianbatdau)
                    AND NOW() < sk.Thoigianketthuc
                    AND sk.Trangthaisukien <> 'Đã đóng' THEN 1
                  ELSE 0
                END AS isOpen,
                eas.closed_at AS sessionClosedAt,
                eas.expires_at AS sessionExpiresAt
         FROM SuKien sk
         JOIN event_attendance_sessions eas ON eas.event_id = sk.Masukien
         LEFT JOIN DonVi dv ON dv.Madv = sk.Madv
         JOIN NguoiDung nd ON nd.Mand = ?
         WHERE sk.Masukien = ?
           AND (? IS NULL OR eas.session_id = ?)
           AND eas.closed_at IS NULL
           AND eas.expires_at > NOW()
           AND (eas.period_start IS NULL
             OR ? = 1
             OR (NOW() >= eas.period_start AND NOW() < eas.period_end))
         ORDER BY eas.opened_at DESC, eas.session_id DESC
         LIMIT 1`,
        [
          allowEarlyAttendance ? 1 : 0,
          request.auth.sub,
          payload.eventId,
          typeof payload.sessionId === 'string' ? payload.sessionId : null,
          typeof payload.sessionId === 'string' ? payload.sessionId : null,
          allowEarlyAttendance ? 1 : 0,
        ],
      );
      if (!preview || Number(preview.isOpen) !== 1) {
        return response.status(410).json({
          message: 'Sự kiện chưa đến giờ, QR đang ngoài khung điểm danh, đã kết thúc hoặc đã bị đóng.',
        });
      }
      const [[registration]] = await pool.execute(
        `SELECT Trangthaidangky AS status
         FROM DangKySuKien
         WHERE Masukien = ? AND Masv = ?
         LIMIT 1`,
        [preview.eventId, request.auth.sub],
      );
      if (!registration
          || ['từ chối', 'đã hủy', 'hủy'].includes(
            String(registration.status || '').trim().toLowerCase(),
          )) {
        return response.status(403).json({
          message: 'Bạn cần có đăng ký hợp lệ cho sự kiện mới được điểm danh.',
        });
      }
      const [[existing]] = await pool.execute(
        `SELECT 1 AS checkedIn
         FROM event_attendance_records
         WHERE event_id = ? AND session_id = ? AND student_id = ?
         LIMIT 1`,
        [preview.eventId, preview.attendanceSessionId, request.auth.sub],
      );
      const [[legacyAttendance]] = typeof payload.sessionId !== 'string'
        ? await pool.execute(
            `SELECT 1 AS checkedIn
             FROM event_attendance
             WHERE event_id = ? AND student_id = ?
             LIMIT 1`,
            [preview.eventId, request.auth.sub],
          )
        : [[null]];
      if (existing || legacyAttendance) {
        return response.status(409).json({
          message: 'Bạn đã điểm danh phiên này.',
        });
      }
      return response.json({
        eventId: preview.eventId,
        eventName: preview.eventName,
        location: preview.location,
        startTime: preview.startTime,
        endTime: preview.endTime,
        organizerName: preview.organizerName,
        attendanceSessionId: preview.attendanceSessionId,
        periodName: preview.periodName,
        periodStart: preview.periodStart,
        periodEnd: preview.periodEnd,
        sessionNumber: preview.sessionNumber,
        studentId: preview.studentId,
        studentName: preview.studentName,
        status: 'Chờ xác nhận',
        method: 'QR',
      });
    }
    return await checkInEventAttendance(
      request,
      response,
      payload,
      deviceId,
      coordinates,
    );
  } catch (error) {
    if (error.name === 'TokenExpiredError' || error.name === 'JsonWebTokenError') {
      return response.status(410).json({
        message: 'Mã QR sự kiện không hợp lệ hoặc đã hết hạn.',
      });
    }
    console.error('Event check-in error:', error.message);
    return response.status(500).json({
      message: 'Không thể ghi nhận điểm danh sự kiện.',
    });
  }
});

// Tính khoảng cách giữa hai tọa độ bằng công thức Haversine.
function distanceInMeters(first, second) {
  const earthRadius = 6371000;
  const toRadians = (value) => value * Math.PI / 180;
  const latitudeDelta = toRadians(second.latitude - first.latitude);
  const longitudeDelta = toRadians(second.longitude - first.longitude);
  const a = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(toRadians(first.latitude))
      * Math.cos(toRadians(second.latitude))
      * Math.sin(longitudeDelta / 2) ** 2;
  return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Tạo JWT dùng làm mã QR cho phiên điểm danh có thời hạn.
function createAttendanceQr(
  sessionId,
  expiresAt,
  coordinates,
  radiusMeters,
  accuracyMeters,
) {
  return jwt.sign(
    {
      type: 'attendance',
      sessionId,
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      radiusMeters,
      accuracyMeters,
      exp: Math.floor(expiresAt.getTime() / 1000),
    },
    jwtSecret,
  );
}

// Tìm phiên điểm danh và xác minh người dùng có quyền quản lý phiên đó.
async function findManagedAttendanceSession(sessionId, auth) {
  const [[session]] = await pool.execute(
    `SELECT bpd.Mabuoidiemdanh AS id, b.Malop AS classId,
            COALESCE(lhp.Tenlop, '') AS className,
            COALESCE(b.Noidung, '') AS sessionName,
            bpd.Trangthaidiemdanh AS status,
            bpd.Thoigiandong AS closedAt,
            (bpd.Thoigiandong > NOW()) AS notExpired
     FROM BuoiDiemDanh bpd
     INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
     LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
     WHERE bpd.Mabuoidiemdanh = ?
       AND (
         ? IN ('Quản trị viên', 'admin')
         OR (? IN ('Giảng viên', 'lecturer') AND lhp.Magv = ?)
         OR (
           ? IN ('Cán bộ', 'organizer')
           AND EXISTS (
             SELECT 1 FROM DonVi dv
             WHERE dv.Madv = lhp.Madv AND dv.Manv = ?
           )
         )
       )
     LIMIT 1`,
    [
      sessionId,
      auth.role,
      auth.role,
      auth.sub,
      auth.role,
      auth.sub,
    ],
  );
  return session;
}

// Tải các buổi học mà giảng viên hoặc quản trị viên được phép mở điểm danh.
app.get('/api/attendance/sessions', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên', 'lecturer'), async (request, response) => {
  try {
    await closeExpiredClassAttendanceSessions();
    const [rows] = await pool.execute(
      `SELECT b.Mabuoi AS classSessionId, b.Malop AS classId,
              COALESCE(lhp.Tenlop, '') AS className,
              COALESCE(mh.Tenmon, '') AS subjectName,
              b.Thoigianbatdau AS startTime,
              b.Thoigianketthuc AS endTime,
              (SELECT bpd.Mabuoidiemdanh
               FROM BuoiDiemDanh bpd
               WHERE bpd.Mabuoi = b.Mabuoi
                 AND bpd.Trangthaidiemdanh = 'Đang mở'
                 AND bpd.Thoigiandong > NOW()
               ORDER BY bpd.Thoigianmo DESC
               LIMIT 1) AS activeSessionId
             FROM Buoi b
             LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
             LEFT JOIN MonHoc mh ON mh.Mamon = lhp.Mamon
             WHERE (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)
             ORDER BY b.Thoigianbatdau DESC`,
      [request.auth.role, request.auth.sub],
    );
    const settingsByClass = new Map();
    for (const row of rows) {
      if (!settingsByClass.has(row.classId)) {
        const { effective } = await getEffectiveAttendanceParameters('class', row.classId);
        settingsByClass.set(row.classId, effective);
      }
      const parameters = settingsByClass.get(row.classId);
      row.gpsRadiusMeters = parameters.gpsRadiusMeters;
      row.qrDurationMinutes = parameters.qrDurationMinutes;
    }
    const { global } = await getEffectiveAttendanceParameters();
    return response.json({
      items: rows,
      allowEarlyAttendance: global.allowEarlyAttendance,
    });
  } catch (error) {
    console.error('Attendance sessions error:', error.message);
    return response.status(500).json({ message: 'Không thể tải phiên điểm danh.' });
  }
});

// Lấy các phiên điểm danh cùng số lượt có mặt, trễ và vắng từ cơ sở dữ liệu.
app.get('/api/admin/attendance/sessions', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên', 'lecturer', 'Cán bộ', 'organizer'), async (request, response) => {
  try {
    await recordExpiredClassAbsences();
    const [rows] = await pool.execute(
      `SELECT bpd.Mabuoidiemdanh AS id, b.Malop AS classId,
              COALESCE(mh.Mamon, '') AS subjectId,
              COALESCE(mh.Tenmon, '') AS subjectName,
              COALESCE(lhp.Tenlop, '') AS className,
              COALESCE(b.Noidung, '') AS sessionName,
              bpd.Thoigianmo AS openedAt, bpd.Thoigiandong AS closedAt,
              bpd.Phuongthuc AS method,
              bpd.Trangthaidiemdanh AS status,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
       FROM BuoiDiemDanh bpd
       INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
       LEFT JOIN MonHoc mh ON mh.Mamon = lhp.Mamon
       LEFT JOIN KetQuaDiemDanh kd ON kd.Mabuoidiemdanh = bpd.Mabuoidiemdanh
       WHERE (
         ? IN ('Quản trị viên', 'admin')
         OR (? IN ('Giảng viên', 'lecturer') AND lhp.Magv = ?)
         OR (
           ? IN ('Cán bộ', 'organizer')
           AND EXISTS (
             SELECT 1 FROM DonVi dv
             WHERE dv.Madv = lhp.Madv AND dv.Manv = ?
           )
         )
       )
       GROUP BY bpd.Mabuoidiemdanh, b.Malop, mh.Mamon, mh.Tenmon, lhp.Tenlop,
                b.Noidung, bpd.Thoigianmo, bpd.Thoigiandong,
                bpd.Phuongthuc, bpd.Trangthaidiemdanh
       ORDER BY bpd.Thoigianmo DESC`,
      [
        request.auth.role,
        request.auth.role,
        request.auth.sub,
        request.auth.role,
        request.auth.sub,
      ],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin attendance sessions error:', error.message);
    return response.status(500).json({ message: 'Không thể tải phiên điểm danh.' });
  }
});

// Trả danh sách sinh viên cùng trạng thái điểm danh của một phiên được phép quản lý.
app.get('/api/admin/attendance/sessions/:sessionId/students', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên', 'lecturer', 'Cán bộ', 'organizer'), async (request, response) => {
  try {
    await recordExpiredClassAbsences();
    const session = await findManagedAttendanceSession(
      request.params.sessionId,
      request.auth,
    );
    if (!session) {
      return response.status(404).json({
        message: 'Không tìm thấy phiên điểm danh hoặc bạn không phụ trách phiên này.',
      });
    }

    const canViewStudentDetails = !['sinh viên', 'student'].includes(
      String(request.auth.role || '').trim().toLowerCase(),
    );
    const [items] = await pool.execute(
      `SELECT tvl.Masv AS studentId,
              COALESCE(nd.Hoten, tvl.Masv) AS studentName,
              ${canViewStudentDetails ? `
                COALESCE(sv.Lop, '') AS className,
                COALESCE(sv.Chuyennganh, '') AS major,` : ''}
              kd.Maketqua AS attendanceId,
              kd.Trangthaiketqua AS attendanceStatus,
              kd.Thoigiandiemdanh AS checkedInAt
       FROM BuoiDiemDanh bpd
       INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
       INNER JOIN ThanhVienLop tvl ON tvl.Malop = b.Malop
       LEFT JOIN NguoiDung nd ON nd.Mand = tvl.Masv
       LEFT JOIN SinhVien sv ON sv.Masv = tvl.Masv
       LEFT JOIN KetQuaDiemDanh kd
         ON kd.Mabuoidiemdanh = bpd.Mabuoidiemdanh
        AND kd.Masv = tvl.Masv
       WHERE bpd.Mabuoidiemdanh = ?
       ORDER BY nd.Hoten, tvl.Masv`,
      [request.params.sessionId],
    );
    return response.json({
      session: {
        ...session,
        canEdit: session.status === 'Đang mở' && Number(session.notExpired) === 1,
      },
      items,
    });
  } catch (error) {
    console.error('Attendance roster error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải danh sách sinh viên điểm danh.',
    });
  }
});

// Cập nhật cùng một trạng thái cho nhiều sinh viên được chọn trong phiên đang mở.
app.post('/api/admin/attendance/sessions/:sessionId/students/bulk-update', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên', 'lecturer', 'Cán bộ', 'organizer'), async (request, response) => {
  const statusLabels = new Map([
    ['present', 'Có mặt'],
    ['late', 'Đi trễ'],
    ['absent', 'Vắng mặt'],
    ['excused', 'Vắng có phép'],
  ]);
  const submittedRecords = Array.isArray(request.body?.records)
    ? request.body.records.map((record) => ({
        studentId: String(record?.studentId || '').trim(),
        status: String(record?.status || '').trim(),
      }))
    : Array.isArray(request.body?.studentIds)
      ? request.body.studentIds.map((studentId) => ({
          studentId: String(studentId || '').trim(),
          status: String(request.body?.status || '').trim(),
        }))
      : [];
  const records = [...new Map(submittedRecords
    .filter((record) => record.studentId)
    .map((record) => [record.studentId, record])).values()];
  const studentIds = records.map((record) => record.studentId);
  if (records.length === 0 || records.length > 500
      || records.some((record) => !statusLabels.has(record.status))) {
    return response.status(400).json({ message: 'Cần chọn 1–500 sinh viên và trạng thái điểm danh hợp lệ cho từng sinh viên.' });
  }

  let connection;
  try {
    const session = await findManagedAttendanceSession(request.params.sessionId, request.auth);
    if (!session) {
      return response.status(404).json({ message: 'Không tìm thấy phiên điểm danh hoặc bạn không phụ trách phiên này.' });
    }
    if (session.status !== 'Đang mở' || Number(session.notExpired) !== 1) {
      return response.status(409).json({ message: 'Phiên điểm danh đã đóng hoặc hết hạn.' });
    }

    const placeholders = studentIds.map(() => '?').join(', ');
    const [members] = await pool.execute(
      `SELECT tvl.Masv AS id
       FROM ThanhVienLop tvl
       INNER JOIN Buoi b ON b.Malop = tvl.Malop
       INNER JOIN BuoiDiemDanh bpd ON bpd.Mabuoi = b.Mabuoi
       WHERE bpd.Mabuoidiemdanh = ? AND tvl.Masv IN (${placeholders})`,
      [request.params.sessionId, ...studentIds],
    );
    const memberIds = new Set(members.map((member) => String(member.id)));
    const invalidIds = studentIds.filter((id) => !memberIds.has(id));
    if (invalidIds.length) {
      return response.status(400).json({ message: `${invalidIds.length} sinh viên không thuộc lớp của phiên điểm danh.` });
    }

    connection = await pool.getConnection();
    await connection.beginTransaction();
    for (const { studentId, status } of records) {
      const attendanceStatus = statusLabels.get(status);
      const [[existing]] = await connection.execute(
        `SELECT Maketqua AS id FROM KetQuaDiemDanh
         WHERE Mabuoidiemdanh = ? AND Masv = ? LIMIT 1 FOR UPDATE`,
        [request.params.sessionId, studentId],
      );
      if (existing) {
        await connection.execute(
          `UPDATE KetQuaDiemDanh
           SET Thoigiandiemdanh = NOW(), Trangthaiketqua = ?, Vitri = NULL
           WHERE Maketqua = ?`,
          [attendanceStatus, existing.id],
        );
      } else {
        await connection.execute(
          `INSERT INTO KetQuaDiemDanh
           (Maketqua, Thoigiandiemdanh, Trangthaiketqua, Mabuoidiemdanh, Masv)
           VALUES (?, NOW(), ?, ?, ?)`,
          [makeId('RS'), attendanceStatus, request.params.sessionId, studentId],
        );
      }
    }
    await connection.commit();
    return response.json({ message: `Đã cập nhật điểm danh cho ${records.length} sinh viên.`, updatedCount: records.length });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Bulk manual attendance error:', error.message);
    return response.status(500).json({ message: 'Không thể cập nhật điểm danh cho các sinh viên đã chọn.' });
  } finally {
    connection?.release();
  }
});

// Ghi nhận hoặc cập nhật kết quả điểm danh thủ công của sinh viên trong phiên đang mở.
app.post('/api/admin/attendance/sessions/:sessionId/students/:studentId', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên', 'lecturer', 'Cán bộ', 'organizer'), async (request, response) => {
  const statusLabels = new Map([
    ['present', 'Có mặt'],
    ['late', 'Đi trễ'],
    ['absent', 'Vắng mặt'],
    ['excused', 'Vắng có phép'],
  ]);
  const attendanceStatus = statusLabels.get(request.body?.status);
  if (!attendanceStatus) {
    return response.status(400).json({
      message: 'Trạng thái điểm danh không hợp lệ.',
    });
  }

  let connection;
  try {
    const session = await findManagedAttendanceSession(
      request.params.sessionId,
      request.auth,
    );
    if (!session) {
      return response.status(404).json({
        message: 'Không tìm thấy phiên điểm danh hoặc bạn không phụ trách phiên này.',
      });
    }
    if (session.status !== 'Đang mở' || Number(session.notExpired) !== 1) {
      return response.status(409).json({
        message: 'Phiên điểm danh đã đóng hoặc hết hạn.',
      });
    }

    const [[student]] = await pool.execute(
      `SELECT tvl.Masv AS id
       FROM ThanhVienLop tvl
       INNER JOIN Buoi b ON b.Malop = tvl.Malop
       INNER JOIN BuoiDiemDanh bpd ON bpd.Mabuoi = b.Mabuoi
       WHERE bpd.Mabuoidiemdanh = ? AND tvl.Masv = ?
       LIMIT 1`,
      [request.params.sessionId, request.params.studentId],
    );
    if (!student) {
      return response.status(404).json({
        message: 'Sinh viên không thuộc lớp của phiên điểm danh này.',
      });
    }

    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[existing]] = await connection.execute(
      `SELECT Maketqua AS id
       FROM KetQuaDiemDanh
       WHERE Mabuoidiemdanh = ? AND Masv = ?
       LIMIT 1
       FOR UPDATE`,
      [request.params.sessionId, request.params.studentId],
    );

    if (existing) {
      await connection.execute(
        `UPDATE KetQuaDiemDanh
         SET Thoigiandiemdanh = NOW(), Trangthaiketqua = ?, Vitri = NULL
         WHERE Maketqua = ?`,
        [attendanceStatus, existing.id],
      );
    } else {
      await connection.execute(
        `INSERT INTO KetQuaDiemDanh
         (Maketqua, Thoigiandiemdanh, Trangthaiketqua, Mabuoidiemdanh, Masv)
         VALUES (?, NOW(), ?, ?, ?)`,
        [
          makeId('RS'),
          attendanceStatus,
          request.params.sessionId,
          request.params.studentId,
        ],
      );
    }
    await connection.commit();
    return response.json({
      message: 'Đã cập nhật điểm danh thủ công.',
      studentId: request.params.studentId,
      status: attendanceStatus,
    });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Manual attendance error:', error.message);
    return response.status(500).json({
      message: 'Không thể cập nhật điểm danh thủ công.',
    });
  } finally {
    connection?.release();
  }
});

// Danh sách lớp mà người dùng được phép xem báo cáo điểm danh.
app.get('/api/reports/attendance/classes', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT lhp.Malop AS id, COALESCE(lhp.Tenlop, '') AS name,
              lhp.Magv AS lecturerId,
              COUNT(DISTINCT tvl.Masv) AS studentCount
       FROM LopHocPhan lhp
       LEFT JOIN ThanhVienLop tvl ON tvl.Malop = lhp.Malop
       WHERE (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)
       GROUP BY lhp.Malop, lhp.Tenlop
       ORDER BY lhp.Tenlop, lhp.Malop`,
      [request.auth.role, request.auth.sub],
    );
    return response.json({
      items: rows.map((row) => ({
        ...row,
        studentCount: Number(row.studentCount || 0),
      })),
    });
  } catch (error) {
    console.error('Attendance report classes error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải danh sách lớp để lập báo cáo.',
    });
  }
});

// Báo cáo số buổi có mặt, đi muộn, vắng và vắng có phép theo từng sinh viên.
app.get('/api/reports/attendance/classes/:classId', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (request, response) => {
  try {
    await recordExpiredClassAbsences();
    const [[classInfo]] = await pool.execute(
      `SELECT lhp.Malop AS id, COALESCE(lhp.Tenlop, '') AS name,
              (SELECT COUNT(*)
               FROM Buoi b
               INNER JOIN BuoiDiemDanh bpd ON bpd.Mabuoi = b.Mabuoi
               WHERE b.Malop = lhp.Malop
                 AND (bpd.Trangthaidiemdanh <> 'Đang mở'
                   OR bpd.Thoigiandong <= NOW())) AS sessionCount
       FROM LopHocPhan lhp
       WHERE lhp.Malop = ?
         AND (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)
       LIMIT 1`,
      [request.params.classId, request.auth.role, request.auth.sub],
    );
    if (!classInfo) {
      return response.status(404).json({
        message: 'Không tìm thấy lớp hoặc bạn không phụ trách lớp này.',
      });
    }

    const { effective: classParameters } = await getEffectiveAttendanceParameters(
      'class', classInfo.id,
    );
    const [students] = await pool.execute(
      `SELECT tvl.Masv AS studentId,
              COALESCE(nd.Hoten, tvl.Masv) AS studentName,
              COUNT(DISTINCT bpd.Mabuoidiemdanh) AS totalSessions,
              COUNT(DISTINCT CASE
                WHEN kd.Trangthaiketqua = 'Có mặt'
                THEN bpd.Mabuoidiemdanh
              END) AS present,
              COUNT(DISTINCT CASE
                WHEN kd.Trangthaiketqua IN ('Đi trễ', 'Đi muộn')
                THEN bpd.Mabuoidiemdanh
              END) AS late,
              COUNT(DISTINCT CASE
                WHEN COALESCE(kd.Trangthaiketqua, 'Vắng mặt') = 'Vắng mặt'
                THEN bpd.Mabuoidiemdanh
              END) AS absent,
              COUNT(DISTINCT CASE
                WHEN kd.Trangthaiketqua = 'Vắng có phép'
                THEN bpd.Mabuoidiemdanh
              END) AS excused
       FROM ThanhVienLop tvl
       LEFT JOIN NguoiDung nd ON nd.Mand = tvl.Masv
       LEFT JOIN Buoi b ON b.Malop = ?
         AND (tvl.NgayThamGia IS NULL
           OR b.Thoigianbatdau >= tvl.NgayThamGia)
       LEFT JOIN BuoiDiemDanh bpd ON bpd.Mabuoi = b.Mabuoi
         AND (bpd.Trangthaidiemdanh <> 'Đang mở' OR bpd.Thoigiandong <= NOW())
       LEFT JOIN KetQuaDiemDanh kd
         ON kd.Mabuoidiemdanh = bpd.Mabuoidiemdanh AND kd.Masv = tvl.Masv
       WHERE tvl.Malop = ?
       GROUP BY tvl.Masv, nd.Hoten
       ORDER BY nd.Hoten, tvl.Masv`,
      [classInfo.id, classInfo.id],
    );
    return response.json({
      class: classInfo,
      sessionCount: Number(classInfo.sessionCount || 0),
      items: students.map((student) => ({
        ...student,
        totalSessions: Number(student.totalSessions || 0),
        present: Number(student.present || 0),
        late: Number(student.late || 0),
        absent: Number(student.absent || 0),
        excused: Number(student.excused || 0),
        attendancePercent: Number(student.totalSessions || 0) > 0
          ? Math.round((Number(student.present || 0) + Number(student.late || 0)) * 100
            / Number(student.totalSessions || 0))
          : 0,
        attendanceThresholdPercent: Number(classParameters.attendanceThresholdPercent),
        requiredAttendanceSessions: Math.ceil(
          Number(student.totalSessions || 0)
            * Number(classParameters.attendanceThresholdPercent) / 100,
        ),
        maxAttendanceAbsences: Number(student.totalSessions || 0) - Math.ceil(
          Number(student.totalSessions || 0)
            * Number(classParameters.attendanceThresholdPercent) / 100,
        ),
        attendanceEligible: Number(student.totalSessions || 0) > 0
          && (Number(student.present || 0) + Number(student.late || 0)) * 100
            >= Number(classParameters.attendanceThresholdPercent) * Number(student.totalSessions || 0),
        attendanceResult: Number(student.totalSessions || 0) === 0
          ? 'Chưa có buổi'
          : (Number(student.present || 0) + Number(student.late || 0)) * 100
            >= Number(classParameters.attendanceThresholdPercent) * Number(student.totalSessions || 0)
            ? 'Đạt'
            : 'Chưa đạt',
      })),
    });
  } catch (error) {
    console.error('Attendance class report error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải báo cáo sinh viên của lớp.',
    });
  }
});

// Tổng hợp kết quả điểm danh theo trạng thái và ngày cho Admin/Giảng viên.
app.get('/api/reports/attendance', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (request, response) => {
  try {
    await recordExpiredClassAbsences();
    const scope = [request.auth.role, request.auth.sub];
    const [[summary]] = await pool.execute(
      `SELECT COUNT(kd.Maketqua) AS total,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
              SUM(CASE WHEN kd.Trangthaiketqua IN ('Đi trễ', 'Đi muộn') THEN 1 ELSE 0 END) AS late,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng có phép' THEN 1 ELSE 0 END) AS excused
       FROM KetQuaDiemDanh kd
       INNER JOIN BuoiDiemDanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
       INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
       WHERE kd.Trangthaiketqua IN ('Có mặt', 'Đi trễ', 'Đi muộn', 'Vắng mặt', 'Vắng có phép')
         AND (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)`,
      scope,
    );
    const [rows] = await pool.execute(
      `SELECT DATE(kd.Thoigiandiemdanh) AS date,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
              SUM(CASE WHEN kd.Trangthaiketqua IN ('Đi trễ', 'Đi muộn') THEN 1 ELSE 0 END) AS late,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng có phép' THEN 1 ELSE 0 END) AS excused
       FROM KetQuaDiemDanh kd
       INNER JOIN BuoiDiemDanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
       INNER JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
       WHERE kd.Thoigiandiemdanh >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
         AND kd.Trangthaiketqua IN ('Có mặt', 'Đi trễ', 'Đi muộn', 'Vắng mặt', 'Vắng có phép')
         AND (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)
       GROUP BY DATE(kd.Thoigiandiemdanh)
       ORDER BY date`,
      scope,
    );
    return response.json({
      summary: {
        total: Number(summary.total || 0),
        present: Number(summary.present || 0),
        late: Number(summary.late || 0),
        absent: Number(summary.absent || 0),
        excused: Number(summary.excused || 0),
      },
      items: rows,
    });
  } catch (error) {
    console.error('Attendance report error:', error.message);
    return response.status(500).json({ message: 'Không thể tải báo cáo điểm danh.' });
  }
});

// Kiểm tra dữ liệu, lưu phiên điểm danh và phát hành mã QR nếu cần.
app.post('/api/attendance/sessions', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (request, response) => {
  const { classSessionId, method = 'QR' } = request.body || {};
  const coordinates = readCoordinates(request.body);
  const accuracyMeters = readLocationAccuracy(request.body);
  if (!classSessionId || !['QR', 'Face', 'Both'].includes(method)
      || !coordinates || accuracyMeters === null) {
    return response.status(400).json({ message: 'Cần chọn buổi học và cho phép vị trí để mở điểm danh.' });
  }

  try {
    await closeExpiredClassAttendanceSessions();
    const [[classSession]] = await pool.execute(
      `SELECT b.Mabuoi AS id, b.Malop AS classId,
              b.Thoigianbatdau > NOW() AS startsInFuture,
              lhp.Trangthailop AS classStatus,
              (lhp.Thoigianbatdau < DATE_SUB(NOW(), INTERVAL 1 YEAR)) AS isArchived,
              COUNT(
                CASE
                  WHEN tvl.Trangthaithanhvien = 'Đang tham gia' THEN tvl.Masv
                END
              ) AS studentCount
       FROM Buoi b
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
       LEFT JOIN ThanhVienLop tvl ON tvl.Malop = b.Malop
       WHERE b.Mabuoi = ?
         AND (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)
       GROUP BY b.Mabuoi, b.Malop, lhp.Trangthailop,
                lhp.Thoigianbatdau
       LIMIT 1`,
      [classSessionId, request.auth.role, request.auth.sub],
    );
    if (!classSession) return response.status(404).json({ message: 'Không tìm thấy buổi học.' });
    if (classSession.classStatus === 'Đã đóng' || Number(classSession.isArchived)) {
      return response.status(409).json({
        message: 'Lớp đã đóng hoặc đã quá 1 năm nên không thể mở điểm danh.',
      });
    }
    const { effective: classParameters } = await getEffectiveAttendanceParameters(
      'class', classSession.classId,
    );
    if (!classParameters.allowEarlyAttendance && Number(classSession.startsInFuture)) {
      return response.status(409).json({
        message: 'Chưa đến giờ bắt đầu buổi học nên chưa thể mở điểm danh.',
      });
    }
    const duration = Number(classParameters.qrDurationMinutes);
    const radiusMeters = Number(classParameters.gpsRadiusMeters) || classAttendanceRadiusMeters;
    const [[activeSession]] = await pool.execute(
      `SELECT Mabuoidiemdanh AS id
       FROM BuoiDiemDanh
       WHERE Mabuoi = ? AND Trangthaidiemdanh = 'Đang mở'
         AND Thoigiandong > NOW()
       ORDER BY Thoigianmo DESC
       LIMIT 1`,
      [classSessionId],
    );
    if (activeSession) {
      return response.status(409).json({
        message: 'Buổi học đang có mã QR hoạt động. Hãy tắt mã hiện tại trước khi tạo mã mới.',
      });
    }
    const openedAt = new Date();
    const closedAt = new Date(openedAt.getTime() + duration * 60 * 1000);
    const id = makeId('AT');
    await pool.execute(
      `INSERT INTO BuoiDiemDanh
        (Mabuoidiemdanh, Thoigianmo, Thoigiandong, Phuongthuc, Trangthaidiemdanh,
         Mabuoi, latitude, longitude, radius_meters, accuracy_meters)
         VALUES (?, ?, ?, ?, 'Đang mở', ?, ?, ?, ?, ?)`,
      [
        id,
        openedAt,
        closedAt,
        method,
        classSessionId,
        coordinates.latitude,
        coordinates.longitude,
        radiusMeters,
        accuracyMeters,
      ],
    );
    sendClassAttendancePush(pool, {
      classId: classSession.classId,
      sessionId: id,
      method,
      closesAt: closedAt,
    }).catch((error) => {
      console.error('Attendance push notification failed:', error.message);
    });
    return response.status(201).json({
      id,
      method,
      openedAt,
      closedAt,
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      radiusMeters,
      qrDurationMinutes: duration,
      qr: method === 'Face'
        ? null
        : createAttendanceQr(
            id,
            closedAt,
            coordinates,
            radiusMeters,
            accuracyMeters,
          ),
    });
  } catch (error) {
    console.error('Create attendance session error:', error.message);
    return response.status(500).json({ message: 'Không thể tạo phiên điểm danh.' });
  }
});

app.post('/api/attendance/sessions/:sessionId/close', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên', 'lecturer'), async (request, response) => {
  try {
    const session = await findManagedAttendanceSession(
      request.params.sessionId,
      request.auth,
    );
    if (!session) {
      return response.status(404).json({
        message: 'Không tìm thấy phiên điểm danh hoặc bạn không phụ trách phiên này.',
      });
    }
    const [result] = await pool.execute(
      `UPDATE BuoiDiemDanh
       SET Trangthaidiemdanh = 'Đã đóng'
       WHERE Mabuoidiemdanh = ?
         AND Trangthaidiemdanh = 'Đang mở'`,
      [request.params.sessionId],
    );
    if (result.affectedRows === 0) {
      return response.json({ message: 'Phiên điểm danh đã được đóng hoặc hết hạn.' });
    }
    return response.json({ message: 'Đã tắt mã QR điểm danh.' });
  } catch (error) {
    console.error('Close attendance session error:', error.message);
    return response.status(500).json({
      message: 'Không thể tắt mã QR điểm danh.',
    });
  }
});

// Xác thực mã QR, vị trí, thành viên lớp và ghi kết quả điểm danh.
app.post('/api/attendance/check-in', requireAuth, async (request, response) => {
  const { qrToken, method = 'QR', deviceId } = request.body || {};
  const coordinates = readCoordinates(request.body);
  const accuracyMeters = readLocationAccuracy(request.body);
  const previewOnly = request.body?.preview === true;
  if (!qrToken || !['QR', 'Face'].includes(method)) {
    return response.status(400).json({ message: 'Thiếu dữ liệu điểm danh.' });
  }
  if (!previewOnly && (typeof deviceId !== 'string' || !/^[a-f0-9]{32}$/.test(deviceId))) {
    return response.status(400).json({ message: 'Không xác định được thiết bị điểm danh.' });
  }
  if (!previewOnly && !coordinates) {
    return response.status(400).json({ message: 'Không lấy được vị trí hiện tại của bạn.' });
  }
  if (!previewOnly && accuracyMeters === null) {
    return response.status(400).json({ message: 'Độ chính xác vị trí không hợp lệ.' });
  }

  if (!['student', 'sinh viên'].includes(String(request.auth.role).toLowerCase())) {
    return response.status(403).json({
      message: 'Sai tài khoản: hãy đăng nhập bằng tài khoản sinh viên để điểm danh.',
    });
  }

  try {
    const [[student]] = await pool.execute(
      'SELECT Masv AS id FROM SinhVien WHERE Masv = ? LIMIT 1',
      [request.auth.sub],
    );
    if (!student) {
      return response.status(403).json({
        message: 'Sai sinh viên: tài khoản này chưa được liên kết với hồ sơ sinh viên.',
      });
    }

    const payload = jwt.verify(qrToken, jwtSecret);
    if (payload.type !== 'attendance') throw new Error('Invalid QR type');
    const [[session]] = await pool.execute(
            `SELECT bpd.Mabuoidiemdanh AS id, bpd.Trangthaidiemdanh AS status,
              bpd.Thoigiandong AS closedAt, bpd.Phuongthuc AS method
             FROM BuoiDiemDanh bpd WHERE bpd.Mabuoidiemdanh = ? LIMIT 1`,
      [payload.sessionId],
    );
    if (!session || session.status !== 'Đang mở' || new Date(session.closedAt) < new Date()) {
      return response.status(410).json({ message: 'Phiên điểm danh đã đóng hoặc hết hạn.' });
    }
    const sessionCoordinates = readCoordinates(payload);
    const radiusMeters = Number(payload.radiusMeters) || classAttendanceRadiusMeters;
    if (!sessionCoordinates) {
      return response.status(410).json({ message: 'Mã QR không hợp lệ hoặc đã hết hạn.' });
    }
    const sessionAccuracyMeters = Number(payload.accuracyMeters) || 0;
    if (!previewOnly && !isWithinAttendanceRadius(
      sessionCoordinates,
      coordinates,
      radiusMeters,
      sessionAccuracyMeters,
      accuracyMeters,
    )) {
      return response.status(403).json({ message: `Bạn đang cách vị trí điểm danh quá xa (phạm vi ${radiusMeters} m).` });
    }
    if (session.method === 'Face' || (method === 'Face' && session.method === 'QR')) {
      return response.status(400).json({ message: 'Phương thức điểm danh không khớp.' });
    }

    const [[membership]] = await pool.execute(
      `SELECT 1 AS enrolled
       FROM BuoiDiemDanh bpd
       JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
       JOIN ThanhVienLop tvl ON tvl.Malop = b.Malop
       WHERE bpd.Mabuoidiemdanh = ? AND tvl.Masv = ?
       LIMIT 1`,
      [session.id, request.auth.sub],
    );
    if (!membership) {
      return response.status(403).json({
        message: 'Sai lớp: sinh viên không thuộc lớp của buổi điểm danh này.',
      });
    }

    const [[existing]] = await pool.execute(
      `SELECT Maketqua AS id, (Vitri IS NULL) AS manuallyRecorded
       FROM KetQuaDiemDanh
       WHERE Mabuoidiemdanh = ? AND Masv = ? LIMIT 1`,
      [session.id, request.auth.sub],
    );
    if (existing) return response.status(409).json({ message: Number(existing.manuallyRecorded) === 1
      ? 'Giảng viên đã ghi nhận trạng thái điểm danh cho bạn trong phiên này. Bạn không thể quét mã thêm.'
      : 'Bạn đã có kết quả điểm danh trong phiên này. Bạn không thể quét mã thêm.' });

    if (previewOnly) {
      const [[preview]] = await pool.execute(
        `SELECT bpd.Mabuoidiemdanh AS attendanceSessionId,
                b.Mabuoi AS classSessionId, b.Malop AS classId,
                COALESCE(lhp.Tenlop, '') AS className,
                COALESCE(b.Noidung, '') AS sessionName,
                b.Thoigianbatdau AS startTime, b.Thoigianketthuc AS endTime,
                COALESCE(lecturer.Hoten, '') AS lecturerName,
                COALESCE((
                  SELECT GROUP_CONCAT(DISTINCT lh.PhongHoc
                    ORDER BY lh.PhongHoc SEPARATOR ', ')
                  FROM LichHocPhan lh
                  WHERE lh.Malop = b.Malop
                    AND lh.ThuTrongTuan = WEEKDAY(b.Thoigianbatdau) + 1
                    AND (lh.NgayBatDau IS NULL
                      OR lh.NgayBatDau <= DATE(b.Thoigianbatdau))
                    AND (lh.NgayKetThuc IS NULL
                      OR lh.NgayKetThuc >= DATE(b.Thoigianbatdau))
                    AND lh.GioBatDau <= TIME(b.Thoigianbatdau)
                    AND lh.GioKetThuc >= TIME(b.Thoigianbatdau)
                ), '') AS room,
                ? AS studentId, COALESCE(attendee.Hoten, '') AS studentName,
                'Chờ xác nhận' AS status, 'QR' AS method
         FROM BuoiDiemDanh bpd
         JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
         LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
         LEFT JOIN GiangVien gv ON gv.Magv = lhp.Magv
         LEFT JOIN NguoiDung lecturer ON lecturer.Mand = gv.Magv
         LEFT JOIN NguoiDung attendee ON attendee.Mand = ?
         WHERE bpd.Mabuoidiemdanh = ?
         LIMIT 1`,
        [request.auth.sub, request.auth.sub, session.id],
      );
      if (!preview) {
        return response.status(404).json({
          message: 'Không tìm thấy thông tin buổi điểm danh.',
        });
      }
      return response.json(preview);
    }

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      await connection.execute(
        `INSERT INTO attendance_device_claims
         (device_id, attendance_date, student_id, attendance_session_id)
         VALUES (?, CURDATE(), ?, ?)`,
        [deviceId, request.auth.sub, session.id],
      );
      await connection.execute(
        `INSERT INTO KetQuaDiemDanh
         (Maketqua, Thoigiandiemdanh, Trangthaiketqua, Vitri, Mabuoidiemdanh, Masv)
         VALUES (?, NOW(), 'Có mặt', ?, ?, ?)`,
        [makeId('RS'), JSON.stringify(coordinates), session.id, request.auth.sub],
      );
      await connection.commit();
    } catch (error) {
      await connection.rollback();
      if (error.code === 'ER_DUP_ENTRY') {
        return response.status(409).json({
          message: 'Thiết bị này đã được dùng để điểm danh phiên này.',
        });
      }
      throw error;
    } finally {
      connection.release();
    }
    const [[result]] = await pool.execute(
      `SELECT bpd.Mabuoidiemdanh AS attendanceSessionId,
              b.Mabuoi AS classSessionId, b.Malop AS classId,
              COALESCE(lhp.Tenlop, '') AS className,
              COALESCE(b.Noidung, '') AS sessionName,
              b.Thoigianbatdau AS startTime, b.Thoigianketthuc AS endTime,
              COALESCE(lecturer.Hoten, '') AS lecturerName,
              COALESCE((
                SELECT GROUP_CONCAT(DISTINCT lh.PhongHoc
                  ORDER BY lh.PhongHoc SEPARATOR ', ')
                FROM LichHocPhan lh
                WHERE lh.Malop = b.Malop
                  AND lh.ThuTrongTuan = WEEKDAY(b.Thoigianbatdau) + 1
                  AND (lh.NgayBatDau IS NULL
                    OR lh.NgayBatDau <= DATE(b.Thoigianbatdau))
                  AND (lh.NgayKetThuc IS NULL
                    OR lh.NgayKetThuc >= DATE(b.Thoigianbatdau))
                  AND lh.GioBatDau <= TIME(b.Thoigianbatdau)
                  AND lh.GioKetThuc >= TIME(b.Thoigianbatdau)
              ), '') AS room,
              kd.Thoigiandiemdanh AS checkedInAt,
              kd.Trangthaiketqua AS status,
              kd.Masv AS studentId, COALESCE(attendee.Hoten, '') AS studentName,
              'QR' AS method
       FROM KetQuaDiemDanh kd
       JOIN BuoiDiemDanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
       JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
       LEFT JOIN GiangVien gv ON gv.Magv = lhp.Magv
       LEFT JOIN NguoiDung lecturer ON lecturer.Mand = gv.Magv
       LEFT JOIN NguoiDung attendee ON attendee.Mand = kd.Masv
       WHERE kd.Mabuoidiemdanh = ? AND kd.Masv = ?
       LIMIT 1`,
      [session.id, request.auth.sub],
    );
    return response.status(201).json({
      message: 'Điểm danh thành công.',
      ...result,
    });
  } catch (error) {
    if (error.name === 'TokenExpiredError' || error.message === 'Invalid QR type') {
      return response.status(410).json({ message: 'Mã QR không hợp lệ hoặc đã hết hạn.' });
    }
    console.error('Check-in error:', error.message);
    return response.status(500).json({ message: 'Không thể ghi nhận điểm danh.' });
  }
});

// Kiểm tra phiên khuôn mặt và vị trí trước khi tiếp nhận kết quả nhận diện.
app.get('/api/attendance/face-options', requireAuth, async (request, response) => {
  if (!['student', 'sinh viên'].includes(String(request.auth.role).toLowerCase())) {
    return response.status(403).json({
      message: 'Chỉ sinh viên mới được chọn phiên điểm danh khuôn mặt.',
    });
  }
  try {
    const { global: globalParameters } = await getEffectiveAttendanceParameters(
      'global',
    );
    const allowEarlyAttendance = globalParameters.allowEarlyAttendance ? 1 : 0;
    const [classSessions] = await pool.execute(
      `SELECT 'class' AS type, bpd.Mabuoidiemdanh AS sessionId,
              COALESCE(mh.Tenmon, '') AS title,
              COALESCE(lhp.Tenlop, '') AS subtitle,
              COALESCE(b.Noidung, '') AS sessionName,
              b.Thoigianbatdau AS startTime,
              bpd.Thoigiandong AS endTime
       FROM BuoiDiemDanh bpd
       JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
       JOIN ThanhVienLop tvl ON tvl.Malop = b.Malop AND tvl.Masv = ?
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
       LEFT JOIN MonHoc mh ON mh.Mamon = lhp.Mamon
       WHERE bpd.Trangthaidiemdanh = 'Đang mở'
         AND bpd.Phuongthuc IN ('Face', 'Both')
         AND bpd.Thoigiandong > NOW()
         AND NOT EXISTS (
           SELECT 1 FROM KetQuaDiemDanh kd
           WHERE kd.Mabuoidiemdanh = bpd.Mabuoidiemdanh
             AND kd.Masv = tvl.Masv
         )
       ORDER BY bpd.Thoigianmo DESC`,
      [request.auth.sub],
    );
    const [events] = await pool.execute(
      `SELECT 'event' AS type, eas.session_id AS sessionId,
              sk.Masukien AS eventId,
              sk.Tensukien AS title,
              COALESCE(dv.Tendv, '') AS subtitle,
              CONCAT(
                'Phiên ',
                (SELECT COUNT(*)
                 FROM event_attendance_sessions previous
                 WHERE previous.event_id = eas.event_id
                   AND (previous.opened_at < eas.opened_at
                     OR (previous.opened_at = eas.opened_at
                       AND previous.session_id <= eas.session_id)))
              ) AS sessionName,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime
       FROM SuKien sk
       JOIN event_attendance_sessions eas ON eas.event_id = sk.Masukien
       JOIN DangKySuKien dk ON dk.Masukien = sk.Masukien AND dk.Masv = ?
       LEFT JOIN DonVi dv ON dv.Madv = sk.Madv
       WHERE eas.expires_at > NOW()
         AND eas.closed_at IS NULL
         AND (? = 1 OR NOW() >= sk.Thoigianbatdau)
         AND NOW() < sk.Thoigianketthuc
         AND (eas.period_start IS NULL OR ? = 1 OR NOW() >= eas.period_start)
         AND sk.Trangthaisukien <> 'Đã đóng'
         AND LOWER(TRIM(COALESCE(dk.Trangthaidangky, ''))) NOT IN ('từ chối', 'đã hủy', 'hủy')
         AND NOT EXISTS (
           SELECT 1 FROM event_attendance_records ear
           WHERE ear.event_id = sk.Masukien
             AND ear.session_id = eas.session_id
             AND ear.student_id = dk.Masv
         )
       ORDER BY eas.opened_at DESC`,
      [request.auth.sub, allowEarlyAttendance, allowEarlyAttendance],
    );
    return response.json({ items: [...classSessions, ...events] });
  } catch (error) {
    console.error('Face attendance options error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải các phiên điểm danh khuôn mặt.',
    });
  }
});

app.post('/api/attendance/face-check-in', requireAuth, async (request, response) => {
  const coordinates = readCoordinates(request.body);
  const accuracyMeters = readLocationAccuracy(request.body);
  const deviceId = request.body?.deviceId;
  const recognizedStudentId = request.body?.recognizedStudentId;
  const sessionType = request.body?.sessionType;
  const sessionId = request.body?.sessionId;
  const previewOnly = request.body?.preview === true;
  if (typeof recognizedStudentId !== 'string'
      || recognizedStudentId !== request.auth.sub) {
    return response.status(403).json({
      message: 'Khuôn mặt không khớp với tài khoản đang đăng nhập.',
    });
  }
  if (!['class', 'event'].includes(sessionType)
      || typeof sessionId !== 'string' || !sessionId) {
    return response.status(400).json({
      message: 'Cần chọn môn học hoặc sự kiện trước khi điểm danh khuôn mặt.',
    });
  }
  if (!['student', 'sinh viên'].includes(String(request.auth.role).toLowerCase())) {
    return response.status(403).json({
      message: 'Sai tài khoản: hãy đăng nhập bằng tài khoản sinh viên để điểm danh.',
    });
  }
  if (!previewOnly && (typeof deviceId !== 'string' || !/^[a-f0-9]{32}$/.test(deviceId))) {
    return response.status(400).json({ message: 'Không xác định được thiết bị điểm danh.' });
  }
  if (!previewOnly && !coordinates) {
    return response.status(400).json({ message: 'Cần xác nhận vị trí hiện tại.' });
  }
  if (!previewOnly && accuracyMeters === null) {
    return response.status(400).json({ message: 'Độ chính xác vị trí không hợp lệ.' });
  }

  if (sessionType === 'event') {
    return checkInEventFace(request, response, {
      sessionId,
      previewOnly,
      deviceId,
      coordinates,
    });
  }

  try {
    const [[session]] = await pool.execute(
      `SELECT bpd.Mabuoidiemdanh AS id, bpd.Phuongthuc AS method,
              bpd.Thoigiandong AS closedAt,
              bpd.latitude AS latitude, bpd.longitude AS longitude,
              bpd.radius_meters AS radiusMeters,
              bpd.accuracy_meters AS accuracyMeters,
              b.Mabuoi AS classSessionId, b.Malop AS classId,
              COALESCE(lhp.Tenlop, '') AS className,
              COALESCE(b.Noidung, '') AS sessionName,
              b.Thoigianbatdau AS startTime, b.Thoigianketthuc AS endTime,
              COALESCE(lecturer.Hoten, '') AS lecturerName,
              COALESCE((
                SELECT GROUP_CONCAT(DISTINCT lh.PhongHoc
                  ORDER BY lh.PhongHoc SEPARATOR ', ')
                FROM LichHocPhan lh
                WHERE lh.Malop = b.Malop
                  AND lh.ThuTrongTuan = WEEKDAY(b.Thoigianbatdau) + 1
                  AND (lh.NgayBatDau IS NULL
                    OR lh.NgayBatDau <= DATE(b.Thoigianbatdau))
                  AND (lh.NgayKetThuc IS NULL
                    OR lh.NgayKetThuc >= DATE(b.Thoigianbatdau))
                  AND lh.GioBatDau <= TIME(b.Thoigianbatdau)
                  AND lh.GioKetThuc >= TIME(b.Thoigianbatdau)
              ), '') AS room,
              COALESCE(attendee.Hoten, '') AS studentName
       FROM BuoiDiemDanh bpd
       JOIN Buoi b ON b.Mabuoi = bpd.Mabuoi
       JOIN ThanhVienLop tvl ON tvl.Malop = b.Malop
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = b.Malop
       LEFT JOIN GiangVien gv ON gv.Magv = lhp.Magv
       LEFT JOIN NguoiDung lecturer ON lecturer.Mand = gv.Magv
       LEFT JOIN NguoiDung attendee ON attendee.Mand = tvl.Masv
       WHERE bpd.Mabuoidiemdanh = ?
         AND tvl.Masv = ? AND bpd.Trangthaidiemdanh = 'Đang mở'
         AND bpd.Thoigiandong > NOW()
         AND bpd.Phuongthuc IN ('Face', 'Both')
       LIMIT 1`,
      [sessionId, request.auth.sub],
    );
    if (!session) {
      return response.status(404).json({
        message: 'Môn học đã đóng, không hỗ trợ điểm danh khuôn mặt hoặc bạn không thuộc lớp.',
      });
    }
    if (previewOnly) {
      const [[existing]] = await pool.execute(
        `SELECT Maketqua AS id, (Vitri IS NULL) AS manuallyRecorded
         FROM KetQuaDiemDanh
         WHERE Mabuoidiemdanh = ? AND Masv = ? LIMIT 1`,
        [session.id, request.auth.sub],
      );
      if (existing) {
        return response.status(409).json({
          message: Number(existing.manuallyRecorded) === 1
            ? 'Giảng viên đã ghi nhận trạng thái điểm danh cho bạn trong phiên này. Bạn không thể quét mã thêm.'
            : 'Bạn đã có kết quả điểm danh trong phiên này. Bạn không thể quét mã thêm.',
        });
      }
      return response.json({
        attendanceSessionId: session.id,
        classSessionId: session.classSessionId,
        classId: session.classId,
        className: session.className,
        sessionName: session.sessionName,
        startTime: session.startTime,
        endTime: session.endTime,
        lecturerName: session.lecturerName,
        room: session.room,
        studentId: request.auth.sub,
        studentName: session.studentName,
        status: 'Chờ xác nhận',
        method: 'Face',
      });
    }
    const [[deviceClaim]] = await pool.execute(
      `SELECT 1 AS used FROM attendance_device_claims
       WHERE device_id = ? AND attendance_session_id = ? LIMIT 1`,
      [deviceId, session.id],
    );
    if (deviceClaim) {
      return response.status(409).json({
        message: 'Thiết bị này đã được dùng để điểm danh phiên này.',
      });
    }

    const radiusMeters = Number(session.radiusMeters) || classAttendanceRadiusMeters;
    if (!isWithinAttendanceRadius(
      { latitude: Number(session.latitude), longitude: Number(session.longitude) },
      coordinates,
      radiusMeters,
      Number(session.accuracyMeters) || 0,
      accuracyMeters,
    )) {
      return response.status(403).json({ message: `Bạn đang cách vị trí điểm danh quá xa (phạm vi ${radiusMeters} m).` });
    }

    const [[existing]] = await pool.execute(
      `SELECT Maketqua AS id, (Vitri IS NULL) AS manuallyRecorded
       FROM KetQuaDiemDanh
       WHERE Mabuoidiemdanh = ? AND Masv = ? LIMIT 1`,
      [session.id, request.auth.sub],
    );
    if (existing) return response.status(409).json({ message: Number(existing.manuallyRecorded) === 1
      ? 'Giảng viên đã ghi nhận trạng thái điểm danh cho bạn trong phiên này. Bạn không thể quét mã thêm.'
      : 'Bạn đã có kết quả điểm danh trong phiên này. Bạn không thể quét mã thêm.' });

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      await connection.execute(
        `INSERT INTO attendance_device_claims
         (device_id, attendance_date, student_id, attendance_session_id)
         VALUES (?, CURDATE(), ?, ?)`,
        [deviceId, request.auth.sub, session.id],
      );
      await connection.execute(
        `INSERT INTO KetQuaDiemDanh
         (Maketqua, Thoigiandiemdanh, Trangthaiketqua, Vitri, Mabuoidiemdanh, Masv)
         VALUES (?, NOW(), 'Có mặt', ?, ?, ?)`,
        [
          makeId('RS'),
          JSON.stringify(coordinates),
          session.id,
          request.auth.sub,
        ],
      );
      await connection.commit();
    } catch (error) {
      await connection.rollback();
      if (error.code === 'ER_DUP_ENTRY') {
        return response.status(409).json({
          message: 'Bạn đã điểm danh phiên này hoặc thiết bị đã được dùng.',
        });
      }
      throw error;
    } finally {
      connection.release();
    }

    const [[result]] = await pool.execute(
      `SELECT Thoigiandiemdanh AS checkedInAt,
              Trangthaiketqua AS status
       FROM KetQuaDiemDanh
       WHERE Mabuoidiemdanh = ? AND Masv = ?
       LIMIT 1`,
      [session.id, request.auth.sub],
    );
    return response.status(201).json({
      message: 'Điểm danh khuôn mặt thành công.',
      attendanceSessionId: session.id,
      classSessionId: session.classSessionId,
      classId: session.classId,
      className: session.className,
      sessionName: session.sessionName,
      startTime: session.startTime,
      endTime: session.endTime,
      lecturerName: session.lecturerName,
      room: session.room,
      checkedInAt: result.checkedInAt,
      status: result.status,
      studentId: request.auth.sub,
      studentName: session.studentName,
      method: 'Face',
    });
  } catch (error) {
    console.error('Face check-in error:', error.message);
    return response.status(500).json({ message: 'Không thể ghi nhận điểm danh khuôn mặt.' });
  }
});

async function checkInEventFace(
  request,
  response,
  { sessionId, previewOnly, deviceId, coordinates },
) {
  try {
    const { global: globalParameters } = await getEffectiveAttendanceParameters(
      'global',
    );
    const allowEarlyAttendance = globalParameters.allowEarlyAttendance ? 1 : 0;
    const [[event]] = await pool.execute(
      `SELECT sk.Masukien AS eventId, sk.Tensukien AS eventName,
              COALESCE(sk.Diadiem, '') AS location,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              COALESCE(dv.Tendv, '') AS organizerName,
              eas.latitude AS latitude, eas.longitude AS longitude,
              eas.radius_meters AS radiusMeters,
              eas.session_id AS attendanceSessionId,
              eas.period_name AS periodName,
              eas.period_start AS periodStart,
              eas.period_end AS periodEnd,
              (SELECT COUNT(*)
               FROM event_attendance_sessions previous
               WHERE previous.event_id = eas.event_id
                 AND (previous.opened_at < eas.opened_at
                   OR (previous.opened_at = eas.opened_at
                     AND previous.session_id <= eas.session_id))) AS sessionNumber,
              nd.Mand AS studentId,
              COALESCE(nd.Hoten, nd.Mand) AS studentName
       FROM SuKien sk
       JOIN event_attendance_sessions eas ON eas.event_id = sk.Masukien
       JOIN DangKySuKien dk ON dk.Masukien = sk.Masukien AND dk.Masv = ?
       JOIN NguoiDung nd ON nd.Mand = dk.Masv
       LEFT JOIN DonVi dv ON dv.Madv = sk.Madv
       WHERE eas.session_id = ?
         AND eas.expires_at > NOW()
         AND eas.closed_at IS NULL
         AND (eas.period_start IS NULL
           OR ? = 1
           OR (NOW() >= eas.period_start AND NOW() < eas.period_end))
         AND (? = 1 OR NOW() >= sk.Thoigianbatdau)
         AND NOW() < sk.Thoigianketthuc
         AND sk.Trangthaisukien <> 'Đã đóng'
         AND LOWER(TRIM(COALESCE(dk.Trangthaidangky, ''))) NOT IN ('từ chối', 'đã hủy', 'hủy')
       LIMIT 1`,
      [request.auth.sub, sessionId, allowEarlyAttendance, allowEarlyAttendance],
    );
    if (!event) {
      return response.status(404).json({
        message: 'Phiên điểm danh đã đóng, đang ngoài khung giờ hoặc bạn chưa đăng ký sự kiện.',
      });
    }

    const [[existing]] = await pool.execute(
      `SELECT 1 AS id FROM event_attendance_records
       WHERE session_id = ? AND student_id = ? LIMIT 1`,
      [sessionId, request.auth.sub],
    );
    if (existing) {
      return response.status(409).json({
        message: 'Bạn đã điểm danh phiên này.',
      });
    }
    if (previewOnly) {
      return response.json({
        ...event,
        status: 'Chờ xác nhận',
        method: 'Face',
      });
    }

    const distance = distanceInMeters(
      { latitude: Number(event.latitude), longitude: Number(event.longitude) },
      coordinates,
    );
    const radiusMeters = Number(event.radiusMeters);
    if (!Number.isFinite(distance) || distance > radiusMeters) {
      return response.status(403).json({
        message: `Bạn đang cách vị trí sự kiện quá xa (phạm vi ${radiusMeters} m).`,
      });
    }

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const [[activeSession]] = await connection.execute(
        `SELECT eas.session_id AS sessionId
         FROM event_attendance_sessions eas
         JOIN SuKien sk ON sk.Masukien = eas.event_id
         WHERE eas.session_id = ? AND eas.expires_at > NOW()
           AND eas.closed_at IS NULL
           AND (eas.period_start IS NULL OR ? = 1 OR NOW() >= eas.period_start)
           AND (? = 1 OR NOW() >= sk.Thoigianbatdau)
           AND NOW() < sk.Thoigianketthuc
           AND sk.Trangthaisukien <> 'Đã đóng'
         FOR UPDATE`,
        [sessionId, allowEarlyAttendance, allowEarlyAttendance],
      );
      if (!activeSession) {
        await connection.rollback();
        return response.status(410).json({
          message: 'Phiên điểm danh sự kiện đã đóng hoặc hết hạn.',
        });
      }
      const [[registration]] = await connection.execute(
        `SELECT 1 AS registered
         FROM DangKySuKien
         WHERE Masukien = ? AND Masv = ?
           AND LOWER(TRIM(COALESCE(Trangthaidangky, ''))) NOT IN ('từ chối', 'đã hủy', 'hủy')
         LIMIT 1 FOR UPDATE`,
        [event.eventId, request.auth.sub],
      );
      if (!registration) {
        await connection.rollback();
        return response.status(403).json({
          message: 'Bạn cần có đăng ký hợp lệ cho sự kiện mới được điểm danh.',
        });
      }
      await connection.execute(
        `INSERT INTO event_attendance_records
         (event_id, session_id, student_id, device_id, method)
         VALUES (?, ?, ?, ?, 'Face')`,
        [event.eventId, sessionId, request.auth.sub, deviceId],
      );
      await connection.execute(
        `INSERT IGNORE INTO event_attendance (event_id, student_id, device_id)
         VALUES (?, ?, ?)`,
        [event.eventId, request.auth.sub, deviceId],
      );
      await connection.commit();
    } catch (error) {
      await connection.rollback();
      if (error.code === 'ER_DUP_ENTRY') {
        return response.status(409).json({
          message: 'Bạn đã điểm danh phiên này hoặc thiết bị đã được dùng trong phiên.',
        });
      }
      throw error;
    } finally {
      connection.release();
    }

    const [[attendance]] = await pool.execute(
      `SELECT checked_in_at AS checkedInAt
       FROM event_attendance_records
       WHERE session_id = ? AND student_id = ? LIMIT 1`,
      [sessionId, request.auth.sub],
    );
    return response.status(201).json({
      ...event,
      checkedInAt: attendance.checkedInAt,
      status: 'Có mặt',
      method: 'Face',
    });
  } catch (error) {
    console.error('Event face check-in error:', error.message);
    return response.status(500).json({
      message: 'Không thể ghi nhận điểm danh khuôn mặt sự kiện.',
    });
  }
}

// Các tuyến quản lý sự kiện và đơn vị dành cho quản trị viên, ban tổ chức.
// Lấy danh sách sự kiện phục vụ màn hình quản lý.
app.get('/api/organizer/events', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  try {
    const [rows] = await pool.execute(
            `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Madv AS organizerId,
              sk.Diadiem AS location, sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              COALESCE(sk.Capchungnhan, 0) AS certificateEnabled,
              ${eventStatusSql} AS status,
              COALESCE(sk.Soluongtoida, 0) AS capacity,
              COUNT(dk.Masv) AS registeredCount,
              (SELECT COUNT(*)
               FROM DangKySuKien dkPresent
               WHERE dkPresent.Masukien = sk.Masukien
                 AND (
                   EXISTS (
                     SELECT 1 FROM event_attendance ea
                     WHERE ea.event_id = sk.Masukien
                       AND ea.student_id = dkPresent.Masv
                   )
                   OR EXISTS (
                     SELECT 1 FROM event_attendance_records ear
                     WHERE ear.event_id = sk.Masukien
                       AND ear.student_id = dkPresent.Masv
                   )
                 )) AS checkedInCount,
              (SELECT COUNT(*)
               FROM DangKySuKien dkAbsent
               WHERE dkAbsent.Masukien = sk.Masukien
                 AND (
                   sk.Trangthaisukien = 'Đã đóng'
                   OR NOW() >= sk.Thoigianketthuc
                 )
                 AND NOT EXISTS (
                   SELECT 1 FROM event_attendance ea
                   WHERE ea.event_id = sk.Masukien
                     AND ea.student_id = dkAbsent.Masv
                 )
                 AND NOT EXISTS (
                   SELECT 1 FROM event_attendance_records ear
                   WHERE ear.event_id = sk.Masukien
                     AND ear.student_id = dkAbsent.Masv
                 )) AS absentCount,
              (SELECT COUNT(*)
               FROM DangKySuKien dkPending
               WHERE dkPending.Masukien = sk.Masukien
                 AND sk.Trangthaisukien <> 'Đã đóng'
                 AND NOW() < sk.Thoigianketthuc
                 AND NOT EXISTS (
                   SELECT 1 FROM event_attendance ea
                   WHERE ea.event_id = sk.Masukien
                     AND ea.student_id = dkPending.Masv
                 )
                 AND NOT EXISTS (
                   SELECT 1 FROM event_attendance_records ear
                   WHERE ear.event_id = sk.Masukien
                     AND ear.student_id = dkPending.Masv
                 )) AS pendingCount
       FROM SuKien sk
       LEFT JOIN DangKySuKien dk ON dk.Masukien = sk.Masukien
       WHERE ? = 1 OR EXISTS (
         SELECT 1 FROM DonVi dv WHERE dv.Madv = sk.Madv AND dv.Manv = ?
       )
      GROUP BY sk.Masukien, sk.Tensukien, sk.Madv, sk.Diadiem,
               sk.Thoigianbatdau, sk.Thoigianketthuc, sk.Trangthaisukien,
                sk.Soluongtoida, sk.Capchungnhan
       ORDER BY sk.Thoigianbatdau`,
      [isAdminAuth(request.auth) ? 1 : 0, request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Organizer events error:', error.message);
    return response.status(500).json({ message: 'Không thể tải sự kiện.' });
  }
});

app.post('/api/organizer/events/:eventId/attendance/qr', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Cán bộ', 'Nhân viên', 'event_organizer'), async (request, response) => {
  const isAdmin = ['quản trị viên', 'admin'].includes(
    String(request.auth.role || '').trim().toLowerCase(),
  );
  const coordinates = readCoordinates(request.body);
  if (!coordinates) {
    return response.status(400).json({
      message: 'Cần lấy vị trí thiết bị để tạo QR điểm danh sự kiện.',
    });
  }
  const requestedPeriodId = request.body?.periodId;
  if (requestedPeriodId !== undefined
      && (typeof requestedPeriodId !== 'string' || !requestedPeriodId)) {
    return response.status(400).json({ message: 'Khung điểm danh không hợp lệ.' });
  }
  try {
    const [[event]] = await pool.execute(
      `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianbatdau > NOW() AS startsInFuture,
              sk.Thoigianketthuc AS endTime,
              sk.Trangthaisukien AS status,
              COALESCE(sk.Capchungnhan, 0) AS certificateEnabled,
              EXISTS (
                SELECT 1 FROM DonVi dv
                WHERE dv.Madv = sk.Madv AND dv.Manv = ?
              ) AS isOrganizer
       FROM SuKien sk
       WHERE sk.Masukien = ?
       LIMIT 1`,
      [request.auth.sub, request.params.eventId],
    );
    if (!event) {
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    if (!isAdmin && !Number(event.isOrganizer)) {
      return response.status(403).json({
        message: 'Bạn không phụ trách sự kiện này.',
      });
    }
    const [periods] = await pool.execute(
      `SELECT period_id AS id, name, starts_at AS startTime,
              starts_at > NOW() AS startsInFuture, ends_at AS endTime
       FROM event_attendance_periods
       WHERE event_id = ?
       ORDER BY display_order, starts_at`,
      [event.id],
    );
    let period = null;
    if (periods.length > 0) {
      if (!requestedPeriodId) {
        return response.status(400).json({
          message: 'Cần chọn khung điểm danh trước khi tạo mã QR.',
        });
      }
      [period] = periods.filter((item) => item.id === requestedPeriodId);
      if (!period) {
        return response.status(404).json({
          message: 'Không tìm thấy khung điểm danh của sự kiện.',
        });
      }
    } else if (requestedPeriodId) {
      return response.status(400).json({
        message: 'Sự kiện chưa cấu hình khung điểm danh.',
      });
    }
    const { effective: eventParameters } = await getEffectiveAttendanceParameters(
      'event', event.id,
    );
    const attendanceStartsInFuture = period
      ? Number(period.startsInFuture)
      : Number(event.startsInFuture);
    if (!eventParameters.allowEarlyAttendance && attendanceStartsInFuture) {
      return response.status(409).json({
        message: 'Chưa đến giờ bắt đầu sự kiện hoặc khung điểm danh nên chưa thể mở điểm danh.',
      });
    }
    const periodEndsAt = new Date(period?.endTime ?? event.endTime);
    const configuredQrEndsAt = new Date(
      Date.now() + Number(eventParameters.qrDurationMinutes) * 60 * 1000,
    );
    const expiresAt = new Date(Math.min(periodEndsAt.getTime(), configuredQrEndsAt.getTime()));
    if (event.status === 'Đã đóng' || expiresAt <= new Date()) {
      return response.status(409).json({
        message: 'Không thể tạo QR cho sự kiện đã đóng hoặc đã kết thúc.',
      });
    }
    const [[activeSession]] = await pool.execute(
      `SELECT session_id AS id
       FROM event_attendance_sessions
       WHERE event_id = ? AND period_id <=> ?
         AND closed_at IS NULL AND expires_at > NOW()
       ORDER BY opened_at DESC
       LIMIT 1`,
      [event.id, period?.id ?? null],
    );
    if (activeSession) {
      return response.status(409).json({
        message: 'Khung điểm danh đang có mã QR hoạt động. Hãy tắt mã hiện tại trước khi tạo mã mới.',
      });
    }
    const expiresIn = Math.floor(expiresAt.getTime() / 1000) - Math.floor(Date.now() / 1000);
    if (expiresIn <= 0) {
      return response.status(409).json({
        message: 'Sự kiện sắp kết thúc, không thể tạo mã QR mới.',
      });
    }
    const sessionId = crypto.randomUUID();
    const qr = jwt.sign(
      {
        type: 'event-attendance',
        eventId: event.id,
        sessionId,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        radiusMeters: Number(eventParameters.gpsRadiusMeters) || eventAttendanceRadiusMeters,
      },
      jwtSecret,
      { expiresIn },
    );
    await pool.execute(
      `INSERT INTO event_attendance_sessions
       (session_id, event_id, latitude, longitude, radius_meters,
        expires_at, period_id, period_name, period_start, period_end, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        sessionId,
        event.id,
        coordinates.latitude,
        coordinates.longitude,
        Number(eventParameters.gpsRadiusMeters) || eventAttendanceRadiusMeters,
        expiresAt,
        period?.id ?? null,
        period?.name ?? null,
        period?.startTime ?? null,
        period?.endTime ?? null,
        request.auth.sub,
      ],
    );
    const [[sessionNumber]] = await pool.execute(
      `SELECT COUNT(*) AS value
       FROM event_attendance_sessions
       WHERE event_id = ?`,
      [event.id],
    );
    return response.json({
      eventId: event.id,
      eventName: event.name,
      sessionId,
      sessionNumber: Number(sessionNumber.value),
      periodId: period?.id ?? null,
      periodName: period?.name ?? null,
      periodStart: period?.startTime ?? null,
      periodEnd: period?.endTime ?? null,
      expiresAt,
      radiusMeters: Number(eventParameters.gpsRadiusMeters) || eventAttendanceRadiusMeters,
      qrDurationMinutes: Number(eventParameters.qrDurationMinutes),
      qr,
    });
  } catch (error) {
    console.error('Create event attendance QR error:', error.message);
    return response.status(500).json({
      message: 'Không thể tạo mã QR điểm danh sự kiện.',
    });
  }
});

app.post('/api/organizer/events/:eventId/attendance/sessions/:sessionId/close', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Cán bộ', 'Nhân viên', 'event_organizer'), async (request, response) => {
  const isAdmin = ['quản trị viên', 'admin'].includes(
    String(request.auth.role || '').trim().toLowerCase(),
  );
  try {
    const [[session]] = await pool.execute(
      `SELECT eas.session_id AS sessionId,
              EXISTS (
                SELECT 1 FROM DonVi dv
                WHERE dv.Madv = sk.Madv AND dv.Manv = ?
              ) AS isOrganizer
       FROM event_attendance_sessions eas
       JOIN SuKien sk ON sk.Masukien = eas.event_id
       WHERE eas.event_id = ? AND eas.session_id = ?
       LIMIT 1`,
      [request.auth.sub, request.params.eventId, request.params.sessionId],
    );
    if (!session) {
      return response.status(404).json({ message: 'Không tìm thấy phiên điểm danh.' });
    }
    if (!isAdmin && !Number(session.isOrganizer)) {
      return response.status(403).json({
        message: 'Bạn không phụ trách sự kiện này.',
      });
    }
    const [result] = await pool.execute(
      `UPDATE event_attendance_sessions
       SET closed_at = COALESCE(closed_at, NOW())
       WHERE event_id = ? AND session_id = ? AND closed_at IS NULL`,
      [request.params.eventId, request.params.sessionId],
    );
    if (result.affectedRows === 0) {
      return response.status(409).json({ message: 'Phiên điểm danh đã được đóng.' });
    }
    return response.json({
      message: 'Đã đóng phiên điểm danh.',
      sessionId: session.sessionId,
    });
  } catch (error) {
    console.error('Close event attendance session error:', error.message);
    return response.status(500).json({
      message: 'Không thể đóng phiên điểm danh sự kiện.',
    });
  }
});

app.post('/api/organizer/events/:eventId/certificates/issue', requireAuth, requireRole(...eventManagerRoles, 'organizer', 'staff', 'employee'), async (request, response) => {
  const isAdmin = ['quản trị viên', 'admin'].includes(
    String(request.auth.role || '').trim().toLowerCase(),
  );
  const requestedStudentId = request.body?.studentId;
  if (requestedStudentId !== undefined
      && (typeof requestedStudentId !== 'string' || !requestedStudentId.trim())) {
    return response.status(400).json({ message: 'Mã sinh viên cần cấp chứng nhận không hợp lệ.' });
  }
  const studentId = typeof requestedStudentId === 'string' ? requestedStudentId.trim() : null;
  let connection;
  try {
    const [[event]] = await pool.execute(
      `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Thoigianketthuc AS endTime, sk.Trangthaisukien AS status,
              COALESCE(sk.Capchungnhan, 0) AS certificateEnabled,
              EXISTS (SELECT 1 FROM DonVi dv
                      WHERE dv.Madv = sk.Madv AND dv.Manv = ?) AS isOrganizer
       FROM SuKien sk WHERE sk.Masukien = ? LIMIT 1`,
      [request.auth.sub, request.params.eventId],
    );
    if (!event) return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    if (!isAdmin && !Number(event.isOrganizer)) {
      return response.status(403).json({ message: 'Bạn không phụ trách sự kiện này.' });
    }
    if (!Number(event.certificateEnabled)) {
      return response.status(409).json({ message: 'Sự kiện này không đăng ký cấp chứng nhận.' });
    }
    const eventIsClosed = String(event.status || '').trim().toLowerCase() === 'đã đóng';
    if (!eventIsClosed && new Date(event.endTime) > new Date()) {
      return response.status(409).json({ message: 'Chỉ có thể cấp chứng nhận sau khi sự kiện kết thúc hoặc đã đóng.' });
    }

    const [candidateAttendees] = await pool.execute(
      `SELECT candidates.studentId
       FROM (
         SELECT dk.Masv AS studentId FROM DangKySuKien dk WHERE dk.Masukien = ?
         UNION
         SELECT ea.student_id AS studentId FROM event_attendance ea WHERE ea.event_id = ?
         UNION
         SELECT ear.student_id AS studentId FROM event_attendance_records ear WHERE ear.event_id = ?
       ) candidates
       WHERE (? IS NULL OR candidates.studentId = ?)
       ORDER BY candidates.studentId`,
      [event.id, event.id, event.id, studentId, studentId],
    );
    const attendees = await filterEligibleEventAttendees(event.id, candidateAttendees);
    if (attendees.length === 0) {
      if (studentId) return response.status(409).json({ message: 'Sinh viên chưa điểm danh sự kiện.' });
      return response.json({ eventId: event.id, issued: 0, skipped: 0, failures: [], message: 'Chưa có sinh viên điểm danh đủ điều kiện.' });
    }

    let issued = 0;
    let skipped = 0;
    const failures = [];
    for (const attendee of attendees) {
      try {
        connection = await pool.getConnection();
        await connection.beginTransaction();
        const [certificates] = await connection.execute(
          `SELECT Machungnhan AS id, Trangthaichungnhan AS status,
                  SignatureSnapshot AS signatureImage,
                  SignatureSnapshotCaptured AS signatureSnapshotCaptured,
                  OrganizerSignatureSnapshot AS organizerSignatureImage,
                  SignatureNameSnapshot AS signatureName,
                  OrganizerSignatureNameSnapshot AS organizerSignatureName
           FROM ChungNhan WHERE Masv = ? AND Masukien = ?
           ORDER BY Ngaycap DESC, Machungnhan DESC FOR UPDATE`,
          [attendee.studentId, event.id],
        );
        const alreadyIssued = certificates.find((certificate) =>
          String(certificate.status || '').trim().toLowerCase() === 'đã cấp');
        if (alreadyIssued) {
          await connection.commit();
          skipped += 1;
          continue;
        }
        const signatureSnapshot = Number(certificates[0]?.signatureSnapshotCaptured)
          ? certificateSignatureSnapshot(certificates[0])
          : await getCertificateSignatureSettings(connection);
        const certificateId = certificates[0]?.id
          || `GCN-${new Date().getFullYear()}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
        if (certificates.length) {
          await connection.execute(
            `UPDATE ChungNhan
             SET Trangthaichungnhan = 'Đã cấp', Ngaycap = NOW(),
                 SignatureSnapshot = ?, OrganizerSignatureSnapshot = ?,
                 SignatureNameSnapshot = ?, OrganizerSignatureNameSnapshot = ?,
                 SignatureSnapshotCaptured = 1, SignatureSnapshotVersion = 1
             WHERE Machungnhan = ?`,
            [signatureSnapshot.signatureImage,
              signatureSnapshot.organizerSignatureImage,
              signatureSnapshot.signatureName,
              signatureSnapshot.organizerSignatureName, certificateId],
          );
        } else {
          await connection.execute(
            `INSERT INTO ChungNhan
             (Machungnhan, Masv, Masukien, Ngaycap, Noidung,
              Trangthaichungnhan, EmailTrangthai, SignatureSnapshot,
              SignatureSnapshotCaptured, OrganizerSignatureSnapshot,
              SignatureNameSnapshot, OrganizerSignatureNameSnapshot,
              SignatureSnapshotVersion)
             VALUES (?, ?, ?, NOW(), ?, 'Đã cấp', 'Chưa gửi', ?, 1, ?, ?, ?, 1)`,
            [certificateId, attendee.studentId, event.id,
              `Giấy chứng nhận tham gia sự kiện ${event.name}`,
              signatureSnapshot.signatureImage,
              signatureSnapshot.organizerSignatureImage,
              signatureSnapshot.signatureName,
              signatureSnapshot.organizerSignatureName],
          );
        }
        await connection.commit();
        issued += 1;
      } catch (error) {
        if (connection) await connection.rollback();
        failures.push({ studentId: attendee.studentId, message: error.message });
      } finally {
        if (connection) connection.release();
        connection = null;
      }
    }
    return response.json({ eventId: event.id, issued, skipped, failures });
  } catch (error) {
    if (connection) {
      await connection.rollback();
      connection.release();
    }
    console.error('Issue in-app certificates error:', error.message);
    return response.status(500).json({ message: 'Không thể cấp chứng nhận trong ứng dụng.' });
  }
});

app.post('/api/organizer/events/:eventId/certificates/send', requireAuth, requireRole(...eventManagerRoles, 'organizer', 'staff', 'employee'), async (request, response) => {
  const isAdmin = ['quản trị viên', 'admin'].includes(
    String(request.auth.role || '').trim().toLowerCase(),
  );
  const requestedStudentId = request.body?.studentId;
  if (
    requestedStudentId !== undefined
    && (typeof requestedStudentId !== 'string' || !requestedStudentId.trim())
  ) {
    return response.status(400).json({
      message: 'Mã sinh viên cần cấp chứng nhận không hợp lệ.',
    });
  }
  const studentId = typeof requestedStudentId === 'string'
    ? requestedStudentId.trim()
    : null;
  let connection;
  try {
    const [[event]] = await pool.execute(
      `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Diadiem AS location,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              sk.Trangthaisukien AS status,
              COALESCE(sk.Capchungnhan, 0) AS certificateEnabled,
              EXISTS (
                SELECT 1 FROM DonVi dv
                WHERE dv.Madv = sk.Madv AND dv.Manv = ?
              ) AS isOrganizer
       FROM SuKien sk
       WHERE sk.Masukien = ?
       LIMIT 1`,
      [request.auth.sub, request.params.eventId],
    );
    if (!event) {
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    if (!isAdmin && !Number(event.isOrganizer)) {
      return response.status(403).json({
        message: 'Bạn không phụ trách sự kiện này.',
      });
    }
    if (!Number(event.certificateEnabled)) {
      return response.status(409).json({
        message: 'Sự kiện này không đăng ký cấp chứng nhận.',
      });
    }
    const eventIsClosed =
      String(event.status || '').trim().toLowerCase() === 'đã đóng';
    if (!eventIsClosed && new Date(event.endTime) > new Date()) {
      return response.status(409).json({
        message: 'Chỉ có thể cấp chứng nhận sau khi sự kiện kết thúc hoặc đã đóng.',
      });
    }

    const [candidateAttendees] = await pool.execute(
      `SELECT candidates.studentId,
              COALESCE(nd.Hoten, candidates.studentId) AS studentName,
              COALESCE(nd.Email, '') AS email
       FROM (
         SELECT dk.Masv AS studentId FROM DangKySuKien dk WHERE dk.Masukien = ?
         UNION
         SELECT ea.student_id AS studentId FROM event_attendance ea WHERE ea.event_id = ?
         UNION
         SELECT ear.student_id AS studentId FROM event_attendance_records ear WHERE ear.event_id = ?
       ) candidates
       LEFT JOIN NguoiDung nd ON nd.Mand = candidates.studentId
       WHERE NOT EXISTS (
         SELECT 1
         FROM ChungNhan mailed
         WHERE mailed.Masv = candidates.studentId
           AND mailed.Masukien = ?
           AND mailed.EmailTrangthai = 'Đã gửi'
       )
         AND (? IS NULL OR candidates.studentId = ?)
       ORDER BY candidates.studentId`,
      [event.id, event.id, event.id, event.id, studentId, studentId],
    );
    const attendees = await filterEligibleEventAttendees(event.id, candidateAttendees);
    if (attendees.length === 0) {
      if (studentId) {
        return response.status(409).json({
          message: 'Sinh viên chưa điểm danh hoặc đã được cấp chứng nhận.',
        });
      }
      return response.json({
        eventId: event.id,
        sent: 0,
        skipped: 0,
        failures: [],
        message: 'Không còn sinh viên đủ điều kiện cấp chứng nhận.',
      });
    }

    let mailTransport;
    try {
      mailTransport = createMailTransport();
      await mailTransport.verify();
    } catch (error) {
      console.error('Email provider configuration error:', error.message);
      return response.status(503).json({
        message: `Không thể khởi tạo dịch vụ email: ${error.message}`,
      });
    }

    const publicBaseUrl = (
      process.env.PUBLIC_API_BASE_URL
      || `${request.protocol}://${request.get('host')}`
    ).replace(/\/+$/, '');
    let sent = 0;
    let skipped = 0;
    const failures = [];

    for (const attendee of attendees) {
      if (!String(attendee.email || '').trim()) {
        failures.push({
          studentId: attendee.studentId,
          message: `${attendee.studentName}: tài khoản chưa có email.`,
        });
        continue;
      }

      try {
        connection = await pool.getConnection();
        await connection.beginTransaction();
        await connection.execute(
          `SELECT checked_in_at
           FROM event_attendance
           WHERE event_id = ? AND student_id = ?
           FOR UPDATE`,
          [event.id, attendee.studentId],
        );
        await connection.execute(
          `SELECT session_id
           FROM event_attendance_records
           WHERE event_id = ? AND student_id = ?
           FOR UPDATE`,
          [event.id, attendee.studentId],
        );
        const [existingCertificates] = await connection.execute(
          `SELECT Machungnhan AS id, Ngaycap AS issuedAt,
                  Trangthaichungnhan AS status, EmailTrangthai AS emailStatus,
                  SignatureSnapshot AS signatureImage,
                  SignatureSnapshotCaptured AS signatureSnapshotCaptured,
                  OrganizerSignatureSnapshot AS organizerSignatureImage,
                  SignatureNameSnapshot AS signatureName,
                  OrganizerSignatureNameSnapshot AS organizerSignatureName
           FROM ChungNhan
           WHERE Masv = ? AND Masukien = ?
           ORDER BY Ngaycap DESC, Machungnhan DESC
           FOR UPDATE`,
          [attendee.studentId, event.id],
        );
        if (
          existingCertificates.some(
            (certificate) =>
              String(certificate.emailStatus || '').trim().toLowerCase() === 'đã gửi',
          )
        ) {
          await connection.commit();
          connection.release();
          connection = null;
          skipped += 1;
          continue;
        }
        if (
          existingCertificates.some(
            (certificate) =>
              String(certificate.emailStatus || '').trim().toLowerCase() === 'đang gửi',
          )
        ) {
          await connection.commit();
          connection.release();
          connection = null;
          skipped += 1;
          continue;
        }

        const pendingCertificate = existingCertificates[0];
        let certificateId = pendingCertificate?.id;
        if (!certificateId) {
          const year = new Date().getFullYear();
          certificateId = `GCN-${year}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
          await connection.execute(
            `INSERT INTO ChungNhan
              (Machungnhan, Masv, Masukien, Ngaycap, Noidung,
               Trangthaichungnhan, EmailTrangthai)
             VALUES (?, ?, ?, NOW(), ?, 'Chưa cấp', 'Đang gửi')`,
            [
              certificateId,
              attendee.studentId,
              event.id,
              `Giấy chứng nhận tham gia sự kiện ${event.name}`,
            ],
          );
        } else {
          await connection.execute(
            `UPDATE ChungNhan
             SET EmailTrangthai = 'Đang gửi'
             WHERE Machungnhan = ?`,
            [certificateId],
          );
        }
        const issuedAt = event.endTime;
        const signatureSnapshot = Number(existingCertificates[0]?.signatureSnapshotCaptured)
          ? certificateSignatureSnapshot(existingCertificates[0])
          : await getCertificateSignatureSettings(connection);

        const verificationUrl =
          `${publicBaseUrl}/certificates/${encodeURIComponent(certificateId)}`;
        const pdf = await createCertificatePdf({
          studentName: attendee.studentName,
          studentId: attendee.studentId,
          eventName: event.name,
          startTime: event.startTime,
          endTime: event.endTime,
          location: event.location,
          certificateId,
          issuedAt,
          verificationUrl,
          organizerSignatureImage: signatureSnapshot.organizerSignatureImage,
          organizerName: signatureSnapshot.organizerSignatureName,
          deanSignatureImage: signatureSnapshot.signatureImage,
          deanName: signatureSnapshot.signatureName,
        });
        await mailTransport.sendMail({
          from: process.env.MAIL_FROM || process.env.SMTP_FROM,
          to: attendee.email,
          subject: `Chứng nhận tham gia sự kiện ${event.name}`,
          text: `Xin chào ${attendee.studentName},\n\nBạn nhận được chứng nhận tham gia sự kiện "${event.name}". Chứng nhận PDF được đính kèm email này.\n\nBan tổ chức`,
          attachments: [{
            filename: `${certificateId}.pdf`,
            content: pdf,
            contentType: 'application/pdf',
          }],
        });
        await connection.execute(
          `UPDATE ChungNhan
           SET EmailTrangthai = 'Đã gửi', EmailNgaygui = NOW(),
               SignatureSnapshot = ?, OrganizerSignatureSnapshot = ?,
               SignatureNameSnapshot = ?, OrganizerSignatureNameSnapshot = ?,
               SignatureSnapshotCaptured = 1, SignatureSnapshotVersion = 1,
               Trangthaichungnhan = CASE
                 WHEN Trangthaichungnhan = 'Đã cấp' AND Ngaycap IS NOT NULL
                   THEN Trangthaichungnhan
                 ELSE 'Chưa cấp'
               END,
               Ngaycap = CASE
                 WHEN Trangthaichungnhan = 'Đã cấp' AND Ngaycap IS NOT NULL
                   THEN Ngaycap
                 ELSE COALESCE(Ngaycap, NOW())
               END
           WHERE Machungnhan = ?`,
          [signatureSnapshot.signatureImage,
            signatureSnapshot.organizerSignatureImage,
            signatureSnapshot.signatureName,
            signatureSnapshot.organizerSignatureName, certificateId],
        );
        await connection.commit();
        connection.release();
        connection = null;
        sent += 1;
      } catch (error) {
        if (connection) {
          await connection.rollback();
          connection.release();
          connection = null;
        }
        console.error(
          `Certificate delivery failed for ${attendee.studentId}:`,
          error.message,
        );
        failures.push({
          studentId: attendee.studentId,
          message: `${attendee.studentName} (${attendee.email}): ${error.message}`,
        });
      }
    }

    return response.json({ eventId: event.id, sent, skipped, failures });
  } catch (error) {
    if (connection) {
      await connection.rollback();
      connection.release();
    }
    console.error('Send event certificates error:', error.message);
    return response.status(500).json({
      message: 'Không thể gửi chứng nhận sự kiện.',
    });
  }
});

app.get('/api/organizer/events/:eventId/students', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  const isAdmin = ['Quản trị viên', 'admin'].includes(request.auth.role);
  try {
    const [[event]] = await pool.execute(
      `SELECT sk.Masukien AS id,
              sk.Trangthaisukien AS status,
              sk.Thoigianketthuc AS endTime,
              COALESCE(sk.attendance_threshold_percent, 100)
                AS attendanceThresholdPercent,
              EXISTS (
                SELECT 1 FROM DonVi dv
                WHERE dv.Madv = sk.Madv AND dv.Manv = ?
              ) AS isOrganizer
       FROM SuKien sk
       WHERE sk.Masukien = ?
       LIMIT 1`,
      [request.auth.sub, request.params.eventId],
    );
    if (!event) {
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    if (!isAdmin && !event.isOrganizer) {
      return response.status(403).json({
        message: 'Bạn không phụ trách sự kiện này.',
      });
    }

    const [[sessionSummary]] = await pool.execute(
      'SELECT COUNT(*) AS totalSessions FROM event_attendance_sessions WHERE event_id = ?',
      [event.id],
    );
    const [[periodSummary]] = await pool.execute(
      'SELECT COUNT(*) AS totalPeriods FROM event_attendance_periods WHERE event_id = ?',
      [event.id],
    );
    const totalAttendanceUnits = Number(periodSummary.totalPeriods)
      || Number(sessionSummary.totalSessions);
    const [sessionAttendance] = await pool.execute(
      `SELECT ear.student_id AS studentId,
              COUNT(DISTINCT CASE
                WHEN ? > 0 THEN eas.period_id ELSE ear.session_id
              END) AS attendedSessions
       FROM event_attendance_records ear
       INNER JOIN event_attendance_sessions eas
         ON eas.session_id = ear.session_id AND eas.event_id = ear.event_id
       WHERE ear.event_id = ?
       GROUP BY ear.student_id`,
      [Number(periodSummary.totalPeriods), event.id],
    );
    const eventAttendanceCounts = new Map(sessionAttendance.map((row) => [
      String(row.studentId), Number(row.attendedSessions),
    ]));
    if (Number(sessionSummary.totalSessions) === 0) {
      const [legacyAttendance] = await pool.execute(
        'SELECT student_id AS studentId FROM event_attendance WHERE event_id = ?',
        [event.id],
      );
      for (const row of legacyAttendance) eventAttendanceCounts.set(String(row.studentId), 1);
    }

    const [rows] = await pool.execute(
      `SELECT dk.Masv AS studentId,
              COALESCE(nd.Hoten, dk.Masv) AS studentName,
              COALESCE(sv.Lop, '') AS className,
              COALESCE(sv.Chuyennganh, '') AS major,
              COALESCE(dk.Trangthaidangky, '') AS status,
              DATE_FORMAT(dk.Ngaydangky, '%d/%m/%Y') AS dateLabel
       FROM DangKySuKien dk
       LEFT JOIN NguoiDung nd ON nd.Mand = dk.Masv
       LEFT JOIN SinhVien sv ON sv.Masv = dk.Masv
       WHERE dk.Masukien = ?
       ORDER BY dk.Ngaydangky DESC, nd.Hoten, dk.Masv`,
      [request.params.eventId],
    );
    const attendanceByStudent = new Map();
    const certificateByStudent = new Map();
    let warning = '';
    try {
      const [legacyAttendance] = await pool.execute(
        `SELECT student_id AS studentId, checked_in_at AS checkedInAt
         FROM event_attendance
         WHERE event_id = ?`,
        [request.params.eventId],
      );
      const [attendanceRecords] = await pool.execute(
        `SELECT student_id AS studentId,
                MIN(checked_in_at) AS checkedInAt,
                GROUP_CONCAT(DISTINCT method ORDER BY method SEPARATOR ',') AS methods
         FROM event_attendance_records
         WHERE event_id = ?
         GROUP BY student_id`,
        [request.params.eventId],
      );
      for (const attendance of legacyAttendance) {
        attendanceByStudent.set(String(attendance.studentId), {
          checkedInAt: attendance.checkedInAt,
          methods: '',
        });
      }
      for (const attendance of attendanceRecords) {
        const key = String(attendance.studentId);
        const existing = attendanceByStudent.get(key);
        attendanceByStudent.set(key, {
          checkedInAt: existing?.checkedInAt || attendance.checkedInAt,
          methods: attendance.methods || '',
        });
      }
    } catch (error) {
      warning = 'Không thể tải trạng thái điểm danh; danh sách đăng ký vẫn được hiển thị.';
      console.error('Organizer event attendance status error:', error.message);
    }

    const [certificates] = await pool.execute(
      `SELECT Masv AS studentId, Ngaycap AS issuedAt,
              Trangthaichungnhan AS status, EmailTrangthai AS emailStatus
       FROM ChungNhan
       WHERE Masukien = ?
       ORDER BY Ngaycap DESC, Machungnhan DESC`,
      [request.params.eventId],
    );
    for (const certificate of certificates) {
      const key = String(certificate.studentId);
      const current = certificateByStudent.get(key) || {};
      const issued = String(certificate.status || '').trim().toLowerCase() === 'đã cấp'
        && certificate.issuedAt != null;
      const emailSent = String(certificate.emailStatus || '').trim().toLowerCase() === 'đã gửi';
      const emailPending = String(certificate.emailStatus || '').trim().toLowerCase() === 'đang gửi';
      certificateByStudent.set(key, {
        certificateStatus: issued || current.certificateStatus === 'Đã cấp'
          ? 'Đã cấp'
          : certificate.status || current.certificateStatus || 'Chưa cấp',
        emailStatus: emailSent || current.emailStatus === 'Đã gửi'
          ? 'Đã gửi'
          : emailPending || current.emailStatus === 'Đang gửi'
            ? 'Đang gửi'
            : 'Chưa gửi',
      });
    }

    const eventEnded = event.status === 'Đã đóng'
      || new Date(event.endTime) <= new Date();
    const items = rows.map((row) => {
      const attendance = attendanceByStudent.get(String(row.studentId));
      const methods = String(attendance?.methods || '').split(',').filter(Boolean);
      let attendanceStatus = eventEnded ? 'Vắng mặt' : 'Chưa điểm danh';
      if (attendance?.checkedInAt) {
        if (methods.includes('Face') && methods.includes('QR')) {
          attendanceStatus = 'Đã điểm danh QR và khuôn mặt';
        } else if (methods.includes('Face')) {
          attendanceStatus = 'Đã điểm danh khuôn mặt';
        } else {
          attendanceStatus = 'Đã điểm danh QR';
        }
      }
      return {
        ...row,
        attendanceStatus,
        checkedInAt: attendance?.checkedInAt || null,
        attendedSessions: eventAttendanceCounts.get(String(row.studentId)) || 0,
        totalAttendanceSessions: totalAttendanceUnits,
        attendanceThresholdPercent: Number(event.attendanceThresholdPercent),
        requiredAttendanceSessions: Math.ceil(
          totalAttendanceUnits * Number(event.attendanceThresholdPercent) / 100,
        ),
        maxAttendanceAbsences: totalAttendanceUnits - Math.ceil(
          totalAttendanceUnits * Number(event.attendanceThresholdPercent) / 100,
        ),
        attendancePercent: totalAttendanceUnits > 0
          ? Math.round((eventAttendanceCounts.get(String(row.studentId)) || 0) * 100
            / totalAttendanceUnits)
          : (eventAttendanceCounts.has(String(row.studentId)) ? 100 : 0),
        attendanceEligible: (Number(event.attendanceThresholdPercent) === 0
          || eventAttendanceCounts.has(String(row.studentId)))
          && (totalAttendanceUnits === 0
            ? Number(event.attendanceThresholdPercent) === 0
              || eventAttendanceCounts.has(String(row.studentId))
            : (eventAttendanceCounts.get(String(row.studentId)) || 0) * 100
              >= Number(event.attendanceThresholdPercent) * totalAttendanceUnits),
        certificateStatus: certificateByStudent.get(String(row.studentId))?.certificateStatus || 'Chưa cấp',
        emailStatus: certificateByStudent.get(String(row.studentId))?.emailStatus || 'Chưa gửi',
      };
    });
    return response.json({ items, ...(warning ? { warning } : {}) });
  } catch (error) {
    console.error('Organizer event students error:', error.code, error.message);
    return response.status(500).json({
      message: 'Không thể tải danh sách sinh viên đăng ký sự kiện.',
    });
  }
});

app.post('/api/organizer/events/:eventId/students/import', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  const { studentIds } = request.body || {};
  const allowHistoricalImport = request.body?.allowHistoricalImport === true;
  if (!Array.isArray(studentIds) || studentIds.length === 0 || studentIds.length > 2000) {
    return response.status(400).json({
      message: 'Danh sách mã sinh viên phải có từ 1 đến 2.000 mã.',
    });
  }
  if (studentIds.some((id) => typeof id !== 'string' || !id.trim() || id.trim().length > 64)) {
    return response.status(400).json({
      message: 'Danh sách chứa mã sinh viên không hợp lệ.',
    });
  }

  const uniqueIdsByKey = new Map();
  for (const studentId of studentIds) {
    const normalizedId = studentId.trim();
    const key = normalizedId.toUpperCase();
    if (!uniqueIdsByKey.has(key)) uniqueIdsByKey.set(key, normalizedId);
  }
  const normalizedIds = [...uniqueIdsByKey.values()];
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[event]] = await connection.execute(
      `SELECT Masukien, Madv AS organizerId,
              Thoigianbatdau AS startTime, Thoigianketthuc AS endTime,
              Soluongtoida AS capacity, Trangthaisukien AS status
       FROM SuKien WHERE Masukien = ? FOR UPDATE`,
      [request.params.eventId],
    );
    if (!event) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    if (!await managesUnit(connection, request.auth, event.organizerId)) {
      await connection.rollback();
      return response.status(403).json({ message: 'Bạn không phụ trách sự kiện này.' });
    }
    if (event.status === 'Đã đóng'
        || (!allowHistoricalImport && new Date(event.endTime) <= new Date())) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Sự kiện đã đóng hoặc đã kết thúc, không thể nhập sinh viên.',
      });
    }
    if (!allowHistoricalImport) {
      const { effective: eventParameters } = await getEffectiveAttendanceParameters(
        'event', event.Masukien, connection,
      );
      const registrationLockAt = new Date(event.startTime).getTime()
        - Number(eventParameters.eventRegistrationLockHours) * 60 * 60 * 1000;
      if (Date.now() >= registrationLockAt) {
        await connection.rollback();
        return response.status(409).json({
          message: `Đã đến thời gian khóa đăng ký trước sự kiện ${eventParameters.eventRegistrationLockHours} giờ. Không thể nhập sinh viên mới.`,
        });
      }
    }

    const placeholders = normalizedIds.map(() => '?').join(', ');
    const [students] = await connection.execute(
      `SELECT Masv FROM SinhVien WHERE Masv IN (${placeholders})`,
      normalizedIds,
    );
    const studentsByKey = new Map(
      students.map((student) => [String(student.Masv).toUpperCase(), String(student.Masv)]),
    );
    const unknownStudentIds = normalizedIds.filter(
      (id) => !studentsByKey.has(id.toUpperCase()),
    );
    const validIds = normalizedIds
      .map((id) => studentsByKey.get(id.toUpperCase()))
      .filter(Boolean);

    let alreadyRegisteredIds = new Set();
    if (validIds.length > 0) {
      const validPlaceholders = validIds.map(() => '?').join(', ');
      const [registrations] = await connection.execute(
        `SELECT Masv FROM DangKySuKien
         WHERE Masukien = ? AND Masv IN (${validPlaceholders})`,
        [event.Masukien, ...validIds],
      );
      alreadyRegisteredIds = new Set(
        registrations.map((registration) => String(registration.Masv)),
      );
    }
    const newIds = validIds.filter((id) => !alreadyRegisteredIds.has(id));
    const [[registrationCount]] = await connection.execute(
      'SELECT COUNT(*) AS total FROM DangKySuKien WHERE Masukien = ?',
      [event.Masukien],
    );
    const remainingCapacity = Number(event.capacity) - Number(registrationCount.total);
    if (newIds.length > remainingCapacity) {
      await connection.rollback();
      return response.status(409).json({
        message: `Sự kiện chỉ còn ${Math.max(0, remainingCapacity)} chỗ trống; không có sinh viên nào được nhập.`,
      });
    }

    for (let offset = 0; offset < newIds.length; offset += 250) {
      const batch = newIds.slice(offset, offset + 250);
      const values = batch.map(() => '(?, ?, NOW(), ?)').join(', ');
      await connection.execute(
        `INSERT INTO DangKySuKien
         (Masukien, Masv, Ngaydangky, Trangthaidangky)
         VALUES ${values}`,
        batch.flatMap((studentId) => [event.Masukien, studentId, 'Đã duyệt']),
      );
    }

    await connection.commit();
    return response.status(200).json({
      importedCount: newIds.length,
      alreadyRegisteredCount: alreadyRegisteredIds.size,
      unknownStudentIds,
    });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Import event students error:', error.message);
    return response.status(500).json({ message: 'Không thể nhập sinh viên vào sự kiện.' });
  } finally {
    if (connection) connection.release();
  }
});

// Lấy danh sách đơn vị để dùng trong biểu mẫu sự kiện.
app.get('/api/organizer/units', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT Madv AS id, Tendv AS name
       FROM DonVi
       WHERE ? = 1 OR Manv = ?
       ORDER BY Tendv`,
      [isAdminAuth(request.auth) ? 1 : 0, request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Organizer units error:', error.message);
    return response.status(500).json({ message: 'Không thể tải đơn vị tổ chức.' });
  }
});

// Kiểm tra dữ liệu biểu mẫu và tạo sự kiện mới trong cơ sở dữ liệu.
app.post('/api/organizer/events', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  const body = request.body || {};
  const { name, organizerId, startTime, endTime, location, capacity } = body;
  const allowHistoricalImport = body.allowHistoricalImport === true;
  const sourceId = body.sourceId === undefined ? '' : String(body.sourceId).trim();
  if (sourceId && (!allowHistoricalImport || !/^[A-Za-z0-9_-]{1,32}$/.test(sourceId))) {
    return response.status(400).json({ message: 'Mã sự kiện trong file Excel không hợp lệ.' });
  }
  if (body.certificateEnabled !== undefined
      && typeof body.certificateEnabled !== 'boolean') {
    return response.status(400).json({
      message: 'Tùy chọn cấp chứng nhận không hợp lệ.',
    });
  }
  const certificateEnabled = body.certificateEnabled === true;
  const attendancePeriodsResult = validateEventAttendancePeriods(
    body.attendancePeriods ?? [],
    new Date(startTime),
    new Date(endTime),
  );
  const attendanceThresholdPercent = Number(
    body.attendanceThresholdPercent ?? 100,
  );
  const parsedCapacity = Number(capacity);
  const parsedStart = new Date(startTime);
  const parsedEnd = new Date(endTime);
  const contentResult = validateEventContent(body);
  const imageResult = validateEventImageUrl(body.imageUrl);
  const registrationFormResult = validateEventRegistrationFormUrl(
    body.registrationFormUrl,
  );

  if (!name || !organizerId || !location || !Number.isInteger(parsedCapacity)
      || parsedCapacity <= 0
      || !isValidEventTimeRange(parsedStart, parsedEnd, {
        requireNonPastStart: !allowHistoricalImport,
      })) {
    return response.status(400).json({
      message: 'Thời gian bắt đầu không được ở quá khứ và thời gian kết thúc phải sau thời gian bắt đầu.',
    });
  }
  if (contentResult.message) {
    return response.status(400).json({ message: contentResult.message });
  }
  if (imageResult.message) {
    return response.status(400).json({ message: imageResult.message });
  }
  if (registrationFormResult.message) {
    return response.status(400).json({ message: registrationFormResult.message });
  }
  if (attendancePeriodsResult.message) {
    return response.status(400).json({
      message: attendancePeriodsResult.message,
    });
  }
  if (!isValidEventAttendanceThreshold(
    attendanceThresholdPercent,
    attendancePeriodsResult.value.length,
  )) {
    return response.status(400).json({
      message: 'Tỷ lệ điểm danh phải là một trong các mức phù hợp với số khung điểm danh.',
    });
  }

  try {
    if (!await managesUnit(pool, request.auth, organizerId.trim())) {
      return response.status(403).json({
        message: 'Bạn chỉ được tạo sự kiện cho đơn vị mình phụ trách.',
      });
    }
    const attempts = sourceId ? 1 : 3;
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      const id = sourceId || generateRecordId('EV');
      const connection = await pool.getConnection();
      try {
        await connection.beginTransaction();
        await connection.execute(
          `INSERT INTO SuKien
           (Masukien, Tensukien, Madv, Mota, HinhAnh, DonDangKy, Thoigianbatdau,
            Thoigianketthuc, Diadiem, Soluongtoida, Trangthaisukien,
            Capchungnhan, attendance_threshold_percent)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Sắp diễn ra', ?, ?)`,
          [
            id,
            name.trim(),
            organizerId.trim(),
            contentResult.value.description,
            imageResult.value || getEventImageUrl(name, contentResult.value.description),
            registrationFormResult.value || null,
            parsedStart,
            parsedEnd,
            location.trim(),
            parsedCapacity,
            certificateEnabled ? 1 : 0,
            attendanceThresholdPercent,
          ],
        );
        await replaceEventContent(connection, id, contentResult.value);
        await replaceEventAttendancePeriods(
          connection,
          id,
          attendancePeriodsResult.value,
        );
        await connection.commit();
        return response.status(201).json({ id, message: 'Tạo sự kiện thành công.' });
      } catch (error) {
        await connection.rollback();
        if (error.code !== 'ER_DUP_ENTRY' || attempt === attempts - 1) throw error;
      } finally {
        connection.release();
      }
    }
  } catch (error) {
    if (error.code === 'ER_DUP_ENTRY') {
      return response.status(409).json({
        message: sourceId
          ? 'Mã sự kiện trong file Excel đã tồn tại.'
          : 'Không thể tạo mã sự kiện duy nhất.',
      });
    }
    if (error.code === 'ER_NO_REFERENCED_ROW_2') {
      return response.status(400).json({ message: 'Đơn vị tổ chức không tồn tại.' });
    }
    console.error('Create organizer event error:', error.message);
    return response.status(500).json({ message: 'Không thể tạo sự kiện.' });
  }
});

// Kiểm tra dữ liệu biểu mẫu và cập nhật sự kiện theo mã định danh.
app.put('/api/organizer/events/:eventId', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  const body = request.body || {};
  const { name, organizerId, startTime, endTime, location, capacity } = body;
  if (body.certificateEnabled !== undefined
      && typeof body.certificateEnabled !== 'boolean') {
    return response.status(400).json({
      message: 'Tùy chọn cấp chứng nhận không hợp lệ.',
    });
  }
  const hasAttendancePeriods = Object.hasOwn(body, 'attendancePeriods');
  const hasAttendanceThreshold = Object.hasOwn(body, 'attendanceThresholdPercent');
  const parsedAttendanceThreshold = hasAttendanceThreshold
    ? Number(body.attendanceThresholdPercent)
    : null;
  const parsedCapacity = Number(capacity);
  const parsedStart = new Date(startTime);
  const parsedEnd = new Date(endTime);
  const hasEventContent = ['description', 'benefits', 'rules']
    .some((field) => Object.hasOwn(body, field));
  const contentResult = validateEventContent(body);
  const imageResult = validateEventImageUrl(body.imageUrl);
  const registrationFormResult = validateEventRegistrationFormUrl(
    body.registrationFormUrl,
  );
  const registrationFormUrl = Object.hasOwn(body, 'registrationFormUrl')
    ? registrationFormResult.value || null
    : null;
  const attendancePeriodsResult = hasAttendancePeriods
    ? validateEventAttendancePeriods(
      body.attendancePeriods,
      parsedStart,
      parsedEnd,
    )
    : null;

  if (!name || !organizerId || !location || !Number.isInteger(parsedCapacity)
      || parsedCapacity <= 0
      || !isValidEventTimeRange(parsedStart, parsedEnd, { requireFutureEnd: true })) {
    return response.status(400).json({
      message: 'Thời gian sự kiện phải hợp lệ, chưa kết thúc và thời gian kết thúc phải sau thời gian bắt đầu.',
    });
  }
  if (hasEventContent && contentResult.message) {
    return response.status(400).json({ message: contentResult.message });
  }
  if (imageResult.message) {
    return response.status(400).json({ message: imageResult.message });
  }
  if (registrationFormResult.message) {
    return response.status(400).json({ message: registrationFormResult.message });
  }
  if (attendancePeriodsResult?.message) {
    return response.status(400).json({
      message: attendancePeriodsResult.message,
    });
  }

  try {
    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const [[existing]] = await connection.execute(
        `SELECT Madv AS organizerId,
                Thoigianbatdau AS startTime, Thoigianketthuc AS endTime,
                Trangthaisukien AS status,
                attendance_threshold_percent AS attendanceThresholdPercent,
                (Thoigianbatdau < DATE_SUB(NOW(), INTERVAL 1 YEAR)) AS isArchived
         FROM SuKien WHERE Masukien = ? FOR UPDATE`,
        [request.params.eventId],
      );
      if (!existing) {
        await connection.rollback();
        return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
      }
      if (!await managesUnit(connection, request.auth, existing.organizerId)
          || !await managesUnit(connection, request.auth, organizerId.trim())) {
        await connection.rollback();
        return response.status(403).json({
          message: 'Bạn chỉ được sửa sự kiện của đơn vị mình phụ trách.',
        });
      }
      if (existing.status === 'Đã đóng' || Number(existing.isArchived)) {
        await connection.rollback();
        return response.status(409).json({
          message: 'Sự kiện đã đóng hoặc đã quá 1 năm nên không thể chỉnh sửa.',
        });
      }
      const existingEnd = new Date(existing.endTime).valueOf();
      if (Date.now() >= existingEnd) {
        await connection.rollback();
        return response.status(409).json({
          message: 'Sự kiện đã kết thúc nên không thể chỉnh sửa.',
        });
      }
      const [[registrationCount]] = await connection.execute(
        'SELECT COUNT(*) AS total FROM DangKySuKien WHERE Masukien = ?',
        [request.params.eventId],
      );
      if (Number(registrationCount.total) > 0) {
        await connection.rollback();
        return response.status(409).json({
          message: 'Không thể chỉnh sửa sự kiện vì đã có sinh viên đăng ký.',
        });
      }
      let attendancePeriodCount;
      if (hasAttendancePeriods) {
        attendancePeriodCount = attendancePeriodsResult.value.length;
      } else {
        const [[periodSummary]] = await connection.execute(
          `SELECT COUNT(*) AS totalPeriods
           FROM event_attendance_periods WHERE event_id = ?`,
          [request.params.eventId],
        );
        attendancePeriodCount = Number(periodSummary.totalPeriods);
      }
      if (hasAttendanceThreshold && !isValidEventAttendanceThreshold(
        parsedAttendanceThreshold,
        attendancePeriodCount,
      )) {
        await connection.rollback();
        return response.status(400).json({
          message: 'Tỷ lệ điểm danh phải là một trong các mức phù hợp với số khung điểm danh.',
        });
      }
      const attendanceThresholdPercent = hasAttendanceThreshold
        ? parsedAttendanceThreshold
        : Number(existing.attendanceThresholdPercent ?? 100);
      const normalizedAttendanceThreshold = isValidEventAttendanceThreshold(
        attendanceThresholdPercent,
        attendancePeriodCount,
      ) ? attendanceThresholdPercent : 100;
      const [result] = await connection.execute(
        `UPDATE SuKien
         SET Tensukien = ?, Madv = ?,
           HinhAnh = ?, DonDangKy = COALESCE(?, DonDangKy),
           Thoigianbatdau = ?, Thoigianketthuc = ?,
           Diadiem = ?, Soluongtoida = ?,
           Capchungnhan = COALESCE(?, Capchungnhan),
           attendance_threshold_percent = ?
         WHERE Masukien = ?`,
      [
        name.trim(),
        organizerId.trim(),
        imageResult.value || getEventImageUrl(name, contentResult.value.description),
        registrationFormUrl,
        parsedStart,
        parsedEnd,
        location.trim(),
        parsedCapacity,
        body.certificateEnabled === undefined
          ? null
          : body.certificateEnabled ? 1 : 0,
        normalizedAttendanceThreshold,
        request.params.eventId,
      ],
      );
      if (hasEventContent) {
        await replaceEventContent(connection, request.params.eventId, contentResult.value);
      }
      if (hasAttendancePeriods) {
        const [existingPeriods] = await connection.execute(
          `SELECT name, starts_at AS startTime, ends_at AS endTime
           FROM event_attendance_periods
           WHERE event_id = ?
           ORDER BY display_order, starts_at`,
          [request.params.eventId],
        );
        if (!areEventAttendancePeriodsEqual(
          existingPeriods,
          attendancePeriodsResult.value,
        )) {
          await connection.execute(
            `UPDATE event_attendance_sessions
             SET closed_at = COALESCE(closed_at, NOW())
             WHERE event_id = ? AND period_id IS NOT NULL
               AND closed_at IS NULL`,
            [request.params.eventId],
          );
          await replaceEventAttendancePeriods(
            connection,
            request.params.eventId,
            attendancePeriodsResult.value,
          );
        }
      }
      await connection.commit();
      if (result.affectedRows === 0) {
        return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
      }
      return response.json({ message: 'Cập nhật sự kiện thành công.' });
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }
  } catch (error) {
    if (error.code === 'ER_NO_REFERENCED_ROW_2') {
      return response.status(400).json({ message: 'Đơn vị tổ chức không tồn tại.' });
    }
    console.error('Update organizer event error:', error.message);
    return response.status(500).json({ message: 'Không thể cập nhật sự kiện.' });
  }
});

app.post('/api/organizer/events/:eventId/close', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  try {
    const [[target]] = await pool.execute(
      'SELECT Madv AS organizerId FROM SuKien WHERE Masukien = ? LIMIT 1',
      [request.params.eventId],
    );
    if (!target) return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    if (!await managesUnit(pool, request.auth, target.organizerId)) {
      return response.status(403).json({ message: 'Bạn không phụ trách sự kiện này.' });
    }
    const [result] = await pool.execute(
      `UPDATE SuKien SET Trangthaisukien = 'Đã đóng'
       WHERE Masukien = ? AND COALESCE(Trangthaisukien, '') <> 'Đã đóng'`,
      [request.params.eventId],
    );
    if (result.affectedRows === 0) {
      const [[event]] = await pool.execute(
        'SELECT Masukien FROM SuKien WHERE Masukien = ? LIMIT 1',
        [request.params.eventId],
      );
      if (!event) return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
      return response.status(409).json({ message: 'Sự kiện đã được đóng.' });
    }
    return response.json({ message: 'Đóng sự kiện thành công.' });
  } catch (error) {
    console.error('Close organizer event error:', error.message);
    return response.status(500).json({ message: 'Không thể đóng sự kiện.' });
  }
});

// Xóa sự kiện sau khi kiểm tra mã sự kiện và ràng buộc dữ liệu liên quan.
app.delete('/api/organizer/events/:eventId', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[event]] = await connection.execute(
      'SELECT Masukien, Madv AS organizerId FROM SuKien WHERE Masukien = ? FOR UPDATE',
      [request.params.eventId],
    );
    if (!event) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    if (!await managesUnit(connection, request.auth, event.organizerId)) {
      await connection.rollback();
      return response.status(403).json({ message: 'Bạn không phụ trách sự kiện này.' });
    }
    const [[registrationCount]] = await connection.execute(
      'SELECT COUNT(*) AS total FROM DangKySuKien WHERE Masukien = ?',
      [request.params.eventId],
    );
    if (Number(registrationCount.total) > 0) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Không thể xóa sự kiện đã có người đăng ký.',
      });
    }
    const [[attendanceCount]] = await connection.execute(
      'SELECT COUNT(*) AS total FROM event_attendance WHERE event_id = ?',
      [request.params.eventId],
    );
    if (Number(attendanceCount.total) > 0) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Không thể xóa sự kiện đã có dữ liệu điểm danh.',
      });
    }
    await connection.execute(
      'DELETE FROM SuKien WHERE Masukien = ?',
      [request.params.eventId],
    );
    await connection.commit();
    return response.json({ message: 'Xóa sự kiện thành công.' });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Delete organizer event error:', error.message);
    return response.status(409).json({
      message: 'Không thể xóa sự kiện đã có dữ liệu đăng ký hoặc điểm danh.',
    });
  } finally {
    connection?.release();
  }
});

app.get('/certificates/:certificateId', async (request, response) => {
  try {
    const certificate = await findPublicCertificate(request.params.certificateId);
    if (!certificate) {
      return response.status(404).send('Không tìm thấy chứng nhận đã cấp.');
    }
    response.set('Cache-Control', 'no-store');
    return response.type('html').send(renderCertificatePage(certificate));
  } catch (error) {
    console.error('Public certificate page error:', error.message);
    return response.status(500).send('Không thể tải thông tin chứng nhận.');
  }
});

app.get('/api/certificates/:certificateId/pdf', async (request, response) => {
  try {
    const certificate = await findPublicCertificate(request.params.certificateId);
    if (!certificate) {
      return response.status(404).json({ message: 'Không tìm thấy chứng nhận đã cấp.' });
    }
    const pdf = await createCertificatePdfForRequest(request, certificate);
    const disposition = request.query.download === '1' ? 'attachment' : 'inline';
    response.set({
      'Content-Type': 'application/pdf',
      'Content-Disposition': `${disposition}; filename="${certificate.certificateId}.pdf"`,
      'Content-Length': pdf.length,
      'Cache-Control': 'private, no-store',
    });
    return response.send(pdf);
  } catch (error) {
    console.error('Public certificate PDF error:', error.message);
    return response.status(500).json({ message: 'Không thể tải PDF chứng nhận.' });
  }
});

app.get('/api/certificates/:certificateId', async (request, response) => {
  return response.redirect(
    302,
    `/certificates/${encodeURIComponent(request.params.certificateId)}`,
  );
});

// Sinh viên chỉ xem chứng nhận đã cấp gắn với mã tài khoản trong token.
app.get('/api/student/certificates', requireAuth, requireRole('Sinh viên', 'student'), async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT cn.Machungnhan AS id, cn.Masukien AS eventId,
              sk.Tensukien AS eventName,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              sk.Diadiem AS location, sk.Thoigianketthuc AS issuedAt,
              cn.Noidung AS content,
              cn.Trangthaichungnhan AS status
       FROM ChungNhan cn
       INNER JOIN SuKien sk ON sk.Masukien = cn.Masukien
       WHERE cn.Masv = ? AND cn.Trangthaichungnhan = 'Đã cấp'
       ORDER BY cn.Ngaycap DESC, cn.Machungnhan DESC`,
      [request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Student certificates error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải danh sách chứng nhận.',
    });
  }
});

// Tạo lại PDF từ thông tin chứng nhận và chỉ cho đúng chủ sở hữu tải xuống.
app.get('/api/student/certificates/:certificateId/pdf', requireAuth, requireRole('Sinh viên', 'student'), async (request, response) => {
  try {
    const [[certificate]] = await pool.execute(
      `SELECT cn.Machungnhan AS certificateId,
              COALESCE(nd.Hoten, cn.Masv) AS studentName,
              cn.Masv AS studentId, sk.Tensukien AS eventName,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              sk.Diadiem AS location, sk.Thoigianketthuc AS issuedAt,
              cn.Noidung AS content,
              cn.SignatureSnapshot AS signatureImage,
              cn.OrganizerSignatureSnapshot AS organizerSignatureImage,
              cn.SignatureNameSnapshot AS signatureName,
              cn.OrganizerSignatureNameSnapshot AS organizerSignatureName
       FROM ChungNhan cn
       INNER JOIN SuKien sk ON sk.Masukien = cn.Masukien
       LEFT JOIN NguoiDung nd ON nd.Mand = cn.Masv
       WHERE cn.Machungnhan = ?
         AND cn.Masv = ?
         AND cn.Trangthaichungnhan = 'Đã cấp'
       LIMIT 1`,
      [request.params.certificateId, request.auth.sub],
    );
    if (!certificate) {
      return response.status(404).json({ message: 'Không tìm thấy chứng nhận.' });
    }

    const pdf = await createCertificatePdfForRequest(request, certificate);

    response.set({
      'Content-Type': 'application/pdf',
      'Content-Disposition': `attachment; filename="${certificate.certificateId}.pdf"`,
      'Content-Length': pdf.length,
      'Cache-Control': 'private, no-store',
    });
    return response.send(pdf);
  } catch (error) {
    console.error('Download student certificate error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải chứng nhận.',
    });
  }
});

app.get('/api/staff/certificate-signature', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên', 'Cán bộ', 'organizer', 'staff', 'employee'), async (_request, response) => {
  try {
    const [[settings]] = await pool.query(
      `SELECT signature_image, signature_mime, signature_name,
              organizer_signature_image, organizer_signature_mime,
              organizer_signature_name
       FROM certificate_signature_settings WHERE setting_id = 1`,
    );
    const imageData = (image, mime) => image
      ? `data:${mime};base64,${Buffer.from(image).toString('base64')}`
      : '';
    return response.json({
      signatureData: imageData(settings?.signature_image, settings?.signature_mime),
      signatureName: settings?.signature_name || '',
      organizerSignatureData: imageData(
        settings?.organizer_signature_image,
        settings?.organizer_signature_mime,
      ),
      organizerSignatureName: settings?.organizer_signature_name || '',
    });
  } catch (error) {
    console.error('Load certificate signature error:', error.message);
    return response.status(500).json({ message: 'Không thể tải chữ ký mẫu.' });
  }
});

app.put('/api/staff/certificate-signature', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên', 'Cán bộ', 'organizer', 'staff', 'employee'), async (request, response) => {
  const dean = request.body?.dean || { imageData: request.body?.imageData || '' };
  const organizer = request.body?.organizer || {};
  let deanSignatureImage;
  let organizerSignatureImage;
  try {
    deanSignatureImage = dean.imageData
      ? decodeCertificateSignature(dean.imageData)
      : null;
    organizerSignatureImage = organizer.imageData
      ? decodeCertificateSignature(organizer.imageData)
      : null;
  } catch (error) {
    return response.status(400).json({ message: error.message });
  }
  const normalizeName = (value) => {
    if (value === undefined || value === null || value === '') return '';
    if (
      typeof value !== 'string'
      || value.trim().length > 120
      || /[\u0000-\u001f\u007f]/.test(value)
    ) {
      throw new Error('Tên người ký không hợp lệ (tối đa 120 ký tự).');
    }
    return value.trim();
  };
  let deanName;
  let organizerName;
  try {
    deanName = normalizeName(dean.name);
    organizerName = normalizeName(organizer.name);
  } catch (error) {
    return response.status(400).json({ message: error.message });
  }
  const mimeType = (imageData) => imageData
    ? /^data:image\/jpe?g;/i.test(imageData) ? 'image/jpeg' : 'image/png'
    : null;
  try {
    await pool.execute(
      `INSERT INTO certificate_signature_settings
         (setting_id, signature_image, signature_mime, signature_name,
          organizer_signature_image, organizer_signature_mime,
          organizer_signature_name, updated_by)
       VALUES (1, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         signature_image = VALUES(signature_image),
         signature_mime = VALUES(signature_mime),
         signature_name = VALUES(signature_name),
         organizer_signature_image = VALUES(organizer_signature_image),
         organizer_signature_mime = VALUES(organizer_signature_mime),
         organizer_signature_name = VALUES(organizer_signature_name),
         updated_by = VALUES(updated_by)`,
      [deanSignatureImage, mimeType(dean.imageData), deanName,
        organizerSignatureImage, mimeType(organizer.imageData),
        organizerName, request.auth.sub],
    );
    return response.json({ message: 'Đã lưu chữ ký mẫu.' });
  } catch (error) {
    console.error('Save certificate signature error:', error.message);
    return response.status(500).json({ message: 'Không thể lưu chữ ký mẫu.' });
  }
});

app.delete('/api/staff/certificate-signature', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên', 'Cán bộ', 'organizer', 'staff', 'employee'), async (_request, response) => {
  try {
    await pool.execute(
      'DELETE FROM certificate_signature_settings WHERE setting_id = 1',
    );
    return response.json({ message: 'Đã đặt lại chữ ký mẫu.' });
  } catch (error) {
    console.error('Reset certificate signature error:', error.message);
    return response.status(500).json({ message: 'Không thể đặt lại chữ ký mẫu.' });
  }
});

app.get('/api/staff/certificates/template/preview', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên', 'Cán bộ', 'organizer', 'staff', 'employee'), async (request, response) => {
  try {
    const now = new Date();
    const signatures = await getCertificateSignatureSettings();
    const publicBaseUrl = (
      process.env.PUBLIC_API_BASE_URL
      || `${request.protocol}://${request.get('host')}`
    ).replace(/\/+$/, '');
    const pdf = await createCertificatePdf({
      studentName: 'Nguyễn Văn Mẫu',
      studentId: '2000000000',
      eventName: 'Tên sự kiện mẫu',
      startTime: now,
      endTime: now,
      location: 'TP. Hồ Chí Minh',
      certificateId: 'GCN-MAU',
      issuedAt: now,
      verificationUrl: `${publicBaseUrl}/api/certificates/GCN-MAU`,
      isSample: true,
      deanSignatureImage: signatures.signatureImage,
      deanName: signatures.signatureName,
      organizerSignatureImage: signatures.organizerSignatureImage,
      organizerName: signatures.organizerSignatureName,
    });
    response.set({
      'Content-Type': 'application/pdf',
      'Content-Disposition': 'inline; filename="mau-chung-nhan.pdf"',
      'Content-Length': pdf.length,
      'Cache-Control': 'private, no-store',
    });
    return response.send(pdf);
  } catch (error) {
    console.error('Preview certificate template error:', error.message);
    return response.status(500).json({ message: 'Không thể xem mẫu chứng nhận.' });
  }
});

app.get('/api/staff/certificates/:certificateId/pdf', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên', 'Cán bộ', 'organizer', 'staff', 'employee'), async (request, response) => {
  const isAdmin = ['quản trị viên', 'admin'].includes(
    String(request.auth.role || '').trim().toLowerCase(),
  );
  try {
    const [[certificate]] = await pool.execute(
      `SELECT cn.Machungnhan AS certificateId,
              COALESCE(nd.Hoten, cn.Masv) AS studentName,
              cn.Masv AS studentId, sk.Masukien AS eventId,
              sk.Tensukien AS eventName,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              sk.Diadiem AS location, sk.Thoigianketthuc AS issuedAt,
              cn.Noidung AS content,
              cn.SignatureSnapshot AS signatureImage,
              cn.OrganizerSignatureSnapshot AS organizerSignatureImage,
              cn.SignatureNameSnapshot AS signatureName,
              cn.OrganizerSignatureNameSnapshot AS organizerSignatureName
       FROM ChungNhan cn
       INNER JOIN SuKien sk ON sk.Masukien = cn.Masukien
       LEFT JOIN NguoiDung nd ON nd.Mand = cn.Masv
       WHERE cn.Machungnhan = ?
         AND ((cn.Trangthaichungnhan = 'Đã cấp' AND cn.Ngaycap IS NOT NULL)
           OR cn.EmailTrangthai = 'Đã gửi')
         AND (? = 1 OR EXISTS (
           SELECT 1 FROM DonVi dv
           WHERE dv.Madv = sk.Madv AND dv.Manv = ?
         ))
       LIMIT 1`,
      [request.params.certificateId, isAdmin ? 1 : 0, request.auth.sub],
    );
    if (!certificate) {
      return response.status(404).json({
        message: 'Không tìm thấy chứng nhận đã cấp.',
      });
    }

    const pdf = await createCertificatePdfForRequest(request, certificate);
    response.set({
      'Content-Type': 'application/pdf',
      'Content-Disposition':
        `inline; filename="${certificate.certificateId}.pdf"`,
      'Content-Length': pdf.length,
      'Cache-Control': 'private, no-store',
    });
    return response.send(pdf);
  } catch (error) {
    console.error('Preview staff certificate error:', error.message);
    return response.status(500).json({
      message: 'Không thể xem trước chứng nhận.',
    });
  }
});

// Lấy chứng chỉ từ cơ sở dữ liệu; cán bộ chỉ xem sự kiện thuộc đơn vị mình.
app.get('/api/staff/certificates', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên', 'Cán bộ', 'organizer', 'staff', 'employee'), async (request, response) => {
  const isAdmin = ['Quản trị viên', 'admin'].includes(request.auth.role);
  try {
    const [rows] = await pool.execute(
      `SELECT cn.Machungnhan AS id, candidates.studentId AS studentId,
              COALESCE(nd.Hoten, candidates.studentId) AS studentName,
              sk.Masukien AS eventId, sk.Tensukien AS eventName,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime, sk.Diadiem AS location,
              sk.Thoigianketthuc AS issuedAt,
              COALESCE(cn.Noidung, CONCAT('Giấy chứng nhận tham gia sự kiện ', sk.Tensukien)) AS content,
              cn.EmailTrangthai AS emailStatus,
              CASE
                WHEN LOWER(TRIM(COALESCE(cn.Trangthaichungnhan, ''))) = 'đã cấp'
                  AND cn.Ngaycap IS NOT NULL THEN 'Đã cấp'
                WHEN cn.EmailTrangthai = 'Đã gửi' THEN 'Đã gửi Gmail'
                WHEN cn.EmailTrangthai = 'Đang gửi' THEN 'Đang gửi Gmail'
                WHEN LOWER(TRIM(COALESCE(cn.Trangthaichungnhan, ''))) = 'đang gửi'
                  THEN 'Đang xử lý'
                ELSE 'Chưa cấp'
              END AS status
       FROM (
         SELECT event_id AS eventId, student_id AS studentId
         FROM event_attendance
         UNION
         SELECT event_id AS eventId, student_id AS studentId
         FROM event_attendance_records
         UNION
         SELECT Masukien AS eventId, Masv AS studentId
         FROM ChungNhan
       ) candidates
       JOIN SuKien sk ON sk.Masukien = candidates.eventId
       LEFT JOIN ChungNhan cn
         ON cn.Masv = candidates.studentId
        AND cn.Masukien = candidates.eventId
        AND cn.Machungnhan = (
          SELECT latest.Machungnhan
          FROM ChungNhan latest
          WHERE latest.Masv = candidates.studentId
            AND latest.Masukien = candidates.eventId
          ORDER BY latest.Ngaycap DESC, latest.Machungnhan DESC
          LIMIT 1
        )
       LEFT JOIN NguoiDung nd ON nd.Mand = candidates.studentId
       WHERE (? = 1 OR EXISTS (
         SELECT 1 FROM DonVi dv
         WHERE dv.Madv = sk.Madv AND dv.Manv = ?
       ))
         AND (
           cn.Machungnhan IS NOT NULL
           OR sk.Trangthaisukien = 'Đã đóng'
           OR sk.Thoigianketthuc <= NOW()
         )
       ORDER BY sk.Thoigianketthuc DESC, studentName, candidates.studentId`,
      [isAdmin ? 1 : 0, request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Staff certificates error:', error.message);
    return response.status(500).json({ message: 'Không thể tải danh sách chứng chỉ.' });
  }
});

// Lấy phản hồi và đánh giá thật; dữ liệu cán bộ được giới hạn theo đơn vị phụ trách.
app.get('/api/staff/feedback', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên', 'Cán bộ', 'organizer', 'staff', 'employee'), async (request, response) => {
  const isAdmin = ['Quản trị viên', 'admin'].includes(request.auth.role);
  try {
    const [rows] = await pool.execute(
      `SELECT CONCAT('PH-', ph.Maphanhoi) AS id, 'Ý kiến' AS sourceType,
              ph.Noidung AS content, ph.Thoigiangui AS sentAt,
              ph.Masv AS studentId, COALESCE(nd.Hoten, ph.Masv) AS studentName,
              ph.Masukien AS eventId, COALESCE(sk.Tensukien, '') AS eventName,
              ph.Malop AS classId, COALESCE(lhp.Tenlop, '') AS className,
              NULL AS rating
       FROM PhanHoi ph
       LEFT JOIN NguoiDung nd ON nd.Mand = ph.Masv
       LEFT JOIN SuKien sk ON sk.Masukien = ph.Masukien
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = ph.Malop
       WHERE (? = 1 OR (ph.Masukien IS NOT NULL AND EXISTS (
         SELECT 1 FROM DonVi dv
         WHERE dv.Madv = sk.Madv AND dv.Manv = ?
       )))
       UNION ALL
       SELECT CONCAT('DG-', dg.Madanhgia) AS id, 'Đánh giá' AS sourceType,
              COALESCE(dg.Noidung, '') AS content,
              dg.Thoigiandanhgia AS sentAt,
              dg.Masv AS studentId, COALESCE(nd.Hoten, dg.Masv) AS studentName,
              dg.Masukien AS eventId, COALESCE(sk.Tensukien, '') AS eventName,
              dg.Malop AS classId, COALESCE(lhp.Tenlop, '') AS className,
              dg.Sosao AS rating
       FROM DanhGia dg
       LEFT JOIN NguoiDung nd ON nd.Mand = dg.Masv
       LEFT JOIN SuKien sk ON sk.Masukien = dg.Masukien
       LEFT JOIN LopHocPhan lhp ON lhp.Malop = dg.Malop
       WHERE (? = 1 OR (dg.Masukien IS NOT NULL AND EXISTS (
         SELECT 1 FROM DonVi dv
         WHERE dv.Madv = sk.Madv AND dv.Manv = ?
       )))
       ORDER BY sentAt DESC, id DESC`,
      [isAdmin ? 1 : 0, request.auth.sub, isAdmin ? 1 : 0, request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Staff feedback error:', error.message);
    return response.status(500).json({ message: 'Không thể tải phản hồi.' });
  }
});

// Lấy danh sách người dùng cho khu vực quản trị.
app.get('/api/admin/users', requireAuth, requireRole('Quản trị viên', 'admin'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
            `SELECT nd.Mand AS id, nd.Hoten AS name,
              nd.Email AS email, nd.Vaitro AS role,
              nd.Trangthaind AS status
             FROM NguoiDung nd ORDER BY nd.Hoten`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin users error:', error.message);
    return response.status(500).json({ message: 'Không thể tải người dùng.' });
  }
});

app.post('/api/admin/users', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const body = request.body || {};
  const id = String(body.id || '').trim();
  const name = String(body.name || '').trim();
  const email = String(body.email || '').trim().toLowerCase();
  const password = String(body.password || '');
  const roleByValue = new Map([
    ['student', 'Sinh viên'],
    ['sinhvien', 'Sinh viên'],
    ['lecturer', 'Giảng viên'],
    ['giangvien', 'Giảng viên'],
    ['employee', 'Cán bộ'],
    ['canbo', 'Cán bộ'],
  ]);
  const normalizeRequestedRole = (value) => String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z]/g, '');
  const role = roleByValue.get(normalizeRequestedRole(body.role));
  const className = String(body.className || '').trim();
  const major = String(body.major || '').trim();
  const subjectDepartment = String(body.subjectDepartment || '').trim();
  const position = String(body.position || '').trim();

  if (!id || !name || !email || !password || !role) {
    return response.status(400).json({
      message: 'Vui lòng nhập mã, họ tên, email, mật khẩu và vai trò hợp lệ.',
    });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 8) {
    return response.status(400).json({
      message: 'Email không hợp lệ hoặc mật khẩu chưa đủ 8 ký tự.',
    });
  }
  if (role === 'Sinh viên' && (!className || !major)) {
    return response.status(400).json({
      message: 'Sinh viên cần có lớp và chuyên ngành.',
    });
  }
  if (role === 'Giảng viên' && !subjectDepartment) {
    return response.status(400).json({ message: 'Giảng viên cần có bộ môn.' });
  }
  if (role === 'Cán bộ' && !position) {
    return response.status(400).json({ message: 'Cán bộ cần có chức vụ.' });
  }

  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[duplicate]] = await connection.execute(
      'SELECT Mand AS id FROM NguoiDung WHERE Mand = ? OR LOWER(Email) = ? LIMIT 1',
      [id, email],
    );
    if (duplicate) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Mã tài khoản hoặc email đã tồn tại.',
      });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    await connection.execute(
      `INSERT INTO NguoiDung
        (Mand, Hoten, Email, Matkhau, Vaitro, Trangthaind, SDT, DiaChi, NgaySinh, GioiTinh, QueQuan)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, name, email, passwordHash, role, 'Đang hoạt động', null, null, null, null, null],
    );
    if (role === 'Sinh viên') {
      await connection.execute(
        'INSERT INTO SinhVien (Masv, Lop, Chuyennganh) VALUES (?, ?, ?)',
        [id, className, major],
      );
    } else if (role === 'Giảng viên') {
      await connection.execute(
        'INSERT INTO GiangVien (Magv, BoMon) VALUES (?, ?)',
        [id, subjectDepartment],
      );
    } else {
      await connection.execute(
        'INSERT INTO CongNhanVien (Manv, Chucvu) VALUES (?, ?)',
        [id, position],
      );
    }
    await connection.commit();
    return response.status(201).json({
      user: { id, name, email, role, status: 'Đang hoạt động' },
    });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Admin user creation error:', error.message);
    if (error.code === 'ER_DUP_ENTRY') {
      return response.status(409).json({
        message: 'Mã tài khoản hoặc email đã tồn tại.',
      });
    }
    return response.status(500).json({
      message: 'Không thể tạo tài khoản.',
    });
  } finally {
    if (connection) connection.release();
  }
});

app.post('/api/admin/master-data/import', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const { units, users } = request.body || {};
  if (!Array.isArray(units) || !Array.isArray(users)
      || units.length > 500 || users.length > 500
      || (units.length === 0 && users.length === 0)) {
    return response.status(400).json({
      message: 'File cần có ít nhất một đơn vị hoặc tài khoản, tối đa 500 dòng mỗi sheet.',
    });
  }

  const unitIds = new Set();
  for (const [index, unit] of units.entries()) {
    const id = String(unit?.id || '').trim();
    const name = String(unit?.name || '').trim();
    if (!id || !name) {
      return response.status(400).json({
        message: `Đơn vị ở dòng ${index + 2} cần có mã và tên.`,
      });
    }
    if (unitIds.has(id.toLocaleLowerCase())) {
      return response.status(400).json({ message: `Mã đơn vị "${id}" bị lặp trong file.` });
    }
    unitIds.add(id.toLocaleLowerCase());
  }

  const userIds = new Set();
  const userEmails = new Set();
  const allowedRoles = new Map([
    ['sinhvien', 'Sinh viên'],
    ['student', 'Sinh viên'],
    ['giangvien', 'Giảng viên'],
    ['lecturer', 'Giảng viên'],
    ['canbo', 'Cán bộ'],
    ['nhanvien', 'Cán bộ'],
    ['employee', 'Cán bộ'],
  ]);
  const normalizeImportRole = (value) => String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z]/g, '');
  for (const [index, user] of users.entries()) {
    const id = String(user?.id || '').trim();
    const name = String(user?.name || '').trim();
    const email = String(user?.email || '').trim().toLowerCase();
    const password = String(user?.password || '');
    const role = allowedRoles.get(normalizeImportRole(user?.role));
    if (!id || !name || !email || !password || !role) {
      return response.status(400).json({
        message: `Tài khoản ở dòng ${index + 2} thiếu thông tin bắt buộc hoặc có vai trò không hợp lệ.`,
      });
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 8) {
      return response.status(400).json({
        message: `Tài khoản ở dòng ${index + 2} cần email hợp lệ và mật khẩu từ 8 ký tự.`,
      });
    }
    if (userIds.has(id.toLocaleLowerCase()) || userEmails.has(email)) {
      return response.status(400).json({
        message: `Mã tài khoản hoặc email bị lặp ở dòng ${index + 2}.`,
      });
    }
    userIds.add(id.toLocaleLowerCase());
    userEmails.add(email);
    if (role === 'Sinh viên' && (!String(user.className || '').trim() || !String(user.major || '').trim())) {
      return response.status(400).json({
        message: `Sinh viên ở dòng ${index + 2} cần có lớp và chuyên ngành.`,
      });
    }
    if (role === 'Giảng viên' && !String(user.subjectDepartment || '').trim()) {
      return response.status(400).json({
        message: `Giảng viên ở dòng ${index + 2} cần có bộ môn.`,
      });
    }
    if (role === 'Cán bộ' && !String(user.position || '').trim()) {
      return response.status(400).json({
        message: `Cán bộ ở dòng ${index + 2} cần có chức vụ.`,
      });
    }
    user.normalizedRole = role;
    user.normalizedEmail = email;
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    for (const [index, user] of users.entries()) {
      const { id, name, password, normalizedRole } = user;
      const email = user.normalizedEmail;
      const status = String(user.status || 'Đang hoạt động').trim();
      if (!['Đang hoạt động', 'Đã khóa'].includes(status)) {
        throw new Error(`Trạng thái tài khoản ở dòng ${index + 2} không hợp lệ.`);
      }

      const [[duplicate]] = await connection.execute(
        'SELECT Mand AS id FROM NguoiDung WHERE Mand = ? OR LOWER(Email) = ? LIMIT 1',
        [id.trim(), email],
      );
      if (duplicate) {
        throw new Error(`Mã tài khoản hoặc email đã tồn tại: ${id.trim()} / ${email}.`);
      }

      const passwordHash = await bcrypt.hash(password, 10);
      await connection.execute(
        `INSERT INTO NguoiDung
          (Mand, Hoten, Email, Matkhau, Vaitro, Trangthaind, SDT, DiaChi, NgaySinh, GioiTinh, QueQuan)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          id.trim(),
          name.trim(),
          email,
          passwordHash,
          normalizedRole,
          status,
          String(user.phone || '').trim() || null,
          String(user.address || '').trim() || null,
          String(user.birthDate || '').trim() || null,
          String(user.gender || '').trim() || null,
          String(user.hometown || '').trim() || null,
        ],
      );

      if (normalizedRole === 'Sinh viên') {
        await connection.execute(
          'INSERT INTO SinhVien (Masv, Lop, Chuyennganh) VALUES (?, ?, ?)',
          [id.trim(), String(user.className).trim(), String(user.major).trim()],
        );
      } else if (normalizedRole === 'Giảng viên') {
        await connection.execute(
          'INSERT INTO GiangVien (Magv, BoMon) VALUES (?, ?)',
          [id.trim(), String(user.subjectDepartment).trim()],
        );
      } else {
        await connection.execute(
          'INSERT INTO CongNhanVien (Manv, Chucvu) VALUES (?, ?)',
          [id.trim(), String(user.position || '').trim() || null],
        );
      }
    }

    for (const [index, unit] of units.entries()) {
      const id = String(unit.id).trim();
      const name = String(unit.name).trim();
      const managerId = String(unit.managerId || '').trim() || null;
      const [[duplicate]] = await connection.execute(
        'SELECT Madv AS id FROM DonVi WHERE Madv = ? LIMIT 1',
        [id],
      );
      if (duplicate) throw new Error(`Mã đơn vị đã tồn tại: ${id}.`);

      if (managerId) {
        const [[manager]] = await connection.execute(
          `SELECT nd.Mand AS id FROM NguoiDung nd
           INNER JOIN CongNhanVien cnv ON cnv.Manv = nd.Mand
           WHERE nd.Mand = ? AND nd.Vaitro IN ('Cán bộ', 'organizer') LIMIT 1`,
          [managerId],
        );
        if (!manager) {
          throw new Error(`Đơn vị ở dòng ${index + 2}: mã nhân viên phụ trách "${managerId}" không tồn tại.`);
        }
      }
      await connection.execute(
        'INSERT INTO DonVi (Madv, Tendv, Manv) VALUES (?, ?, ?)',
        [id, name, managerId],
      );
    }

    await connection.commit();
    return response.json({
      importedUnits: units.length,
      importedUsers: users.length,
    });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Admin master data import error:', error.message);
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 400;
    return response.status(status).json({
      message: error.message || 'Không thể nhập đơn vị và tài khoản.',
    });
  } finally {
    if (connection) connection.release();
  }
});

// Lấy danh sách lớp học phần cho khu vực quản trị.
app.get('/api/admin/classes', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (request, response) => {
  const isAdmin = isAdminAuth(request.auth);
  try {
    const [rows] = await pool.execute(
      `SELECT lhp.Malop AS id, lhp.Malop AS code, lhp.Tenlop AS name,
              lhp.Magv AS lecturerId, lhp.Madv AS departmentId,
              mh.Mabomon AS majorId, bm.Tenbomon AS majorName,
              bm.Maloptat AS majorAbbreviation, lhp.Makhoa AS cohortCode,
              lhp.Mamon AS subjectId, mh.Mamon AS subjectCode,
              mh.Tenmon AS subjectName, lhp.Tinchi AS credits,
              lhp.Soluongtoida AS capacity,
              lhp.Thoigianbatdau AS startTime,
              lhp.Hocky AS semester,
              lhp.Trangthailop AS status,
              COALESCE(nd.Hoten, '') AS lecturerName,
              COUNT(tvl.Masv) AS studentCount
       FROM LopHocPhan lhp
       INNER JOIN MonHoc mh ON mh.Mamon = lhp.Mamon
       INNER JOIN BoMon bm ON bm.Mabomon = mh.Mabomon
       LEFT JOIN GiangVien gv ON gv.Magv = lhp.Magv
       LEFT JOIN NguoiDung nd ON nd.Mand = gv.Magv
       LEFT JOIN ThanhVienLop tvl ON tvl.Malop = lhp.Malop
       ${isAdmin ? '' : 'WHERE lhp.Magv = ?'}
       GROUP BY lhp.Malop, lhp.Tenlop, lhp.Magv, lhp.Madv, mh.Mabomon,
                bm.Tenbomon, bm.Maloptat, lhp.Makhoa, lhp.Mamon, mh.Mamon,
                mh.Tenmon, lhp.Tinchi, lhp.Soluongtoida,
                lhp.Thoigianbatdau, lhp.Hocky, lhp.Trangthailop, nd.Hoten
       ORDER BY lhp.Malop`,
      isAdmin ? [] : [request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin classes error:', error.message);
    return response.status(500).json({ message: 'Không thể tải lớp học.' });
  }
});

app.get('/api/admin/classes/:classId/students', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (request, response) => {
  const isAdmin = isAdminAuth(request.auth);
  try {
    const [[classInfo]] = await pool.execute(
      'SELECT Malop AS id, Magv AS lecturerId FROM LopHocPhan WHERE Malop = ? LIMIT 1',
      [request.params.classId],
    );
    if (!classInfo) {
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    if (!isAdmin && String(classInfo.lecturerId) !== String(request.auth.sub)) {
      return response.status(403).json({
        message: 'Bạn không phụ trách lớp học này.',
      });
    }

    const [rows] = await pool.execute(
      `SELECT tvl.Masv AS studentId,
              COALESCE(nd.Hoten, tvl.Masv) AS studentName,
              COALESCE(nd.Email, '') AS email,
              COALESCE(tvl.TrangThaiThanhVien, '') AS status,
              DATE_FORMAT(tvl.NgayThamGia, '%d/%m/%Y') AS dateLabel
       FROM ThanhVienLop tvl
       LEFT JOIN NguoiDung nd ON nd.Mand = tvl.Masv
       WHERE tvl.Malop = ?
       ORDER BY nd.Hoten, tvl.Masv`,
      [request.params.classId],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Class students error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải danh sách sinh viên của lớp.',
    });
  }
});

// Nhập danh sách sinh viên đã có trong hệ thống vào một lớp học phần.
app.post('/api/admin/classes/:classId/students/import', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const { studentIds } = request.body || {};
  if (!Array.isArray(studentIds) || studentIds.length === 0 || studentIds.length > 2000) {
    return response.status(400).json({
      message: 'Danh sách mã sinh viên phải có từ 1 đến 2.000 mã.',
    });
  }
  if (studentIds.some((id) => typeof id !== 'string' || !id.trim() || id.trim().length > 64)) {
    return response.status(400).json({
      message: 'Danh sách chứa mã sinh viên không hợp lệ.',
    });
  }

  const uniqueIdsByKey = new Map();
  for (const studentId of studentIds) {
    const normalizedId = studentId.trim();
    const key = normalizedId.toUpperCase();
    if (!uniqueIdsByKey.has(key)) uniqueIdsByKey.set(key, normalizedId);
  }
  const normalizedIds = [...uniqueIdsByKey.values()];
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();

    const [[classInfo]] = await connection.execute(
      `SELECT Malop, Magv AS lecturerId, Trangthailop AS status,
              (Thoigianbatdau < DATE_SUB(NOW(), INTERVAL 1 YEAR)) AS isArchived
       FROM LopHocPhan WHERE Malop = ? FOR UPDATE`,
      [request.params.classId],
    );
    if (!classInfo) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    if (!['Quản trị viên', 'admin'].includes(request.auth.role)
        && String(classInfo.lecturerId) !== String(request.auth.sub)) {
      await connection.rollback();
      return response.status(403).json({
        message: 'Bạn chỉ được thêm sinh viên vào lớp mình phụ trách.',
      });
    }
    if (classInfo.status === 'Đã đóng' || Number(classInfo.isArchived)) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Lớp đã đóng hoặc đã quá 1 năm nên không thể thêm sinh viên.',
      });
    }

    const placeholders = normalizedIds.map(() => '?').join(', ');
    const [students] = await connection.execute(
      `SELECT Masv FROM SinhVien WHERE Masv IN (${placeholders})`,
      normalizedIds,
    );
    const knownIds = new Set(students.map((student) => String(student.Masv).toUpperCase()));
    const unknownStudentIds = normalizedIds.filter((id) => !knownIds.has(id.toUpperCase()));
    const validIds = normalizedIds.filter((id) => knownIds.has(id.toUpperCase()));

    let existingIds = new Set();
    if (validIds.length > 0) {
      const validPlaceholders = validIds.map(() => '?').join(', ');
      const [existingMembers] = await connection.execute(
        `SELECT Masv FROM ThanhVienLop
         WHERE Malop = ? AND Masv IN (${validPlaceholders})`,
        [classInfo.Malop, ...validIds],
      );
      existingIds = new Set(
        existingMembers.map((student) => String(student.Masv).toUpperCase()),
      );
    }

    const newIds = validIds.filter((id) => !existingIds.has(id));
    for (let offset = 0; offset < newIds.length; offset += 250) {
      const batch = newIds.slice(offset, offset + 250);
      const values = batch.map(() => '(?, ?, CURRENT_DATE, ?)').join(', ');
      await connection.execute(
        `INSERT INTO ThanhVienLop (Malop, Masv, NgayThamGia, TrangThaiThanhVien)
         VALUES ${values}`,
        batch.flatMap((studentId) => [
          classInfo.Malop,
          studentId,
          'Đang tham gia',
        ]),
      );
    }

    await connection.commit();
    return response.status(200).json({
      importedCount: newIds.length,
      alreadyMemberCount: existingIds.size,
      unknownStudentIds,
    });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Import class students error:', error.message);
    return response.status(500).json({ message: 'Không thể nhập sinh viên vào lớp.' });
  } finally {
    if (connection) connection.release();
  }
});

app.get('/api/admin/class-options', requireAuth, requireRole('Quản trị viên', 'admin'), async (_request, response) => {
  try {
    const [cohorts] = await pool.query(
      `SELECT MaKhoa AS code FROM QuyUocKhoa
       UNION
       SELECT DISTINCT MaKhoa AS code FROM SinhVien
       ORDER BY code DESC`,
    );
    const [subjects] = await pool.query(
      `SELECT mh.Mamon AS id, mh.Mamon AS code, mh.Tenmon AS name,
              mh.Sotinchi AS credits,
              mh.Hocky AS semester, bm.Mabomon AS majorId,
              bm.Tenbomon AS majorName, bm.Madv AS departmentId
       FROM MonHoc mh
       INNER JOIN BoMon bm ON bm.Mabomon = mh.Mabomon
       ORDER BY mh.Tenmon, mh.Mamon`,
    );
    return response.json({ cohorts, subjects });
  } catch (error) {
    console.error('Admin class options error:', error.message);
    return response.status(500).json({ message: 'Không thể tải môn học và khóa sinh viên.' });
  }
});

app.get('/api/admin/lecturers', requireAuth, requireRole('Quản trị viên', 'admin'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
      `SELECT gv.Magv AS id, COALESCE(nd.Hoten, gv.Magv) AS name
       FROM GiangVien gv
       LEFT JOIN NguoiDung nd ON nd.Mand = gv.Magv
       ORDER BY name`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin lecturers error:', error.message);
    return response.status(500).json({ message: 'Không thể tải danh sách giảng viên.' });
  }
});

app.post('/api/admin/classes', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const {
    name,
    subjectId,
    cohortCode,
    semester,
    startTime,
    lecturerId = null,
    capacity,
  } = request.body || {};
  const normalizedName = typeof name === 'string' ? name.trim() : '';
  const normalizedSubjectId = typeof subjectId === 'string' ? subjectId.trim() : '';
  const normalizedCohortCode = typeof cohortCode === 'string' ? cohortCode.trim() : '';
  const normalizedStartTime = normalizeDateTime(startTime);
  const parsedCapacity = Number(capacity);
  if (!normalizedName || !normalizedSubjectId || !normalizedCohortCode || !normalizedStartTime) {
    return response.status(400).json({
      message: 'Tên lớp, môn học, khóa sinh viên và thời gian bắt đầu là bắt buộc.',
    });
  }
  if (!Number.isInteger(parsedCapacity) || parsedCapacity < 1) {
    return response.status(400).json({ message: 'Sĩ số tối đa phải là số nguyên lớn hơn 0.' });
  }
  const requestedSemester = typeof semester === 'string' ? semester.trim() : '';
  if (requestedSemester && !['HK1', 'HK2', 'HK3'].includes(requestedSemester)) {
    return response.status(400).json({ message: 'Học kỳ không hợp lệ.' });
  }
  const normalizedLecturerId = typeof lecturerId === 'string' && lecturerId.trim()
    ? lecturerId.trim()
    : null;

  try {
    const [[subject]] = await pool.execute(
      `SELECT mh.Mamon, mh.Hocky, bm.Madv AS departmentId
       FROM MonHoc mh
       INNER JOIN BoMon bm ON bm.Mabomon = mh.Mabomon
       WHERE mh.Mamon = ?`,
      [normalizedSubjectId],
    );
    if (!subject) {
      return response.status(400).json({ message: 'Môn học đã chọn không tồn tại.' });
    }
    const [cohorts] = await pool.execute(
      `SELECT MaKhoa FROM QuyUocKhoa WHERE MaKhoa = ?
       UNION
       SELECT MaKhoa FROM SinhVien WHERE MaKhoa = ? LIMIT 1`,
      [normalizedCohortCode, normalizedCohortCode],
    );
    if (cohorts.length === 0) {
      return response.status(400).json({ message: 'Khóa sinh viên đã chọn không tồn tại.' });
    }
    const normalizedSemester = requestedSemester || `HK${subject.Hocky}`;

    await pool.execute(
      `INSERT INTO LopHocPhan
       (Malop, Magv, Madv, Mamon, Makhoa, Tenlop, Hocky, Namhoc,
        Soluongtoida, Trangthailop, Thoigianbatdau)
       VALUES ('', ?, ?, ?, ?, ?, ?, ?, ?, 'Đang học', ?)`,
      [normalizedLecturerId, subject.departmentId, normalizedSubjectId,
        normalizedCohortCode, normalizedName, normalizedSemester,
        academicYearFromDateTime(normalizedStartTime),
        parsedCapacity, normalizedStartTime],
    );
    return response.status(201).json({ message: 'Tạo lớp thành công.' });
  } catch (error) {
    if (error.code === 'ER_NO_REFERENCED_ROW_2') {
      return response.status(400).json({ message: 'Giảng viên không tồn tại.' });
    }
    if (error.sqlState === '45000') {
      const message = error.sqlMessage || 'Không thể tạo lớp theo quy tắc cơ sở dữ liệu.';
      const status = message.includes('giới hạn 99 lớp') ? 409 : 400;
      return response.status(status).json({ message });
    }
    console.error('Create admin class error:', error.message);
    return response.status(500).json({ message: 'Không thể tạo lớp.' });
  }
});

app.put('/api/admin/classes/:classId', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const {
    name,
    semester,
    startTime,
    lecturerId = null,
    capacity,
  } = request.body || {};
  const parsedCapacity = Number(capacity);
  if (typeof name !== 'string' || !name.trim()) {
    return response.status(400).json({
      message: 'Vui lòng nhập tên lớp hợp lệ.',
    });
  }
  if (!Number.isInteger(parsedCapacity) || parsedCapacity < 1) {
    return response.status(400).json({ message: 'Sĩ số tối đa phải là số nguyên lớn hơn 0.' });
  }
  const normalizedStartTime = normalizeDateTime(startTime);
  if (!['HK1', 'HK2', 'HK3'].includes(semester)
      || !normalizedStartTime) {
    return response.status(400).json({
      message: 'Học kỳ hoặc thời gian bắt đầu không hợp lệ.',
    });
  }
  const normalizedLecturerId = typeof lecturerId === 'string' && lecturerId.trim()
    ? lecturerId.trim()
    : null;
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[existing]] = await connection.execute(
      `SELECT Malop, Trangthailop AS status,
              (Thoigianbatdau < DATE_SUB(NOW(), INTERVAL 1 YEAR)) AS isArchived
       FROM LopHocPhan WHERE Malop = ? FOR UPDATE`,
      [request.params.classId],
    );
    if (!existing) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    if (existing.status === 'Đã đóng' || Number(existing.isArchived)) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Lớp đã đóng hoặc đã quá 1 năm nên không thể chỉnh sửa.',
      });
    }
    const [[memberCount]] = await connection.execute(
      'SELECT COUNT(*) AS total FROM ThanhVienLop WHERE Malop = ?',
      [request.params.classId],
    );
    if (parsedCapacity < Number(memberCount.total)) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Sĩ số tối đa không thể thấp hơn số sinh viên hiện có.',
      });
    }
    await connection.execute(
      `UPDATE LopHocPhan
         SET Magv = ?, Tenlop = ?, Hocky = ?, Namhoc = ?, Thoigianbatdau = ?,
             Soluongtoida = ?
       WHERE Malop = ?`,
      [
        normalizedLecturerId,
        name.trim(),
        semester,
        academicYearFromDateTime(normalizedStartTime),
        normalizedStartTime,
        parsedCapacity,
        request.params.classId,
      ],
    );
    await connection.commit();
    return response.json({ message: 'Cập nhật lớp thành công.' });
  } catch (error) {
    if (connection) await connection.rollback();
    if (error.code === 'ER_NO_REFERENCED_ROW_2') {
      return response.status(400).json({ message: 'Giảng viên không tồn tại.' });
    }
    console.error('Update admin class error:', error.message);
    return response.status(500).json({ message: 'Không thể cập nhật lớp.' });
  } finally {
    connection?.release();
  }
});

app.post('/api/admin/classes/:classId/close', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  try {
    const [result] = await pool.execute(
      `UPDATE LopHocPhan SET Trangthailop = 'Đã đóng'
       WHERE Malop = ? AND COALESCE(Trangthailop, '') <> 'Đã đóng'`,
      [request.params.classId],
    );
    if (result.affectedRows === 0) {
      const [[classInfo]] = await pool.execute(
        'SELECT Malop FROM LopHocPhan WHERE Malop = ? LIMIT 1',
        [request.params.classId],
      );
      if (!classInfo) return response.status(404).json({ message: 'Không tìm thấy lớp.' });
      return response.status(409).json({ message: 'Lớp đã được đóng.' });
    }
    return response.json({ message: 'Đóng lớp thành công.' });
  } catch (error) {
    console.error('Close admin class error:', error.message);
    return response.status(500).json({ message: 'Không thể đóng lớp.' });
  }
});

app.delete('/api/admin/classes/:classId', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[existing]] = await connection.execute(
      'SELECT Malop FROM LopHocPhan WHERE Malop = ? FOR UPDATE',
      [request.params.classId],
    );
    if (!existing) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    const [[dependencies]] = await connection.execute(
      `SELECT
         (SELECT COUNT(*) FROM ThanhVienLop WHERE Malop = ?) AS members,
         (SELECT COUNT(*) FROM Buoi WHERE Malop = ?) AS sessions`,
      [request.params.classId, request.params.classId],
    );
    if (Number(dependencies.members) > 0 || Number(dependencies.sessions) > 0) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Không thể xóa lớp đang có thành viên hoặc buổi học.',
      });
    }
    await connection.execute(
      'DELETE FROM LopHocPhan WHERE Malop = ?',
      [request.params.classId],
    );
    await connection.commit();
    return response.json({ message: 'Xóa lớp thành công.' });
  } catch (error) {
    if (connection) await connection.rollback();
    console.error('Delete admin class error:', error.message);
    return response.status(409).json({
      message: 'Không thể xóa lớp đang được dữ liệu khác tham chiếu.',
    });
  } finally {
    connection?.release();
  }
});

// Lấy danh sách sự kiện và số lượng đăng ký cho khu vực quản trị.
app.get('/api/admin/events', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Cán bộ', 'Nhân viên'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
            `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Diadiem AS location, sk.Thoigianbatdau AS startTime,
              ${eventStatusSql} AS status,
              COUNT(dk.Masv) AS registeredCount
             FROM SuKien sk
             LEFT JOIN DangKySuKien dk ON dk.Masukien = sk.Masukien
             GROUP BY sk.Masukien, sk.Tensukien, sk.Diadiem,
          sk.Thoigianbatdau, sk.Thoigianketthuc, sk.Trangthaisukien
            ORDER BY sk.Thoigianbatdau`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin events error:', error.message);
    return response.status(500).json({ message: 'Không thể tải sự kiện.' });
  }
});

app.put('/api/admin/settings/early-attendance', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const { allowEarlyAttendance } = request.body || {};
  if (typeof allowEarlyAttendance !== 'boolean') {
    return response.status(400).json({
      message: 'Trạng thái cho phép mở điểm danh sớm không hợp lệ.',
    });
  }
  try {
    await pool.execute(
      `INSERT INTO system_parameters
         (scope_type, scope_id, allow_early_attendance, updated_by)
       VALUES ('global', '', ?, ?)
       ON DUPLICATE KEY UPDATE
         allow_early_attendance = VALUES(allow_early_attendance),
         updated_by = VALUES(updated_by)`,
      [allowEarlyAttendance ? 1 : 0, request.auth.sub],
    );
    return response.json({ allowEarlyAttendance });
  } catch (error) {
    console.error('Save early attendance setting error:', error.message);
    return response.status(500).json({
      message: 'Không thể lưu cài đặt mở điểm danh sớm.',
    });
  }
});

app.put('/api/admin/settings/overlapping-event-attendance', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const { allowOverlappingEventAttendance } = request.body || {};
  if (typeof allowOverlappingEventAttendance !== 'boolean') {
    return response.status(400).json({
      message: 'Trạng thái cho phép điểm danh sự kiện trùng lịch không hợp lệ.',
    });
  }
  try {
    await pool.execute(
      `INSERT INTO system_parameters
         (scope_type, scope_id, allow_overlapping_event_attendance, updated_by)
       VALUES ('global', '', ?, ?)
       ON DUPLICATE KEY UPDATE
         allow_overlapping_event_attendance = VALUES(allow_overlapping_event_attendance),
         updated_by = VALUES(updated_by)`,
      [allowOverlappingEventAttendance ? 1 : 0, request.auth.sub],
    );
    return response.json({ allowOverlappingEventAttendance });
  } catch (error) {
    console.error('Save overlapping event attendance setting error:', error.message);
    return response.status(500).json({
      message: 'Không thể lưu cài đặt điểm danh sự kiện trùng lịch.',
    });
  }
});

app.get('/api/admin/settings/parameters/options', requireAuth, requireRole('Quản trị viên', 'admin'), async (_request, response) => {
  try {
    const [classes] = await pool.query(
      `SELECT lhp.Malop AS id, lhp.Tenlop AS name,
              COALESCE(mh.Tenmon, '') AS subjectName
       FROM LopHocPhan lhp
       LEFT JOIN MonHoc mh ON mh.Mamon = lhp.Mamon
       ORDER BY lhp.Tenlop, lhp.Malop`,
    );
    const [events] = await pool.query(
      `SELECT Masukien AS id, Tensukien AS name, Thoigianbatdau AS startTime
       FROM SuKien ORDER BY Thoigianbatdau DESC`,
    );
    return response.json({ classes, events });
  } catch (error) {
    console.error('Parameter options error:', error.message);
    return response.status(500).json({ message: 'Không thể tải danh sách lớp và sự kiện.' });
  }
});

app.get('/api/admin/settings/parameters', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const scopeType = String(request.query.scopeType || 'global');
  const scopeId = String(request.query.scopeId || '').trim();
  if (!['global', 'class', 'event', 'all_classes', 'all_events'].includes(scopeType)
      || (['class', 'event'].includes(scopeType) && !scopeId)) {
    return response.status(400).json({ message: 'Phạm vi cấu hình không hợp lệ.' });
  }
  try {
    if (scopeType === 'class') {
      const [[item]] = await pool.execute(
        'SELECT Malop FROM LopHocPhan WHERE Malop = ? LIMIT 1', [scopeId],
      );
      if (!item) return response.status(404).json({ message: 'Không tìm thấy lớp học phần.' });
    } else if (scopeType === 'event') {
      const [[item]] = await pool.execute(
        'SELECT Masukien FROM SuKien WHERE Masukien = ? LIMIT 1', [scopeId],
      );
      if (!item) return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    return response.json(await getEffectiveAttendanceParameters(scopeType, scopeId));
  } catch (error) {
    console.error('Read parameters error:', error.message);
    return response.status(500).json({ message: 'Không thể tải tham số hệ thống.' });
  }
});

app.put('/api/admin/settings/parameters', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const scopeType = String(request.body?.scopeType || '');
  const scopeId = ['global', 'all_classes', 'all_events'].includes(scopeType)
    ? ''
    : String(request.body?.scopeId || '').trim();
  const body = request.body || {};
  if (!['global', 'class', 'event', 'all_classes', 'all_events'].includes(scopeType)
      || (['class', 'event'].includes(scopeType) && !scopeId)) {
    return response.status(400).json({ message: 'Phạm vi cấu hình không hợp lệ.' });
  }
  const values = {
    gpsRadiusMeters: body.gpsRadiusMeters,
    eventRegistrationLockHours: body.eventRegistrationLockHours,
    qrDurationMinutes: body.qrDurationMinutes,
  };
  const ranges = {
    gpsRadiusMeters: [10, 5000],
    eventRegistrationLockHours: [0, 720],
    qrDurationMinutes: [1, 180],
    attendanceThresholdPercent: [0, 100],
  };
  for (const [key, [minimum, maximum]] of Object.entries(ranges)) {
    if (['class', 'all_classes'].includes(scopeType)
        && key === 'eventRegistrationLockHours') {
      if (values[key] !== null && values[key] !== undefined) {
        return response.status(400).json({ message: 'Thời gian khóa đăng ký chỉ áp dụng cho phạm vi sự kiện.' });
      }
      values[key] = null;
      continue;
    }
    if (values[key] === null || values[key] === undefined || values[key] === '') {
      if (scopeType === 'global') {
        return response.status(400).json({ message: 'Cấu hình toàn hệ thống cần đủ ba tham số.' });
      }
      values[key] = null;
      continue;
    }
    const parsed = Number(values[key]);
    if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
      return response.status(400).json({
        message: `${key} phải là số nguyên từ ${minimum} đến ${maximum}.`,
      });
    }
    values[key] = parsed;
  }
  try {
    if (scopeType === 'class') {
      const [[item]] = await pool.execute(
        'SELECT Malop FROM LopHocPhan WHERE Malop = ? LIMIT 1', [scopeId],
      );
      if (!item) return response.status(404).json({ message: 'Không tìm thấy lớp học phần.' });
    } else if (scopeType === 'event') {
      const [[item]] = await pool.execute(
        'SELECT Masukien FROM SuKien WHERE Masukien = ? LIMIT 1', [scopeId],
      );
      if (!item) return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    await pool.execute(
      `INSERT INTO system_parameters
         (scope_type, scope_id, gps_radius_meters,
          event_registration_lock_hours, qr_duration_minutes, updated_by)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         gps_radius_meters = VALUES(gps_radius_meters),
         event_registration_lock_hours = VALUES(event_registration_lock_hours),
         qr_duration_minutes = VALUES(qr_duration_minutes),
         updated_by = VALUES(updated_by)`,
      [scopeType, scopeId, values.gpsRadiusMeters,
        values.eventRegistrationLockHours, values.qrDurationMinutes,
        request.auth.sub],
    );
    return response.json(await getEffectiveAttendanceParameters(scopeType, scopeId));
  } catch (error) {
    console.error('Save parameters error:', error.message);
    return response.status(500).json({ message: 'Không thể lưu tham số hệ thống.' });
  }
});

ensureAttendanceLocationColumns()
  .then(async () => {
    await ensureSystemParametersTable();
    await ensureCertificateSignatureTable();
    await ensureEventStatusColumn();
    await ensureEventImageColumn();
    await ensureEventRegistrationFormColumn();
    await ensureEventCertificateColumn();
    await ensureEventAttendanceThresholdColumn();
    await ensureCertificateEmailColumns();
    await ensureCertificateSignatureSnapshots();
    await ensurePasswordResetChallengesTable();
    await ensureUserFcmTokensTable();
    await ensureAttendanceDeviceClaimsTable();
    await ensureEventAttendanceTable();
    await ensureEventAttendanceSessionsTable();
    await ensureEventAttendancePeriodsTable();
    await synchronizeEventStatuses();
    await closeExpiredClassAttendanceSessions();
    await recordExpiredClassAbsences();
    const statusSyncTimer = setInterval(() => {
      synchronizeEventStatuses().catch((error) => {
        console.error('Event status sync failed:', error.message);
      });
    }, 60_000);
    statusSyncTimer.unref();
    const classAbsenceTimer = setInterval(() => {
      recordExpiredClassAbsences().catch((error) => {
        console.error('Class absence recording failed:', error.message);
      });
    }, 60_000);
    classAbsenceTimer.unref();
    const attendanceExpiryTimer = setInterval(() => {
      closeExpiredClassAttendanceSessions().catch((error) => {
        console.error('Attendance session expiry failed:', error.message);
      });
    }, 15_000);
    attendanceExpiryTimer.unref();
    app.listen(port, '0.0.0.0', () => {
      console.log(`API listening on http://0.0.0.0:${port}`);
      console.log(`LAN URL: http://<IP_CUA_MAY_TINH>:${port}`);
    });
  })
  .catch((error) => {
    console.error('Database migration failed:', error.message);
    process.exit(1);
  });
