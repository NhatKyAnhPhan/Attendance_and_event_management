const crypto = require('crypto');
const bcrypt = require('bcryptjs');

const genericResponse = {
  message: 'Nếu email thuộc tài khoản hợp lệ, hướng dẫn khôi phục sẽ được gửi.',
};
const genericInvalidCode = 'Mã xác nhận không hợp lệ hoặc đã hết hạn.';
const requestLimits = new Map();
const requestWindowMs = 15 * 60 * 1000;
const requestLimit = 10;

function hash(value, secret) {
  return crypto.createHmac('sha256', secret).update(value).digest('hex');
}

function equalHex(left, right) {
  if (!/^[a-f0-9]{64}$/i.test(left) || !/^[a-f0-9]{64}$/i.test(right)) {
    return false;
  }
  return crypto.timingSafeEqual(Buffer.from(left, 'hex'), Buffer.from(right, 'hex'));
}

function isRateLimited(key) {
  const now = Date.now();
  for (const [entryKey, entry] of requestLimits) {
    if (now - entry.startedAt >= requestWindowMs) requestLimits.delete(entryKey);
  }

  const entry = requestLimits.get(key);
  if (!entry) {
    requestLimits.set(key, { startedAt: now, count: 1 });
    return false;
  }
  if (entry.count >= requestLimit) return true;
  entry.count += 1;
  return false;
}

function createPasswordResetHandlers({
  pool,
  secret,
  mailTransportFactory,
  mailConfigured = () => Boolean(
    process.env.SMTP_HOST && process.env.SMTP_PORT && process.env.SMTP_FROM,
  ),
}) {
  function isConfigured() {
    return typeof secret === 'string'
      && Buffer.byteLength(secret) >= 32
      && mailConfigured();
  }

  function checkRequest(request, response) {
    if (!isConfigured()) {
      response.status(503).json({
        message: 'Chức năng khôi phục mật khẩu chưa được cấu hình email.',
      });
      return false;
    }
    const address = request.ip || request.socket.remoteAddress || 'unknown';
    if (isRateLimited(address)) {
      response.status(429).json({
        message: 'Bạn đã gửi quá nhiều yêu cầu. Vui lòng thử lại sau.',
      });
      return false;
    }
    return true;
  }

  async function requestCode(request, response) {
    if (!checkRequest(request, response)) return;
    const email = typeof request.body?.email === 'string'
      ? request.body.email.trim().toLowerCase()
      : '';
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 150) {
      return response.status(400).json({ message: 'Email không hợp lệ.' });
    }

    try {
      const [[user]] = await pool.execute(
        `SELECT Mand AS id, Email AS email
         FROM nguoidung
         WHERE LOWER(TRIM(Email)) = ?
         LIMIT 1`,
        [email],
      );
      if (!user) return response.status(202).json(genericResponse);

      const [[recentRequest]] = await pool.execute(
        `SELECT TIMESTAMPDIFF(SECOND, requested_at, UTC_TIMESTAMP()) AS elapsed
         FROM password_reset_challenges
         WHERE user_id = ?
         LIMIT 1`,
        [user.id],
      );
      if (recentRequest && Number(recentRequest.elapsed) < 60) {
        return response.status(202).json(genericResponse);
      }

      const code = crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
      const codeHash = hash(`${user.id}:${email}:${code}`, secret);
      await pool.execute(
        `INSERT INTO password_reset_challenges
           (user_id, email, code_hash, reset_token_hash, expires_at,
            requested_at, attempts)
         VALUES (?, ?, ?, NULL, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 10 MINUTE),
                 UTC_TIMESTAMP(), 0)
         ON DUPLICATE KEY UPDATE
           email = VALUES(email),
           code_hash = VALUES(code_hash),
           reset_token_hash = NULL,
           expires_at = VALUES(expires_at),
           requested_at = VALUES(requested_at),
           attempts = 0`,
        [user.id, email, codeHash],
      );

      try {
        const transport = mailTransportFactory();
        await transport.sendMail({
          from: process.env.MAIL_FROM || process.env.SMTP_FROM,
          to: user.email,
          subject: 'Mã khôi phục mật khẩu',
          text: `Mã xác nhận của bạn là ${code}. Mã có hiệu lực trong 10 phút. Nếu bạn không yêu cầu, hãy bỏ qua email này.`,
        });
      } catch (error) {
        await pool.execute(
          'DELETE FROM password_reset_challenges WHERE user_id = ? AND code_hash = ?',
          [user.id, codeHash],
        );
        console.error('Password reset email delivery failed:', error.code || error.name);
        return response.status(202).json(genericResponse);
      }

      return response.status(202).json(genericResponse);
    } catch (error) {
      console.error('Password reset request failed:', error.code || error.name);
      return response.status(500).json({
        message: 'Không thể xử lý yêu cầu khôi phục mật khẩu.',
      });
    }
  }

  async function verifyCode(request, response) {
    if (!checkRequest(request, response)) return;
    const email = typeof request.body?.email === 'string'
      ? request.body.email.trim().toLowerCase()
      : '';
    const code = request.body?.code;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
      || email.length > 150
      || typeof code !== 'string'
      || !/^\d{6}$/.test(code)) {
      return response.status(400).json({ message: genericInvalidCode });
    }

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const [[challenge]] = await connection.execute(
        `SELECT user_id AS userId, email, code_hash AS codeHash,
                attempts, expires_at > UTC_TIMESTAMP() AS isValid
         FROM password_reset_challenges
         WHERE email = ?
         LIMIT 1
         FOR UPDATE`,
        [email],
      );
      const expectedHash = challenge
        ? hash(`${challenge.userId}:${email}:${code}`, secret)
        : '';
      if (!challenge || !challenge.codeHash
        || !Number(challenge.isValid)
        || Number(challenge.attempts) >= 5
        || !equalHex(challenge.codeHash, expectedHash)) {
        if (challenge && Number(challenge.attempts) < 5) {
          await connection.execute(
            `UPDATE password_reset_challenges
             SET attempts = attempts + 1
             WHERE user_id = ?`,
            [challenge.userId],
          );
        }
        await connection.commit();
        return response.status(400).json({ message: genericInvalidCode });
      }

      const resetToken = crypto.randomBytes(32).toString('hex');
      await connection.execute(
        `UPDATE password_reset_challenges
         SET code_hash = NULL,
             reset_token_hash = ?,
             expires_at = DATE_ADD(UTC_TIMESTAMP(), INTERVAL 10 MINUTE),
             attempts = 0
         WHERE user_id = ?`,
        [hash(resetToken, secret), challenge.userId],
      );
      await connection.commit();
      return response.json({ resetToken });
    } catch (error) {
      await connection.rollback();
      console.error('Password reset code verification failed:', error.code || error.name);
      return response.status(500).json({
        message: 'Không thể xác nhận mã khôi phục.',
      });
    } finally {
      connection.release();
    }
  }

  async function resetPassword(request, response) {
    if (!checkRequest(request, response)) return;
    const email = typeof request.body?.email === 'string'
      ? request.body.email.trim().toLowerCase()
      : '';
    const { resetToken, newPassword } = request.body || {};
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
      || email.length > 150
      || typeof resetToken !== 'string'
      || !/^[a-f0-9]{64}$/.test(resetToken)
      || typeof newPassword !== 'string'
      || newPassword.length < 8
      || Buffer.byteLength(newPassword) > 72) {
      return response.status(400).json({
        message: 'Thông tin không hợp lệ. Mật khẩu cần từ 8 ký tự và tối đa 72 byte.',
      });
    }

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const [[challenge]] = await connection.execute(
        `SELECT user_id AS userId, reset_token_hash AS resetTokenHash,
                expires_at > UTC_TIMESTAMP() AS isValid
         FROM password_reset_challenges
         WHERE email = ?
         LIMIT 1
         FOR UPDATE`,
        [email],
      );
      const tokenHash = hash(resetToken, secret);
      if (!challenge || !Number(challenge.isValid)
        || !equalHex(challenge.resetTokenHash || '', tokenHash)) {
        await connection.rollback();
        return response.status(400).json({ message: genericInvalidCode });
      }

      const passwordHash = await bcrypt.hash(newPassword, 12);
      await connection.execute(
        'UPDATE nguoidung SET Matkhau = ? WHERE Mand = ?',
        [passwordHash, challenge.userId],
      );
      await connection.execute(
        'DELETE FROM password_reset_challenges WHERE user_id = ?',
        [challenge.userId],
      );
      await connection.commit();
      return response.json({ message: 'Đặt lại mật khẩu thành công.' });
    } catch (error) {
      await connection.rollback();
      console.error('Password reset failed:', error.code || error.name);
      return response.status(500).json({
        message: 'Không thể đặt lại mật khẩu lúc này.',
      });
    } finally {
      connection.release();
    }
  }

  return { requestCode, verifyCode, resetPassword };
}

module.exports = { createPasswordResetHandlers };
