const fs = require('fs');
const path = require('path');
const nodemailer = require('nodemailer');
const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');

const templatePath = path.join(__dirname, 'certificate-template.png');

function findCertificateFont() {
  const candidates = [
    process.env.CERTIFICATE_FONT_PATH,
    path.join(process.env.WINDIR || 'C:\\Windows', 'Fonts', 'arial.ttf'),
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
  ].filter(Boolean);
  const fontPath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!fontPath) {
    throw new Error(
      'Không tìm thấy font TTF hỗ trợ tiếng Việt. Hãy cấu hình CERTIFICATE_FONT_PATH.',
    );
  }
  return fontPath;
}

function createMailTransport() {
  const { SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM } = process.env;
  if (!SMTP_HOST || !SMTP_PORT || !SMTP_FROM) {
    throw new Error('Thiếu cấu hình SMTP_HOST, SMTP_PORT hoặc SMTP_FROM trong .env.');
  }
  if ((SMTP_USER && !SMTP_PASSWORD) || (!SMTP_USER && SMTP_PASSWORD)) {
    throw new Error('SMTP_USER và SMTP_PASSWORD phải được cấu hình cùng nhau.');
  }

  return nodemailer.createTransport({
    host: SMTP_HOST,
    port: Number(SMTP_PORT),
    secure: String(process.env.SMTP_SECURE).toLowerCase() === 'true',
    ...(SMTP_USER ? { auth: { user: SMTP_USER, pass: SMTP_PASSWORD } } : {}),
  });
}

async function createCertificatePdf({
  studentName,
  studentId,
  eventName,
  startTime,
  endTime,
  location,
  certificateId,
  issuedAt,
  verificationUrl,
}) {
  if (!fs.existsSync(templatePath)) {
    throw new Error(`Không tìm thấy mẫu chứng nhận: ${templatePath}`);
  }
  const fontPath = findCertificateFont();
  const verificationQr = await QRCode.toBuffer(verificationUrl, {
    type: 'png',
    width: 180,
    margin: 0,
    errorCorrectionLevel: 'M',
  });
  const pageWidth = 841.89;
  const pageHeight = 595.28;
  const document = new PDFDocument({
    size: 'A4',
    layout: 'landscape',
    margin: 0,
    autoFirstPage: true,
  });
  const chunks = [];
  const pdfBuffer = new Promise((resolve, reject) => {
    document.on('data', (chunk) => chunks.push(chunk));
    document.on('end', () => resolve(Buffer.concat(chunks)));
    document.on('error', reject);
  });

  document.image(templatePath, 0, 0, { width: pageWidth, height: pageHeight });
  document.font(fontPath).fillColor('#10274d');

  document.save();
  document.fillColor('#ffffff').rect(244, 242, 354, 30).fill();
  document.restore();
  document.fontSize(23).text(studentName, 210, 242, {
    width: 422,
    height: 32,
    align: 'center',
    lineBreak: false,
    ellipsis: true,
  });

  document.save();
  document.fillColor('#ffffff').rect(385, 273, 150, 17).fill();
  document.restore();
  document.fontSize(12).text(`MSSV: ${studentId}`, 250, 274, {
    width: 342,
    height: 17,
    align: 'center',
    lineBreak: false,
    ellipsis: true,
  });

  document.save();
  document.fillColor('#ffffff').rect(185, 330, 472, 23).fill();
  document.restore();
  document.fontSize(17).fillColor('#164b85').text(`“${eventName}”`, 185, 330, {
    width: 472,
    height: 23,
    align: 'center',
    lineBreak: false,
    ellipsis: true,
  });

  const formatDate = (value) => new Intl.DateTimeFormat('vi-VN', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: 'Asia/Ho_Chi_Minh',
  }).format(new Date(value));
  const startDate = formatDate(startTime);
  const endDate = formatDate(endTime);
  const eventDate = startDate === endDate ? startDate : `${startDate} - ${endDate}`;

  document.save();
  document.fillColor('#ffffff').rect(342, 366, 300, 39).fill();
  document.restore();
  document.fontSize(11).fillColor('#10274d');
  document.text(`Thời gian tổ chức: ${eventDate}`, 348, 369, {
    width: 285,
    height: 14,
    lineBreak: false,
    ellipsis: true,
  });
  document.text(`Địa điểm: ${location}`, 348, 387, {
    width: 285,
    height: 14,
    lineBreak: false,
    ellipsis: true,
  });

  const issuedDate = formatDate(issuedAt);
  document.save();
  document.fillColor('#ffffff').rect(67, 477, 190, 33).fill();
  document.restore();
  document.fontSize(10).fillColor('#10274d');
  document.text(`Mã chứng nhận: ${certificateId}`, 70, 479, {
    width: 185,
    height: 13,
    lineBreak: false,
    ellipsis: true,
  });
  document.text(`Ngày cấp: ${issuedDate}`, 70, 495, {
    width: 185,
    height: 13,
    lineBreak: false,
    ellipsis: true,
  });
  document.image(verificationQr, 270, 472, { width: 66, height: 66 });

  document.fontSize(10).text(
    `TP. Hồ Chí Minh, ngày ${new Intl.DateTimeFormat('vi-VN', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      timeZone: 'Asia/Ho_Chi_Minh',
    }).format(new Date(issuedAt))}`,
    510,
    448,
    { width: 260, align: 'right', lineBreak: false, ellipsis: true },
  );

  document.end();
  return pdfBuffer;
}

module.exports = { createCertificatePdf, createMailTransport };
