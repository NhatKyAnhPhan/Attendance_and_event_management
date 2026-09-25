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

app.get('/api/organizer/events', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
            `SELECT sk.\`Mã sự kiện\` AS id, sk.\`Tên sự kiện\` AS name,
              sk.\`Mã đơn vị\` AS organizerId,
              sk.\`Địa điểm\` AS location, sk.\`Thời gian bắt đầu\` AS startTime,
              sk.\`Thời gian kết thúc\` AS endTime,
              sk.\`Trạng thái sự kiện\` AS status,
              COALESCE(sk.\`Số lượng tối đa\`, 0) AS capacity,
              COUNT(dk.\`Mã sinh viên\`) AS registeredCount
       FROM \`Sự kiện\` sk
       LEFT JOIN \`Đăng ký sự kiện\` dk ON dk.\`Mã sự kiện\` = sk.\`Mã sự kiện\`
      GROUP BY sk.\`Mã sự kiện\`, sk.\`Tên sự kiện\`, sk.\`Mã đơn vị\`, sk.\`Địa điểm\`,
                sk.\`Thời gian bắt đầu\`, sk.\`Thời gian kết thúc\`,
                sk.\`Trạng thái sự kiện\`, sk.\`Số lượng tối đa\`
       ORDER BY sk.\`Thời gian bắt đầu\``,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Organizer events error:', error.message);
    return response.status(500).json({ message: 'Không thể tải sự kiện.' });
  }
});

app.get('/api/organizer/units', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (_request, response) => {
  try {
    const [rows] = await pool.query(
      `SELECT \`Mã đơn vị\` AS id, \`Tên đơn vị\` AS name
       FROM \`Đơn vị\` ORDER BY \`Tên đơn vị\``,
    );
    return response.json({ items: rows });
  } catch (error) {
    console.error('Organizer units error:', error.message);
    return response.status(500).json({ message: 'Không thể tải đơn vị tổ chức.' });
  }
});

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
      `INSERT INTO \`Sự kiện\`
       (\`Mã sự kiện\`, \`Tên sự kiện\`, \`Mã đơn vị\`, \`Thời gian bắt đầu\`,
        \`Thời gian kết thúc\`, \`Địa điểm\`, \`Số lượng tối đa\`, \`Trạng thái sự kiện\`)
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
      `UPDATE \`Sự kiện\`
       SET \`Tên sự kiện\` = ?, \`Mã đơn vị\` = ?,
           \`Thời gian bắt đầu\` = ?, \`Thời gian kết thúc\` = ?,
           \`Địa điểm\` = ?, \`Số lượng tối đa\` = ?
       WHERE \`Mã sự kiện\` = ?`,
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

app.delete('/api/organizer/events/:eventId', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (request, response) => {
  try {
    const [result] = await pool.execute(
      'DELETE FROM `Sự kiện` WHERE `Mã sự kiện` = ?',
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

app.get('/api/admin/events', requireAuth, requireRole('Quản trị viên', 'admin', 'Ban tổ chức', 'Nhân viên'), async (_request, response) => {
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

app.listen(port, () => {
  console.log(`API listening on http://localhost:${port}`);
});
