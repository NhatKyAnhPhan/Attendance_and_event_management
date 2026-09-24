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

async function ensureAttendanceLocationColumns() {
  for (const column of ['latitude', 'longitude']) {
    try {
      await pool.query(`ALTER TABLE \`buổi điểm danh\` ADD COLUMN \`${column}\` DECIMAL(10, 7) NULL`);
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

function requireRole(...roles) {
  return (request, response, next) => {
    if (!roles.includes(request.auth.role)) {
      return response.status(403).json({ message: 'Bạn không có quyền truy cập.' });
    }
    return next();
  };
}

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

app.post('/api/auth/login', async (request, response) => {
  const { identifier, password } = request.body || {};

  if (!identifier || !password) {
    return response.status(400).json({ message: 'Vui lòng nhập tài khoản và mật khẩu.' });
  }

  try {
    const [rows] = await pool.execute(
      `SELECT \`Mã người dùng\`, \`Họ tên\`, \`Email\`, \`Mật khẩu\`,
              \`Vai trò\`, \`Trạng thái người dùng\`
       FROM \`Người dùng\`
       WHERE \`Mã người dùng\` = ? OR \`Email\` = ?
       LIMIT 1`,
      [identifier, identifier],
    );
    const user = rows[0];

    if (!user || user['Trạng thái người dùng'] !== 'Đang hoạt động'
        || !passwordsMatch(password, user['Mật khẩu'])) {
      return response.status(401).json({ message: 'Tài khoản hoặc mật khẩu không đúng.' });
    }

    const token = jwt.sign(
      { sub: user['Mã người dùng'], role: user['Vai trò'] },
      jwtSecret,
      { expiresIn: '8h' },
    );

    return response.json({
      token,
      user: {
        id: user['Mã người dùng'],
        name: user['Họ tên'],
        email: user.Email,
        role: user['Vai trò'],
      },
    });
  } catch (error) {
    console.error('Login error:', error.message);
    return response.status(500).json({ message: 'Không thể kết nối cơ sở dữ liệu.' });
  }
});

app.get('/api/me', requireAuth, async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT nd.\`Mã người dùng\` AS id, nd.\`Họ tên\` AS name,
              nd.\`Email\` AS email, nd.\`Vai trò\` AS role,
              nd.\`Trạng thái người dùng\` AS status,
              sv.\`Lớp\` AS className, sv.\`Chuyên ngành\` AS major
       FROM \`Người dùng\` nd
       LEFT JOIN \`Sinh viên\` sv ON sv.\`Mã sinh viên\` = nd.\`Mã người dùng\`
       WHERE nd.\`Mã người dùng\` = ?
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

app.get('/api/classes', requireAuth, async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT lhp.\`Mã lớp\` AS id, lhp.\`Mã lớp\` AS code,
              lhp.\`Tên lớp\` AS name, lhp.\`Học kỳ\` AS semester,
              lhp.\`Năm học\` AS schoolYear, lhp.\`Mã giảng viên\` AS lecturerId,
              COALESCE(nd.\`Họ tên\`, '') AS lecturerName,
              COUNT(DISTINCT tvl.\`Mã sinh viên\`) AS studentCount
       FROM \`Lớp học phần\` lhp
       LEFT JOIN \`Giảng viên\` gv ON gv.\`Mã giảng viên\` = lhp.\`Mã giảng viên\`
       LEFT JOIN \`Người dùng\` nd ON nd.\`Mã người dùng\` = gv.\`Mã giảng viên\`
       LEFT JOIN \`Thành viên lớp\` tvl ON tvl.\`Mã lớp\` = lhp.\`Mã lớp\`
       WHERE EXISTS (
         SELECT 1 FROM \`Thành viên lớp\` mine
         WHERE mine.\`Mã lớp\` = lhp.\`Mã lớp\`
           AND mine.\`Mã sinh viên\` = ?
       )
       GROUP BY lhp.\`Mã lớp\`, lhp.\`Tên lớp\`, lhp.\`Học kỳ\`,
                lhp.\`Năm học\`, lhp.\`Mã giảng viên\`, nd.\`Họ tên\`
       ORDER BY lhp.\`Mã lớp\``,
      [request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Classes error:', error.message);
    return response.status(500).json({ message: 'Không thể tải danh sách lớp.' });
  }
});

app.get('/api/events', requireAuth, async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT sk.\`Mã sự kiện\` AS id, sk.\`Tên sự kiện\` AS name,
              sk.\`Mã đơn vị\` AS organizerId, COALESCE(dv.\`Tên đơn vị\`, '') AS organizerName,
              sk.\`Thời gian bắt đầu\` AS startTime, sk.\`Thời gian kết thúc\` AS endTime,
              COALESCE(sk.\`Địa điểm\`, '') AS location,
              COALESCE(sk.\`Số lượng tối đa\`, 0) AS capacity,
              COUNT(DISTINCT dkAll.\`Mã sinh viên\`) AS registeredCount,
              CASE WHEN dkMine.\`Mã sinh viên\` IS NULL THEN 'notRegistered'
                   ELSE LOWER(REPLACE(dkMine.\`Trạng thái đăng ký\`, ' ', '')) END AS registrationStatus
       FROM \`Sự kiện\` sk
       LEFT JOIN \`Đơn vị\` dv ON dv.\`Mã đơn vị\` = sk.\`Mã đơn vị\`
       LEFT JOIN \`Đăng ký sự kiện\` dkAll ON dkAll.\`Mã sự kiện\` = sk.\`Mã sự kiện\`
       LEFT JOIN \`Đăng ký sự kiện\` dkMine
         ON dkMine.\`Mã sự kiện\` = sk.\`Mã sự kiện\`
        AND dkMine.\`Mã sinh viên\` = ?
       GROUP BY sk.\`Mã sự kiện\`, sk.\`Tên sự kiện\`, sk.\`Mã đơn vị\`, dv.\`Tên đơn vị\`,
                sk.\`Thời gian bắt đầu\`, sk.\`Thời gian kết thúc\`, sk.\`Địa điểm\`,
                sk.\`Số lượng tối đa\`, dkMine.\`Mã sinh viên\`, dkMine.\`Trạng thái đăng ký\`
       ORDER BY sk.\`Thời gian bắt đầu\``,
      [request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Events error:', error.message);
    return response.status(500).json({ message: 'Không thể tải danh sách sự kiện.' });
  }
});

app.post('/api/events/:eventId/register', requireAuth, async (request, response) => {
  try {
    await pool.execute(
      `INSERT INTO \`Đăng ký sự kiện\`
       (\`Mã sự kiện\`, \`Mã sinh viên\`, \`Ngày đăng ký\`, \`Trạng thái đăng ký\`)
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

app.get('/api/dashboard', requireAuth, async (request, response) => {
  try {
    const [[classes]] = await pool.execute(
      `SELECT COUNT(*) AS total FROM \`Thành viên lớp\` WHERE \`Mã sinh viên\` = ?`,
      [request.auth.sub],
    );
    const [[events]] = await pool.execute(
      `SELECT COUNT(*) AS total FROM \`Đăng ký sự kiện\` WHERE \`Mã sinh viên\` = ?`,
      [request.auth.sub],
    );
    const [[attendance]] = await pool.execute(
      `SELECT
         SUM(CASE WHEN \`Trạng thái kết quả\` = 'Có mặt' THEN 1 ELSE 0 END) AS present,
         SUM(CASE WHEN \`Trạng thái kết quả\` = 'Đi trễ' THEN 1 ELSE 0 END) AS late,
         SUM(CASE WHEN \`Trạng thái kết quả\` = 'Vắng mặt' THEN 1 ELSE 0 END) AS absent
       FROM \`Kết quả điểm danh\` WHERE \`Mã sinh viên\` = ?`,
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

function makeId(prefix) {
  return `${prefix}_${crypto.randomBytes(10).toString('hex')}`.slice(0, 30);
}

const attendanceRadiusMeters = 150;

function readCoordinates(body) {
  const latitude = Number(body?.latitude);
  const longitude = Number(body?.longitude);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90
      || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return null;
  }
  return { latitude, longitude };
}

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

app.get('/api/attendance/sessions', requireAuth, async (request, response) => {
  try {
    const [rows] = await pool.execute(
      `SELECT b.\`Mã buổi\` AS classSessionId, b.\`Nội dung\` AS content,
              b.\`Mã lớp\` AS classId, b.\`Thời gian bắt đầu\` AS startTime,
              b.\`Thời gian kết thúc\` AS endTime
       FROM \`buổi\` b
       LEFT JOIN \`lớp học phần\` lhp ON lhp.\`Mã lớp\` = b.\`Mã lớp\`
       WHERE (? IN ('Quản trị viên', 'admin') OR lhp.\`Mã giảng viên\` = ?)
       ORDER BY b.\`Thời gian bắt đầu\` DESC`,
      [request.auth.role, request.auth.sub],
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Attendance sessions error:', error.message);
    return response.status(500).json({ message: 'Không thể tải phiên điểm danh.' });
  }
});

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
      `SELECT b.\`Mã buổi\` AS id
       FROM \`buổi\` b
       LEFT JOIN \`lớp học phần\` lhp ON lhp.\`Mã lớp\` = b.\`Mã lớp\`
       WHERE b.\`Mã buổi\` = ?
         AND (? IN ('Quản trị viên', 'admin') OR lhp.\`Mã giảng viên\` = ?)
       LIMIT 1`,
      [classSessionId, request.auth.role, request.auth.sub],
    );
    if (!classSession) return response.status(404).json({ message: 'Không tìm thấy buổi học.' });

    const openedAt = new Date();
    const closedAt = new Date(openedAt.getTime() + duration * 60 * 1000);
    const id = makeId('AT');
    await pool.execute(
      `INSERT INTO \`buổi điểm danh\`
         (\`Mã buổi điểm danh\`, \`Thời gian mở\`, \`Thời gian đóng\`, \`Phương thức\`, \`Trạng thái điểm danh\`, \`Mã buổi\`, \`latitude\`, \`longitude\`)
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
            `SELECT bpd.\`Mã buổi điểm danh\` AS id, bpd.\`Trạng thái điểm danh\` AS status,
              bpd.\`Thời gian đóng\` AS closedAt, bpd.\`Phương thức\` AS method
             FROM \`buổi điểm danh\` bpd WHERE bpd.\`Mã buổi điểm danh\` = ? LIMIT 1`,
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
       FROM \`buổi điểm danh\` bpd
       JOIN \`buổi\` b ON b.\`Mã buổi\` = bpd.\`Mã buổi\`
       JOIN \`thành viên lớp\` tvl ON tvl.\`Mã lớp\` = b.\`Mã lớp\`
       WHERE bpd.\`Mã buổi điểm danh\` = ? AND tvl.\`Mã sinh viên\` = ?
       LIMIT 1`,
      [session.id, request.auth.sub],
    );
    if (!membership) {
      return response.status(403).json({ message: 'Bạn không thuộc lớp của buổi điểm danh này.' });
    }

    const [[existing]] = await pool.execute(
      `SELECT \`Mã kết quả\` AS id FROM \`kết quả điểm danh\`
       WHERE \`Mã buổi điểm danh\` = ? AND \`Mã sinh viên\` = ? LIMIT 1`,
      [session.id, request.auth.sub],
    );
    if (existing) return response.status(409).json({ message: 'Bạn đã điểm danh phiên này.' });

    await pool.execute(
      `INSERT INTO \`kết quả điểm danh\`
       (\`Mã kết quả\`, \`Thời gian điểm danh\`, \`Trạng thái kết quả\`, \`Vị trí\`, \`Mã buổi điểm danh\`, \`Mã sinh viên\`)
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

app.post('/api/attendance/face-check-in', requireAuth, async (request, response) => {
  const coordinates = readCoordinates(request.body);
  if (!coordinates || request.body?.faceDetected !== true) {
    return response.status(400).json({ message: 'Cần xác nhận khuôn mặt và vị trí hiện tại.' });
  }

  try {
    const [[session]] = await pool.execute(
      `SELECT bpd.\`Mã buổi điểm danh\` AS id, bpd.\`Phương thức\` AS method,
              bpd.\`Thời gian đóng\` AS closedAt,
              bpd.\`latitude\` AS latitude, bpd.\`longitude\` AS longitude
       FROM \`buổi điểm danh\` bpd
       JOIN \`buổi\` b ON b.\`Mã buổi\` = bpd.\`Mã buổi\`
       JOIN \`thành viên lớp\` tvl ON tvl.\`Mã lớp\` = b.\`Mã lớp\`
       WHERE tvl.\`Mã sinh viên\` = ? AND bpd.\`Trạng thái điểm danh\` = 'Đang mở'
         AND bpd.\`Thời gian đóng\` > NOW()
       ORDER BY bpd.\`Thời gian mở\` DESC LIMIT 1`,
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
      `SELECT 1 AS id FROM \`kết quả điểm danh\`
       WHERE \`Mã buổi điểm danh\` = ? AND \`Mã sinh viên\` = ? LIMIT 1`,
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

app.get('/api/admin/users', requireAuth, requireRole('Quản trị viên', 'admin'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
      `SELECT nd.\`Mã người dùng\` AS id, nd.\`Họ tên\` AS name,
              nd.\`Email\` AS email, nd.\`Vai trò\` AS role,
              nd.\`Trạng thái người dùng\` AS status
       FROM \`Người dùng\` nd ORDER BY nd.\`Họ tên\``,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin users error:', error.message);
    return response.status(500).json({ message: 'Không thể tải người dùng.' });
  }
});

app.get('/api/admin/classes', requireAuth, requireRole('Quản trị viên', 'admin', 'Giảng viên'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
      `SELECT lhp.\`Mã lớp\` AS id, lhp.\`Tên lớp\` AS name,
              lhp.\`Học kỳ\` AS semester, lhp.\`Năm học\` AS schoolYear,
              COALESCE(nd.\`Họ tên\`, '') AS lecturerName,
              COUNT(tvl.\`Mã sinh viên\`) AS studentCount
       FROM \`Lớp học phần\` lhp
       LEFT JOIN \`Giảng viên\` gv ON gv.\`Mã giảng viên\` = lhp.\`Mã giảng viên\`
       LEFT JOIN \`Người dùng\` nd ON nd.\`Mã người dùng\` = gv.\`Mã giảng viên\`
       LEFT JOIN \`Thành viên lớp\` tvl ON tvl.\`Mã lớp\` = lhp.\`Mã lớp\`
       GROUP BY lhp.\`Mã lớp\`, lhp.\`Tên lớp\`, lhp.\`Học kỳ\`, lhp.\`Năm học\`, nd.\`Họ tên\`
       ORDER BY lhp.\`Mã lớp\``,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Admin classes error:', error.message);
    return response.status(500).json({ message: 'Không thể tải lớp học.' });
  }
});

app.get('/api/admin/events', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
      `SELECT sk.\`Mã sự kiện\` AS id, sk.\`Tên sự kiện\` AS name,
              sk.\`Địa điểm\` AS location, sk.\`Thời gian bắt đầu\` AS startTime,
              sk.\`Trạng thái sự kiện\` AS status,
              COUNT(dk.\`Mã sinh viên\`) AS registeredCount
       FROM \`Sự kiện\` sk
       LEFT JOIN \`Đăng ký sự kiện\` dk ON dk.\`Mã sự kiện\` = sk.\`Mã sự kiện\`
       GROUP BY sk.\`Mã sự kiện\`, sk.\`Tên sự kiện\`, sk.\`Địa điểm\`,
                sk.\`Thời gian bắt đầu\`, sk.\`Trạng thái sự kiện\`
      ORDER BY sk.\`Thời gian bắt đầu\``,
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
