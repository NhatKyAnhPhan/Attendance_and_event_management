require('dotenv').config();

const crypto = require('crypto');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const mysql = require('mysql2/promise');

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
  WHEN NOW() < sk.Thoigianbatdau THEN 'Sắp diễn ra'
  WHEN NOW() < sk.Thoigianketthuc THEN 'Đang diễn ra'
  ELSE 'Đã kết thúc'
END`;

async function synchronizeEventStatuses() {
  await pool.query(
    `UPDATE sukien sk
     SET Trangthaisukien = ${eventStatusSql}
     WHERE NOT (Trangthaisukien <=> ${eventStatusSql})`,
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

function isValidClassDateRange(startDate, endDate, schoolYear) {
  const isDateOnly = (value) => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      return false;
    }
    const [year, month, day] = value.split('-').map(Number);
    const parsed = new Date(Date.UTC(year, month - 1, day));
    return parsed.toISOString().slice(0, 10) === value;
  };

  const schoolYearMatch = typeof schoolYear === 'string'
    ? /^(\d{4})-\d{4}$/.exec(schoolYear.trim())
    : null;

  return isDateOnly(startDate)
    && isDateOnly(endDate)
    && startDate <= endDate
    && schoolYearMatch !== null
    && Number(startDate.slice(0, 4)) >= Number(schoolYearMatch[1]);
}

// Bổ sung cột tọa độ nếu cơ sở dữ liệu cũ chưa có thông tin vị trí.
async function ensureAttendanceLocationColumns() {
  for (const column of ['latitude', 'longitude']) {
    try {
      await pool.query(`ALTER TABLE \`buoidiemdanh\` ADD COLUMN \`${column}\` DECIMAL(10, 7) NULL`);
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

async function ensureClassPeriodColumns() {
  for (const column of ['Thoigianbatdau', 'Thoigianketthuc']) {
    try {
      await pool.query(`ALTER TABLE \`lophocphan\` ADD COLUMN \`${column}\` DATE NULL`);
    } catch (error) {
      if (error.code !== 'ER_DUP_FIELDNAME') throw error;
    }
  }
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

function requireAuth(request, response, next) {
  const header = request.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';

  if (!token) {
    return response.status(401).json({ message: 'Bạn chưa đăng nhập.' });
  }

  try {
    request.auth = jwt.verify(token, jwtSecret);
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
              Vaitro AS role, Trangthainguoidung AS status
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
              nd.Email AS email, nd.Vaitro AS role,
              nd.Trangthainguoidung AS status,
              sv.Lop AS className, sv.Chuyennganh AS major
             FROM nguoidung nd
             LEFT JOIN sinhvien sv ON sv.Masv = nd.Mand
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
              lhp.Namhoc AS schoolYear, lhp.Magv AS lecturerId,
              DATE_FORMAT(lhp.Thoigianbatdau, '%Y-%m-%d') AS startDate,
              DATE_FORMAT(lhp.Thoigianketthuc, '%Y-%m-%d') AS endDate,
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
                lhp.Namhoc, lhp.Magv, lhp.Thoigianbatdau,
                lhp.Thoigianketthuc, nd.Hoten, attendance.present,
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
                sk.Thoigianbatdau, sk.Thoigianketthuc, sk.Diadiem,
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
        "SELECT Thutu AS sortOrder, Trangthainoiquy AS text",
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

// Ghi nhận đăng ký tham gia sự kiện cho sinh viên hiện tại.
app.post('/api/events/:eventId/register', requireAuth, async (request, response) => {
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[event]] = await connection.execute(
      `SELECT Thoigianbatdau AS startTime, Thoigianketthuc AS endTime,
              Soluongtoida AS capacity
       FROM sukien WHERE Masukien = ? FOR UPDATE`,
      [request.params.eventId],
    );
    if (!event) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
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

const attendanceRadiusMeters = 150;

// Đọc và kiểm tra vĩ độ, kinh độ từ request hoặc payload QR.
function readCoordinates(body) {
  const latitude = Number(body?.latitude);
  const longitude = Number(body?.longitude);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90
      || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return null;
  }
  return { latitude, longitude };
}

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
function createAttendanceQr(sessionId, expiresAt, coordinates) {
  return jwt.sign(
    {
      type: 'attendance',
      sessionId,
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      radiusMeters: attendanceRadiusMeters,
      exp: Math.floor(expiresAt.getTime() / 1000),
    },
    jwtSecret,
  );
}

// Tải các buổi học mà giảng viên hoặc quản trị viên được phép mở điểm danh.
app.get('/api/attendance/sessions', requireAuth, async (request, response) => {
  try {
    const [rows] = await pool.execute(
            `SELECT b.Mabuoi AS classSessionId, b.Noidung AS content,
              b.Malop AS classId, b.Thoigianbatdau AS startTime,
              b.Thoigianketthuc AS endTime
             FROM buoi b
             LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
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
app.get('/api/admin/attendance/sessions', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (request, response) => {
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
       WHERE (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)
       GROUP BY bpd.Mabuoidiemdanh, b.Malop, lhp.Tenlop,
                b.Noidung, bpd.Thoigianmo, bpd.Thoigiandong,
                bpd.Phuongthuc, bpd.Trangthaidiemdanh
       ORDER BY bpd.Thoigianmo DESC`,
      [request.auth.role, request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin attendance sessions error:', error.message);
    return response.status(500).json({ message: 'Không thể tải phiên điểm danh.' });
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
      `SELECT b.Mabuoi AS id
       FROM buoi b
       LEFT JOIN lophocphan lhp ON lhp.Malop = b.Malop
       WHERE b.Mabuoi = ?
         AND (? IN ('Quản trị viên', 'admin') OR lhp.Magv = ?)
       LIMIT 1`,
      [classSessionId, request.auth.role, request.auth.sub],
    );
    if (!classSession) return response.status(404).json({ message: 'Không tìm thấy buổi học.' });

    const openedAt = new Date();
    const closedAt = new Date(openedAt.getTime() + duration * 60 * 1000);
    const id = makeId('AT');
    await pool.execute(
      `INSERT INTO buoidiemdanh
        (Mabuoidiemdanh, Thoigianmo, Thoigiandong, Phuongthuc, Trangthaidiemdanh, Mabuoi, latitude, longitude)
         VALUES (?, ?, ?, ?, 'Đang mở', ?, ?, ?)`,
        [id, openedAt, closedAt, method, classSessionId, coordinates.latitude, coordinates.longitude],
    );
    return response.status(201).json({
      id,
      method,
      openedAt,
      closedAt,
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      radiusMeters: attendanceRadiusMeters,
      qr: method === 'Face' ? null : createAttendanceQr(id, closedAt, coordinates),
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
  if (!qrToken || !['QR', 'Face'].includes(method)) {
    return response.status(400).json({ message: 'Thiếu dữ liệu điểm danh.' });
  }
  if (typeof deviceId !== 'string' || !/^[a-f0-9]{32}$/.test(deviceId)) {
    return response.status(400).json({ message: 'Không xác định được thiết bị điểm danh.' });
  }
  if (!coordinates) {
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
    const radiusMeters = Number(payload.radiusMeters) || attendanceRadiusMeters;
    if (!sessionCoordinates || distanceInMeters(sessionCoordinates, coordinates) > radiusMeters) {
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
  if (typeof deviceId !== 'string' || !/^[a-f0-9]{32}$/.test(deviceId)) {
    return response.status(400).json({ message: 'Không xác định được thiết bị điểm danh.' });
  }
  if (!coordinates || request.body?.faceDetected !== true) {
    return response.status(400).json({ message: 'Cần xác nhận khuôn mặt và vị trí hiện tại.' });
  }

  try {
    const [[session]] = await pool.execute(
      `SELECT bpd.Mabuoidiemdanh AS id, bpd.Phuongthuc AS method,
              bpd.Thoigiandong AS closedAt,
              bpd.latitude AS latitude, bpd.longitude AS longitude
       FROM buoidiemdanh bpd
       JOIN buoi b ON b.Mabuoi = bpd.Mabuoi
       JOIN thanhvienlop tvl ON tvl.Malop = b.Malop
       WHERE tvl.Masv = ? AND bpd.Trangthaidiemdanh = 'Đang mở'
         AND bpd.Thoigiandong > NOW()
       ORDER BY bpd.Thoigianmo DESC LIMIT 1`,
      [request.auth.sub],
    );
    if (!session || !['Face', 'Both'].includes(session.method)) {
      return response.status(404).json({ message: 'Không có phiên khuôn mặt đang mở cho bạn.' });
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
    if (!Number.isFinite(distance) || distance > attendanceRadiusMeters) {
      return response.status(403).json({ message: `Bạn đang cách vị trí điểm danh quá xa (phạm vi ${attendanceRadiusMeters} m).` });
    }

    const [[existing]] = await pool.execute(
      `SELECT 1 AS id FROM ketquadiemdanh
       WHERE Mabuoidiemdanh = ? AND Masv = ? LIMIT 1`,
      [session.id, request.auth.sub],
    );
    if (existing) return response.status(409).json({ message: 'Bạn đã điểm danh phiên này.' });

    return response.status(501).json({
      message: 'Đã nhận diện khuôn mặt nhưng hệ thống chưa có mẫu khuôn mặt để xác thực danh tính.',
    });
  } catch (error) {
    console.error('Face check-in error:', error.message);
    return response.status(500).json({ message: 'Không thể ghi nhận điểm danh khuôn mặt.' });
  }
});

// Các tuyến quản lý sự kiện và đơn vị dành cho quản trị viên, ban tổ chức.
// Lấy danh sách sự kiện phục vụ màn hình quản lý.
app.get('/api/organizer/events', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Cán bộ', 'Nhân viên'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
            `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Madv AS organizerId,
              sk.Diadiem AS location, sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              ${eventStatusSql} AS status,
              COALESCE(sk.Soluongtoida, 0) AS capacity,
              COUNT(dk.Masv) AS registeredCount
       FROM sukien sk
       LEFT JOIN dangkysukien dk ON dk.Masukien = sk.Masukien
      GROUP BY sk.Masukien, sk.Tensukien, sk.Madv, sk.Diadiem,
                sk.Thoigianbatdau, sk.Thoigianketthuc,
                sk.Soluongtoida
       ORDER BY sk.Thoigianbatdau`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Organizer events error:', error.message);
    return response.status(500).json({ message: 'Không thể tải sự kiện.' });
  }
});

// Lấy danh sách đơn vị để dùng trong biểu mẫu sự kiện.
app.get('/api/organizer/units', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Cán bộ', 'Nhân viên'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
      `SELECT Madv AS id, Tendv AS name
       FROM donvi ORDER BY Tendv`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Organizer units error:', error.message);
    return response.status(500).json({ message: 'Không thể tải đơn vị tổ chức.' });
  }
});

// Kiểm tra dữ liệu biểu mẫu và tạo sự kiện mới trong cơ sở dữ liệu.
app.post('/api/organizer/events', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'event_organizer'), async (request, response) => {
  const { name, organizerId, startTime, endTime, location, capacity } = request.body || {};
  const parsedCapacity = Number(capacity);
  const parsedStart = new Date(startTime);
  const parsedEnd = new Date(endTime);

  if (!name || !organizerId || !location || !Number.isInteger(parsedCapacity)
      || parsedCapacity <= 0
      || !isValidEventTimeRange(parsedStart, parsedEnd, { requireFutureStart: true })) {
    return response.status(400).json({
      message: 'Thời gian sự kiện phải bắt đầu trong tương lai và kéo dài không quá 1 ngày.',
    });
  }

  try {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const id = generateRecordId('EV');
      try {
        await pool.execute(
          `INSERT INTO sukien
           (Masukien, Tensukien, Madv, Thoigianbatdau,
            Thoigianketthuc, Diadiem, Soluongtoida, Trangthaisukien)
           VALUES (?, ?, ?, ?, ?, ?, ?, 'Sắp diễn ra')`,
          [id, name.trim(), organizerId.trim(), parsedStart, parsedEnd, location.trim(), parsedCapacity],
        );
        return response.status(201).json({ id, message: 'Tạo sự kiện thành công.' });
      } catch (error) {
        if (error.code !== 'ER_DUP_ENTRY' || attempt === 2) throw error;
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
app.put('/api/organizer/events/:eventId', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'event_organizer'), async (request, response) => {
  const { name, organizerId, startTime, endTime, location, capacity } = request.body || {};
  const parsedCapacity = Number(capacity);
  const parsedStart = new Date(startTime);
  const parsedEnd = new Date(endTime);

  if (!name || !organizerId || !location || !Number.isInteger(parsedCapacity)
      || parsedCapacity <= 0
      || !isValidEventTimeRange(parsedStart, parsedEnd, { requireFutureEnd: true })) {
    return response.status(400).json({
      message: 'Thời gian sự kiện phải hợp lệ, còn thời gian diễn ra và kéo dài không quá 1 ngày.',
    });
  }

  try {
    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const [[existing]] = await connection.execute(
        'SELECT Thoigianbatdau AS startTime, Thoigianketthuc AS endTime FROM sukien WHERE Masukien = ? FOR UPDATE',
        [request.params.eventId],
      );
      if (!existing) {
        await connection.rollback();
        return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
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

// Xóa sự kiện sau khi kiểm tra mã sự kiện và ràng buộc dữ liệu liên quan.
app.delete('/api/organizer/events/:eventId', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [[event]] = await connection.execute(
      'SELECT Masukien FROM sukien WHERE Masukien = ? FOR UPDATE',
      [request.params.eventId],
    );
    if (!event) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
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
              nd.Trangthainguoidung AS status
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
              lhp.Magv AS lecturerId,
              lhp.Hocky AS semester, lhp.Namhoc AS schoolYear,
              DATE_FORMAT(lhp.Thoigianbatdau, '%Y-%m-%d') AS startDate,
              DATE_FORMAT(lhp.Thoigianketthuc, '%Y-%m-%d') AS endDate,
              COALESCE(nd.Hoten, '') AS lecturerName,
              COUNT(tvl.Masv) AS studentCount
             FROM lophocphan lhp
             LEFT JOIN giangvien gv ON gv.Magv = lhp.Magv
             LEFT JOIN nguoidung nd ON nd.Mand = gv.Magv
             LEFT JOIN thanhvienlop tvl ON tvl.Malop = lhp.Malop
             GROUP BY lhp.Malop, lhp.Tenlop, lhp.Hocky, lhp.Namhoc,
                      lhp.Thoigianbatdau, lhp.Thoigianketthuc, nd.Hoten
             ORDER BY lhp.Malop`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin classes error:', error.message);
    return response.status(500).json({ message: 'Không thể tải lớp học.' });
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
    sourceClassId,
    semester = '',
    schoolYear = '',
    lecturerId = null,
    startDate,
    endDate,
  } = request.body || {};
  if (typeof sourceClassId !== 'string' || !sourceClassId.trim()
    || !isValidClassDateRange(startDate, endDate, schoolYear)) {
    return response.status(400).json({
      message: 'Môn học có sẵn và khoảng ngày học kỳ hợp lệ là bắt buộc.',
    });
  }
  const normalizedLecturerId = typeof lecturerId === 'string' && lecturerId.trim()
    ? lecturerId.trim()
    : null;
  if (!normalizedLecturerId) {
    return response.status(400).json({ message: 'Vui lòng chọn giảng viên.' });
  }

  try {
    const [[sourceClass]] = await pool.execute(
      'SELECT Tenlop AS name FROM lophocphan WHERE Malop = ?',
      [sourceClassId.trim()],
    );
    if (!sourceClass || !String(sourceClass.name || '').trim()) {
      return response.status(400).json({ message: 'Môn học đã chọn không tồn tại.' });
    }
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const id = generateRecordId('CL');
      try {
        await pool.execute(
          `INSERT INTO lophocphan
           (Malop, Magv, Tenlop, Hocky, Namhoc, Thoigianbatdau,
            Thoigianketthuc, Trangthailop)
           VALUES (?, ?, ?, ?, ?, ?, ?, 'Đang học')`,
          [id, normalizedLecturerId, sourceClass.name, String(semester).trim(), String(schoolYear).trim(), startDate, endDate],
        );
        return response.status(201).json({ id, message: 'Tạo lớp thành công.' });
      } catch (error) {
        if (error.code !== 'ER_DUP_ENTRY' || attempt === 2) throw error;
      }
    }
  } catch (error) {
    if (error.code === 'ER_NO_REFERENCED_ROW_2') {
      return response.status(400).json({ message: 'Giảng viên không tồn tại.' });
    }
    console.error('Create admin class error:', error.message);
    return response.status(500).json({ message: 'Không thể tạo lớp.' });
  }
});

app.put('/api/admin/classes/:classId', requireAuth, requireRole('Quản trị viên', 'admin'), async (request, response) => {
  const {
    name,
    semester = '',
    schoolYear = '',
    lecturerId = null,
    startDate,
    endDate,
  } = request.body || {};
  if (typeof name !== 'string' || !name.trim()
    || !isValidClassDateRange(startDate, endDate, schoolYear)) {
    return response.status(400).json({
      message: 'Tên lớp hợp lệ và ngày kết thúc phải bằng hoặc sau ngày bắt đầu.',
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
      'SELECT Malop FROM lophocphan WHERE Malop = ? FOR UPDATE',
      [request.params.classId],
    );
    if (!existing) {
      await connection.rollback();
      return response.status(404).json({ message: 'Không tìm thấy lớp.' });
    }
    await connection.execute(
      `UPDATE lophocphan
         SET Magv = ?, Tenlop = ?, Hocky = ?, Namhoc = ?,
           Thoigianbatdau = ?, Thoigianketthuc = ?
       WHERE Malop = ?`,
        [normalizedLecturerId, name.trim(), String(semester).trim(), String(schoolYear).trim(), startDate, endDate, request.params.classId],
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
          sk.Thoigianbatdau, sk.Thoigianketthuc
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
    await ensureClassPeriodColumns();
    await synchronizeEventStatuses();
    const statusSyncTimer = setInterval(() => {
      synchronizeEventStatuses().catch((error) => {
        console.error('Event status sync failed:', error.message);
      });
    }, 60_000);
    statusSyncTimer.unref();
    app.listen(port, () => {
      console.log(`API listening on http://localhost:${port}`);
    });
  })
  .catch((error) => {
    console.error('Database migration failed:', error.message);
    process.exit(1);
  });
