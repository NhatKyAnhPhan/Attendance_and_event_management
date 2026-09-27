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
  return (request, response, next) => {
    if (!roles.includes(request.auth.role)) {
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
              COALESCE(nd.Hoten, '') AS lecturerName,
              COUNT(DISTINCT tvl.Masv) AS studentCount
       FROM lophocphan lhp
       LEFT JOIN giangvien gv ON gv.Magv = lhp.Magv
       LEFT JOIN nguoidung nd ON nd.Mand = gv.Magv
       LEFT JOIN thanhvienlop tvl ON tvl.Malop = lhp.Malop
       WHERE EXISTS (
         SELECT 1 FROM thanhvienlop mine
         WHERE mine.Malop = lhp.Malop
           AND mine.Masv = ?
       )
       GROUP BY lhp.Malop, lhp.Tenlop, lhp.Hocky,
                lhp.Namhoc, lhp.Magv, nd.Hoten
       ORDER BY lhp.Malop`,
      [request.auth.sub],
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
              COALESCE(sk.Diadiem, '') AS location,
              COALESCE(sk.Soluongtoida, 0) AS capacity,
              COUNT(DISTINCT dkAll.Masv) AS registeredCount,
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
                sk.Soluongtoida, dkMine.Masv, dkMine.Trangthaidangky
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
        "(SELECT COUNT(*) FROM dangkysukien mine",
        "WHERE mine.Masukien = sk.Masukien AND mine.Masv = ?) AS isRegistered",
        "FROM sukien sk INNER JOIN donvi dv ON dv.Madv = sk.Madv",
        "WHERE sk.Masukien = ? LIMIT 1",
      ].join(' '),
      [request.auth.sub, request.params.eventId],
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
  try {
    await pool.execute(
      `INSERT INTO dangkysukien
       (Masukien, Masv, Ngaydangky, Trangthaidangky)
       VALUES (?, ?, NOW(), 'Chờ duyệt')`,
      [request.params.eventId, request.auth.sub],
    );
    return response.status(201).json({ message: 'Đăng ký sự kiện thành công.' });
  } catch (error) {
    if (error.code === 'ER_DUP_ENTRY') {
      return response.status(409).json({ message: 'Bạn đã đăng ký sự kiện này.' });
    }
    console.error('Event registration error:', error.message);
    return response.status(500).json({ message: 'Không thể đăng ký sự kiện.' });
  }
});

// Tổng hợp số lớp, sự kiện và kết quả điểm danh của sinh viên.
app.get('/api/dashboard', requireAuth, async (request, response) => {
  try {
    const [[classes]] = await pool.execute(
      `SELECT COUNT(*) AS total FROM thanhvienlop WHERE Masv = ?`,
      [request.auth.sub],
    );
    const [[events]] = await pool.execute(
      `SELECT COUNT(*) AS total FROM dangkysukien WHERE Masv = ?`,
      [request.auth.sub],
    );
    const [[attendance]] = await pool.execute(
      `SELECT
         SUM(CASE WHEN Trangthaiketqua = 'Có mặt' THEN 1 ELSE 0 END) AS present,
         SUM(CASE WHEN Trangthaiketqua = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
         SUM(CASE WHEN Trangthaiketqua = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
       FROM ketquadiemdanh WHERE Masv = ?`,
      [request.auth.sub],
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
  const { qrToken, method = 'QR' } = request.body || {};
  const coordinates = readCoordinates(request.body);
  if (!qrToken || !['QR', 'Face'].includes(method)) {
    return response.status(400).json({ message: 'Thiếu dữ liệu điểm danh.' });
  }
  if (!coordinates) {
    return response.status(400).json({ message: 'Không lấy được vị trí hiện tại của bạn.' });
  }

  try {
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
      return response.status(403).json({ message: 'Bạn không thuộc lớp của buổi điểm danh này.' });
    }

    const [[existing]] = await pool.execute(
      `SELECT Maketqua AS id FROM ketquadiemdanh
       WHERE Mabuoidiemdanh = ? AND Masv = ? LIMIT 1`,
      [session.id, request.auth.sub],
    );
    if (existing) return response.status(409).json({ message: 'Bạn đã điểm danh phiên này.' });

    await pool.execute(
      `INSERT INTO ketquadiemdanh
       (Maketqua, Thoigiandiemdanh, Trangthaiketqua, Vitri, Mabuoidiemdanh, Masv)
       VALUES (?, NOW(), 'Có mặt', ?, ?, ?)`,
      [makeId('RS'), JSON.stringify(coordinates), session.id, request.auth.sub],
    );
    return response.status(201).json({ message: 'Điểm danh thành công.', sessionId: session.id });
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
app.get('/api/organizer/events', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
            `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Madv AS organizerId,
              sk.Diadiem AS location, sk.Thoigianbatdau AS startTime,
              sk.Thoigianketthuc AS endTime,
              sk.Trangthaisukien AS status,
              COALESCE(sk.Soluongtoida, 0) AS capacity,
              COUNT(dk.Masv) AS registeredCount
       FROM sukien sk
       LEFT JOIN dangkysukien dk ON dk.Masukien = sk.Masukien
      GROUP BY sk.Masukien, sk.Tensukien, sk.Madv, sk.Diadiem,
                sk.Thoigianbatdau, sk.Thoigianketthuc,
                sk.Trangthaisukien, sk.Soluongtoida
       ORDER BY sk.Thoigianbatdau`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Organizer events error:', error.message);
    return response.status(500).json({ message: 'Không thể tải sự kiện.' });
  }
});

// Lấy danh sách đơn vị để dùng trong biểu mẫu sự kiện.
app.get('/api/organizer/units', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (_request, response) => {
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
app.post('/api/organizer/events', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (request, response) => {
  const { id, name, organizerId, startTime, endTime, location, capacity } = request.body || {};
  const parsedCapacity = Number(capacity);
  const parsedStart = new Date(startTime);
  const parsedEnd = new Date(endTime);

  if (!id || !name || !organizerId || !location || !Number.isInteger(parsedCapacity)
      || parsedCapacity <= 0 || Number.isNaN(parsedStart.valueOf())
      || Number.isNaN(parsedEnd.valueOf()) || parsedEnd <= parsedStart) {
    return response.status(400).json({ message: 'Thông tin sự kiện không hợp lệ.' });
  }

  try {
    await pool.execute(
      `INSERT INTO sukien
       (Masukien, Tensukien, Madv, Thoigianbatdau,
        Thoigianketthuc, Diadiem, Soluongtoida, Trangthaisukien)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'Sắp diễn ra')`,
      [id.trim(), name.trim(), organizerId.trim(), parsedStart, parsedEnd, location.trim(), parsedCapacity],
    );
    return response.status(201).json({ message: 'Tạo sự kiện thành công.' });
  } catch (error) {
    if (error.code === 'ER_DUP_ENTRY') {
      return response.status(409).json({ message: 'Mã sự kiện đã tồn tại.' });
    }
    if (error.code === 'ER_NO_REFERENCED_ROW_2') {
      return response.status(400).json({ message: 'Đơn vị tổ chức không tồn tại.' });
    }
    console.error('Create organizer event error:', error.message);
    return response.status(500).json({ message: 'Không thể tạo sự kiện.' });
  }
});

// Kiểm tra dữ liệu biểu mẫu và cập nhật sự kiện theo mã định danh.
app.put('/api/organizer/events/:eventId', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (request, response) => {
  const { name, organizerId, startTime, endTime, location, capacity } = request.body || {};
  const parsedCapacity = Number(capacity);
  const parsedStart = new Date(startTime);
  const parsedEnd = new Date(endTime);

  if (!name || !organizerId || !location || !Number.isInteger(parsedCapacity)
      || parsedCapacity <= 0 || Number.isNaN(parsedStart.valueOf())
      || Number.isNaN(parsedEnd.valueOf()) || parsedEnd <= parsedStart) {
    return response.status(400).json({ message: 'Thông tin sự kiện không hợp lệ.' });
  }

  try {
    const [result] = await pool.execute(
        `UPDATE sukien
         SET Tensukien = ?, Madv = ?,
           Thoigianbatdau = ?, Thoigianketthuc = ?,
           Diadiem = ?, Soluongtoida = ?
         WHERE Masukien = ?`,
      [name.trim(), organizerId.trim(), parsedStart, parsedEnd, location.trim(), parsedCapacity, request.params.eventId],
    );
    if (result.affectedRows === 0) {
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    return response.json({ message: 'Cập nhật sự kiện thành công.' });
  } catch (error) {
    if (error.code === 'ER_NO_REFERENCED_ROW_2') {
      return response.status(400).json({ message: 'Đơn vị tổ chức không tồn tại.' });
    }
    console.error('Update organizer event error:', error.message);
    return response.status(500).json({ message: 'Không thể cập nhật sự kiện.' });
  }
});

// Xóa sự kiện sau khi kiểm tra mã sự kiện và ràng buộc dữ liệu liên quan.
app.delete('/api/organizer/events/:eventId', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (request, response) => {
  try {
    const [result] = await pool.execute(
      'DELETE FROM sukien WHERE Masukien = ?',
      [request.params.eventId],
    );
    if (result.affectedRows === 0) {
      return response.status(404).json({ message: 'Không tìm thấy sự kiện.' });
    }
    return response.json({ message: 'Xóa sự kiện thành công.' });
  } catch (error) {
    console.error('Delete organizer event error:', error.message);
    return response.status(409).json({
      message: 'Không thể xóa sự kiện đã có dữ liệu đăng ký hoặc điểm danh.',
    });
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
            `SELECT lhp.Malop AS id, lhp.Tenlop AS name,
              lhp.Hocky AS semester, lhp.Namhoc AS schoolYear,
              COALESCE(nd.Hoten, '') AS lecturerName,
              COUNT(tvl.Masv) AS studentCount
             FROM lophocphan lhp
             LEFT JOIN giangvien gv ON gv.Magv = lhp.Magv
             LEFT JOIN nguoidung nd ON nd.Mand = gv.Magv
             LEFT JOIN thanhvienlop tvl ON tvl.Malop = lhp.Malop
             GROUP BY lhp.Malop, lhp.Tenlop, lhp.Hocky, lhp.Namhoc, nd.Hoten
             ORDER BY lhp.Malop`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin classes error:', error.message);
    return response.status(500).json({ message: 'Không thể tải lớp học.' });
  }
});

// Lấy danh sách sự kiện và số lượng đăng ký cho khu vực quản trị.
app.get('/api/admin/events', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
            `SELECT sk.Masukien AS id, sk.Tensukien AS name,
              sk.Diadiem AS location, sk.Thoigianbatdau AS startTime,
              sk.Trangthaisukien AS status,
              COUNT(dk.Masv) AS registeredCount
             FROM sukien sk
             LEFT JOIN dangkysukien dk ON dk.Masukien = sk.Masukien
             GROUP BY sk.Masukien, sk.Tensukien, sk.Diadiem,
          sk.Thoigianbatdau, sk.Trangthaisukien
            ORDER BY sk.Thoigianbatdau`,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin events error:', error.message);
    return response.status(500).json({ message: 'Không thể tải sự kiện.' });
  }
});

ensureAttendanceLocationColumns()
  .then(() => app.listen(port, () => {
    console.log(`API listening on http://localhost:${port}`);
  }))
  .catch((error) => {
    console.error('Attendance location migration failed:', error.message);
    process.exit(1);
  });
