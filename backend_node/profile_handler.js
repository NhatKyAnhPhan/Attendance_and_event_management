const crypto = require('crypto');
const bcrypt = require('bcryptjs');

async function passwordsMatch(password, storedPassword) {
  if (storedPassword.startsWith('$2')) {
    return bcrypt.compare(password, storedPassword);
  }

  if (Buffer.byteLength(password) !== Buffer.byteLength(storedPassword)) {
    return false;
  }

  return crypto.timingSafeEqual(
    Buffer.from(password),
    Buffer.from(storedPassword),
  );
}

async function changePassword(pool, request, response) {
  const payload = request.body || {};
  const allowedFields = new Set(['currentPassword', 'newPassword']);
  const unexpectedFields = Object.keys(payload).filter((key) => !allowedFields.has(key));
  if (unexpectedFields.length > 0) {
    return response.status(400).json({ message: 'Dữ liệu đổi mật khẩu không hợp lệ.' });
  }

  const { currentPassword, newPassword } = payload;
  if (typeof currentPassword !== 'string' || !currentPassword) {
    return response.status(400).json({ message: 'Vui lòng nhập mật khẩu hiện tại.' });
  }
  if (typeof newPassword !== 'string'
    || newPassword.length < 8
    || Buffer.byteLength(newPassword) > 72) {
    return response.status(400).json({
      message: 'Mật khẩu mới phải có từ 8 ký tự và không vượt quá 72 byte.',
    });
  }

  try {
    const [rows] = await pool.execute(
      'SELECT Matkhau AS password FROM nguoidung WHERE Mand = ? LIMIT 1',
      [request.auth.sub],
    );
    const user = rows[0];
    if (!user) {
      return response.status(404).json({ message: 'Không tìm thấy người dùng.' });
    }
    if (!await passwordsMatch(currentPassword, user.password)) {
      return response.status(400).json({ message: 'Mật khẩu hiện tại không đúng.' });
    }
    if (await passwordsMatch(newPassword, user.password)) {
      return response.status(400).json({ message: 'Mật khẩu mới phải khác mật khẩu hiện tại.' });
    }

    const passwordHash = await bcrypt.hash(newPassword, 12);
    await pool.execute(
      'UPDATE nguoidung SET Matkhau = ? WHERE Mand = ?',
      [passwordHash, request.auth.sub],
    );
    return response.json({ message: 'Đổi mật khẩu thành công.' });
  } catch (error) {
    console.error('Change password error:', error.message);
    return response.status(500).json({ message: 'Không thể đổi mật khẩu.' });
  }
}

function createUpdateProfileHandler(pool) {
  return async (request, response) => {
    if (request.query.action === 'password') {
      return changePassword(pool, request, response);
    }

    const payload = request.body || {};
    const allowedFields = new Set(['email']);
    const unexpectedFields = Object.keys(payload).filter((key) => !allowedFields.has(key));

    if (unexpectedFields.length > 0) {
      return response.status(400).json({
        message: 'Chỉ được cập nhật email.',
      });
    }

    const email = typeof payload.email === 'string' ? payload.email.trim() : '';
    if (!email || email.length > 150 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return response.status(400).json({ message: 'Email không hợp lệ.' });
    }

    try {
      const [result] = await pool.execute(
        'UPDATE nguoidung SET Email = ? WHERE Mand = ?',
        [email, request.auth.sub],
      );
      if (result.affectedRows === 0) {
        return response.status(404).json({ message: 'Không tìm thấy người dùng.' });
      }

      const [rows] = await pool.execute(
        `SELECT nd.Mand AS id, nd.Hoten AS name,
          nd.Email AS email, nd.Vaitro AS role,
          nd.Trangthaind AS status,
          sv.Lop AS className, sv.Chuyennganh AS major,
          gv.Bomon AS subjectDepartment, cnv.Chucvu AS position
         FROM nguoidung nd
         LEFT JOIN sinhvien sv ON sv.Masv = nd.Mand
         LEFT JOIN giangvien gv ON gv.Magv = nd.Mand
         LEFT JOIN congnhanvien cnv ON cnv.Manv = nd.Mand
         WHERE nd.Mand = ?
         LIMIT 1`,
        [request.auth.sub],
      );
      return response.json({ user: rows[0] });
    } catch (error) {
      console.error('Update profile error:', error.message);
      if (error.code === 'ER_DUP_ENTRY') {
        return response.status(409).json({ message: 'Email đã được sử dụng.' });
      }
      return response.status(500).json({ message: 'Không thể cập nhật thông tin người dùng.' });
    }
  };
}

module.exports = { createUpdateProfileHandler };