const fs = require('fs');
const path = require('path');
const nodemailer = require('nodemailer');
const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');

const templatePath = path.join(__dirname, 'certificate-template.png');

function parseSender(from) {
  const value = typeof from === 'string' ? from.trim() : '';
  const match = value.match(/^(?:[^<>]*<([^<>]+)>|([^<>]+))$/);
  const address = (match?.[1] || match?.[2] || '').trim();
  if (!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(address)) return null;
  const name = match?.[1] ? value.slice(0, value.indexOf('<')).trim() : '';
  return { email: address, ...(name ? { name } : {}) };
}

function isValidResendFrom(from) {
  return Boolean(parseSender(from));
}

function plainTextToHtml(text) {
  return String(text)
    .replace(/[&<>"]/g, (character) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
    })[character])
    .replace(/\r?\n/g, '<br>');
}

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
  const provider = String(process.env.MAIL_PROVIDER || '').trim().toLowerCase();
  const from = process.env.MAIL_FROM || process.env.SMTP_FROM;
  const resendApiKey = process.env.RESEND_API_KEY;

  if (provider === 'brevo') {
    const brevoApiKey = process.env.BREVO_API_KEY;
    const sender = parseSender(from);
    if (!brevoApiKey) {
      throw new Error('Brevo cần BREVO_API_KEY.');
    }
    if (!sender) {
      throw new Error(
        'MAIL_FROM phải là địa chỉ email người gửi đã xác thực trên Brevo, ví dụ "HUIT <chungnhan@example.com>".',
      );
    }
    if (typeof fetch !== 'function') {
      throw new Error('Brevo cần Node.js 18 trở lên để gọi API HTTPS.');
    }
    return {
      async verify() {
        return true;
      },
      async sendMail(message) {
        const attachments = (message.attachments || []).map((attachment) => {
          const content = Buffer.isBuffer(attachment.content)
            ? attachment.content
            : Buffer.from(String(attachment.content || ''));
          return {
            name: attachment.filename,
            content: content.toString('base64'),
          };
        });
        const recipients = Array.isArray(message.to) ? message.to : [message.to];
        const payload = {
          sender,
          to: recipients.map((recipient) => (
            typeof recipient === 'string'
              ? { email: recipient }
              : { email: recipient.email, ...(recipient.name ? { name: recipient.name } : {}) }
          )),
          subject: message.subject,
          ...(message.text
            ? { textContent: message.text, htmlContent: plainTextToHtml(message.text) }
            : {}),
          ...(message.html ? { htmlContent: message.html } : {}),
          ...(attachments.length ? { attachment: attachments } : {}),
        };
        const response = await fetch('https://api.brevo.com/v3/smtp/email', {
          method: 'POST',
          headers: {
            'api-key': brevoApiKey,
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
          body: JSON.stringify(payload),
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok) {
          const error = new Error(
            result.message || result.code || `Brevo API trả về HTTP ${response.status}.`,
          );
          error.code = result.code || `BREVO_HTTP_${response.status}`;
          throw error;
        }
        return { messageId: result.messageId };
      },
    };
  }

  if (provider === 'resend' || (!provider && resendApiKey)) {
    if (!resendApiKey) {
      throw new Error('Resend cần RESEND_API_KEY.');
    }
    if (!isValidResendFrom(from)) {
      throw new Error(
        'MAIL_FROM phải là địa chỉ email, ví dụ "HUIT <chungnhan@ten-mien-da-xac-minh>".',
      );
    }
    if (typeof fetch !== 'function') {
      throw new Error('Resend cần Node.js 18 trở lên để gọi API HTTPS.');
    }
    return {
      async verify() {
        // Resend xác thực API key trong mỗi yêu cầu gửi email.
        return true;
      },
      async sendMail(message) {
        const attachments = (message.attachments || []).map((attachment) => {
          const content = Buffer.isBuffer(attachment.content)
            ? attachment.content
            : Buffer.from(String(attachment.content || ''));
          return {
            filename: attachment.filename,
            content: content.toString('base64'),
            ...(attachment.contentType
              ? { content_type: attachment.contentType }
              : {}),
          };
        });
        const payload = {
          from: message.from || from,
          to: Array.isArray(message.to) ? message.to : [message.to],
          subject: message.subject,
          ...(message.text ? { text: message.text } : {}),
          ...(message.html ? { html: message.html } : {}),
          ...(attachments.length ? { attachments } : {}),
        };
        const response = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${resendApiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload),
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok) {
          const error = new Error(
            result.message || result.error || `Resend API trả về HTTP ${response.status}.`,
          );
          error.code = result.name || `RESEND_HTTP_${response.status}`;
          throw error;
        }
        return { messageId: result.id };
      },
    };
  }

  if (provider && provider !== 'smtp') {
    throw new Error('MAIL_PROVIDER chỉ hỗ trợ giá trị "brevo", "resend" hoặc "smtp".');
  }

  const { SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM } = process.env;
  if (!SMTP_HOST || !SMTP_PORT || !from) {
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

function isMailConfigured() {
  const provider = String(process.env.MAIL_PROVIDER || '').trim().toLowerCase();
  const from = process.env.MAIL_FROM || process.env.SMTP_FROM;
  if (provider === 'brevo') {
    return Boolean(process.env.BREVO_API_KEY && parseSender(from));
  }
  if (provider === 'resend' || (!provider && process.env.RESEND_API_KEY)) {
    return Boolean(process.env.RESEND_API_KEY && isValidResendFrom(from));
  }
  if (provider && provider !== 'smtp') return false;
  return Boolean(process.env.SMTP_HOST && process.env.SMTP_PORT && from);
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
  isSample = false,
  organizerSignatureImage = null,
  organizerName = '',
  deanSignatureImage = null,
  deanName = '',
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
  document.fillColor('#ffffff').rect(340, 271, 260, 22).fill();
  document.restore();
  document.fontSize(12).text(`MSSV: ${studentId}`, 250, 274, {
    width: 440,
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
  document.fillColor('#ffffff').rect(304, 360, 350, 45).fill();
  document.restore();
  document.fontSize(11).fillColor('#10274d');
  document.text(`Thời gian tổ chức: ${eventDate}`, 310, 369, {
    width: 340,
    height: 14,
    lineBreak: false,
    ellipsis: true,
  });
  document.text(`Địa điểm: ${location}`, 310, 387, {
    width: 340,
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

  document.save();
  document.fillColor('#ffffff').rect(500, 444, 295, 22).fill();
  document.restore();
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

  if (organizerSignatureImage) {
    document.image(organizerSignatureImage, 454, 485, {
      fit: [136, 36],
      align: 'center',
      valign: 'center',
    });
  }
  if (deanSignatureImage) {
    document.image(deanSignatureImage, 627, 485, {
      fit: [136, 36],
      align: 'center',
      valign: 'center',
    });
  }
  for (const [name, x] of [[organizerName, 454], [deanName, 627]]) {
    if (name) {
      document
        .font(fontPath)
        .fontSize(10)
        .fillColor('#10274d')
        .text(name, x, 541, {
          width: 136,
          height: 14,
          align: 'center',
          lineBreak: false,
          ellipsis: true,
        });
    }
  }

  if (isSample) {
    document
      .save()
      .rotate(-24, { origin: [pageWidth / 2, pageHeight / 2] })
      .fontSize(42)
      .fillColor('#b91c1c', 0.2)
      .text('BẢN MẪU KIỂM THỬ', 60, pageHeight / 2 - 20, {
        width: pageWidth - 120,
        align: 'center',
        lineBreak: false,
      })
      .restore();
  }

  document.end();
  return pdfBuffer;
}

module.exports = {
  createCertificatePdf,
  createMailTransport,
  isMailConfigured,
};
