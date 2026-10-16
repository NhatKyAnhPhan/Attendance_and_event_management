require('dotenv').config();

const crypto = require('crypto');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const mysql = require('mysql2/promise');
const { createUpdateProfileHandler } = require('./profile_handler');
const { createCertificatePdf, createMailTransport } = require('./certificate_mailer');

const app = express();
const port = Number(process.env.PORT || 3000);
const jwtSecret = process.env.JWT_SECRET || 'change-this-development-secret';

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'QL_SuKienDA',
  waitForConnections: true,
  connectionLimit: 10,
  charset: 'utf8mb4',
});

const eventStatusSql = `CASE
  WHEN sk.Trangthaisukien = 'Đã đóng' THEN 'Đã đóng'
  WHEN NOW() < sk.Thoigianbatdau THEN 'Sắp diễn ra'
  WHEN NOW() < sk.Thoigianketthuc THEN 'Đang diễn ra'
  ELSE 'Đã kết thúc'
END`;

async function synchronizeEventStatuses() {
  await pool.query(
    `UPDATE sukien sk
     SET Trangthaisukien = ${eventStatusSql}
     WHERE Trangthaisukien <> 'Đã đóng'
       AND NOT (Trangthaisukien <=> ${eventStatusSql})`,
  );
}

// Sinh mã sự kiện ngẫu nhiên; khóa duy nhất của cơ sở dữ liệu ngăn mã trùng.
function generateRecordId(prefix) {
  return `${prefix}${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
}

// Kiểm tra khoảng thời gian hợp lệ và giới hạn thời lượng sự kiện trong 24 giờ.
function isValidEventTimeRange(startTime, endTime, { requireFutureStart = false, requireFutureEnd = false } = {}) {
  const start = startTime.valueOf();
  const end = endTime.valueOf();
  const now = Date.now();
  return Number.isFinite(start)
    && Number.isFinite(end)
    && end > start
    && end - start <= 24 * 60 * 60 * 1000
    && (!requireFutureStart || start > now)
    && (!requireFutureEnd || end > now);
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
    'UPDATE sukien SET Mota = ? WHERE Masukien = ?',
    [content.description, eventId],
  );
  await connection.execute('DELETE FROM quyenloi WHERE Masukien = ?', [eventId]);
  await connection.execute('DELETE FROM noiquy WHERE Masukien = ?', [eventId]);

  for (const benefit of content.benefits) {
    await connection.execute(
      `INSERT INTO quyenloi (Maquyenloi, Masukien, Loaiquyenloi, Sodiem, Noidung)
       VALUES (?, ?, ?, ?, ?)`,
      [generateRecordId('QL'), eventId, benefit.type, benefit.points, benefit.content],
    );
  }
  for (const [index, rule] of content.rules.entries()) {
    await connection.execute(
      `INSERT INTO noiquy (Manoiquy, Masukien, Thutu, Noidung)
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
  ]) {
    try {
      await pool.query(`ALTER TABLE \`buoidiemdanh\` ADD COLUMN \`${column}\` ${definition}`);
    } catch (error) {
      if (error.code !== 'ER_DUP_FIELDNAME') throw error;
    }
  }
}

async function ensureAttendanceDeviceClaimsTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS attendance_device_claims (
       device_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       attendance_date DATE NOT NULL,
       student_id VARCHAR(64) NOT NULL,
       attendance_session_id VARCHAR(64) NOT NULL,
       created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
       PRIMARY KEY (device_id, attendance_session_id)
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

async function ensureEventAttendanceTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS event_attendance (
       event_id VARCHAR(64) NOT NULL,
       student_id VARCHAR(64) NOT NULL,
       device_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
       checked_in_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
       PRIMARY KEY (event_id, student_id),
       UNIQUE KEY unique_event_attendance_device (event_id, device_id)
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  );
}

app.use(cors());
app.use(express.json());

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

function isAdminAuth(auth) {
  return ['quản trị viên', 'admin'].includes(String(auth.role || '').trim().toLowerCase());
}

// Kiểm tra người dùng có phụ trách đơn vị tổ chức (DonVi.MaNV) hay không.
async function managesUnit(executor, auth, unitId) {
  if (isAdminAuth(auth)) return true;
  const [[unit]] = await executor.execute(
    'SELECT 1 AS ok FROM donvi WHERE Madv = ? AND Manv = ? LIMIT 1',
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
             FROM nguoidung
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
              gv.Bomon AS subjectDepartment, cnv.Chucvu AS position
             FROM nguoidung nd
             LEFT JOIN sinhvien sv ON sv.Masv = nd.Mand
             LEFT JOIN giangvien gv ON gv.Magv = nd.Mand
              LEFT JOIN congnhanvien cnv ON cnv.Manv = nd.Mand
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
    return response.json({ items: rows });
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
        "FROM buoidiemdanh bpd",
        "INNER JOIN buoi b ON b.Mabuoi = bpd.Mabuoi",
        "INNER JOIN thanhvienlop tvl ON tvl.Malop = b.Malop",
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
                FROM lichhocphan lh WHERE lh.Malop = lhp.Malop
              ), '') AS schedule,
              COALESCE((
                SELECT GROUP_CONCAT(DISTINCT lh.PhongHoc
                  ORDER BY lh.PhongHoc SEPARATOR ', ')
                FROM lichhocphan lh WHERE lh.Malop = lhp.Malop
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
                FROM lichhocphan lh
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
       FROM lophocphan lhp
       LEFT JOIN giangvien gv ON gv.Magv = lhp.Magv
       LEFT JOIN nguoidung nd ON nd.Mand = gv.Magv
       LEFT JOIN thanhvienlop tvl ON tvl.Malop = lhp.Malop
            LEFT JOIN (
              SELECT b.Malop, kd.Masv,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent,
                COUNT(DISTINCT bpd.Mabuoidiemdanh) AS sessions
              FROM ketquadiemdanh kd
              INNER JOIN buoidiemdanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
              INNER JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
              GROUP BY b.Malop, kd.Masv
            ) attendance ON attendance.Malop = lhp.Malop
                   AND attendance.Masv = ?
       WHERE EXISTS (
         SELECT 1 FROM thanhvienlop mine
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
              (SELECT COUNT(*) FROM thanhvienlop tvl
               WHERE tvl.Malop = lhp.Malop) AS studentCount
       FROM lophocphan lhp
       INNER JOIN monhoc mh ON mh.Mamon = lhp.Mamon
       LEFT JOIN donvi dv ON dv.Madv = lhp.Madv
       LEFT JOIN giangvien gv ON gv.Magv = lhp.Magv
       LEFT JOIN nguoidung nd ON nd.Mand = gv.Magv
       WHERE lhp.Malop = ?
         AND EXISTS (
           SELECT 1 FROM thanhvienlop mine
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
       FROM lichhocphan
       WHERE Malop = ?
       ORDER BY ThuTrongTuan, GioBatDau`,
      [request.params.classId],
    );
    const [students] = await pool.execute(
      `SELECT tvl.Masv AS studentId,
              COALESCE(nd.Hoten, tvl.Masv) AS studentName,
              COALESCE(tvl.TrangThaiThanhVien, '') AS status,
              DATE_FORMAT(tvl.NgayThamGia, '%d/%m/%Y') AS dateLabel
       FROM thanhvienlop tvl
       LEFT JOIN nguoidung nd ON nd.Mand = tvl.Masv
       WHERE tvl.Malop = ?
       ORDER BY nd.Hoten, tvl.Masv`,
      [request.params.classId],
    );
    return response.json({ class: classInfo, schedules, students });
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
              sk.Madv AS organizerId, COALESCE(dv.Tendv, '') AS organizerName,
              sk.Thoigianbatdau AS startTime, sk.Thoigianketthuc AS endTime,
              ${eventStatusSql} AS status,
              COALESCE(sk.Diadiem, '') AS location,
              COALESCE(sk.Soluongtoida, 0) AS capacity,
              COUNT(DISTINCT dkAll.Masv) AS registeredCount,
              dkMine.Ngaydangky AS registeredAt,
              CASE WHEN dkMine.Masv IS NULL THEN 'notRegistered'
                   ELSE LOWER(REPLACE(dkMine.Trangthaidangky, ' ', '')) END AS registrationStatus
       FROM sukien sk
       LEFT JOIN donvi dv ON dv.Madv = sk.Madv
       LEFT JOIN dangkysukien dkAll ON dkAll.Masukien = sk.Masukien
       LEFT JOIN dangkysukien dkMine
         ON dkMine.Masukien = sk.Masukien
        AND dkMine.Masv = ?
       GROUP BY sk.Masukien, sk.Tensukien, sk.Madv, dv.Tendv,
                sk.Thoigianbatdau, sk.Thoigianketthuc, sk.Trangthaisukien,
                sk.Diadiem,
                sk.Soluongtoida, dkMine.Masv, dkMine.Trangthaidangky,
                dkMine.Ngaydangky
       ORDER BY sk.Thoigianbatdau`,
      [request.auth.sub],
    );
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
        "sk.Mota AS description, COALESCE(sk.Diadiem, '') AS location,",
        "sk.Thoigianbatdau AS startTime, sk.Thoigianketthuc AS endTime,",
        "COALESCE(sk.Soluongtoida, 0) AS capacity,",
        "dv.Tendv AS organizerName,",
        "(SELECT COUNT(*) FROM dangkysukien allRegs",
        "WHERE allRegs.Masukien = sk.Masukien) AS registeredCount,",
        "(SELECT COUNT(*) FROM dangkysukien myRegistration",
        "WHERE myRegistration.Masukien = sk.Masukien AND myRegistration.Masv = ?) AS isRegistered,",
        "(SELECT myRegistration.Ngaydangky FROM dangkysukien myRegistration",
        "WHERE myRegistration.Masukien = sk.Masukien AND myRegistration.Masv = ? LIMIT 1) AS registeredAt",
        "FROM sukien sk INNER JOIN donvi dv ON dv.Madv = sk.Madv",
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
        "FROM quyenloi WHERE Masukien = ? ORDER BY Maquyenloi",
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
        "FROM noiquy WHERE Masukien = ? ORDER BY Thutu",
      ].join(' '),
      [event.id],
      );
    } catch (error) {
      if (error.code !== 'ER_NO_SUCH_TABLE') throw error;
    }
    return response.json({ ...event, benefits, rules });
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
       FROM phanhoi ph
       LEFT JOIN sukien sk ON sk.Masukien = ph.Masukien
       LEFT JOIN lophocphan lhp ON lhp.Malop = ph.Malop
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
       FROM danhgia dg
       LEFT JOIN sukien sk ON sk.Masukien = dg.Masukien
       LEFT JOIN lophocphan lhp ON lhp.Malop = dg.Malop
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
       FROM danhgia WHERE Masukien = ?`,
      [request.params.eventId],
    );
    const [items] = await pool.execute(
      `SELECT dg.SoSao AS rating,
              COALESCE(NULLIF(dg.Noidung, ''), ph.Noidung, '') AS comment,
              COALESCE(dg.Thoigiandanhgia, ph.Thoigiangui) AS createdAt
       FROM phanhoi ph
       LEFT JOIN danhgia dg
         ON dg.Masv = ph.Masv AND dg.Masukien = ph.Masukien
       WHERE ph.Masukien = ?
       UNION ALL
       SELECT dg.SoSao AS rating, COALESCE(dg.Noidung, '') AS comment,
              dg.Thoigiandanhgia AS createdAt
       FROM danhgia dg
       WHERE dg.Masukien = ?
         AND NOT EXISTS (
           SELECT 1 FROM phanhoi ph
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
      `SELECT Masukien AS id FROM sukien
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
      `SELECT Masv FROM dangkysukien
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
        `INSERT INTO danhgia (Madanhgia, Sosao, Noidung, Masv, Masukien)
         VALUES (?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           Sosao = VALUES(Sosao), Noidung = VALUES(Noidung),
           Thoigiandanhgia = CURRENT_TIMESTAMP`,
        [generateRecordId('DG'), Number(rating), normalizedComment, request.auth.sub, event.id],
      );
    }
    if (normalizedComment) {
      await connection.execute(
        `INSERT INTO phanhoi (Maphanhoi, Noidung, Masv, Masukien)
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
      'SELECT Malop FROM lophocphan WHERE Malop = ? LIMIT 1',
      [request.params.classId],
    );
    if (!classInfo) {
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    const [[summary]] = await pool.execute(
      `SELECT COALESCE(AVG(SoSao), 0) AS averageRating,
              COUNT(*) AS ratingCount
       FROM danhgia WHERE Malop = ?`,
      [request.params.classId],
    );
    const [items] = await pool.execute(
      `SELECT dg.SoSao AS rating,
              COALESCE(NULLIF(dg.Noidung, ''), ph.Noidung, '') AS comment,
              COALESCE(dg.Thoigiandanhgia, ph.Thoigiangui) AS createdAt
       FROM phanhoi ph
       LEFT JOIN danhgia dg
         ON dg.Masv = ph.Masv AND dg.Malop = ph.Malop
       WHERE ph.Malop = ?
       UNION ALL
       SELECT dg.SoSao AS rating, COALESCE(dg.Noidung, '') AS comment,
              dg.Thoigiandanhgia AS createdAt
       FROM danhgia dg
       WHERE dg.Malop = ?
         AND NOT EXISTS (
           SELECT 1 FROM phanhoi ph
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
      'SELECT Malop AS id FROM lophocphan WHERE Malop = ? FOR UPDATE',
      [request.params.classId],
    );
    if (!classInfo) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    const [[membership]] = await connection.execute(
      `SELECT Masv FROM thanhvienlop
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
        `INSERT INTO danhgia (Madanhgia, Sosao, Noidung, Masv, Malop)
         VALUES (?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           Sosao = VALUES(Sosao), Noidung = VALUES(Noidung),
           Thoigiandanhgia = CURRENT_TIMESTAMP`,
        [generateRecordId('DG'), Number(rating), normalizedComment, request.auth.sub, classInfo.id],
      );
    }
    if (normalizedComment) {
      await connection.execute(
        `INSERT INTO phanhoi (Maphanhoi, Noidung, Masv, Malop)
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
       FROM sukien WHERE Masukien = ? FOR UPDATE`,
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
    const [[registrationCount]] = await connection.execute(
      'SELECT COUNT(*) AS total FROM dangkysukien WHERE Masukien = ?',
      [request.params.eventId],
    );
    if (Number(registrationCount.total) >= Number(event.capacity)) {
      await connection.rollback();
      return response.status(409).json({ message: 'Sự kiện đã đủ số lượng đăng ký.' });
    }

    const [eventConflicts] = await connection.execute(
      `SELECT sk.Tensukien AS name
       FROM dangkysukien dk
       INNER JOIN sukien sk ON sk.Masukien = dk.Masukien
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
       FROM thanhvienlop tvl
       INNER JOIN buoi b ON b.Malop = tvl.Malop
       INNER JOIN lophocphan lhp ON lhp.Malop = b.Malop
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
      `INSERT INTO dangkysukien
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

// Hủy đăng ký nếu thời điểm đăng ký chưa quá 24 giờ.
app.delete('/api/events/:eventId/register', requireAuth, async (request, response) => {
  try {
    const [[event]] = await pool.execute(
      `SELECT CASE WHEN Thoigianketthuc <= NOW() THEN 1 ELSE 0 END AS ended
       FROM sukien WHERE Masukien = ? LIMIT 1`,
      [request.params.eventId],
    );
    if (!event) {
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    if (Number(event.ended) === 1) {
      return response.status(409).json({
        message: 'Sự kiện đã kết thúc, không thể hủy đăng ký.',
      });
    }
    const [result] = await pool.execute(
      `DELETE FROM dangkysukien
       WHERE Masukien = ? AND Masv = ?
         AND Ngaydangky >= DATE_SUB(NOW(), INTERVAL 1 DAY)
         AND EXISTS (
           SELECT 1 FROM sukien sk
           WHERE sk.Masukien = ? AND sk.Thoigianketthuc > NOW()
         )`,
      [request.params.eventId, request.auth.sub, request.params.eventId],
    );
    if (result.affectedRows === 1) {
      return response.json({ message: 'Đã hủy đăng ký sự kiện.' });
    }

    const [[registration]] = await pool.execute(
      `SELECT dk.Ngaydangky AS registeredAt,
              CASE WHEN sk.Thoigianketthuc <= NOW() THEN 1 ELSE 0 END AS ended
       FROM dangkysukien dk
       INNER JOIN sukien sk ON sk.Masukien = dk.Masukien
       WHERE dk.Masukien = ? AND dk.Masv = ? LIMIT 1`,
      [request.params.eventId, request.auth.sub],
    );
    if (!registration) {
      return response.status(404).json({ message: 'Bạn chưa đăng ký sự kiện này.' });
    }
    if (Number(registration.ended) === 1) {
      return response.status(409).json({
        message: 'Sự kiện đã kết thúc, không thể hủy đăng ký.',
      });
    }
    return response.status(403).json({
      message: 'Đã quá 24 giờ kể từ lúc đăng ký, bạn không thể hủy sự kiện này.',
    });
  } catch (error) {
    console.error('Event cancellation error:', error.message);
    return response.status(500).json({ message: 'Không thể hủy đăng ký sự kiện.' });
  }
});

// Tổng hợp số lớp, sự kiện và kết quả điểm danh của sinh viên.
app.get('/api/dashboard', requireAuth, async (request, response) => {
  try {
    const currentRole = String(request.auth.role || '').trim().toLowerCase();
    const userId = request.auth.sub;

    if (['quản trị viên', 'admin'].includes(currentRole)) {
      const [[users]] = await pool.query(
        'SELECT COUNT(*) AS total FROM nguoidung',
      );
      const [[students]] = await pool.query(
        'SELECT COUNT(*) AS total FROM sinhvien',
      );
      const [[classes]] = await pool.query(
        'SELECT COUNT(*) AS total FROM lophocphan',
      );
      const [[events]] = await pool.query(
        'SELECT COUNT(*) AS total FROM sukien',
      );
      const [[sessions]] = await pool.query(
        'SELECT COUNT(*) AS total FROM buoidiemdanh',
      );
      const [[attendance]] = await pool.query(
        `SELECT COUNT(*) AS total,
                SUM(CASE WHEN Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present
         FROM ketquadiemdanh`,
      );
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
      });
    }

    if (['cán bộ', 'nhân viên', 'ban tổ chức', 'organizer', 'staff', 'employee'].includes(currentRole)) {
      const [[events]] = await pool.execute(
        `SELECT COUNT(DISTINCT sk.Masukien) AS total,
                COUNT(DISTINCT dk.Masv, dk.Masukien) AS registrations
         FROM donvi dv
         LEFT JOIN sukien sk ON sk.Madv = dv.Madv
         LEFT JOIN dangkysukien dk ON dk.Masukien = sk.Masukien
         WHERE dv.Manv = ?`,
        [userId],
      );
      const [[certificates]] = await pool.execute(
        `SELECT COUNT(*) AS total
         FROM chungnhan cn
         INNER JOIN sukien sk ON sk.Masukien = cn.Masukien
         INNER JOIN donvi dv ON dv.Madv = sk.Madv
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
         FROM lophocphan lhp
         LEFT JOIN thanhvienlop tvl ON tvl.Malop = lhp.Malop
         LEFT JOIN buoi b ON b.Malop = lhp.Malop
         WHERE lhp.Magv = ?`,
        [userId],
      );
      const [[attendance]] = await pool.execute(
        `SELECT COUNT(kd.Maketqua) AS total,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
                SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
         FROM ketquadiemdanh kd
         INNER JOIN buoidiemdanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
         INNER JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
         INNER JOIN lophocphan lhp ON lhp.Malop = b.Malop
         WHERE lhp.Magv = ?`,
        [userId],
      );
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
      });
    }

    const [[classes]] = await pool.execute(
      'SELECT COUNT(*) AS total FROM thanhvienlop WHERE Masv = ?',
      [userId],
    );
    const [[events]] = await pool.execute(
      'SELECT COUNT(*) AS total FROM dangkysukien WHERE Masv = ?',
      [userId],
    );
    const [[attendance]] = await pool.execute(
      `SELECT
         SUM(CASE WHEN Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
         SUM(CASE WHEN Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
         SUM(CASE WHEN Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
      FROM ketquadiemdanh WHERE Masv = ?`,
          [userId],
    );
    return response.json({
      classes: Number(classes.total || 0),
      events: Number(events.total || 0),
      present: Number(attendance.present || 0),
      late: Number(attendance.late || 0),
      absent: Number(attendance.absent || 0),
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

function classRadiusForStudentCount(studentCount) {
  const count = Math.max(0, Number(studentCount) || 0);
  if (count <= 50) return 20;
  return Math.min(
    classAttendanceRadiusMeters,
    Math.ceil(20 + ((count - 50) / 50) * 80),
  );
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

async function checkInEventAttendance(request, response, payload, deviceId, coordinates) {
  if (typeof payload.eventId !== 'string' || !payload.eventId) {
    return response.status(410).json({ message: 'Mã QR sự kiện không hợp lệ.' });
  }
  const eventCoordinates = readCoordinates(payload);
  const radiusMeters = Number(payload.radiusMeters);
  if (!eventCoordinates || radiusMeters !== eventAttendanceRadiusMeters) {
    return response.status(410).json({
      message: 'Mã QR sự kiện thiếu thông tin vị trí hợp lệ hoặc đã hết hạn.',
    });
  }
  if (distanceInMeters(eventCoordinates, coordinates) > radiusMeters) {
    return response.status(403).json({
      message: `Bạn đang cách vị trí sự kiện quá xa (phạm vi ${radiusMeters} m).`,
    });
  }

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
                WHEN NOW() >= sk.Thoigianbatdau
                  AND NOW() < sk.Thoigianketthuc
                  AND sk.Trangthaisukien <> 'Đã đóng' THEN 1
                ELSE 0
              END AS isOpen
       FROM sukien sk
       WHERE sk.Masukien = ?
       FOR UPDATE`,
      [payload.eventId],
    );
    if (!event || Number(event.isOpen) !== 1) {
      await connection.rollback();
      return response.status(410).json({
        message: 'QR được nhận diện nhưng sự kiện chưa đến giờ điểm danh, đã kết thúc hoặc đã bị đóng.',
      });
    }

    const [[registration]] = await connection.execute(
      `SELECT Trangthaidangky AS status
       FROM dangkysukien
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
      `INSERT INTO event_attendance (event_id, student_id, device_id)
       VALUES (?, ?, ?)`,
      [event.id, request.auth.sub, deviceId],
    );
    const [[attendee]] = await connection.execute(
      `SELECT sk.Masukien AS eventId, sk.Tensukien AS eventName,
              sk.Diadiem AS location, sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              COALESCE(dv.Tendv, '') AS organizerName,
              ea.checked_in_at AS checkedInAt,
              nd.Mand AS studentId, COALESCE(nd.Hoten, nd.Mand) AS studentName
       FROM event_attendance ea
       INNER JOIN sukien sk ON sk.Masukien = ea.event_id
       LEFT JOIN donvi dv ON dv.Madv = sk.Madv
       INNER JOIN nguoidung nd ON nd.Mand = ea.student_id
       WHERE ea.event_id = ? AND ea.student_id = ?
       LIMIT 1`,
      [event.id, request.auth.sub],
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
        message: 'Bạn đã điểm danh sự kiện này hoặc thiết bị đã được dùng.',
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
      'SELECT Masv AS id FROM sinhvien WHERE Masv = ? LIMIT 1',
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
      const [[preview]] = await pool.execute(
        `SELECT sk.Masukien AS eventId, sk.Tensukien AS eventName,
                COALESCE(sk.Diadiem, '') AS location,
                sk.Thoigianbatdau AS startTime,
                sk.Thoigianketthuc AS endTime,
                COALESCE(dv.Tendv, '') AS organizerName,
                nd.Mand AS studentId,
                COALESCE(nd.Hoten, nd.Mand) AS studentName,
                CASE
                  WHEN NOW() >= sk.Thoigianbatdau
                    AND NOW() < sk.Thoigianketthuc
                    AND sk.Trangthaisukien <> 'Đã đóng' THEN 1
                  ELSE 0
                END AS isOpen
         FROM sukien sk
         LEFT JOIN donvi dv ON dv.Madv = sk.Madv
         JOIN nguoidung nd ON nd.Mand = ?
         WHERE sk.Masukien = ?
         LIMIT 1`,
        [request.auth.sub, payload.eventId],
      );
      if (!preview || Number(preview.isOpen) !== 1) {
        return response.status(410).json({
          message: 'Sự kiện chưa đến giờ điểm danh, đã kết thúc hoặc đã bị đóng.',
        });
      }
      const [[registration]] = await pool.execute(
        `SELECT Trangthaidangky AS status
         FROM dangkysukien
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
         FROM event_attendance
         WHERE event_id = ? AND student_id = ?
         LIMIT 1`,
        [preview.eventId, request.auth.sub],
      );
      if (existing) {
        return response.status(409).json({
          message: 'Bạn đã điểm danh sự kiện này.',
        });
      }
      return response.json({
        eventId: preview.eventId,
        eventName: preview.eventName,
        location: preview.location,
        startTime: preview.startTime,
        endTime: preview.endTime,
        organizerName: preview.organizerName,
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
function createAttendanceQr(sessionId, expiresAt, coordinates, radiusMeters) {
  return jwt.sign(
    {
      type: 'attendance',
      sessionId,
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      radiusMeters,
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
     FROM buoidiemdanh bpd
     INNER JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
     LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
     WHERE bpd.Mabuoidiemdanh = ?
       AND (
         ? IN ('Quản trị viên', 'admin')
         OR (? IN ('Giảng viên', 'lecturer') AND lhp.Magv = ?)
         OR (
           ? IN ('Cán bộ', 'Nhân viên', 'organizer', 'staff')
           AND EXISTS (
             SELECT 1 FROM donvi dv
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
app.get('/api/attendance/sessions', requireAuth, async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT b.Mabuoi AS classSessionId, b.Malop AS classId,
              COALESCE(lhp.Tenlop, '') AS className,
              COALESCE(mh.Tenmon, '') AS subjectName,
              b.Thoigianbatdau AS startTime,
              b.Thoigianketthuc AS endTime
             FROM buoi b
             LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
             LEFT JOIN monhoc mh ON mh.Mamon = lhp.Mamon
             WHERE (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)
             ORDER BY b.Thoigianbatdau DESC`,
      [request.auth.role, request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Attendance sessions error:', error.message);
    return response.status(500).json({ message: 'Không thể tải phiên điểm danh.' });
  }
});

// Lấy các phiên điểm danh cùng số lượt có mặt, trễ và vắng từ cơ sở dữ liệu.
app.get('/api/admin/attendance/sessions', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên', 'Cán bộ', 'Nhân viên', 'organizer', 'staff'), async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT bpd.Mabuoidiemdanh AS id, b.Malop AS classId,
              COALESCE(lhp.Tenlop, '') AS className,
              COALESCE(b.Noidung, '') AS sessionName,
              bpd.Thoigianmo AS openedAt, bpd.Thoigiandong AS closedAt,
              bpd.Phuongthuc AS method,
              bpd.Trangthaidiemdanh AS status,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
       FROM buoidiemdanh bpd
       INNER JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
       LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
       LEFT JOIN ketquadiemdanh kd ON kd.Mabuoidiemdanh = bpd.Mabuoidiemdanh
       WHERE (
         ? IN ('Quản trị viên', 'admin')
         OR (? IN ('Giảng viên', 'lecturer') AND lhp.Magv = ?)
         OR (
           ? IN ('Cán bộ', 'Nhân viên', 'organizer', 'staff')
           AND EXISTS (
             SELECT 1 FROM donvi dv
             WHERE dv.Madv = lhp.Madv AND dv.Manv = ?
           )
         )
       )
       GROUP BY bpd.Mabuoidiemdanh, b.Malop, lhp.Tenlop,
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
app.get('/api/admin/attendance/sessions/:sessionId/students', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên', 'Cán bộ', 'Nhân viên', 'organizer', 'staff'), async (request, response) => {
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

    const [items] = await pool.execute(
      `SELECT tvl.Masv AS studentId,
              COALESCE(nd.Hoten, tvl.Masv) AS studentName,
              COALESCE(nd.Email, '') AS email,
              kd.Maketqua AS attendanceId,
              kd.Trangthaiketqua AS attendanceStatus,
              kd.Thoigiandiemdanh AS checkedInAt
       FROM buoidiemdanh bpd
       INNER JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
       INNER JOIN thanhvienlop tvl ON tvl.Malop = b.Malop
       LEFT JOIN nguoidung nd ON nd.Mand = tvl.Masv
       LEFT JOIN ketquadiemdanh kd
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

// Ghi nhận hoặc cập nhật kết quả điểm danh thủ công của sinh viên trong phiên đang mở.
app.post('/api/admin/attendance/sessions/:sessionId/students/:studentId', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên', 'Cán bộ', 'Nhân viên', 'organizer', 'staff'), async (request, response) => {
  const statusLabels = new Map([
    ['present', 'Có mặt'],
    ['late', 'Đi trễ'],
    ['absent', 'Vắng mặt'],
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
       FROM thanhvienlop tvl
       INNER JOIN buoi b ON b.Malop = tvl.Malop
       INNER JOIN buoidiemdanh bpd ON bpd.Mabuoi = b.Mabuoi
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
       FROM ketquadiemdanh
       WHERE Mabuoidiemdanh = ? AND Masv = ?
       LIMIT 1
       FOR UPDATE`,
      [request.params.sessionId, request.params.studentId],
    );

    if (existing) {
      await connection.execute(
        `UPDATE ketquadiemdanh
         SET Thoigiandiemdanh = NOW(), Trangthaiketqua = ?
         WHERE Maketqua = ?`,
        [attendanceStatus, existing.id],
      );
    } else {
      await connection.execute(
        `INSERT INTO ketquadiemdanh
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

// Tổng hợp kết quả điểm danh theo trạng thái và ngày cho Admin/Giảng viên.
app.get('/api/reports/attendance', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (request, response) => {
  try {
    const scope = [request.auth.role, request.auth.sub];
    const [[summary]] = await pool.execute(
      `SELECT COUNT(kd.Maketqua) AS total,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
       FROM ketquadiemdanh kd
       INNER JOIN buoidiemdanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
       INNER JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
       LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
       WHERE (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)`,
      scope,
    );
    const [rows] = await pool.execute(
      `SELECT DATE(kd.Thoigiandiemdanh) AS date,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
              SUM(CASE WHEN kd.Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
       FROM ketquadiemdanh kd
       INNER JOIN buoidiemdanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
       INNER JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
       LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
       WHERE kd.Thoigiandiemdanh >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
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
  const { classSessionId, method = 'QR', durationMinutes = 15 } = request.body || {};
  const duration = Number(durationMinutes);
  const coordinates = readCoordinates(request.body);
  if (!classSessionId || !['QR', 'Face', 'Both'].includes(method)
      || !Number.isInteger(duration) || duration < 1 || duration > 180 || !coordinates) {
    return response.status(400).json({ message: 'Cần chọn buổi học và cho phép vị trí để mở điểm danh.' });
  }

  try {
    const [[classSession]] = await pool.execute(
      `SELECT b.Mabuoi AS id, b.Malop AS classId,
              lhp.Trangthailop AS classStatus,
              (lhp.Thoigianbatdau < DATE_SUB(NOW(), INTERVAL 1 YEAR)) AS isArchived,
              COUNT(
                CASE
                  WHEN tvl.Trangthaithanhvien = 'Đang tham gia' THEN tvl.Masv
                END
              ) AS studentCount
       FROM buoi b
       LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
       LEFT JOIN thanhvienlop tvl ON tvl.Malop = b.Malop
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
    const radiusMeters = classRadiusForStudentCount(classSession.studentCount);

    const openedAt = new Date();
    const closedAt = new Date(openedAt.getTime() + duration * 60 * 1000);
    const id = makeId('AT');
    await pool.execute(
      `INSERT INTO buoidiemdanh
        (Mabuoidiemdanh, Thoigianmo, Thoigiandong, Phuongthuc, Trangthaidiemdanh,
         Mabuoi, latitude, longitude, radius_meters)
         VALUES (?, ?, ?, ?, 'Đang mở', ?, ?, ?, ?)`,
      [
        id,
        openedAt,
        closedAt,
        method,
        classSessionId,
        coordinates.latitude,
        coordinates.longitude,
        radiusMeters,
      ],
    );
    return response.status(201).json({
      id,
      method,
      openedAt,
      closedAt,
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      radiusMeters,
      qr: method === 'Face'
        ? null
        : createAttendanceQr(id, closedAt, coordinates, radiusMeters),
    });
  } catch (error) {
    console.error('Create attendance session error:', error.message);
    return response.status(500).json({ message: 'Không thể tạo phiên điểm danh.' });
  }
});

// Xác thực mã QR, vị trí, thành viên lớp và ghi kết quả điểm danh.
app.post('/api/attendance/check-in', requireAuth, async (request, response) => {
  const { qrToken, method = 'QR', deviceId } = request.body || {};
  const coordinates = readCoordinates(request.body);
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

  if (!['student', 'sinh viên'].includes(String(request.auth.role).toLowerCase())) {
    return response.status(403).json({
      message: 'Sai tài khoản: hãy đăng nhập bằng tài khoản sinh viên để điểm danh.',
    });
  }

  try {
    const [[student]] = await pool.execute(
      'SELECT Masv AS id FROM sinhvien WHERE Masv = ? LIMIT 1',
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
             FROM buoidiemdanh bpd WHERE bpd.Mabuoidiemdanh = ? LIMIT 1`,
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
    if (!previewOnly && distanceInMeters(sessionCoordinates, coordinates) > radiusMeters) {
      return response.status(403).json({ message: `Bạn đang cách vị trí điểm danh quá xa (phạm vi ${radiusMeters} m).` });
    }
    if (session.method === 'Face' || (method === 'Face' && session.method === 'QR')) {
      return response.status(400).json({ message: 'Phương thức điểm danh không khớp.' });
    }

    const [[membership]] = await pool.execute(
      `SELECT 1 AS enrolled
       FROM buoidiemdanh bpd
       JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
       JOIN thanhvienlop tvl ON tvl.Malop = b.Malop
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
      `SELECT Maketqua AS id FROM ketquadiemdanh
       WHERE Mabuoidiemdanh = ? AND Masv = ? LIMIT 1`,
      [session.id, request.auth.sub],
    );
    if (existing) return response.status(409).json({ message: 'Bạn đã điểm danh phiên này.' });

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
                  FROM lichhocphan lh
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
         FROM buoidiemdanh bpd
         JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
         LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
         LEFT JOIN giangvien gv ON gv.Magv = lhp.Magv
         LEFT JOIN nguoidung lecturer ON lecturer.Mand = gv.Magv
         LEFT JOIN nguoidung attendee ON attendee.Mand = ?
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
        `INSERT INTO ketquadiemdanh
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
                FROM lichhocphan lh
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
       FROM ketquadiemdanh kd
       JOIN buoidiemdanh bpd ON bpd.Mabuoidiemdanh = kd.Mabuoidiemdanh
       JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
       LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
       LEFT JOIN giangvien gv ON gv.Magv = lhp.Magv
       LEFT JOIN nguoidung lecturer ON lecturer.Mand = gv.Magv
       LEFT JOIN nguoidung attendee ON attendee.Mand = kd.Masv
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
app.post('/api/attendance/face-check-in', requireAuth, async (request, response) => {
  const coordinates = readCoordinates(request.body);
  const deviceId = request.body?.deviceId;
  const recognizedStudentId = request.body?.recognizedStudentId;
  const previewOnly = request.body?.preview === true;
  if (typeof recognizedStudentId !== 'string'
      || recognizedStudentId !== request.auth.sub) {
    return response.status(403).json({
      message: 'Khuôn mặt không khớp với tài khoản đang đăng nhập.',
    });
  }
  if (!previewOnly && (typeof deviceId !== 'string' || !/^[a-f0-9]{32}$/.test(deviceId))) {
    return response.status(400).json({ message: 'Không xác định được thiết bị điểm danh.' });
  }
  if (!previewOnly && !coordinates) {
    return response.status(400).json({ message: 'Cần xác nhận vị trí hiện tại.' });
  }

  try {
    const [[session]] = await pool.execute(
      `SELECT bpd.Mabuoidiemdanh AS id, bpd.Phuongthuc AS method,
              bpd.Thoigiandong AS closedAt,
              bpd.latitude AS latitude, bpd.longitude AS longitude,
              bpd.radius_meters AS radiusMeters,
              b.Mabuoi AS classSessionId, b.Malop AS classId,
              COALESCE(lhp.Tenlop, '') AS className,
              COALESCE(b.Noidung, '') AS sessionName,
              b.Thoigianbatdau AS startTime, b.Thoigianketthuc AS endTime,
              COALESCE(lecturer.Hoten, '') AS lecturerName,
              COALESCE((
                SELECT GROUP_CONCAT(DISTINCT lh.PhongHoc
                  ORDER BY lh.PhongHoc SEPARATOR ', ')
                FROM lichhocphan lh
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
       FROM buoidiemdanh bpd
       JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
       JOIN thanhvienlop tvl ON tvl.Malop = b.Malop
       LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
       LEFT JOIN giangvien gv ON gv.Magv = lhp.Magv
       LEFT JOIN nguoidung lecturer ON lecturer.Mand = gv.Magv
       LEFT JOIN nguoidung attendee ON attendee.Mand = tvl.Masv
       WHERE tvl.Masv = ? AND bpd.Trangthaidiemdanh = 'Đang mở'
         AND bpd.Thoigiandong > NOW()
       ORDER BY bpd.Thoigianmo DESC LIMIT 1`,
      [request.auth.sub],
    );
    if (!session || !['Face', 'Both'].includes(session.method)) {
      return response.status(404).json({ message: 'Không có phiên khuôn mặt đang mở cho bạn.' });
    }
    if (previewOnly) {
      const [[existing]] = await pool.execute(
        `SELECT 1 AS id FROM ketquadiemdanh
         WHERE Mabuoidiemdanh = ? AND Masv = ? LIMIT 1`,
        [session.id, request.auth.sub],
      );
      if (existing) {
        return response.status(409).json({
          message: 'Bạn đã điểm danh phiên này.',
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

    const distance = distanceInMeters(
      { latitude: Number(session.latitude), longitude: Number(session.longitude) },
      coordinates,
    );
    const radiusMeters = Number(session.radiusMeters) || classAttendanceRadiusMeters;
    if (!Number.isFinite(distance) || distance > radiusMeters) {
      return response.status(403).json({ message: `Bạn đang cách vị trí điểm danh quá xa (phạm vi ${radiusMeters} m).` });
    }

    const [[existing]] = await pool.execute(
      `SELECT 1 AS id FROM ketquadiemdanh
       WHERE Mabuoidiemdanh = ? AND Masv = ? LIMIT 1`,
      [session.id, request.auth.sub],
    );
    if (existing) return response.status(409).json({ message: 'Bạn đã điểm danh phiên này.' });

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
        `INSERT INTO ketquadiemdanh
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
       FROM ketquadiemdanh
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

// Các tuyến quản lý sự kiện và đơn vị dành cho quản trị viên, ban tổ chức.
// Lấy danh sách sự kiện phục vụ màn hình quản lý.
app.get('/api/organizer/events', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  try {
    const [rows] = await pool.execute(
            `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Madv AS organizerId,
              sk.Diadiem AS location, sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              ${eventStatusSql} AS status,
              COALESCE(sk.Soluongtoida, 0) AS capacity,
              COUNT(dk.Masv) AS registeredCount,
              (SELECT COUNT(*)
               FROM event_attendance ea
               WHERE ea.event_id = sk.Masukien) AS checkedInCount
       FROM sukien sk
       LEFT JOIN dangkysukien dk ON dk.Masukien = sk.Masukien
       WHERE ? = 1 OR EXISTS (
         SELECT 1 FROM donvi dv WHERE dv.Madv = sk.Madv AND dv.Manv = ?
       )
      GROUP BY sk.Masukien, sk.Tensukien, sk.Madv, sk.Diadiem,
               sk.Thoigianbatdau, sk.Thoigianketthuc, sk.Trangthaisukien,
                sk.Soluongtoida
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
  try {
    const [[event]] = await pool.execute(
      `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Thoigianketthuc AS endTime,
              sk.Trangthaisukien AS status,
              EXISTS (
                SELECT 1 FROM donvi dv
                WHERE dv.Madv = sk.Madv AND dv.Manv = ?
              ) AS isOrganizer
       FROM sukien sk
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
    const expiresAt = new Date(event.endTime);
    if (event.status === 'Đã đóng' || expiresAt <= new Date()) {
      return response.status(409).json({
        message: 'Không thể tạo QR cho sự kiện đã đóng hoặc đã kết thúc.',
      });
    }
    const expiresIn = Math.floor(expiresAt.getTime() / 1000) - Math.floor(Date.now() / 1000);
    if (expiresIn <= 0) {
      return response.status(409).json({
        message: 'Sự kiện sắp kết thúc, không thể tạo mã QR mới.',
      });
    }
    const qr = jwt.sign(
      {
        type: 'event-attendance',
        eventId: event.id,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        radiusMeters: eventAttendanceRadiusMeters,
      },
      jwtSecret,
      { expiresIn },
    );
    return response.json({
      eventId: event.id,
      eventName: event.name,
      expiresAt,
      radiusMeters: eventAttendanceRadiusMeters,
      qr,
    });
  } catch (error) {
    console.error('Create event attendance QR error:', error.message);
    return response.status(500).json({
      message: 'Không thể tạo mã QR điểm danh sự kiện.',
    });
  }
});

app.post('/api/organizer/events/:eventId/certificates/send', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Cán bộ', 'Nhân viên', 'event_organizer'), async (request, response) => {
  const isAdmin = ['quản trị viên', 'admin'].includes(
    String(request.auth.role || '').trim().toLowerCase(),
  );
  let connection;
  try {
    const [[event]] = await pool.execute(
      `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Diadiem AS location,
              sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              sk.Trangthaisukien AS status,
              EXISTS (
                SELECT 1 FROM donvi dv
                WHERE dv.Madv = sk.Madv AND dv.Manv = ?
              ) AS isOrganizer
       FROM sukien sk
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
    if (new Date(event.endTime) > new Date()) {
      return response.status(409).json({
        message: 'Chỉ có thể gửi chứng nhận sau khi sự kiện kết thúc.',
      });
    }

    const [attendees] = await pool.execute(
      `SELECT ea.student_id AS studentId,
              COALESCE(nd.Hoten, ea.student_id) AS studentName,
              COALESCE(nd.Email, '') AS email
       FROM event_attendance ea
       LEFT JOIN nguoidung nd ON nd.Mand = ea.student_id
       WHERE ea.event_id = ?
       ORDER BY ea.checked_in_at, ea.student_id`,
      [event.id],
    );
    if (attendees.length === 0) {
      return response.status(409).json({
        message: 'Chưa có sinh viên điểm danh sự kiện để cấp chứng nhận.',
      });
    }

    let mailTransport;
    try {
      mailTransport = createMailTransport();
      await mailTransport.verify();
    } catch (error) {
      console.error('SMTP configuration error:', error.message);
      return response.status(503).json({
        message: `Không thể kết nối SMTP: ${error.message}`,
      });
    }

    const publicBaseUrl = (
      process.env.PUBLIC_API_BASE_URL
      || `${request.protocol}://${request.get('host')}`
    ).replace(/\/+$/, '');
    let sent = 0;
    const failures = [];

    for (const attendee of attendees) {
      if (!attendee.email.trim()) {
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
        const [[existingCertificate]] = await connection.execute(
          `SELECT Machungnhan AS id, Ngaycap AS issuedAt
           FROM chungnhan
           WHERE Masv = ? AND Masukien = ?
           ORDER BY Ngaycap DESC, Machungnhan DESC
           LIMIT 1
           FOR UPDATE`,
          [attendee.studentId, event.id],
        );
        let certificateId = existingCertificate?.id;
        let issuedAt = existingCertificate?.issuedAt;
        if (!certificateId) {
          const year = new Date().getFullYear();
          certificateId = `GCN-${year}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
          await connection.execute(
            `INSERT INTO chungnhan
              (Machungnhan, Masv, Masukien, Ngaycap, Noidung, Trangthaichungnhan)
             VALUES (?, ?, ?, NOW(), ?, 'Đã cấp')`,
            [
              certificateId,
              attendee.studentId,
              event.id,
              `Giấy chứng nhận tham gia sự kiện ${event.name}`,
            ],
          );
          issuedAt = new Date();
        }
        await connection.commit();
        connection.release();
        connection = null;

        const verificationUrl =
          `${publicBaseUrl}/api/certificates/${encodeURIComponent(certificateId)}`;
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
        });
        await mailTransport.sendMail({
          from: process.env.SMTP_FROM,
          to: attendee.email,
          subject: `Chứng nhận tham gia sự kiện ${event.name}`,
          text: `Xin chào ${attendee.studentName},\n\nBạn nhận được chứng nhận tham gia sự kiện "${event.name}". Chứng nhận PDF được đính kèm email này.\n\nBan tổ chức`,
          attachments: [{
            filename: `${certificateId}.pdf`,
            content: pdf,
            contentType: 'application/pdf',
          }],
        });
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

    return response.json({ eventId: event.id, sent, failures });
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

app.get('/api/organizer/events/:eventId/students', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Cán bộ', 'Nhân viên'), async (request, response) => {
  const isAdmin = ['Quản trị viên', 'admin'].includes(request.auth.role);
  try {
    const [[event]] = await pool.execute(
      `SELECT sk.Masukien AS id,
              EXISTS (
                SELECT 1 FROM donvi dv
                WHERE dv.Madv = sk.Madv AND dv.Manv = ?
              ) AS isOrganizer
       FROM sukien sk
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

    const [rows] = await pool.execute(
      `SELECT dk.Masv AS studentId,
              COALESCE(nd.Hoten, dk.Masv) AS studentName,
              COALESCE(nd.Email, '') AS email,
              COALESCE(dk.Trangthaidangky, '') AS status,
              CASE WHEN ea.checked_in_at IS NULL
                   THEN 'Chưa điểm danh' ELSE 'Đã điểm danh QR' END AS attendanceStatus,
              ea.checked_in_at AS checkedInAt,
              DATE_FORMAT(dk.Ngaydangky, '%d/%m/%Y') AS dateLabel
       FROM dangkysukien dk
       LEFT JOIN nguoidung nd ON nd.Mand = dk.Masv
       LEFT JOIN event_attendance ea
         ON ea.event_id = dk.Masukien AND ea.student_id = dk.Masv
       WHERE dk.Masukien = ?
       ORDER BY dk.Ngaydangky DESC, nd.Hoten, dk.Masv`,
      [request.params.eventId],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Organizer event students error:', error.message);
    return response.status(500).json({
      message: 'Không thể tải danh sách sinh viên đăng ký sự kiện.',
    });
  }
});

// Lấy danh sách đơn vị để dùng trong biểu mẫu sự kiện.
app.get('/api/organizer/units', requireAuth, requireRole(...eventManagerRoles), async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT Madv AS id, Tendv AS name
       FROM donvi
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
  const parsedCapacity = Number(capacity);
  const parsedStart = new Date(startTime);
  const parsedEnd = new Date(endTime);
  const contentResult = validateEventContent(body);

  if (!name || !organizerId || !location || !Number.isInteger(parsedCapacity)
      || parsedCapacity <= 0
      || !isValidEventTimeRange(parsedStart, parsedEnd, { requireFutureStart: true })) {
    return response.status(400).json({
      message: 'Thời gian sự kiện phải bắt đầu trong tương lai và kéo dài không quá 1 ngày.',
    });
  }
  if (contentResult.message) {
    return response.status(400).json({ message: contentResult.message });
  }

  try {
    if (!await managesUnit(pool, request.auth, organizerId.trim())) {
      return response.status(403).json({
        message: 'Bạn chỉ được tạo sự kiện cho đơn vị mình phụ trách.',
      });
    }
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const id = generateRecordId('EV');
      const connection = await pool.getConnection();
      try {
        await connection.beginTransaction();
        await connection.execute(
          `INSERT INTO sukien
           (Masukien, Tensukien, Madv, Mota, Thoigianbatdau,
            Thoigianketthuc, Diadiem, Soluongtoida, Trangthaisukien)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'Sắp diễn ra')`,
          [
            id,
            name.trim(),
            organizerId.trim(),
            contentResult.value.description,
            parsedStart,
            parsedEnd,
            location.trim(),
            parsedCapacity,
          ],
        );
        await replaceEventContent(connection, id, contentResult.value);
        await connection.commit();
        return response.status(201).json({ id, message: 'Tạo sự kiện thành công.' });
      } catch (error) {
        await connection.rollback();
        if (error.code !== 'ER_DUP_ENTRY' || attempt === 2) throw error;
      } finally {
        connection.release();
      }
    }
  } catch (error) {
    if (error.code === 'ER_DUP_ENTRY') {
      return response.status(409).json({ message: 'Không thể tạo mã sự kiện duy nhất.' });
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
  const parsedCapacity = Number(capacity);
  const parsedStart = new Date(startTime);
  const parsedEnd = new Date(endTime);
  const hasEventContent = ['description', 'benefits', 'rules']
    .some((field) => Object.hasOwn(body, field));
  const contentResult = validateEventContent(body);

  if (!name || !organizerId || !location || !Number.isInteger(parsedCapacity)
      || parsedCapacity <= 0
      || !isValidEventTimeRange(parsedStart, parsedEnd, { requireFutureEnd: true })) {
    return response.status(400).json({
      message: 'Thời gian sự kiện phải hợp lệ, còn thời gian diễn ra và kéo dài không quá 1 ngày.',
    });
  }
  if (hasEventContent && contentResult.message) {
    return response.status(400).json({ message: contentResult.message });
  }

  try {
    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const [[existing]] = await connection.execute(
        `SELECT Madv AS organizerId,
                Thoigianbatdau AS startTime, Thoigianketthuc AS endTime,
                Trangthaisukien AS status,
                (Thoigianbatdau < DATE_SUB(NOW(), INTERVAL 1 YEAR)) AS isArchived
         FROM sukien WHERE Masukien = ? FOR UPDATE`,
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
      const existingStart = new Date(existing.startTime).valueOf();
      const existingEnd = new Date(existing.endTime).valueOf();
      if (Date.now() >= existingEnd
          || Date.now() - existingStart > 24 * 60 * 60 * 1000
          || existingEnd - existingStart > 24 * 60 * 60 * 1000) {
        await connection.rollback();
        return response.status(409).json({
          message: 'Sự kiện đã kết thúc hoặc đã bắt đầu quá 1 ngày nên không thể chỉnh sửa.',
        });
      }
      const [[registrationCount]] = await connection.execute(
        'SELECT COUNT(*) AS total FROM dangkysukien WHERE Masukien = ?',
        [request.params.eventId],
      );
      const hasRegistrations = Number(registrationCount.total) > 0;
      if (hasRegistrations && (
        new Date(existing.startTime).valueOf() !== parsedStart.valueOf()
        || new Date(existing.endTime).valueOf() !== parsedEnd.valueOf()
      )) {
        await connection.rollback();
        return response.status(409).json({
          message: 'Không thể đổi lịch sự kiện sau khi đã có người đăng ký.',
        });
      }
      if (parsedCapacity < Number(registrationCount.total)) {
        await connection.rollback();
        return response.status(409).json({
          message: 'Sức chứa không thể thấp hơn số người đã đăng ký.',
        });
      }
      const [result] = await connection.execute(
        `UPDATE sukien
         SET Tensukien = ?, Madv = ?,
           Thoigianbatdau = ?, Thoigianketthuc = ?,
           Diadiem = ?, Soluongtoida = ?
         WHERE Masukien = ?`,
      [name.trim(), organizerId.trim(), parsedStart, parsedEnd, location.trim(), parsedCapacity, request.params.eventId],
      );
      if (hasEventContent) {
        await replaceEventContent(connection, request.params.eventId, contentResult.value);
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
      'SELECT Madv AS organizerId FROM sukien WHERE Masukien = ? LIMIT 1',
      [request.params.eventId],
    );
    if (!target) return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    if (!await managesUnit(pool, request.auth, target.organizerId)) {
      return response.status(403).json({ message: 'Bạn không phụ trách sự kiện này.' });
    }
    const [result] = await pool.execute(
      `UPDATE sukien SET Trangthaisukien = 'Đã đóng'
       WHERE Masukien = ? AND COALESCE(Trangthaisukien, '') <> 'Đã đóng'`,
      [request.params.eventId],
    );
    if (result.affectedRows === 0) {
      const [[event]] = await pool.execute(
        'SELECT Masukien FROM sukien WHERE Masukien = ? LIMIT 1',
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
      'SELECT Masukien, Madv AS organizerId FROM sukien WHERE Masukien = ? FOR UPDATE',
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
      'SELECT COUNT(*) AS total FROM dangkysukien WHERE Masukien = ?',
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
      'DELETE FROM sukien WHERE Masukien = ?',
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

app.get('/api/certificates/:certificateId', async (request, response) => {
  try {
    const [[certificate]] = await pool.execute(
      `SELECT cn.Machungnhan AS certificateId,
              COALESCE(nd.Hoten, cn.Masv) AS studentName,
              cn.Masv AS studentId, sk.Tensukien AS eventName,
              cn.Ngaycap AS issuedAt, cn.Trangthaichungnhan AS status
       FROM chungnhan cn
       INNER JOIN sukien sk ON sk.Masukien = cn.Masukien
       LEFT JOIN nguoidung nd ON nd.Mand = cn.Masv
       WHERE cn.Machungnhan = ?
       LIMIT 1`,
      [request.params.certificateId],
    );
    if (!certificate) {
      return response.status(404).json({ message: 'Không tìm thấy chứng nhận.' });
    }
    return response.json(certificate);
  } catch (error) {
    console.error('Verify certificate error:', error.message);
    return response.status(500).json({
      message: 'Không thể xác minh chứng nhận.',
    });
  }
});

// Lấy chứng chỉ từ cơ sở dữ liệu; cán bộ chỉ xem sự kiện thuộc đơn vị mình.
app.get('/api/staff/certificates', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên', 'Cán bộ', 'organizer', 'staff', 'employee'), async (request, response) => {
  const isAdmin = ['Quản trị viên', 'admin'].includes(request.auth.role);
  try {
    const [rows] = await pool.execute(
      `SELECT cn.Machungnhan AS id, cn.Masv AS studentId,
              COALESCE(nd.Hoten, cn.Masv) AS studentName,
              cn.Masukien AS eventId, sk.Tensukien AS eventName,
              cn.Ngaycap AS issuedAt, cn.Noidung AS content,
              cn.Trangthaichungnhan AS status
       FROM chungnhan cn
       JOIN sukien sk ON sk.Masukien = cn.Masukien
       LEFT JOIN nguoidung nd ON nd.Mand = cn.Masv
       WHERE (? = 1 OR EXISTS (
         SELECT 1 FROM donvi dv
         WHERE dv.Madv = sk.Madv AND dv.Manv = ?
       ))
       ORDER BY cn.Ngaycap DESC, cn.Machungnhan DESC`,
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
       FROM phanhoi ph
       LEFT JOIN nguoidung nd ON nd.Mand = ph.Masv
       LEFT JOIN sukien sk ON sk.Masukien = ph.Masukien
       LEFT JOIN lophocphan lhp ON lhp.Malop = ph.Malop
       WHERE (? = 1 OR (ph.Masukien IS NOT NULL AND EXISTS (
         SELECT 1 FROM donvi dv
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
       FROM danhgia dg
       LEFT JOIN nguoidung nd ON nd.Mand = dg.Masv
       LEFT JOIN sukien sk ON sk.Masukien = dg.Masukien
       LEFT JOIN lophocphan lhp ON lhp.Malop = dg.Malop
       WHERE (? = 1 OR (dg.Masukien IS NOT NULL AND EXISTS (
         SELECT 1 FROM donvi dv
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
             FROM nguoidung nd ORDER BY nd.Hoten`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin users error:', error.message);
    return response.status(500).json({ message: 'Không thể tải người dùng.' });
  }
});

// Lấy danh sách lớp học phần cho khu vực quản trị.
app.get('/api/admin/classes', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
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
       FROM lophocphan lhp
       INNER JOIN monhoc mh ON mh.Mamon = lhp.Mamon
       INNER JOIN bomon bm ON bm.Mabomon = mh.Mabomon
       LEFT JOIN giangvien gv ON gv.Magv = lhp.Magv
       LEFT JOIN nguoidung nd ON nd.Mand = gv.Magv
       LEFT JOIN thanhvienlop tvl ON tvl.Malop = lhp.Malop
       GROUP BY lhp.Malop, lhp.Tenlop, lhp.Magv, lhp.Madv, mh.Mabomon,
                bm.Tenbomon, bm.Maloptat, lhp.Makhoa, lhp.Mamon, mh.Mamon,
                mh.Tenmon, lhp.Tinchi, lhp.Soluongtoida,
                lhp.Thoigianbatdau, lhp.Hocky, lhp.Trangthailop, nd.Hoten
       ORDER BY lhp.Malop`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin classes error:', error.message);
    return response.status(500).json({ message: 'Không thể tải lớp học.' });
  }
});

app.get('/api/admin/classes/:classId/students', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (request, response) => {
  const isAdmin = ['Quản trị viên', 'admin'].includes(request.auth.role);
  try {
    const [[classInfo]] = await pool.execute(
      'SELECT Malop AS id, Magv AS lecturerId FROM lophocphan WHERE Malop = ? LIMIT 1',
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
       FROM thanhvienlop tvl
       LEFT JOIN nguoidung nd ON nd.Mand = tvl.Masv
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
      `SELECT Malop, Trangthailop AS status,
              (Thoigianbatdau < DATE_SUB(NOW(), INTERVAL 1 YEAR)) AS isArchived
       FROM lophocphan WHERE Malop = ? FOR UPDATE`,
      [request.params.classId],
    );
    if (!classInfo) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    if (classInfo.status === 'Đã đóng' || Number(classInfo.isArchived)) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Lớp đã đóng hoặc đã quá 1 năm nên không thể thêm sinh viên.',
      });
    }

    const placeholders = normalizedIds.map(() => '?').join(', ');
    const [students] = await connection.execute(
      `SELECT Masv FROM sinhvien WHERE Masv IN (${placeholders})`,
      normalizedIds,
    );
    const knownIds = new Set(students.map((student) => String(student.Masv).toUpperCase()));
    const unknownStudentIds = normalizedIds.filter((id) => !knownIds.has(id.toUpperCase()));
    const validIds = normalizedIds.filter((id) => knownIds.has(id.toUpperCase()));

    let existingIds = new Set();
    if (validIds.length > 0) {
      const validPlaceholders = validIds.map(() => '?').join(', ');
      const [existingMembers] = await connection.execute(
        `SELECT Masv FROM thanhvienlop
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
        `INSERT INTO thanhvienlop (Malop, Masv, NgayThamGia, TrangThaiThanhVien)
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
       SELECT DISTINCT MaKhoa AS code FROM sinhvien
       ORDER BY code DESC`,
    );
    const [subjects] = await pool.query(
      `SELECT mh.Mamon AS id, mh.Mamon AS code, mh.Tenmon AS name,
              mh.Sotinchi AS credits,
              mh.Hocky AS semester, bm.Mabomon AS majorId,
              bm.Tenbomon AS majorName, bm.Madv AS departmentId
       FROM monhoc mh
       INNER JOIN bomon bm ON bm.Mabomon = mh.Mabomon
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
       FROM giangvien gv
       LEFT JOIN nguoidung nd ON nd.Mand = gv.Magv
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
       FROM monhoc mh
       INNER JOIN bomon bm ON bm.Mabomon = mh.Mabomon
       WHERE mh.Mamon = ?`,
      [normalizedSubjectId],
    );
    if (!subject) {
      return response.status(400).json({ message: 'Môn học đã chọn không tồn tại.' });
    }
    const [cohorts] = await pool.execute(
      `SELECT MaKhoa FROM QuyUocKhoa WHERE MaKhoa = ?
       UNION
       SELECT MaKhoa FROM sinhvien WHERE MaKhoa = ? LIMIT 1`,
      [normalizedCohortCode, normalizedCohortCode],
    );
    if (cohorts.length === 0) {
      return response.status(400).json({ message: 'Khóa sinh viên đã chọn không tồn tại.' });
    }
    const normalizedSemester = requestedSemester || `HK${subject.Hocky}`;

    await pool.execute(
      `INSERT INTO lophocphan
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
       FROM lophocphan WHERE Malop = ? FOR UPDATE`,
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
      'SELECT COUNT(*) AS total FROM thanhvienlop WHERE Malop = ?',
      [request.params.classId],
    );
    if (parsedCapacity < Number(memberCount.total)) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Sĩ số tối đa không thể thấp hơn số sinh viên hiện có.',
      });
    }
    await connection.execute(
      `UPDATE lophocphan
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
      `UPDATE lophocphan SET Trangthailop = 'Đã đóng'
       WHERE Malop = ? AND COALESCE(Trangthailop, '') <> 'Đã đóng'`,
      [request.params.classId],
    );
    if (result.affectedRows === 0) {
      const [[classInfo]] = await pool.execute(
        'SELECT Malop FROM lophocphan WHERE Malop = ? LIMIT 1',
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
      'SELECT Malop FROM lophocphan WHERE Malop = ? FOR UPDATE',
      [request.params.classId],
    );
    if (!existing) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    const [[dependencies]] = await connection.execute(
      `SELECT
         (SELECT COUNT(*) FROM thanhvienlop WHERE Malop = ?) AS members,
         (SELECT COUNT(*) FROM buoi WHERE Malop = ?) AS sessions`,
      [request.params.classId, request.params.classId],
    );
    if (Number(dependencies.members) > 0 || Number(dependencies.sessions) > 0) {
      await connection.rollback();
      return response.status(409).json({
        message: 'Không thể xóa lớp đang có thành viên hoặc buổi học.',
      });
    }
    await connection.execute(
      'DELETE FROM lophocphan WHERE Malop = ?',
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
             FROM sukien sk
             LEFT JOIN dangkysukien dk ON dk.Masukien = sk.Masukien
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

ensureAttendanceLocationColumns()
  .then(async () => {
    await ensureAttendanceDeviceClaimsTable();
    await ensureEventAttendanceTable();
    await synchronizeEventStatuses();
    const statusSyncTimer = setInterval(() => {
      synchronizeEventStatuses().catch((error) => {
        console.error('Event status sync failed:', error.message);
      });
    }, 60_000);
    statusSyncTimer.unref();
    app.listen(port, '0.0.0.0', () => {
      console.log(`API listening on http://0.0.0.0:${port}`);
      console.log(`LAN URL: http://<IP_CUA_MAY_TINH>:${port}`);
    });
  })
  .catch((error) => {
    console.error('Database migration failed:', error.message);
    process.exit(1);
  });
