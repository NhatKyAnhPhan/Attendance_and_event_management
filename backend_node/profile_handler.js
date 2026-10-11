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
    const fieldColumns = {
      email: 'Email',
      phone: 'SDT',
      address: 'DiaChi',
      birthDate: 'NgaySinh',
      gender: 'GioiTinh',
      hometown: 'QueQuan',
    };
    const allowedFields = new Set(Object.keys(fieldColumns));
    const unexpectedFields = Object.keys(payload).filter((key) => !allowedFields.has(key));

    if (unexpectedFields.length > 0) {
      return response.status(400).json({
        message: 'Thông tin hồ sơ có trường không hợp lệ.',
      });
    }

    const fields = Object.keys(payload);
    if (fields.length === 0) {
      return response.status(400).json({ message: 'Không có thông tin hồ sơ để cập nhật.' });
    }

    const values = {};
    for (const field of fields) {
      if (typeof payload[field] !== 'string') {
        return response.status(400).json({ message: 'Thông tin hồ sơ không hợp lệ.' });
      }
      values[field] = payload[field].trim();
    }

    if (Object.hasOwn(values, 'email')
      && (!values.email
        || values.email.length > 150
        || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.email))) {
      return response.status(400).json({ message: 'Email không hợp lệ.' });
    }
    if (Object.hasOwn(values, 'phone')
      && values.phone
      && (values.phone.length > 15 || !/^[0-9+()\-\s]+$/.test(values.phone))) {
      return response.status(400).json({ message: 'Số điện thoại không hợp lệ.' });
    }
    for (const field of ['address', 'hometown']) {
      if (Object.hasOwn(values, field) && values[field].length > 200) {
        return response.status(400).json({ message: 'Địa chỉ không được vượt quá 200 ký tự.' });
      }
    }
    if (Object.hasOwn(values, 'gender')
      && values.gender
      && !['Nam', 'Nữ', 'Khác'].includes(values.gender)) {
      return response.status(400).json({ message: 'Giới tính không hợp lệ.' });
    }
    if (Object.hasOwn(values, 'birthDate') && values.birthDate) {
      const parsedDate = new Date(`${values.birthDate}T00:00:00.000Z`);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(values.birthDate)
        || Number.isNaN(parsedDate.valueOf())
        || parsedDate.toISOString().slice(0, 10) !== values.birthDate
        || parsedDate > new Date()) {
        return response.status(400).json({ message: 'Ngày sinh không hợp lệ.' });
      }
    }

    try {
      const assignments = fields.map((field) => `${fieldColumns[field]} = ?`);
      const parameters = fields.map((field) => (
        values[field] === '' && field !== 'email' ? null : values[field]
      ));
      parameters.push(request.auth.sub);
      await pool.execute(
        `UPDATE nguoidung SET ${assignments.join(', ')} WHERE Mand = ?`,
        parameters,
      );
      const [rows] = await pool.execute(
        `SELECT nd.Mand AS id, nd.Hoten AS name,
          nd.Email AS email, nd.Vaitro AS role, nd.SDT AS phone,
          nd.DiaChi AS address, nd.NgaySinh AS birthDate,
          nd.GioiTinh AS gender, nd.QueQuan AS hometown,
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
      if (!rows[0]) {
        return response.status(404).json({ message: 'Không tìm thấy người dùng.' });
      }
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