import { useCallback, useEffect, useState } from 'react';
import {
  Activity, Award, BarChart3, Bell, BookOpen, Building2, CalendarDays, Download,
  ChevronLeft, ChevronRight, ClipboardCheck, Home, LogOut,
  Menu, MessageSquare, Moon, Plus, RefreshCw, Search, Settings, ShieldCheck,
  QrCode, Sun, Trash2, Upload, Users, X,
} from 'lucide-react';
import { api } from './api.js';
import { QRCodeSVG } from 'qrcode.react';
import { AttendanceDonutChart } from './StatisticsCharts.jsx';
import { parseStudentIds } from './studentIds.js';
import './role-portal.css';

const ADMIN_ITEMS = [
  ['dashboard', 'Trang chủ', Home], ['users', 'Quản lý người dùng', Users],
  ['orgUnits', 'Đơn vị tổ chức', Building2], ['classes', 'Quản lý lớp học', BookOpen],
  ['events', 'Quản lý sự kiện', CalendarDays], ['attendance', 'Điểm danh', ClipboardCheck],
  ['reports', 'Báo cáo & Thống kê', BarChart3], ['feedback', 'Phản hồi', MessageSquare],
  ['certificates', 'Chứng chỉ', Award], ['settings', 'Cài đặt', Settings],
];
const LECTURER_ITEMS = [
  ['dashboard', 'Trang chủ', Home], ['calendar', 'Lịch của tôi', CalendarDays],
  ['classes', 'Quản lý lớp học', BookOpen], ['attendance', 'Điểm danh', ClipboardCheck],
  ['reports', 'Báo cáo & Thống kê', BarChart3], ['notifications', 'Thông báo', Bell],
];
const EMPLOYEE_ITEMS = [
  ['dashboard', 'Trang chủ', Home], ['calendar', 'Lịch của tôi', CalendarDays],
  ['attendance', 'Điểm danh', ClipboardCheck], ['events', 'Quản lý sự kiện', CalendarDays],
  ['certificates', 'Chứng chỉ', Award], ['feedback', 'Phản hồi', MessageSquare],
];
const PAGE_TITLES = { ...Object.fromEntries([...ADMIN_ITEMS, ...LECTURER_ITEMS, ...EMPLOYEE_ITEMS].map(([id, title]) => [id, title])), profile: 'Hồ sơ cá nhân' };
const isAdminRole = (role) => ['admin', 'administrator', 'quản trị viên'].includes(String(role || '').trim().toLowerCase());
const isLecturerRole = (role) => ['lecturer', 'teacher', 'giảng viên'].includes(String(role || '').trim().toLowerCase());
const nameOf = (user) => user?.name || user?.fullName || user?.id || 'Người dùng';
const initialsOf = (name) => String(name || 'H').trim().split(/\s+/).slice(-2).map((part) => part[0]).join('').toUpperCase();
const itemsOf = (result) => Array.isArray(result?.items) ? result.items : [];
const formatDate = (value) => {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? String(value) : new Intl.DateTimeFormat('vi-VN', { dateStyle: 'short', timeStyle: 'short' }).format(date);
};

function resourceFor(page, role) {
  const admin = isAdminRole(role);
  const lecturer = isLecturerRole(role);
  if (page === 'dashboard') return { endpoint: '/api/dashboard', kind: 'metrics' };
  if (page === 'calendar') return {
    endpoint: lecturer ? '/api/calendar/classes' : '/api/organizer/events',
    kind: lecturer ? 'calendar-classes' : 'events',
  };
  if (page === 'classes') return { endpoint: '/api/admin/classes', kind: 'classes' };
  if (page === 'events') return { endpoint: '/api/organizer/events', kind: 'events' };
  if (page === 'attendance') return lecturer || admin
    ? { endpoint: '/api/admin/attendance/sessions', kind: 'sessions' }
    : { endpoint: '/api/organizer/events', kind: 'event-attendance' };
  if (page === 'reports') return { endpoint: '/api/reports/attendance/classes', kind: 'report-classes' };
  if (page === 'notifications') return { endpoint: '/api/notifications', kind: 'notifications' };
  if (page === 'certificates') return { endpoint: '/api/staff/certificates', kind: 'certificates' };
  if (page === 'feedback') return { endpoint: '/api/staff/feedback', kind: 'feedback' };
  if (page === 'users') return { endpoint: '/api/admin/users', kind: 'users' };
  if (page === 'orgUnits') return { endpoint: '/api/organizer/units', kind: 'units' };
  if (page === 'profile') return { endpoint: '/api/me', kind: 'profile' };
  return null;
}

export default function RolePortal({ user, onUserChange, onLogout, showNotice, darkMode, setDarkMode }) {
  const admin = isAdminRole(user.role);
  const lecturer = isLecturerRole(user.role);
  const roleLabel = admin ? 'Quản trị viên' : lecturer ? 'Giảng viên' : 'Công nhân viên';
  const nav = admin ? ADMIN_ITEMS : lecturer ? LECTURER_ITEMS : EMPLOYEE_ITEMS;
  const [activePage, setActivePage] = useState('dashboard');
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const goTo = (page) => {
    setActivePage(page);
    setMobileMenuOpen(false);
  };

  return (
    <div className={`role-portal ${darkMode ? 'portal-dark' : ''}`}>
      {mobileMenuOpen && <button className="rp-backdrop" aria-label="Đóng menu" onClick={() => setMobileMenuOpen(false)} />}
      <aside className={`rp-sidebar ${mobileMenuOpen ? 'rp-sidebar-open' : ''}`}>
        <div className="rp-brand">
          <span className="rp-logo"><img src="/huit-logo.jpg" alt="Logo Trường Đại học Công Thương TP.HCM" /></span>
          <span><strong>HUIT</strong><small>Điểm danh thông minh</small></span>
        </div>
        <div className="rp-role-badge">{roleLabel}</div>
        <nav className="rp-nav" aria-label="Điều hướng">
          {nav.map(([id, label, Icon]) => (
            <button key={id} className={`rp-nav-item ${activePage === id ? 'active' : ''}`} onClick={() => goTo(id)}>
              <Icon size={18} /><span>{label}</span>
            </button>
          ))}
        </nav>
        <div className="rp-sidebar-footer">
          <div className="rp-user">
            <span className="rp-avatar">{initialsOf(nameOf(user))}</span>
            <span><strong>{nameOf(user)}</strong><small>{user.id || roleLabel}</small></span>
          </div>
          <button className="rp-logout" onClick={onLogout}><LogOut size={17} /><span>Đăng xuất</span></button>
        </div>
      </aside>
      <main className="rp-main">
        <header className="rp-header">
          <button className="rp-menu-button" aria-label="Mở menu" onClick={() => setMobileMenuOpen(true)}><Menu size={21} /></button>
          <div className="rp-breadcrumb">{activePage !== 'dashboard' && <><span>Trang chủ</span><ChevronRight size={15} /></>}<strong>{PAGE_TITLES[activePage] || 'Trang chủ'}</strong></div>
          <div className="rp-header-actions">
            <span className="rp-connected"><i /> Đang kết nối</span>
            <button className="rp-icon-button" aria-label={darkMode ? 'Giao diện sáng' : 'Giao diện tối'} onClick={() => setDarkMode((value) => !value)}>
              {darkMode ? <Sun size={18} /> : <Moon size={18} />}
            </button>
            <button className="rp-header-avatar" title={`${nameOf(user)} · ${roleLabel}`} onClick={() => goTo('profile')}>{initialsOf(nameOf(user))}</button>
          </div>
        </header>
        <section className="rp-content">
          <RolePortalPage page={activePage} role={user.role} user={user} onUserChange={onUserChange} onNavigate={goTo} showNotice={showNotice} darkMode={darkMode} setDarkMode={setDarkMode} />
        </section>
      </main>
    </div>
  );
}

function RolePortalPage({ page, role, user, onUserChange, onNavigate, showNotice, darkMode, setDarkMode }) {
  const config = resourceFor(page, role);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(Boolean(config));
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');
  const [selectedId, setSelectedId] = useState('');
  const [detail, setDetail] = useState(null);
  const [detailError, setDetailError] = useState('');
  const [detailLoading, setDetailLoading] = useState(false);
  const [selectedDate, setSelectedDate] = useState(() => new Date());

  const load = useCallback(async () => {
    if (!config) return;
    setLoading(true);
    setError('');
    try {
      const result = await api(config.endpoint);
      setData(result);
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể tải dữ liệu.');
    } finally {
      setLoading(false);
    }
  }, [config?.endpoint, config?.kind]);

  useEffect(() => {
    setQuery('');
    setSelectedId('');
    setDetail(null);
    setDetailError('');
    void load();
  }, [load]);

  const loadDetail = async (item) => {
    if (!item?.id) return;
    setSelectedId(String(item.id));
    setDetail(null);
    setDetailError('');
    setDetailLoading(true);
    try {
      const result = await api(`/api/admin/classes/${encodeURIComponent(item.id)}/students`);
      setDetail(itemsOf(result));
    } catch (exception) {
      setDetailError(exception instanceof Error ? exception.message : 'Không thể tải danh sách sinh viên.');
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể tải danh sách sinh viên.');
    } finally {
      setDetailLoading(false);
    }
  };

  if (page === 'dashboard') return <Dashboard data={data} loading={loading} error={error} onRefresh={load} role={role} onNavigate={onNavigate} />;
  if (page === 'calendar') return <CalendarView data={data} loading={loading} error={error} onRefresh={load} selectedDate={selectedDate} setSelectedDate={setSelectedDate} role={role} />;
  if (page === 'classes') return <ClassesView data={data} loading={loading} error={error} query={query} setQuery={setQuery} onRefresh={load} onSelect={loadDetail} selectedId={selectedId} detail={detail} detailError={detailError} detailLoading={detailLoading} onCloseDetail={() => { setSelectedId(''); setDetail(null); setDetailError(''); }} role={role} showNotice={showNotice} />;
  if (page === 'attendance') return <AttendanceView data={data} loading={loading} error={error} query={query} setQuery={setQuery} onRefresh={load} role={role} />;
  if (page === 'reports') return <ReportsView data={data} loading={loading} error={error} onRefresh={load} role={role} />;
  if (page === 'profile') return <ProfileView data={data?.user || user} loading={loading} error={error} onRefresh={load} role={role} onUserChange={onUserChange} showNotice={showNotice} />;
  if (page === 'settings') return <SettingsView darkMode={darkMode} setDarkMode={setDarkMode} />;
  if (page === 'events') return <ManagedEventsView data={data} loading={loading} error={error} query={query} setQuery={setQuery} onRefresh={load} role={role} showNotice={showNotice} />;

  const titles = {
    events: 'Quản lý sự kiện',
    notifications: 'Thông báo',
    certificates: 'Chứng chỉ',
    feedback: 'Phản hồi',
    users: 'Quản lý người dùng',
    orgUnits: 'Đơn vị tổ chức',
  };
  const rows = itemsOf(data).filter((item) => JSON.stringify(item).toLowerCase().includes(query.trim().toLowerCase()));
  return (
    <>
      <PageTitle title={titles[page] || 'Dashboard'} subtitle="Dữ liệu được tải trực tiếp từ hệ thống HUIT." onRefresh={load} loading={loading} />
      {page !== 'notifications' && <SearchBox value={query} onChange={setQuery} placeholder={`Tìm trong ${(titles[page] || '').toLowerCase()}...`} />}
      {error ? <ErrorPanel message={error} onRetry={load} /> : loading ? <LoadingPanel /> : (
        page === 'events' ? <EventsView items={rows} />
          : page === 'notifications' ? <EmptyPanel title="Không có thông báo" message="Hiện chưa có thông báo dành cho vai trò này." />
            : page === 'certificates' ? <StaffCertificateTable items={rows} showNotice={showNotice} />
            : <GenericTable page={page} items={rows} />
      )}
    </>
  );
}

function ProfileView({ data, loading, error, onRefresh, role, onUserChange, showNotice }) {
  const [form, setForm] = useState({ email: data?.email || '', phone: data?.phone || '', address: data?.address || '', birthDate: data?.birthDate ? String(data.birthDate).slice(0, 10) : '', gender: data?.gender || '', hometown: data?.hometown || '' });
  const [saving, setSaving] = useState(false);
  const [profileError, setProfileError] = useState('');
  const [password, setPassword] = useState({ currentPassword: '', newPassword: '', confirm: '' });
  const [passwordError, setPasswordError] = useState('');
  const [changingPassword, setChangingPassword] = useState(false);
  const isLecturer = isLecturerRole(role);
  const roleLabel = isAdminRole(role) ? 'Quản trị viên' : isLecturer ? 'Giảng viên' : 'Công nhân viên';
  const details = [
    ['Mã tài khoản', data?.id],
    ['Họ và tên', data?.name || data?.fullName],
    ['Email', data?.email],
    ['Số điện thoại', data?.phone],
    ['Đơn vị', data?.department || data?.unit],
    ['Vai trò', roleLabel],
  ];
  const saveProfile = async (event) => {
    event.preventDefault();
    setSaving(true);
    setProfileError('');
    try {
      const result = await api('/api/me', { method: 'PUT', body: form });
      if (!result.user) throw new Error('Máy chủ không trả về hồ sơ mới.');
      onUserChange(result.user);
      showNotice('success', 'Thông tin hồ sơ đã được cập nhật.');
    } catch (exception) {
      setProfileError(exception instanceof Error ? exception.message : 'Không thể cập nhật hồ sơ.');
    } finally {
      setSaving(false);
    }
  };
  const savePassword = async (event) => {
    event.preventDefault();
    setPasswordError('');
    if (password.newPassword.length < 8) { setPasswordError('Mật khẩu mới cần có ít nhất 8 ký tự.'); return; }
    if (password.newPassword !== password.confirm) { setPasswordError('Mật khẩu xác nhận không khớp.'); return; }
    setChangingPassword(true);
    try {
      const result = await api('/api/me?action=password', { method: 'PUT', body: { currentPassword: password.currentPassword, newPassword: password.newPassword } });
      setPassword({ currentPassword: '', newPassword: '', confirm: '' });
      showNotice('success', result.message || 'Đổi mật khẩu thành công.');
    } catch (exception) {
      setPasswordError(exception instanceof Error ? exception.message : 'Không thể đổi mật khẩu.');
    } finally {
      setChangingPassword(false);
    }
  };
  return (
    <>
      <PageTitle title="Hồ sơ cá nhân" subtitle="Thông tin tài khoản được xác thực bởi hệ thống HUIT." onRefresh={onRefresh} loading={loading} />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : (
        <section className="rp-profile-layout">
          <article className="rp-card rp-profile-summary"><span className="rp-profile-avatar">{initialsOf(data?.name || data?.fullName || data?.id)}</span><h2>{data?.name || data?.fullName || 'Người dùng HUIT'}</h2><code>{data?.id || 'Chưa cập nhật mã'}</code><span className="rp-tag">{roleLabel}</span></article>
          <article className="rp-card rp-profile-details"><h2>Thông tin tài khoản</h2><form className="rp-profile-form" onSubmit={saveProfile}>{profileError && <ErrorPanel message={profileError} />}<div className="rp-form-grid"><label>Email<input type="email" required value={form.email} onChange={(event) => setForm({ ...form, email: event.target.value })} /></label><label>Số điện thoại<input type="tel" value={form.phone} onChange={(event) => setForm({ ...form, phone: event.target.value })} /></label><label>Ngày sinh<input type="date" value={form.birthDate} onChange={(event) => setForm({ ...form, birthDate: event.target.value })} /></label><label>Giới tính<select value={form.gender} onChange={(event) => setForm({ ...form, gender: event.target.value })}><option value="">Chưa cập nhật</option><option>Nam</option><option>Nữ</option><option>Khác</option></select></label><label>Quê quán<input value={form.hometown} onChange={(event) => setForm({ ...form, hometown: event.target.value })} /></label><label>Địa chỉ hiện tại<input value={form.address} onChange={(event) => setForm({ ...form, address: event.target.value })} /></label></div><button className="rp-secondary-button" disabled={saving}>{saving ? 'Đang lưu...' : 'Lưu thay đổi'}</button></form><div className="rp-account-readonly">{details.filter(([label]) => ['Mã tài khoản', 'Vai trò', 'Đơn vị'].includes(label)).map(([label, value]) => <div key={label}><span>{label}</span><strong>{value || 'Chưa cập nhật'}</strong></div>)}</div><form className="rp-profile-form" onSubmit={savePassword}><h2>Bảo mật tài khoản</h2>{passwordError && <ErrorPanel message={passwordError} />}<div className="rp-form-grid"><label>Mật khẩu hiện tại<input type="password" autoComplete="current-password" required value={password.currentPassword} onChange={(event) => setPassword({ ...password, currentPassword: event.target.value })} /></label><label>Mật khẩu mới<input type="password" autoComplete="new-password" required value={password.newPassword} onChange={(event) => setPassword({ ...password, newPassword: event.target.value })} /></label><label>Nhập lại mật khẩu<input type="password" autoComplete="new-password" required value={password.confirm} onChange={(event) => setPassword({ ...password, confirm: event.target.value })} /></label></div><button className="rp-secondary-button" disabled={changingPassword}>{changingPassword ? 'Đang cập nhật...' : 'Đổi mật khẩu'}</button></form></article>
        </section>
      )}
    </>
  );
}

function PageTitle({ title, subtitle, onRefresh, loading, action }) {
  return (
    <div className="rp-page-title">
      <div><h1>{title}</h1>{subtitle && <p>{subtitle}</p>}</div>
      <div className="rp-page-actions">{action}{onRefresh && <button className="rp-secondary-button" onClick={onRefresh} disabled={loading}><RefreshCw size={16} /> Làm mới</button>}</div>
    </div>
  );
}

function Dashboard({ data, loading, error, onRefresh, role, onNavigate }) {
  const metrics = Array.isArray(data?.metrics) ? data.metrics : [];
  const [attendanceReport, setAttendanceReport] = useState(null);
  const [attendanceReportLoading, setAttendanceReportLoading] = useState(false);
  const [attendanceReportError, setAttendanceReportError] = useState('');
  const [classOptions, setClassOptions] = useState([]);
  const [eventOptions, setEventOptions] = useState([]);
  const [classOptionsError, setClassOptionsError] = useState('');
  const [eventOptionsError, setEventOptionsError] = useState('');
  const [optionsReload, setOptionsReload] = useState(0);
  const [classSearch, setClassSearch] = useState('');
  const [eventSearch, setEventSearch] = useState('');
  const [selectedClassId, setSelectedClassId] = useState('');
  const [selectedEventId, setSelectedEventId] = useState('');
  const [selectedClassReport, setSelectedClassReport] = useState(null);
  const [selectedClassLoading, setSelectedClassLoading] = useState(false);
  const [selectedClassError, setSelectedClassError] = useState('');
  const [classReportReload, setClassReportReload] = useState(0);
  const canViewAttendanceReport = isAdminRole(role) || isLecturerRole(role);
  const canViewClasses = canViewAttendanceReport;
  const canViewEvents = !isLecturerRole(role);
  const loadAttendanceReport = useCallback(async () => {
    setAttendanceReportLoading(true);
    setAttendanceReportError('');
    try {
      setAttendanceReport(await api('/api/reports/attendance'));
    } catch (exception) {
      setAttendanceReportError(exception instanceof Error ? exception.message : 'Không thể tải báo cáo điểm danh.');
    } finally {
      setAttendanceReportLoading(false);
    }
  }, []);
  useEffect(() => {
    let active = true;
    if (canViewClasses) {
      setClassOptionsError('');
      api('/api/reports/attendance/classes')
        .then((result) => {
          if (active) setClassOptions(itemsOf(result));
        })
        .catch((exception) => {
          if (active) setClassOptionsError(exception instanceof Error ? exception.message : 'Không thể tải danh sách lớp.');
        });
    }
    if (canViewEvents) {
      setEventOptionsError('');
      api('/api/organizer/events')
        .then((result) => {
          if (active) setEventOptions(itemsOf(result));
        })
        .catch((exception) => {
          if (active) setEventOptionsError(exception instanceof Error ? exception.message : 'Không thể tải danh sách sự kiện.');
        });
    }
    return () => { active = false; };
  }, [canViewClasses, canViewEvents, optionsReload]);

  useEffect(() => {
    if (!data || data.attendanceBreakdown || !canViewAttendanceReport) return;
    void loadAttendanceReport();
  }, [data, data?.attendanceBreakdown, canViewAttendanceReport, loadAttendanceReport]);

  useEffect(() => {
    if (!selectedClassId) {
      setSelectedClassReport(null);
      setSelectedClassError('');
      setSelectedClassLoading(false);
      return undefined;
    }
    let active = true;
    setSelectedClassReport(null);
    setSelectedClassError('');
    setSelectedClassLoading(true);
    api(`/api/reports/attendance/classes/${encodeURIComponent(selectedClassId)}`)
      .then((result) => {
        if (active) setSelectedClassReport(result);
      })
      .catch((exception) => {
        if (active) setSelectedClassError(exception instanceof Error ? exception.message : 'Không thể tải báo cáo lớp.');
      })
      .finally(() => {
        if (active) setSelectedClassLoading(false);
      });
    return () => { active = false; };
  }, [selectedClassId, classReportReload]);

  const filteredClasses = classOptions.filter((item) => String(item.id) === selectedClassId || `${item.id} ${item.name}`.toLowerCase().includes(classSearch.trim().toLowerCase()));
  const filteredEvents = eventOptions.filter((item) => String(item.id) === selectedEventId || `${item.id} ${item.name}`.toLowerCase().includes(eventSearch.trim().toLowerCase()));
  const selectedClass = classOptions.find((item) => String(item.id) === selectedClassId);
  const selectedEvent = eventOptions.find((item) => String(item.id) === selectedEventId);
  const classBreakdown = selectedClassReport?.items?.reduce((summary, student) => ({
    present: summary.present + Number(student.present || 0),
    late: summary.late + Number(student.late || 0),
    absent: summary.absent + Number(student.absent || 0),
    excused: summary.excused + Number(student.excused || 0),
  }), { present: 0, late: 0, absent: 0, excused: 0 });
  const eventBreakdown = selectedEvent ? {
    present: Number(selectedEvent.checkedInCount || 0),
    late: 0,
    absent: Number(selectedEvent.absentCount || 0),
    pending: Number(selectedEvent.pendingCount || 0),
  } : null;
  const aggregateEventBreakdown = eventOptions.reduce((summary, event) => ({
    present: summary.present + Number(event.checkedInCount || 0),
    late: summary.late,
    absent: summary.absent + Number(event.absentCount || 0),
    pending: summary.pending + Number(event.pendingCount || 0),
  }), { present: 0, late: 0, absent: 0, pending: 0 });
  const isClassSelected = Boolean(selectedClassId);
  const isEventSelected = Boolean(selectedEventId);
  const attendanceBreakdown = isClassSelected
    ? classBreakdown
    : isEventSelected
      ? eventBreakdown
      : data?.attendanceBreakdown || attendanceReport?.summary || (!canViewAttendanceReport ? aggregateEventBreakdown : null);
  const chartData = attendanceBreakdown ? [
    { label: 'Có mặt', value: Number(attendanceBreakdown.present) || 0, color: '#28a76c' },
    { label: 'Đi muộn', value: Number(attendanceBreakdown.late) || 0, color: '#e7a639' },
    { label: 'Vắng', value: Number(attendanceBreakdown.absent) || 0, color: '#d95d54' },
    ...(Number(attendanceBreakdown.excused) > 0 ? [{ label: 'Vắng có phép', value: Number(attendanceBreakdown.excused), color: '#8b5cf6' }] : []),
    ...(Number(attendanceBreakdown.pending) > 0 ? [{ label: 'Chưa điểm danh', value: Number(attendanceBreakdown.pending), color: '#94a3b8' }] : []),
  ] : [];
  const chartTotal = chartData.reduce((total, item) => total + item.value, 0);
  const chartTitle = isClassSelected
    ? `Kết quả điểm danh · Lớp ${selectedClass?.name || selectedClassId}`
    : isEventSelected
      ? `Kết quả điểm danh · ${selectedEvent?.name || selectedEventId}`
      : 'Kết quả điểm danh toàn hệ thống';
  const selectClass = (event) => {
    setSelectedClassId(event.target.value);
    if (event.target.value) setSelectedEventId('');
  };
  const selectEvent = (event) => {
    setSelectedEventId(event.target.value);
    if (event.target.value) setSelectedClassId('');
  };

  return (
    <>
      <PageTitle title="Trang chủ" subtitle={`Số liệu hiện tại · ${isAdminRole(role) ? 'Quản trị viên' : isLecturerRole(role) ? 'Giảng viên' : 'Công nhân viên'}`} onRefresh={onRefresh} loading={loading} />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading && !metrics.length ? <LoadingPanel /> : metrics.length === 0 ? <EmptyPanel title="Chưa có dữ liệu tổng quan" message="Thống kê sẽ hiển thị khi có dữ liệu trong hệ thống." /> : (
        <>
          <div className="rp-metrics-grid">
            {metrics.map((metric, index) => (
              <article className="rp-metric-card" key={`${metric.label}-${index}`}>
                <span className={`rp-metric-icon tone-${index % 5}`}><Activity size={20} /></span>
                <div><span>{metric.label}</span><strong>{metric.value ?? 0}</strong></div>
              </article>
            ))}
          </div>
          <section className="rp-dashboard-filters" aria-label="Lọc kết quả điểm danh">
            {canViewClasses && <div className="rp-dashboard-filter-group">
            <h2><BookOpen size={17} /> Theo lớp học</h2>
            <label className="rp-search"><Search size={16} /><input value={classSearch} onChange={(event) => setClassSearch(event.target.value)} placeholder="Tìm mã hoặc tên lớp..." aria-label="Tìm lớp học" /></label>
            <select value={selectedClassId} onChange={selectClass} aria-label="Chọn lớp học">
              <option value="">Tất cả lớp học</option>
              {filteredClasses.map((item) => <option key={item.id} value={item.id}>{item.name || item.id} · {item.id}</option>)}
            </select>
            {classOptionsError && <p className="rp-filter-error">{classOptionsError} <button type="button" onClick={() => setOptionsReload((value) => value + 1)}>Thử lại</button></p>}
            {!classOptionsError && classOptions.length > 0 && filteredClasses.length === 0 && <p className="rp-filter-hint">Không tìm thấy lớp phù hợp.</p>}
            </div>}
            {canViewEvents && <div className="rp-dashboard-filter-group">
            <h2><CalendarDays size={17} /> Theo sự kiện</h2>
            <label className="rp-search"><Search size={16} /><input value={eventSearch} onChange={(event) => setEventSearch(event.target.value)} placeholder="Tìm mã hoặc tên sự kiện..." aria-label="Tìm sự kiện" /></label>
            <select value={selectedEventId} onChange={selectEvent} aria-label="Chọn sự kiện">
              <option value="">Tất cả sự kiện</option>
              {filteredEvents.map((item) => <option key={item.id} value={item.id}>{item.name || item.id} · {item.id}</option>)}
            </select>
            {eventOptionsError && <p className="rp-filter-error">{eventOptionsError} <button type="button" onClick={() => setOptionsReload((value) => value + 1)}>Thử lại</button></p>}
            {!eventOptionsError && eventOptions.length > 0 && filteredEvents.length === 0 && <p className="rp-filter-hint">Không tìm thấy sự kiện phù hợp.</p>}
            </div>}
          </section>
          {selectedClassLoading && <LoadingPanel />}
          {selectedClassError && <ErrorPanel message={selectedClassError} onRetry={() => setClassReportReload((value) => value + 1)} />}
          {attendanceBreakdown && chartTotal > 0 && <AttendanceDonutChart title={chartTitle} data={chartData} />}
          {attendanceBreakdown && chartTotal === 0 && !selectedClassLoading && <EmptyPanel title="Chưa có kết quả điểm danh" message="Chưa ghi nhận kết quả cho lựa chọn này." />}
          {!isClassSelected && !isEventSelected && !attendanceBreakdown && attendanceReportLoading && <LoadingPanel />}
          {!isClassSelected && !isEventSelected && !attendanceBreakdown && attendanceReportError && <ErrorPanel message={attendanceReportError} onRetry={loadAttendanceReport} />}
          {!isClassSelected && !isEventSelected && !attendanceBreakdown && !attendanceReportLoading && !attendanceReportError && <EmptyPanel title="Chưa có kết quả điểm danh" message="Chưa có dữ liệu điểm danh phù hợp để hiển thị." />}
          {isClassSelected && !attendanceBreakdown && !selectedClassLoading && !selectedClassError && <EmptyPanel title="Chưa có kết quả điểm danh" message="Chưa ghi nhận kết quả cho lớp đã chọn." />}
          <div className="rp-quick-actions">
            <button className="rp-card rp-quick-card" onClick={() => onNavigate(isLecturerRole(role) ? 'classes' : 'events')}><BookOpen size={20} /><span><strong>{isLecturerRole(role) ? 'Lớp học của tôi' : 'Sự kiện phụ trách'}</strong><small>Mở danh sách và thông tin chi tiết</small></span><ChevronRight size={18} /></button>
            <button className="rp-card rp-quick-card" onClick={() => onNavigate('attendance')}><ClipboardCheck size={20} /><span><strong>Điểm danh</strong><small>Xem các phiên và kết quả tham dự</small></span><ChevronRight size={18} /></button>
          </div>
        </>
      )}
    </>
  );
}

function CalendarView({ data, loading, error, onRefresh, selectedDate, setSelectedDate, role }) {
  const [view, setView] = useState('week');
  const items = itemsOf(data);
  const organizer = !isLecturerRole(role);
  const start = new Date(selectedDate);
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
  start.setHours(0, 0, 0, 0);
  const weekDays = Array.from({ length: 7 }, (_, index) => {
    const day = new Date(start);
    day.setDate(start.getDate() + index);
    return day;
  });
  const classEntries = organizer ? [] : items.flatMap((item) => (item.schedules || []).map((schedule) => ({
    id: `${item.id}-${schedule.weekday}-${schedule.startTime}`,
    title: item.name,
    subject: item.subjectName,
    weekday: Number(schedule.weekday),
    startTime: schedule.startTime,
    endTime: schedule.endTime,
    startsOn: schedule.startsOn,
    endsOn: schedule.endsOn,
    place: schedule.room,
    type: 'class',
  })));
  const eventEntries = organizer ? items.map((event) => ({
    id: event.id,
    title: event.name,
    date: event.startTime,
    place: event.location,
    time: event.startTime ? new Date(event.startTime).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' }) : '',
    detail: event.status,
    type: 'event',
  })) : [];
  const itemsForDay = (day) => {
    if (organizer) return eventEntries.filter((entry) => {
      const eventDate = new Date(entry.date);
      return !Number.isNaN(eventDate.valueOf()) && eventDate.toDateString() === day.toDateString();
    });
    const weekday = ((day.getDay() + 6) % 7) + 1;
    return classEntries.filter((entry) => entry.weekday === weekday
      && (!entry.startsOn || new Date(entry.startsOn) <= day)
      && (!entry.endsOn || new Date(entry.endsOn) >= day));
  };
  const agendaItems = weekDays.flatMap((day) => itemsForDay(day).map((entry, index) => ({
    ...entry,
    day,
    key: `${day.toISOString()}-${entry.id}-${index}`,
  })));
  const rangeLabel = `${new Intl.DateTimeFormat('vi-VN', { day: '2-digit', month: '2-digit' }).format(weekDays[0])} – ${new Intl.DateTimeFormat('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' }).format(weekDays[6])}`;
  return (
    <>
      <PageTitle title="Lịch của tôi" subtitle="Lịch học và lịch sự kiện của bạn." onRefresh={onRefresh} loading={loading} />
      <section className="panel-card calendar-panel">
        <div className="calendar-toolbar">
          <div className="calendar-switch">
            <button className="icon-button" aria-label="Tuần trước" onClick={() => setSelectedDate((date) => new Date(date.getTime() - 7 * 86400000))}><ChevronLeft size={18} /></button>
            <button className="icon-button" aria-label="Tuần sau" onClick={() => setSelectedDate((date) => new Date(date.getTime() + 7 * 86400000))}><ChevronRight size={18} /></button>
            <strong>{rangeLabel}</strong>
            <button className="text-button today-button" onClick={() => setSelectedDate(new Date())}>Hôm nay</button>
          </div>
          <div className="filter-tabs"><button className={view === 'week' ? 'selected' : ''} onClick={() => setView('week')}>Tuần</button><button className={view === 'agenda' ? 'selected' : ''} onClick={() => setView('agenda')}>Danh sách</button></div>
        </div>
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : (
        view === 'week' ? <div className="week-grid">
          {weekDays.map((day) => {
            const dayItems = itemsForDay(day);
            const isToday = day.toDateString() === new Date().toDateString();
            return <div className={`week-day ${isToday ? 'is-today' : ''}`} key={day.toISOString()}><div className="week-day-heading"><span>{new Intl.DateTimeFormat('vi-VN', { weekday: 'short' }).format(day)}</span><strong>{day.getDate()}</strong></div><div className="week-day-items">{dayItems.map((entry, index) => <div className={`calendar-event ${entry.type}`} key={`${entry.id}-${index}`}><strong>{entry.title}</strong><span>{entry.time || (entry.startTime ? `${entry.startTime}–${entry.endTime || ''}` : 'Cả ngày')}</span>{(entry.place || entry.subject) && <small>{entry.place || entry.subject}</small>}</div>)}{!dayItems.length && <span className="empty-day">—</span>}</div></div>;
          })}
        </div> : <div className="agenda-list">
          {agendaItems.map((entry) => <div className="agenda-item" key={entry.key}><div className="agenda-date"><strong>{entry.day.getDate()}</strong><span>{new Intl.DateTimeFormat('vi-VN', { weekday: 'short', month: 'short' }).format(entry.day)}</span></div><div className={`agenda-icon ${entry.type}`}><CalendarDays size={17} /></div><div className="agenda-info"><strong>{entry.title}</strong><span>{entry.subject || entry.detail || entry.place || (entry.type === 'class' ? 'Lịch học' : 'Sự kiện')}</span></div><span className="agenda-time">{entry.time || (entry.startTime ? `${entry.startTime}–${entry.endTime || ''}` : 'Cả ngày')}</span></div>)}
          {!agendaItems.length && <EmptyPanel title="Tuần này chưa có lịch" message="Lịch học và sự kiện được phân công sẽ hiển thị tại đây." />}
        </div>
      )}
        <div className="calendar-legend"><span><i className="legend-dot class" /> {organizer ? 'Sự kiện phụ trách' : 'Lịch học'}</span>{!organizer && <span><i className="legend-dot event" /> Hoạt động</span>}</div>
      </section>
    </>
  );
}

function weekdayName(value) {
  const day = Number(value);
  return ({ 1: 'Thứ 2', 2: 'Thứ 3', 3: 'Thứ 4', 4: 'Thứ 5', 5: 'Thứ 6', 6: 'Thứ 7', 7: 'Chủ nhật' })[day] || 'Chưa xếp lịch';
}

function ClassesView({ data, loading, error, query, setQuery, onRefresh, onSelect, selectedId, detail, detailError, detailLoading, onCloseDetail, role, showNotice }) {
  const classes = itemsOf(data).filter((item) => JSON.stringify(item).toLowerCase().includes(query.trim().toLowerCase()));
  const canManage = isAdminRole(role);
  const selectedClass = classes.find((item) => String(item.id) === String(selectedId));
  return (
    <>
      <PageTitle title="Quản lý lớp học" subtitle="Lớp được phân quyền theo tài khoản đang đăng nhập." onRefresh={onRefresh} loading={loading} action={canManage && <ClassAdminActions createOnly onRefresh={onRefresh} showNotice={showNotice} />} />
      <SearchBox value={query} onChange={setQuery} placeholder="Tìm tên lớp, mã lớp, giảng viên..." />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : classes.length ? (
        <div className="rp-class-grid">{classes.map((item) => <article className="rp-card rp-class-card" key={item.id}><button className="rp-class-open" onClick={() => onSelect(item)}><span className="rp-class-code">{item.code || item.id}</span><h2>{item.name || 'Lớp học phần'}</h2><p>{item.subjectName || item.subjectCode || 'Môn học'} · {item.lecturerName || 'Giảng viên'}</p><div className="rp-class-meta"><span><Users size={15} /> {item.studentCount ?? 0} sinh viên</span><span>{item.status || item.semester || 'Đang mở'}</span></div></button>{canManage && <ClassAdminActions item={item} onRefresh={onRefresh} showNotice={showNotice} />}</article>)}</div>
      ) : <EmptyPanel title="Chưa có lớp học" message="Không tìm thấy lớp học phù hợp." />}
      {selectedId && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onCloseDetail(); }}><section className="rp-modal" role="dialog" aria-modal="true"><header><div><h2>{selectedClass?.name || 'Chi tiết lớp học'}</h2><p>{selectedClass?.code || selectedId} · {selectedClass?.status || 'Thông tin lớp học phần'}</p></div><button className="rp-icon-button" onClick={onCloseDetail} aria-label="Đóng"><X size={18} /></button></header>{selectedClass && <><section className="rp-detail-intro"><span className="rp-detail-eyebrow">GIỚI THIỆU LỚP HỌC</span><p>Lớp học phần {selectedClass.name || selectedClass.code || selectedId}{selectedClass.subjectName ? ` thuộc học phần ${selectedClass.subjectName}` : ''}{selectedClass.lecturerName ? `, do giảng viên ${selectedClass.lecturerName} phụ trách` : ''}. Thông tin dưới đây giúp bạn theo dõi học phần, sĩ số và danh sách thành viên lớp.</p></section><div className="rp-profile-grid rp-class-detail-grid"><div><span>Môn học</span><strong>{selectedClass.subjectName || selectedClass.subjectCode || 'Chưa cập nhật'}</strong></div><div><span>Giảng viên</span><strong>{selectedClass.lecturerName || 'Chưa cập nhật'}</strong></div><div><span>Học kỳ</span><strong>{selectedClass.semester || 'Chưa cập nhật'}</strong></div><div><span>Số tín chỉ</span><strong>{selectedClass.credits ?? 'Chưa cập nhật'}</strong></div><div><span>Sĩ số</span><strong>{selectedClass.studentCount ?? 0}{selectedClass.capacity ? ` / ${selectedClass.capacity}` : ''} sinh viên</strong></div><div><span>Trạng thái</span><strong>{selectedClass.status || 'Đang mở'}</strong></div></div></>}<h3 className="rp-modal-section-title">Danh sách sinh viên ({detail?.length ?? selectedClass?.studentCount ?? 0})</h3>{detailLoading ? <LoadingPanel /> : detailError ? <div className="rp-detail-error" role="alert">Không thể tải danh sách sinh viên: {detailError}</div> : detail?.length ? <DataTable items={detail} columns={[['Mã sinh viên', 'studentId'], ['Họ tên', 'studentName'], ['Email', 'email'], ['Trạng thái', 'status']]} /> : <EmptyPanel title="Chưa có sinh viên" message="Lớp hiện chưa có sinh viên." />}</section></div>}
    </>
  );
}

function ClassAdminActions({ item, createOnly = false, onRefresh, showNotice }) {
  const [form, setForm] = useState(null);
  const [options, setOptions] = useState({ cohorts: [], subjects: [] });
  const [lecturers, setLecturers] = useState([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const openForm = async (target = null) => {
    setError('');
    setForm(target ? {
      id: target.id, name: target.name || '', subjectId: target.subjectId || '',
      cohortCode: target.cohortCode || '', semester: target.semester || 'HK1',
      startTime: toDateTimeInput(target.startTime), lecturerId: target.lecturerId || '',
      capacity: String(target.capacity || 50),
    } : {
      id: '', name: '', subjectId: '', cohortCode: '', semester: 'HK1',
      startTime: toDateTimeInput(new Date()), lecturerId: '', capacity: '50',
    });
    setBusy(true);
    try {
      const [classOptions, lecturerResult] = await Promise.all([
        api('/api/admin/class-options'), api('/api/admin/lecturers'),
      ]);
      setOptions({ cohorts: classOptions.cohorts || [], subjects: classOptions.subjects || [] });
      setLecturers(itemsOf(lecturerResult));
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể tải dữ liệu biểu mẫu.');
    } finally {
      setBusy(false);
    }
  };

  const save = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const body = {
      name: form.name.trim(), semester: form.semester,
      startTime: `${form.startTime.replace('T', ' ')}:00`,
      lecturerId: form.lecturerId || null, capacity: Number(form.capacity),
    };
    if (!form.id) Object.assign(body, { subjectId: form.subjectId, cohortCode: form.cohortCode });
    try {
      const result = await api(form.id ? `/api/admin/classes/${encodeURIComponent(form.id)}` : '/api/admin/classes', {
        method: form.id ? 'PUT' : 'POST', body,
      });
      setForm(null);
      showNotice('success', result.message || (form.id ? 'Đã cập nhật lớp.' : 'Đã tạo lớp.'));
      await onRefresh();
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể lưu lớp học.');
    } finally {
      setBusy(false);
    }
  };

  const runAction = async (action) => {
    const label = action === 'close' ? 'đóng' : 'xóa';
    if (!window.confirm(`Bạn có chắc muốn ${label} lớp "${item.name || item.id}"?`)) return;
    try {
      const result = await api(`/api/admin/classes/${encodeURIComponent(item.id)}${action === 'close' ? '/close' : ''}`, {
        method: action === 'close' ? 'POST' : 'DELETE',
      });
      showNotice('success', result.message || `Đã ${label} lớp.`);
      await onRefresh();
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể cập nhật lớp.');
    }
  };

  const importStudents = async (event) => {
    event.preventDefault();
    const ids = parseStudentIds(form.studentIds);
    if (!ids.length) return;
    setBusy(true);
    try {
      const result = await api(`/api/admin/classes/${encodeURIComponent(item.id)}/students/import`, {
        method: 'POST', body: { studentIds: ids },
      });
      const unknown = result.unknownStudentIds?.length ? ` Mã không tồn tại: ${result.unknownStudentIds.join(', ')}.` : '';
      showNotice('success', `Đã thêm ${result.importedCount || 0} sinh viên; ${result.alreadyMemberCount || 0} sinh viên đã có trong lớp.${unknown}`);
      setForm(null);
      await onRefresh();
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể nhập sinh viên.');
    } finally {
      setBusy(false);
    }
  };

  const loadStudentIdsFromWorkbook = async (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    setBusy(true);
    setError('');
    try {
      const ids = await readStudentIdsFromWorkbook(file);
      if (!ids.length) throw new Error('Không tìm thấy mã sinh viên trong file Excel.');
      setForm({ studentIds: ids.join('\n') });
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể đọc file Excel.');
    } finally {
      setBusy(false);
      event.target.value = '';
    }
  };

  return (
    <>
      {createOnly ? <button className="rp-secondary-button" onClick={() => openForm()}><Plus size={16} /> Tạo lớp</button> : <div className="rp-inline-actions">
        <button className="rp-secondary-button" onClick={() => { setError(''); setForm({ studentIds: '' }); }}><Upload size={15} /> Nhập SV</button>
        <button className="rp-secondary-button" onClick={() => openForm(item)}><Settings size={15} /> Sửa</button>
        {item.status !== 'Đã đóng' && <button className="rp-secondary-button" onClick={() => runAction('close')}><ShieldCheck size={15} /> Đóng lớp</button>}
        <button className="rp-icon-button" aria-label="Xóa lớp" title="Xóa lớp" onClick={() => runAction('delete')}><Trash2 size={16} /></button>
      </div>}
      {form && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) setForm(null); }}>
        <form className="rp-modal rp-form-modal" role="dialog" aria-modal="true" onSubmit={form.studentIds !== undefined ? importStudents : save}>
          <header><div><h2>{form.studentIds !== undefined ? 'Nhập sinh viên vào lớp' : form.id ? 'Chỉnh sửa lớp học' : 'Tạo lớp học'}</h2><p>{form.studentIds !== undefined ? item.name || item.id : form.id || 'Nhập thông tin lớp học phần.'}</p></div><button type="button" className="rp-icon-button" onClick={() => setForm(null)} aria-label="Đóng"><X size={18} /></button></header>
          {error && <ErrorPanel message={error} />}
          {form.studentIds !== undefined ? <><label>Chọn file Excel (.xlsx)<input type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={loadStudentIdsFromWorkbook} disabled={busy} />{busy && <small role="status">Đang đọc file Excel...</small>}</label><label>Hoặc nhập mã sinh viên<textarea rows="7" required value={form.studentIds} onChange={(event) => setForm({ ...form, studentIds: event.target.value })} placeholder="Mỗi dòng một mã sinh viên; có thể phân tách bằng dấu phẩy hoặc dấu chấm phẩy." /></label></> : <div className="rp-form-grid">
            <label>Tên lớp<input required value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} /></label>
            {!form.id && <><label>Môn học<select required value={form.subjectId} onChange={(event) => setForm({ ...form, subjectId: event.target.value })}><option value="">Chọn môn học</option>{options.subjects.map((subject) => <option key={subject.id} value={subject.id}>{subject.name} · {subject.code}</option>)}</select></label><label>Khóa sinh viên<select required value={form.cohortCode} onChange={(event) => setForm({ ...form, cohortCode: event.target.value })}><option value="">Chọn khóa</option>{options.cohorts.map((cohort) => <option key={cohort.code} value={cohort.code}>{cohort.code}</option>)}</select></label></>}
            <label>Học kỳ<select value={form.semester} onChange={(event) => setForm({ ...form, semester: event.target.value })}>{['HK1', 'HK2', 'HK3'].map((semester) => <option key={semester}>{semester}</option>)}</select></label>
            <label>Thời gian bắt đầu<input type="datetime-local" required value={form.startTime} onChange={(event) => setForm({ ...form, startTime: event.target.value })} /></label>
            <label>Giảng viên<select value={form.lecturerId} onChange={(event) => setForm({ ...form, lecturerId: event.target.value })}><option value="">Chưa phân công</option>{lecturers.map((lecturer) => <option key={lecturer.id} value={lecturer.id}>{lecturer.name}</option>)}</select></label>
            <label>Sĩ số tối đa<input type="number" min="1" required value={form.capacity} onChange={(event) => setForm({ ...form, capacity: event.target.value })} /></label>
          </div>}
          <footer><button type="button" className="rp-secondary-button" onClick={() => setForm(null)} disabled={busy}>Hủy</button><button className="rp-secondary-button" disabled={busy}>{busy ? 'Đang xử lý...' : form.studentIds !== undefined ? 'Nhập sinh viên' : form.id ? 'Lưu thay đổi' : 'Tạo lớp'}</button></footer>
        </form>
      </div>}
    </>
  );
}

function toDateTimeInput(value) {
  const date = value instanceof Date ? value : new Date(value || '');
  if (Number.isNaN(date.valueOf())) return '';
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}

async function readStudentIdsFromWorkbook(file) {
  const { default: readExcelFile } = await import('read-excel-file/universal');
  const workbook = await readExcelFile(file);
  const rows = Array.isArray(workbook[0]) ? workbook : workbook[0]?.data;
  if (!Array.isArray(rows)) throw new Error('Không tìm thấy dữ liệu trong file Excel.');
  const normalizeHeader = (cell) => String(cell || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
  const headerNames = new Set(['mssv', 'masv', 'masinhvien', 'studentid', 'studentcode']);
  const headerIndex = rows.findIndex((row) => row.some((cell) => headerNames.has(normalizeHeader(cell))));
  if (headerIndex < 0) throw new Error('Cột mã sinh viên cần có tiêu đề MSSV, Mã SV, Mã sinh viên hoặc Student ID.');
  const columnIndex = rows[headerIndex].findIndex((cell) => headerNames.has(normalizeHeader(cell)));
  return [...new Set(rows.slice(headerIndex + 1).map((row) => String(row[columnIndex] ?? '').trim()).filter(Boolean))];
}

function ManagedEventsView({ data, loading, error, query, setQuery, onRefresh, role, showNotice }) {
  const [form, setForm] = useState(null);
  const [units, setUnits] = useState([]);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState('');
  const [selected, setSelected] = useState(null);
  const [details, setDetails] = useState(null);
  const [detailError, setDetailError] = useState('');
  const [students, setStudents] = useState([]);
  const [rosterError, setRosterError] = useState('');
  const [rosterWarning, setRosterWarning] = useState('');
  const [detailLoading, setDetailLoading] = useState(false);
  const [importTarget, setImportTarget] = useState(null);
  const [studentIds, setStudentIds] = useState('');
  const [busyAction, setBusyAction] = useState('');
  const [imagePreview, setImagePreview] = useState('');
  const [imageInputVersion, setImageInputVersion] = useState(0);
  const events = itemsOf(data).filter((item) => JSON.stringify(item).toLowerCase().includes(query.trim().toLowerCase()));
  const canManage = !isLecturerRole(role);
  const selectedImageFile = form?.imageFile || null;

  useEffect(() => {
    if (!selectedImageFile) {
      setImagePreview('');
      return undefined;
    }
    const previewUrl = URL.createObjectURL(selectedImageFile);
    setImagePreview(previewUrl);
    return () => URL.revokeObjectURL(previewUrl);
  }, [selectedImageFile]);

  const openForm = async (item = null) => {
    setFormError('');
    setImageInputVersion((version) => version + 1);
    setSaving(true);
    try {
      const [unitResult, eventDetails] = await Promise.all([
        api('/api/organizer/units'),
        item ? api(`/api/events/${encodeURIComponent(item.id)}`) : Promise.resolve({}),
      ]);
      const current = eventDetails || {};
      const benefits = (current.benefits || []).map((benefit) => ({
        type: benefit.type || 'Khác',
        points: String(benefit.points || 0),
        content: benefit.content || '',
      }));
      const rules = (current.rules || []).map((rule) => typeof rule === 'string' ? rule : rule.text || '').join('\n');
      const periods = (current.attendancePeriods || []).map((period) => ({
        name: period.name || '',
        startTime: toDateTimeInput(period.startTime),
        endTime: toDateTimeInput(period.endTime),
      }));
      setUnits(itemsOf(unitResult));
      setForm({
        id: item?.id || '', name: current.name || item?.name || '', organizerId: current.organizerId || item?.organizerId || '',
        startTime: toDateTimeInput(current.startTime || item?.startTime || new Date()),
        endTime: toDateTimeInput(current.endTime || item?.endTime || new Date(Date.now() + 7200000)),
        location: current.location || item?.location || '', capacity: String(current.capacity || item?.capacity || 100),
        certificateEnabled: current.certificateEnabled === true || Number(current.certificateEnabled) === 1,
        imageUrl: current.imageUrl || item?.imageUrl || '',
        description: current.description || '', benefits, rules, periods,
      });
    } catch (exception) {
      setFormError(exception instanceof Error ? exception.message : 'Không thể tải dữ liệu sự kiện.');
      setForm({ id: item?.id || '', name: item?.name || '', organizerId: item?.organizerId || '', startTime: '', endTime: '', location: item?.location || '', capacity: String(item?.capacity || 100), certificateEnabled: item?.certificateEnabled === true || Number(item?.certificateEnabled) === 1, imageUrl: item?.imageUrl || '', description: '', benefits: [], rules: '', periods: [] });
    } finally {
      setSaving(false);
    }
  };

  const saveEvent = async (event) => {
    event.preventDefault();
    setSaving(true);
    setFormError('');
    let parsePeriods;
    try {
      parsePeriods = form.periods.map((period) => {
        const start = new Date(period.startTime);
        const end = new Date(period.endTime);
        if (!period.name.trim() || Number.isNaN(start.valueOf()) || Number.isNaN(end.valueOf())) throw new Error('Vui lòng nhập tên, thời gian bắt đầu và kết thúc cho mỗi khung điểm danh.');
        return { name: period.name.trim(), startTime: start.toISOString(), endTime: end.toISOString() };
      });
    } catch (exception) {
      setFormError(exception instanceof Error ? exception.message : 'Khung điểm danh không hợp lệ.');
      setSaving(false);
      return;
    }
    const parseBenefits = form.benefits.map((benefit) => ({
      type: benefit.type,
      points: Number(benefit.points) || 0,
      content: benefit.content.trim(),
    }));
    const body = {
      name: form.name.trim(), organizerId: form.organizerId,
      startTime: new Date(form.startTime).toISOString(), endTime: new Date(form.endTime).toISOString(),
      location: form.location.trim(), capacity: Number(form.capacity), description: form.description.trim(),
      certificateEnabled: form.certificateEnabled === true,
      imageUrl: form.imageUrl.trim(),
      benefits: parseBenefits, rules: form.rules.split('\n').map((line) => line.trim()).filter(Boolean),
      attendancePeriods: parsePeriods,
    };
    try {
      if (form.imageFile) {
        const uploadBody = new FormData();
        uploadBody.append('image', form.imageFile);
        const uploadedImage = await api('/api/organizer/event-images', {
          method: 'POST',
          body: uploadBody,
          timeoutMs: 30000,
        });
        body.imageUrl = uploadedImage.imageUrl;
      }
      const result = await api(form.id ? `/api/organizer/events/${encodeURIComponent(form.id)}` : '/api/organizer/events', {
        method: form.id ? 'PUT' : 'POST', body,
      });
      setForm(null);
      showNotice('success', result.message || (form.id ? 'Đã cập nhật sự kiện.' : 'Đã tạo sự kiện.'));
      await onRefresh();
    } catch (exception) {
      setFormError(exception instanceof Error ? exception.message : 'Không thể lưu sự kiện.');
    } finally {
      setSaving(false);
    }
  };

  const openDetails = async (item) => {
    setSelected(item);
    setDetails(null);
    setDetailError('');
    setStudents([]);
    setRosterError('');
    setRosterWarning('');
    setDetailLoading(true);
    const [eventResult, rosterResult] = await Promise.allSettled([
      api(`/api/events/${encodeURIComponent(item.id)}`),
      api(`/api/organizer/events/${encodeURIComponent(item.id)}/students`),
    ]);
    if (eventResult.status === 'fulfilled') setDetails(eventResult.value);
    else setDetailError(eventResult.reason instanceof Error ? eventResult.reason.message : 'Không thể tải chi tiết sự kiện.');
    if (rosterResult.status === 'fulfilled') {
      setStudents(itemsOf(rosterResult.value));
      setRosterWarning(rosterResult.value?.warning || '');
    }
    else {
      const message = rosterResult.reason instanceof Error ? rosterResult.reason.message : 'Không thể tải danh sách đăng ký.';
      setRosterError(message);
      showNotice('error', message);
    }
    setDetailLoading(false);
  };

  const runEventAction = async (item, action) => {
    const labels = { close: 'đóng', delete: 'xóa', certificates: 'gửi chứng nhận' };
    if (!window.confirm(`Bạn có chắc muốn ${labels[action]} cho sự kiện "${item.name}"?`)) return;
    setBusyAction(`${item.id}:${action}`);
    try {
      const path = action === 'certificates'
        ? `/api/organizer/events/${encodeURIComponent(item.id)}/certificates/send`
        : `/api/organizer/events/${encodeURIComponent(item.id)}${action === 'close' ? '/close' : ''}`;
      const result = await api(path, { method: action === 'delete' ? 'DELETE' : 'POST' });
      showNotice('success', result.message || `Đã ${labels[action]}.`);
      await onRefresh();
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : `Không thể ${labels[action]}.`);
    } finally {
      setBusyAction('');
    }
  };

  const importStudents = async (event) => {
    event.preventDefault();
    const ids = parseStudentIds(studentIds);
    if (!ids.length) return;
    setBusyAction('import');
    try {
      const result = await api(`/api/organizer/events/${encodeURIComponent(importTarget.id)}/students/import`, { method: 'POST', body: { studentIds: ids } });
      const unknown = result.unknownStudentIds?.length ? ` Mã không tồn tại: ${result.unknownStudentIds.join(', ')}.` : '';
      showNotice('success', `Đã thêm ${result.importedCount || 0} sinh viên đăng ký; ${result.alreadyRegisteredCount || 0} sinh viên đã đăng ký trước đó.${unknown}`);
      setImportTarget(null);
      setStudentIds('');
      await onRefresh();
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể nhập sinh viên.');
    } finally {
      setBusyAction('');
    }
  };

  const readEventStudentWorkbook = async (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    setBusyAction('reading-import');
    try {
      const ids = await readStudentIdsFromWorkbook(file);
      if (!ids.length) throw new Error('Không tìm thấy mã sinh viên trong file Excel.');
      setStudentIds(ids.join('\n'));
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể đọc file Excel.');
    } finally {
      setBusyAction('');
      event.target.value = '';
    }
  };

  return <>
    <PageTitle title="Quản lý sự kiện" subtitle="Sự kiện và đăng ký được đồng bộ trực tiếp từ hệ thống HUIT." onRefresh={onRefresh} loading={loading} action={canManage && <button className="rp-secondary-button" onClick={() => openForm()}><Plus size={16} /> Tạo sự kiện</button>} />
    <SearchBox value={query} onChange={setQuery} placeholder="Tìm tên sự kiện, địa điểm, trạng thái..." />
    {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : events.length ? <div className="rp-event-grid">{events.map((item) => {
      const eventEnded = item.status === 'Đã đóng' || item.status === 'Đã kết thúc' || (item.endTime && new Date(item.endTime) <= new Date());
      return <article className="rp-card rp-event-card" key={item.id}><button className="rp-event-open" onClick={() => openDetails(item)}><div className="rp-event-top"><span className="rp-tag">{item.status || 'Sự kiện'}</span><span className="rp-event-id">{item.id}</span></div><h2>{item.name || 'Sự kiện HUIT'}</h2><div className="rp-event-detail"><Award size={15} />{Number(item.certificateEnabled) === 1 || item.certificateEnabled === true ? 'Có cấp chứng nhận' : 'Không cấp chứng nhận'}</div><div className="rp-event-detail"><CalendarDays size={15} />{formatDate(item.startTime)}</div><div className="rp-event-detail"><Building2 size={15} />{item.location || 'Chưa cập nhật địa điểm'}</div><div className="rp-event-progress"><span>Đăng ký</span><strong>{item.registeredCount ?? 0}{item.capacity ? ` / ${item.capacity}` : ''}</strong></div><div className="rp-progress-track"><i style={{ width: `${item.capacity ? Math.min(100, Number(item.registeredCount || 0) * 100 / item.capacity) : 0}%` }} /></div></button>{canManage && <div className="rp-inline-actions"><button className="rp-secondary-button" onClick={() => openForm(item)}><Settings size={15} /> Sửa</button><button className="rp-secondary-button" onClick={() => { setImportTarget(item); setStudentIds(''); }} disabled={eventEnded} title={eventEnded ? 'Không thể nhập sinh viên vào sự kiện đã đóng hoặc kết thúc.' : 'Nhập danh sách sinh viên đăng ký'}><Upload size={15} /> Nhập SV</button>{(Number(item.certificateEnabled) === 1 || item.certificateEnabled === true) && <button className="rp-secondary-button" onClick={() => runEventAction(item, 'certificates')} disabled={busyAction === `${item.id}:certificates`}><Award size={15} /> Chứng nhận</button>}{item.status !== 'Đã đóng' && <button className="rp-secondary-button" onClick={() => runEventAction(item, 'close')}><ShieldCheck size={15} /> Đóng</button>}<button className="rp-icon-button" aria-label="Xóa sự kiện" title="Xóa sự kiện" onClick={() => runEventAction(item, 'delete')}><Trash2 size={15} /></button></div>}</article>;
    })}</div> : <EmptyPanel title="Chưa có sự kiện" message="Không tìm thấy sự kiện phù hợp." />}
    {form && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !saving) setForm(null); }}><form className="rp-modal rp-form-modal" role="dialog" aria-modal="true" onSubmit={saveEvent}><header><div><h2>{form.id ? 'Chỉnh sửa sự kiện' : 'Tạo sự kiện'}</h2><p>{form.id || 'Nhập thông tin hoạt động.'}</p></div><button type="button" className="rp-icon-button" onClick={() => setForm(null)} aria-label="Đóng"><X size={18} /></button></header>{formError && <ErrorPanel message={formError} />}<div className="rp-form-grid"><label>Tên sự kiện<input required value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} /></label><label>Đơn vị tổ chức<select required value={form.organizerId} onChange={(event) => setForm({ ...form, organizerId: event.target.value })}><option value="">Chọn đơn vị</option>{units.map((unit) => <option key={unit.id} value={unit.id}>{unit.name}</option>)}</select></label><label>Bắt đầu<input type="datetime-local" required value={form.startTime} onChange={(event) => setForm({ ...form, startTime: event.target.value })} /></label><label>Kết thúc<input type="datetime-local" required value={form.endTime} onChange={(event) => setForm({ ...form, endTime: event.target.value })} /></label><label>Địa điểm<input required value={form.location} onChange={(event) => setForm({ ...form, location: event.target.value })} /></label><label>Sức chứa<input type="number" min="1" required value={form.capacity} onChange={(event) => setForm({ ...form, capacity: event.target.value })} /></label><label className="rp-form-wide rp-checkbox-field"><input type="checkbox" checked={form.certificateEnabled === true} onChange={(event) => setForm({ ...form, certificateEnabled: event.target.checked })} /><span>Cấp chứng nhận cho người tham dự</span><small>Chỉ bật nếu sự kiện này sẽ phát hành giấy chứng nhận.</small></label><label className="rp-form-wide">Chọn ảnh từ máy<input key={imageInputVersion} type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => { const imageFile = event.target.files?.[0] || null; setForm({ ...form, imageFile, ...(imageFile ? { imageUrl: '' } : {}) }); }} /><small className="rp-image-help">JPEG, PNG hoặc WebP, tối đa 5 MB. Ảnh sẽ tải lên khi lưu sự kiện.</small></label><label className="rp-form-wide">Hoặc dùng URL ảnh<input type="url" maxLength="1000" value={form.imageUrl} onChange={(event) => { if (form.imageFile) setImageInputVersion((version) => version + 1); setForm({ ...form, imageUrl: event.target.value, imageFile: null }); }} placeholder="https://..." /><small className="rp-image-help">Để trống cả hai trường để tự chọn ảnh theo chủ đề sự kiện.</small>{(imagePreview || form.imageUrl) && <img key={imagePreview || form.imageUrl} className="rp-event-image-preview" src={imagePreview || form.imageUrl} alt="Xem trước ảnh sự kiện" onError={(event) => { event.currentTarget.hidden = true; }} />}</label><label className="rp-form-wide">Mô tả<textarea rows="3" value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })} /></label><section className="rp-form-wide rp-editor-section"><div className="rp-editor-heading"><strong>Quyền lợi</strong><button type="button" className="rp-secondary-button" onClick={() => setForm({ ...form, benefits: [...form.benefits, { type: 'Khác', points: '0', content: '' }] })} disabled={form.benefits.length >= 20}><Plus size={15} /> Thêm quyền lợi</button></div>{form.benefits.map((benefit, index) => <div className="rp-editor-row rp-benefit-row" key={`benefit-${index}`}><select aria-label={`Loại quyền lợi ${index + 1}`} value={benefit.type} onChange={(event) => setForm({ ...form, benefits: form.benefits.map((item, itemIndex) => itemIndex === index ? { ...item, type: event.target.value } : item) })}>{['Điểm rèn luyện', 'Điểm công tác xã hội', 'Chứng nhận', 'Khác'].map((type) => <option key={type} value={type}>{type}</option>)}</select><input aria-label={`Số điểm quyền lợi ${index + 1}`} type="number" min="0" step="1" required value={benefit.points} onChange={(event) => setForm({ ...form, benefits: form.benefits.map((item, itemIndex) => itemIndex === index ? { ...item, points: event.target.value } : item) })} placeholder="Số điểm" /><input aria-label={`Nội dung quyền lợi ${index + 1}`} maxLength="500" required value={benefit.content} onChange={(event) => setForm({ ...form, benefits: form.benefits.map((item, itemIndex) => itemIndex === index ? { ...item, content: event.target.value } : item) })} placeholder="Nội dung quyền lợi" /><button type="button" className="rp-icon-button" aria-label={`Xóa quyền lợi ${index + 1}`} onClick={() => setForm({ ...form, benefits: form.benefits.filter((_, itemIndex) => itemIndex !== index) })}><Trash2 size={15} /></button></div>)}</section><label className="rp-form-wide">Nội quy<textarea rows="3" value={form.rules} onChange={(event) => setForm({ ...form, rules: event.target.value })} placeholder="Mỗi dòng một nội quy" /></label><section className="rp-form-wide rp-editor-section"><div className="rp-editor-heading"><strong>Khung giờ điểm danh</strong><button type="button" className="rp-secondary-button" onClick={() => setForm({ ...form, periods: [...form.periods, { name: `Đợt ${form.periods.length + 1}`, startTime: form.startTime, endTime: form.endTime }] })} disabled={form.periods.length >= 12}><Plus size={15} /> Thêm khung giờ</button></div><small>Chọn ngày giờ trên lịch; để trống danh sách nếu điểm danh trong toàn bộ thời gian sự kiện.</small>{form.periods.map((period, index) => <div className="rp-editor-row rp-period-row" key={`period-${index}`}><input aria-label={`Tên khung điểm danh ${index + 1}`} required maxLength="60" value={period.name} onChange={(event) => setForm({ ...form, periods: form.periods.map((item, itemIndex) => itemIndex === index ? { ...item, name: event.target.value } : item) })} placeholder="Tên khung, ví dụ: Đợt 1" /><label>Bắt đầu<input aria-label={`Bắt đầu khung ${index + 1}`} type="datetime-local" required value={period.startTime} onChange={(event) => setForm({ ...form, periods: form.periods.map((item, itemIndex) => itemIndex === index ? { ...item, startTime: event.target.value } : item) })} /></label><label>Kết thúc<input aria-label={`Kết thúc khung ${index + 1}`} type="datetime-local" required value={period.endTime} onChange={(event) => setForm({ ...form, periods: form.periods.map((item, itemIndex) => itemIndex === index ? { ...item, endTime: event.target.value } : item) })} /></label><button type="button" className="rp-icon-button" aria-label={`Xóa khung điểm danh ${index + 1}`} onClick={() => setForm({ ...form, periods: form.periods.filter((_, itemIndex) => itemIndex !== index) })}><Trash2 size={15} /></button></div>)}</section></div><footer><button type="button" className="rp-secondary-button" onClick={() => setForm(null)} disabled={saving}>Hủy</button><button className="rp-secondary-button" disabled={saving}>{saving ? 'Đang lưu...' : form.id ? 'Lưu thay đổi' : 'Tạo sự kiện'}</button></footer></form></div>}
    {importTarget && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !busyAction) setImportTarget(null); }}><form className="rp-modal rp-form-modal" role="dialog" aria-modal="true" onSubmit={importStudents}><header><div><h2>Nhập sinh viên đăng ký</h2><p>{importTarget.name}</p></div><button type="button" className="rp-icon-button" onClick={() => setImportTarget(null)} aria-label="Đóng"><X size={18} /></button></header><label>Chọn file Excel (.xlsx)<input type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={readEventStudentWorkbook} disabled={Boolean(busyAction)} />{busyAction === 'reading-import' && <small role="status">Đang đọc file Excel...</small>}</label><label>Mã sinh viên<textarea rows="7" required value={studentIds} onChange={(event) => setStudentIds(event.target.value)} placeholder="Mỗi dòng một mã sinh viên; có thể phân tách bằng dấu phẩy hoặc dấu chấm phẩy." /></label><footer><button type="button" className="rp-secondary-button" onClick={() => setImportTarget(null)} disabled={busyAction === 'import'}>Hủy</button><button className="rp-secondary-button" disabled={busyAction === 'import'}>{busyAction === 'import' ? 'Đang nhập...' : 'Nhập sinh viên'}</button></footer></form></div>}
    {selected && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelected(null); }}><section className="rp-modal" role="dialog" aria-modal="true"><header><div><h2>{details?.name || selected.name}</h2><p>{selected.id} · {details?.status || selected.status || 'Sự kiện'}</p></div><button className="rp-icon-button" onClick={() => setSelected(null)} aria-label="Đóng"><X size={18} /></button></header>{detailLoading ? <LoadingPanel /> : <><div className={`rp-event-detail-cover${(details?.imageUrl || selected.imageUrl) ? ' has-image' : ''}`}>{(details?.imageUrl || selected.imageUrl) && <img src={details?.imageUrl || selected.imageUrl} alt="" onError={(event) => { event.currentTarget.hidden = true; }} />}<span>{details?.id || selected.id} · HOẠT ĐỘNG HUIT</span></div><section className="rp-detail-intro"><span className="rp-detail-eyebrow">GIỚI THIỆU SỰ KIỆN</span><p>{details?.description?.trim() || `Sự kiện ${details?.name || selected.name || 'HUIT'} là hoạt động dành cho sinh viên quan tâm đến các chương trình và trải nghiệm tại trường. Xem thông tin thời gian, địa điểm, quyền lợi và nội quy bên dưới để chuẩn bị tham gia.`}</p></section>{detailError && <div className="rp-detail-error" role="alert">Không tải được một số thông tin chi tiết: {detailError}. Thông tin cơ bản bên dưới được lấy từ danh sách sự kiện.</div>}<div className="rp-profile-grid"><div><span>Đơn vị tổ chức</span><strong>{details?.organizerName || selected.organizerName || 'Chưa cập nhật'}</strong></div><div><span>Thời gian</span><strong>{formatDate(details?.startTime || selected.startTime)} – {formatDate(details?.endTime || selected.endTime)}</strong></div><div><span>Địa điểm</span><strong>{details?.location || selected.location || 'Chưa cập nhật'}</strong></div><div><span>Số lượng đăng ký</span><strong>{details?.registeredCount ?? selected.registeredCount ?? 0}{(details?.capacity || selected.capacity) ? ` / ${details?.capacity || selected.capacity}` : ''}</strong></div></div><h3 className="rp-modal-section-title">Quyền lợi</h3>{details?.benefits?.length ? details.benefits.map((benefit, index) => <p className="rp-detail-list-item" key={index}>{benefit.type}{benefit.points ? ` · ${benefit.points} điểm` : ''}: {benefit.content}</p>) : <p className="rp-modal-muted">Thông tin quyền lợi sẽ được cập nhật bởi đơn vị tổ chức.</p>}<h3 className="rp-modal-section-title">Nội quy tham gia</h3>{details?.rules?.length ? details.rules.map((rule, index) => <p className="rp-detail-list-item" key={index}>{index + 1}. {rule.text || rule}</p>) : <p className="rp-modal-muted">Vui lòng theo dõi thông báo của ban tổ chức trước khi tham gia.</p>}<h3 className="rp-modal-section-title">Danh sách đăng ký ({students.length})</h3>{rosterWarning && <div className="rp-detail-error" role="status">{rosterWarning}</div>}{rosterError ? <div className="rp-detail-error" role="alert">Không thể tải danh sách đăng ký: {rosterError}</div> : students.length ? <DataTable items={students} columns={[["Mã SV", "studentId"], ["Họ tên", "studentName"], ["Lớp", "className"], ["Trạng thái đăng ký", "status"], ["Điểm danh", "attendanceStatus"]]} /> : <EmptyPanel title="Chưa có đăng ký" message="Sự kiện hiện chưa có sinh viên đăng ký." />}</>}</section></div>}
  </>;
}

function EventQrAction({ item }) {
  const [open, setOpen] = useState(false);
  const [periods, setPeriods] = useState([]);
  const [periodsConfigured, setPeriodsConfigured] = useState(false);
  const [periodId, setPeriodId] = useState('');
  const [qr, setQr] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const openDialog = async () => {
    setOpen(true);
    setError('');
    setPeriodsConfigured(false);
    try {
      const details = await api(`/api/events/${encodeURIComponent(item.id)}`);
      const allPeriods = details.attendancePeriods || [];
      const next = allPeriods.filter((period) => !period.endTime || new Date(period.endTime) > new Date());
      setPeriodsConfigured(allPeriods.length > 0);
      setPeriods(next);
      setPeriodId(next[0]?.id || '');
      if (allPeriods.length && !next.length) setError('Tất cả khung điểm danh của sự kiện đã kết thúc.');
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không tải được khung điểm danh.');
    }
  };

  const createQr = async () => {
    if (!navigator.geolocation) { setError('Trình duyệt không hỗ trợ lấy vị trí.'); return; }
    setBusy(true);
    setError('');
    try {
      const position = await new Promise((resolve, reject) => navigator.geolocation.getCurrentPosition(resolve, reject, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }));
      const result = await api(`/api/organizer/events/${encodeURIComponent(item.id)}/attendance/qr`, {
        method: 'POST', body: { latitude: position.coords.latitude, longitude: position.coords.longitude, ...(periodId ? { periodId } : {}) },
      });
      if (!result.qr) throw new Error('Backend không trả về mã QR.');
      setQr(result);
    } catch (exception) {
      setError(exception?.code === 1 ? 'Cần cấp quyền vị trí cho trình duyệt.' : exception instanceof Error ? exception.message : 'Không thể tạo QR sự kiện.');
    } finally {
      setBusy(false);
    }
  };

  const stopQr = async () => {
    if (!qr?.sessionId) return;
    setBusy(true);
    setError('');
    try {
      await api(`/api/organizer/events/${encodeURIComponent(item.id)}/attendance/sessions/${encodeURIComponent(qr.sessionId)}/close`, { method: 'POST' });
      setQr(null);
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể tắt mã QR sự kiện.');
    } finally {
      setBusy(false);
    }
  };

  return <><button className="rp-secondary-button" onClick={openDialog}><QrCode size={15} /> Tạo QR</button>{open && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) setOpen(false); }}><section className="rp-modal rp-qr-modal" role="dialog" aria-modal="true"><header><div><h2>QR điểm danh sự kiện</h2><p>{item.name} · Flutter có thể quét mã này</p></div><button className="rp-icon-button" onClick={() => setOpen(false)} aria-label="Đóng"><X size={18} /></button></header>{error && <ErrorPanel message={error} />}{qr ? <div className="rp-qr-result"><div className="rp-qr-image"><QRCodeSVG value={qr.qr} size={250} level="M" includeMargin /></div><strong>QR sự kiện đã sẵn sàng</strong><p>Mã được backend ký. Sinh viên cần đăng ký sự kiện và xác nhận vị trí trên Flutter.</p><button className="rp-secondary-button" onClick={stopQr} disabled={busy}>{busy ? 'Đang tắt...' : 'Tắt mã QR để tạo mã mới'}</button></div> : <><div className="rp-form-grid">{periods.length > 0 && <label>Khung điểm danh<select value={periodId} onChange={(event) => setPeriodId(event.target.value)}>{periods.map((period) => <option key={period.id} value={period.id}>{period.name} · {formatDate(period.startTime)}</option>)}</select></label>}<p className="rp-form-hint">Trình duyệt sẽ yêu cầu quyền vị trí của nơi tổ chức.</p></div><footer><button className="rp-secondary-button" onClick={() => setOpen(false)} disabled={busy}>Hủy</button><button className="rp-secondary-button" onClick={createQr} disabled={busy || (periodsConfigured && (!periods.length || !periodId))}>{busy ? 'Đang tạo...' : 'Lấy vị trí và tạo QR'}</button></footer></>}</section></div>}</>;
}

function EventsView({ items }) {
  return items.length ? <div className="rp-event-grid">{items.map((item) => <article className="rp-card rp-event-card" key={item.id}><div className="rp-event-top"><span className="rp-tag">{item.status || 'Sự kiện'}</span><span className="rp-event-id">{item.id}</span></div><h2>{item.name || 'Sự kiện HUIT'}</h2><div className="rp-event-detail"><CalendarDays size={15} />{formatDate(item.startTime)}</div><div className="rp-event-detail"><Building2 size={15} />{item.location || 'Chưa cập nhật địa điểm'}</div><div className="rp-event-progress"><span>Đăng ký</span><strong>{item.registeredCount ?? 0}{item.capacity ? ` / ${item.capacity}` : ''}</strong></div><div className="rp-progress-track"><i style={{ width: `${item.capacity ? Math.min(100, Number(item.registeredCount || 0) * 100 / item.capacity) : 0}%` }} /></div></article>)}</div> : <EmptyPanel title="Chưa có sự kiện" message="Đơn vị của bạn chưa có sự kiện hoặc không tìm thấy kết quả." />;
}

function AttendanceView({ data, loading, error, query, setQuery, onRefresh, role }) {
  const [selected, setSelected] = useState(null);
  const [roster, setRoster] = useState(null);
  const [rosterLoading, setRosterLoading] = useState(false);
  const [rosterError, setRosterError] = useState('');
  const [savingStudent, setSavingStudent] = useState('');
  const lecturerOrAdmin = isLecturerRole(role) || isAdminRole(role);
  const items = itemsOf(data).map((item) => ({
    ...item,
    classLabel: item.className
      ? `${item.className} · ${item.classId}`
      : item.classId || '',
  })).filter((item) => JSON.stringify(item).toLowerCase().includes(query.trim().toLowerCase()));
  const stats = lecturerOrAdmin
    ? [['Có mặt', sum(items, 'present')], ['Đi trễ', sum(items, 'late')], ['Vắng mặt', sum(items, 'absent')]]
    : [['Đăng ký', sum(items, 'registeredCount')], ['Đã tham dự', sum(items, 'checkedInCount')], ['Vắng mặt', sum(items, 'absentCount')]];

  const openRoster = async (session) => {
    setSelected(session);
    setRoster(null);
    setRosterError('');
    setRosterLoading(true);
    try {
      setRoster(await api(`/api/admin/attendance/sessions/${encodeURIComponent(session.id)}/students`));
    } catch (exception) {
      setRosterError(exception instanceof Error ? exception.message : 'Không thể tải danh sách điểm danh.');
    } finally {
      setRosterLoading(false);
    }
  };

  const updateStudentStatus = async (studentId, status) => {
    setSavingStudent(studentId);
    setRosterError('');
    try {
      await api(`/api/admin/attendance/sessions/${encodeURIComponent(selected.id)}/students/${encodeURIComponent(studentId)}`, {
        method: 'POST', body: { status },
      });
      await openRoster(selected);
      onRefresh();
    } catch (exception) {
      setRosterError(exception instanceof Error ? exception.message : 'Không thể cập nhật điểm danh.');
    } finally {
      setSavingStudent('');
    }
  };
  return (
    <>
      <PageTitle title="Điểm danh" subtitle={lecturerOrAdmin ? 'Phiên học và kết quả tham dự từ cơ sở dữ liệu.' : 'Tổng hợp điểm danh các sự kiện thuộc đơn vị.'} onRefresh={onRefresh} loading={loading} action={lecturerOrAdmin && <ClassQrGenerator onCreated={onRefresh} />} />
      <div className="rp-metrics-grid rp-metrics-compact">{stats.map(([label, value]) => <article className="rp-metric-card" key={label}><span className="rp-metric-icon"><ClipboardCheck size={19} /></span><div><span>{label}</span><strong>{value}</strong></div></article>)}</div>
      <SearchBox value={query} onChange={setQuery} placeholder="Tìm mã lớp, sự kiện, trạng thái..." />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : lecturerOrAdmin
        ? <DataTable items={items} columns={[[ 'Lớp', 'classLabel'], ['Buổi học', 'sessionName'], ['Mở lúc', 'openedAt'], ['Đóng lúc', 'closedAt'], ['Phương thức', 'method'], ['Có mặt', 'present'], ['Đi trễ', 'late'], ['Vắng', 'absent']]} />
        : <EventAttendanceView items={items} />}
      {lecturerOrAdmin && <div className="rp-attendance-session-actions">{items.map((item) => <button key={item.id} className="rp-secondary-button" onClick={() => openRoster(item)}>{item.classLabel} · {item.sessionName || 'Buổi học'} · Danh sách</button>)}</div>}
      {selected && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelected(null); }}><section className="rp-modal" role="dialog" aria-modal="true"><header><div><h2>Danh sách điểm danh</h2><p>{selected.classLabel || selected.className || selected.classId} · {selected.sessionName || 'Buổi học'}</p></div><button className="rp-icon-button" onClick={() => setSelected(null)} aria-label="Đóng"><X size={18} /></button></header>{rosterError && <ErrorPanel message={rosterError} onRetry={() => openRoster(selected)} />}{rosterLoading ? <LoadingPanel /> : roster && <><div className="rp-roster-summary"><span>{roster.session?.canEdit ? 'Phiên đang mở · có thể cập nhật' : 'Phiên đã đóng · chỉ xem'}</span><button className="rp-secondary-button" onClick={() => openRoster(selected)}><RefreshCw size={15} /> Làm mới</button></div><div className="rp-table-wrap"><table className="rp-table"><thead><tr><th>Mã sinh viên</th><th>Họ tên</th><th>Trạng thái</th><th>Thời gian</th></tr></thead><tbody>{itemsOf(roster).map((student) => <tr key={student.studentId}><td>{student.studentId}</td><td>{student.studentName}</td><td>{roster.session?.canEdit ? <select aria-label={`Trạng thái ${student.studentName}`} value={statusValue(student.attendanceStatus)} disabled={savingStudent === student.studentId} onChange={(event) => updateStudentStatus(student.studentId, event.target.value)}><option value="">Chưa ghi nhận</option><option value="present">Có mặt</option><option value="late">Đi muộn</option><option value="absent">Vắng mặt</option><option value="excused">Vắng có phép</option></select> : student.attendanceStatus || 'Chưa ghi nhận'}</td><td>{formatDate(student.checkedInAt)}</td></tr>)}</tbody></table></div>{!itemsOf(roster).length && <EmptyPanel title="Chưa có sinh viên" message="Lớp chưa có sinh viên tham gia." />}</>}</section></div>}
    </>
  );
}

function EventAttendanceView({ items }) {
  const [selected, setSelected] = useState(null);
  const [details, setDetails] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const openDetails = async (item) => {
    setSelected(item); setDetails(null); setError(''); setLoading(true);
    try { setDetails(await api(`/api/events/${encodeURIComponent(item.id)}`)); }
    catch (exception) { setError(exception instanceof Error ? exception.message : 'Không thể tải chi tiết sự kiện.'); }
    finally { setLoading(false); }
  };
  const openEvents = items.filter((item) => !['đã đóng', 'đã kết thúc', 'closed', 'ended'].includes(String(item.status || '').trim().toLowerCase()) && (!item.endTime || new Date(item.endTime) > new Date()));
  return (
    <>
      {openEvents.length ? (
        <div className="rp-event-grid">
          {openEvents.map((item) => (
            <article className="rp-card rp-event-card" key={item.id}>
              <button className="rp-event-open" onClick={() => openDetails(item)}>
                <div className="rp-event-top"><span className="rp-tag">{item.status || 'Đang mở'}</span><span className="rp-event-id">{item.id}</span></div>
                <h2>{item.name || 'Sự kiện HUIT'}</h2>
                <div className="rp-event-detail"><CalendarDays size={15} />{formatDate(item.startTime)}</div>
                <div className="rp-event-detail"><Building2 size={15} />{item.location || 'Chưa cập nhật địa điểm'}</div>
                <div className="rp-event-progress"><span>Đăng ký</span><strong>{item.registeredCount ?? 0}{item.capacity ? ` / ${item.capacity}` : ''}</strong></div>
              </button>
              <div className="rp-inline-actions">
                <button className="rp-secondary-button" onClick={() => openDetails(item)}>Chi tiết sự kiện</button>
                <EventQrAction item={item} />
              </div>
            </article>
          ))}
        </div>
      ) : <EmptyPanel title="Không có sự kiện đang mở" message="Chỉ những sự kiện chưa đóng mới hiển thị tại đây." />}
      {selected && (
        <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelected(null); }}>
          <section className="rp-modal" role="dialog" aria-modal="true">
            <header>
              <div><h2>Chi tiết sự kiện</h2><p>{selected.name || selected.id}</p></div>
              <button className="rp-icon-button" onClick={() => setSelected(null)} aria-label="Đóng"><X size={18} /></button>
            </header>
            {loading ? <LoadingPanel /> : error ? <ErrorPanel message={error} /> : details && (
              <>
                <p className="rp-event-description">{details.description || 'Chưa có mô tả cho sự kiện này.'}</p>
                <div className="rp-detail-grid">
                  <div><small>Thời gian</small><strong>{formatDate(details.startTime)} – {formatDate(details.endTime)}</strong></div>
                  <div><small>Địa điểm</small><strong>{details.location || '—'}</strong></div>
                  <div><small>Đơn vị tổ chức</small><strong>{details.organizerName || '—'}</strong></div>
                  <div><small>Đăng ký</small><strong>{details.registeredCount ?? selected.registeredCount ?? 0}{details.capacity ? ` / ${details.capacity}` : ''}</strong></div>
                </div>
                {details.rules?.length > 0 && (
                  <>
                    <h3>Nội quy</h3>
                    <ul>{details.rules.map((rule, index) => <li key={index}>{typeof rule === 'string' ? rule : rule.text || rule.content}</li>)}</ul>
                  </>
                )}
              </>
            )}
          </section>
        </div>
      )}
    </>
  );
}

function statusValue(status) {
  return ({ 'Có mặt': 'present', 'Đi trễ': 'late', 'Đi muộn': 'late', 'Vắng mặt': 'absent', 'Vắng có phép': 'excused' })[status] || '';
}

function ClassQrGenerator({ onCreated }) {
  const [open, setOpen] = useState(false);
  const [sessions, setSessions] = useState([]);
  const [sessionId, setSessionId] = useState('');
  const [duration, setDuration] = useState('15');
  const [qr, setQr] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!qr?.closedAt) return undefined;
    const remaining = new Date(qr.closedAt).getTime() - Date.now();
    if (!Number.isFinite(remaining) || remaining <= 0) {
      setQr(null);
      api('/api/attendance/sessions').then((result) => {
        const nextSessions = itemsOf(result);
        setSessions(nextSessions);
        setSessionId((current) => nextSessions.some((session) => session.classSessionId === current)
          ? current
          : nextSessions[0]?.classSessionId || '');
      }).catch(() => {});
      return undefined;
    }
    const timer = window.setTimeout(() => {
      setQr(null);
      api('/api/attendance/sessions').then((result) => {
        const nextSessions = itemsOf(result);
        setSessions(nextSessions);
        setSessionId((current) => nextSessions.some((session) => session.classSessionId === current)
          ? current
          : nextSessions[0]?.classSessionId || '');
      }).catch(() => {});
    }, remaining);
    return () => window.clearTimeout(timer);
  }, [qr]);

  const openDialog = async () => {
    setOpen(true);
    setError('');
    setLoading(true);
    try {
      const result = await api('/api/attendance/sessions');
      const nextSessions = itemsOf(result);
      setSessions(nextSessions);
      setSessionId(nextSessions[0]?.classSessionId || '');
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể tải buổi học.');
    } finally {
      setLoading(false);
    }
  };

  const createQr = async (event) => {
    event.preventDefault();
    setError('');
    if (!navigator.geolocation) {
      setError('Trình duyệt này không hỗ trợ lấy vị trí.');
      return;
    }
    setLoading(true);
    try {
      const position = await new Promise((resolve, reject) => navigator.geolocation.getCurrentPosition(resolve, reject, {
        enableHighAccuracy: true, timeout: 15000, maximumAge: 0,
      }));
      const result = await api('/api/attendance/sessions', {
        method: 'POST',
        body: {
          classSessionId: sessionId,
          method: 'Both',
          durationMinutes: Number(duration),
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy: position.coords.accuracy,
        },
      });
      if (!result.qr) throw new Error('Backend không trả về mã QR.');
      setQr(result);
      onCreated();
    } catch (exception) {
      const message = exception?.code === 1
        ? 'Cần cấp quyền vị trí cho trình duyệt để mở phiên điểm danh.'
        : exception?.code === 3
          ? 'Không lấy được vị trí trong thời gian chờ. Hãy thử lại.'
          : exception instanceof Error ? exception.message : 'Không thể tạo mã QR.';
      setError(message);
    } finally {
      setLoading(false);
    }
  };

  const activeSessionId = sessions.find((session) => session.classSessionId === sessionId)?.activeSessionId;
  const stopQr = async (targetSessionId) => {
    setLoading(true);
    setError('');
    try {
      await api(`/api/attendance/sessions/${encodeURIComponent(targetSessionId)}/close`, { method: 'POST' });
      setQr(null);
      setSessions((current) => current.map((session) => session.classSessionId === sessionId
        ? { ...session, activeSessionId: null }
        : session));
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể tắt mã QR.');
    } finally {
      setLoading(false);
    }
  };

  return <>
    <button className="rp-secondary-button" onClick={openDialog}><QrCode size={16} /> Tạo mã QR</button>
    {open && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !loading) setOpen(false); }}>
      <section className="rp-modal rp-qr-modal" role="dialog" aria-modal="true" aria-labelledby="rp-qr-title">
        <header><div><h2 id="rp-qr-title">Tạo mã QR điểm danh</h2><p>Mã do backend HUIT phát hành, tương thích với ứng dụng Flutter.</p></div><button className="rp-icon-button" onClick={() => setOpen(false)} aria-label="Đóng"><X size={18} /></button></header>
        {error && <ErrorPanel message={error} />}
        {qr ? <div className="rp-qr-result"><div className="rp-qr-image"><QRCodeSVG value={qr.qr} size={250} level="M" includeMargin /></div><strong>Phiên điểm danh đang mở</strong><span>Đóng lúc {formatDate(qr.closedAt)}</span><p>Sinh viên mở Flutter, chọn Điểm danh và quét mã này. Vị trí cần được bật trên cả hai thiết bị.</p><button className="rp-secondary-button" onClick={() => stopQr(qr.id)} disabled={loading}>{loading ? 'Đang tắt...' : 'Tắt mã QR để tạo mã mới'}</button></div> : <form onSubmit={createQr}>
          {loading && !sessions.length ? <LoadingPanel /> : <div className="rp-form-grid"><label>Buổi học<select required value={sessionId} onChange={(event) => setSessionId(event.target.value)}><option value="">Chọn buổi học</option>{sessions.map((session) => <option key={session.classSessionId} value={session.classSessionId}>{session.className || session.classId} · {session.classId} · Buổi {session.classSessionId} · {formatDate(session.startTime)}{session.activeSessionId ? ' · Đang có QR' : ''}</option>)}</select></label><label>Thời lượng<select value={duration} onChange={(event) => setDuration(event.target.value)}>{[5, 10, 15, 30, 60].map((minutes) => <option key={minutes} value={minutes}>{minutes} phút</option>)}</select></label><p className="rp-form-hint">Trình duyệt sẽ yêu cầu quyền vị trí. Hãy mở trang qua HTTPS hoặc localhost.</p>{activeSessionId && <><p className="rp-form-hint">Buổi học đã có mã QR hoạt động. Tắt mã đó trước khi tạo mã mới.</p><button type="button" className="rp-secondary-button" onClick={() => stopQr(activeSessionId)} disabled={loading}>Tắt mã QR đang hoạt động</button></>}</div>}
          <footer><button type="button" className="rp-secondary-button" onClick={() => setOpen(false)} disabled={loading}>Hủy</button><button className="rp-secondary-button" disabled={loading || !sessionId || Boolean(activeSessionId)}>{loading ? 'Đang tạo...' : 'Lấy vị trí và tạo QR'}</button></footer>
        </form>}
      </section>
    </div>}
  </>;
}

function ReportsView({ data, loading, error, onRefresh, role }) {
  const [selectedClassId, setSelectedClassId] = useState('');
  const [report, setReport] = useState(null);
  const [reportLoading, setReportLoading] = useState(false);
  const [exporting, setExporting] = useState(false);
  const classes = itemsOf(data);
  useEffect(() => {
    setSelectedClassId('');
    setReport(null);
  }, [role]);
  const selectClass = async (event) => {
    const classId = event.target.value;
    setSelectedClassId(classId);
    setReport(null);
    if (!classId) return;
    setReportLoading(true);
    try {
      setReport(await api(`/api/reports/attendance/classes/${encodeURIComponent(classId)}`));
    } catch (exception) {
      setReport({ error: exception instanceof Error ? exception.message : 'Không thể tải báo cáo.' });
    } finally {
      setReportLoading(false);
    }
  };
  const summary = report?.items || [];
  const totals = [
    ['Có mặt', sum(summary, 'present')], ['Đi trễ', sum(summary, 'late')],
    ['Vắng mặt', sum(summary, 'absent')], ['Vắng có phép', sum(summary, 'excused')],
  ];
  const exportReport = async () => {
    if (!report || report.error) return;
    setExporting(true);
    try {
      const cell = (value, style = {}) => ({ value, ...style });
      const rows = [
        [cell('BÁO CÁO ĐIỂM DANH', { columnSpan: 8, fontWeight: 'bold', fontSize: 18, textColor: '#FFFFFF', backgroundColor: '#174B8A', align: 'center', height: 32 })],
        [cell('LỚP HỌC PHẦN', { fontWeight: 'bold', textColor: '#36536F', backgroundColor: '#EAF2FB' }), cell(classes.find((item) => String(item.id) === selectedClassId)?.name || selectedClassId, { columnSpan: 7, backgroundColor: '#EAF2FB' })],
        [cell('TỔNG SỐ BUỔI', { fontWeight: 'bold', textColor: '#36536F', backgroundColor: '#EAF2FB' }), cell(report.sessionCount ?? report.totalSessions ?? 0, { fontWeight: 'bold', textColor: '#174B8A', backgroundColor: '#EAF2FB' })],
        [],
        ['STT', 'Mã sinh viên', 'Họ và tên', 'Tổng số buổi', 'Có mặt', 'Đi muộn', 'Vắng', 'Vắng có phép'].map((value) => cell(value, { fontWeight: 'bold', textColor: '#FFFFFF', backgroundColor: '#2467A6', align: 'center', wrap: true, height: 26 })),
        ...summary.map((item, index) => {
          const stripe = index % 2 ? '#F4F8FC' : '#FFFFFF';
          return [cell(index + 1, { backgroundColor: stripe, align: 'center' }), cell(item.studentId || '', { backgroundColor: stripe }), cell(item.studentName || '', { backgroundColor: stripe }), cell(Number(item.totalSessions) || 0, { backgroundColor: stripe, align: 'center' }), cell(Number(item.present) || 0, { backgroundColor: '#E7F6ED', textColor: '#187747', align: 'center', fontWeight: 'bold' }), cell(Number(item.late) || 0, { backgroundColor: '#FFF3D8', textColor: '#9A6200', align: 'center', fontWeight: 'bold' }), cell(Number(item.absent) || 0, { backgroundColor: '#FCE8E7', textColor: '#AC3832', align: 'center', fontWeight: 'bold' }), cell(Number(item.excused) || 0, { backgroundColor: '#EAF0FF', textColor: '#385AA8', align: 'center', fontWeight: 'bold' })];
        }),
      ];
      const { default: writeExcelFile } = await import('write-excel-file/universal');
      const workbook = await writeExcelFile(rows, { sheet: 'Báo cáo điểm danh', columns: [{ width: 8 }, { width: 18 }, { width: 30 }, { width: 17 }, { width: 13 }, { width: 13 }, { width: 13 }, { width: 18 }] });
      const url = URL.createObjectURL(await workbook.toBlob());
      const link = document.createElement('a');
      link.href = url;
      link.download = `bao_cao_diem_danh_${String(selectedClassId).replace(/[^A-Za-z0-9._-]/g, '_')}.xlsx`;
      link.click();
      URL.revokeObjectURL(url);
    } catch (exception) {
      setReport({ ...report, error: exception instanceof Error ? exception.message : 'Không thể xuất Excel.' });
    } finally {
      setExporting(false);
    }
  };
  return (
    <>
      <PageTitle title="Báo cáo & thống kê" subtitle="Báo cáo điểm danh theo lớp học." onRefresh={onRefresh} loading={loading} action={report && !report.error && <button className="rp-secondary-button" onClick={exportReport} disabled={exporting || reportLoading}><Download size={16} />{exporting ? 'Đang xuất...' : 'Xuất Excel'}</button>} />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : (
        <>
          <section className="rp-card rp-report-select"><label htmlFor="rp-report-class">Chọn lớp học</label><select id="rp-report-class" value={selectedClassId} onChange={selectClass}><option value="">Chọn lớp để xem báo cáo</option>{classes.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.studentCount ?? 0} sinh viên</option>)}</select></section>
          {reportLoading && <LoadingPanel />}
          {report?.error && <ErrorPanel message={report.error} />}
          {report && !report.error && <><div className="rp-metrics-grid rp-metrics-compact">{totals.map(([label, value]) => <article className="rp-metric-card" key={label}><span className="rp-metric-icon"><BarChart3 size={19} /></span><div><span>{label}</span><strong>{value}</strong></div></article>)}</div><AttendanceDonutChart title="Phân bổ kết quả điểm danh" data={[{ label: 'Có mặt', value: sum(summary, 'present'), color: '#28a76c' }, { label: 'Đi muộn', value: sum(summary, 'late'), color: '#e7a639' }, { label: 'Vắng mặt', value: sum(summary, 'absent'), color: '#d95d54' }, { label: 'Vắng có phép', value: sum(summary, 'excused'), color: '#4770d8' }]} /><DataTable items={summary} columns={[['Mã sinh viên', 'studentId'], ['Họ tên', 'studentName'], ['Tổng buổi', 'totalSessions'], ['Có mặt', 'present'], ['Đi trễ', 'late'], ['Vắng', 'absent'], ['Có phép', 'excused']]} /></>}
          {!classes.length && <EmptyPanel title="Chưa có lớp" message="Tài khoản chưa được phân công lớp học." />}
        </>
      )}
    </>
  );
}

function SettingsView({ darkMode, setDarkMode }) {
  return <>
    <PageTitle title="Cài đặt" subtitle="Tùy chỉnh giao diện ứng dụng." />
    <section className="rp-card rp-settings-card">
      <div>
        <h2>Giao diện</h2>
        <p>Chọn giao diện phù hợp với bạn.</p>
      </div>
      <button className="rp-secondary-button" onClick={() => setDarkMode((value) => !value)}>
        {darkMode ? <Sun size={16} /> : <Moon size={16} />}
        {darkMode ? 'Giao diện sáng' : 'Giao diện tối'}
      </button>
    </section>
  </>;
}

function GenericTable({ page, items }) {
  const [selected, setSelected] = useState(null);
  const columns = page === 'users' ? [['Mã', 'id'], ['Họ tên', 'name'], ['Email', 'email'], ['Vai trò', 'role'], ['Trạng thái', 'status']]
    : page === 'orgUnits' ? [['Mã đơn vị', 'id'], ['Tên đơn vị', 'name']]
      : page === 'certificates' ? [['Mã chứng chỉ', 'id'], ['Sinh viên', 'studentName'], ['Sự kiện', 'eventName'], ['Ngày cấp', 'issuedAt'], ['Trạng thái', 'status']]
        : page === 'feedback' ? [['Loại', 'sourceType'], ['Sinh viên', 'studentName'], ['Nội dung', 'content'], ['Sự kiện / lớp', 'eventName'], ['Thời gian', 'sentAt']]
          : [['Mã', 'id'], ['Nội dung', 'title'], ['Thời gian', 'createdAt']];
  return <>{items.length ? <div className="rp-table-wrap"><table className="rp-table"><thead><tr>{columns.map(([label]) => <th key={label}>{label}</th>)}</tr></thead><tbody>{items.map((item, index) => <tr key={item.id || index} className={page === 'feedback' ? 'rp-clickable-row' : ''} onClick={() => page === 'feedback' && setSelected(item)}>{columns.map(([label, key]) => <td key={key}>{formatCell(item[key])}</td>)}</tr>)}</tbody></table></div> : <EmptyPanel title="Chưa có dữ liệu" message="Danh sách sẽ hiển thị khi hệ thống có bản ghi." />}{selected && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelected(null); }}><section className="rp-modal" role="dialog" aria-modal="true"><header><div><h2>Chi tiết {selected.rating != null ? 'đánh giá' : 'phản hồi'}</h2><p>{selected.studentName || selected.studentId || 'Sinh viên'}</p></div><button className="rp-icon-button" onClick={() => setSelected(null)} aria-label="Đóng"><X size={18} /></button></header><div className="rp-detail-grid"><div><small>Đối tượng</small><strong>{selected.eventName || selected.className || selected.sourceType || '—'}</strong></div><div><small>Thời gian</small><strong>{formatDate(selected.sentAt || selected.createdAt)}</strong></div>{selected.rating != null && <div><small>Đánh giá</small><strong>{selected.rating} / 5 ★</strong></div>}</div><div className="rp-feedback-content">{selected.content || selected.comment || 'Không có nội dung.'}</div></section></div>}</>;
}

function StaffCertificateTable({ items, showNotice }) {
  const [downloading, setDownloading] = useState('');
  const [selected, setSelected] = useState(null);
  const [previewUrl, setPreviewUrl] = useState('');
  const [previewLoading, setPreviewLoading] = useState(false);
  useEffect(() => () => { if (previewUrl) URL.revokeObjectURL(previewUrl); }, [previewUrl]);
  const openDetails = async (item) => {
    setSelected(item); setPreviewUrl(''); setPreviewLoading(true);
    try {
      const blob = await api(`/api/staff/certificates/${encodeURIComponent(item.id)}/pdf`, { responseType: 'blob' });
      setPreviewUrl(URL.createObjectURL(blob));
    } catch (exception) { showNotice('error', exception instanceof Error ? exception.message : 'Không thể mở chứng nhận.'); }
    finally { setPreviewLoading(false); }
  };
  const download = async (item) => {
    setDownloading(item.id);
    try {
      const blob = await api(`/api/staff/certificates/${encodeURIComponent(item.id)}/pdf`, { responseType: 'blob' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `${String(item.id).replace(/[^A-Za-z0-9._-]/g, '_')}.pdf`;
      link.click();
      URL.revokeObjectURL(url);
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể tải chứng nhận.');
    } finally {
      setDownloading('');
    }
  };
  return <>{items.length ? <div className="rp-table-wrap"><table className="rp-table"><thead><tr>{['Mã chứng nhận', 'Sinh viên', 'Sự kiện', 'Ngày cấp', 'Trạng thái', ''].map((label) => <th key={label}>{label}</th>)}</tr></thead><tbody>{items.map((item) => <tr key={item.id} className="rp-clickable-row" onClick={() => openDetails(item)}><td>{item.id}</td><td>{item.studentName || item.studentId || '—'}</td><td>{item.eventName || '—'}</td><td>{formatDate(item.issuedAt)}</td><td>{item.status || '—'}</td><td><button className="rp-secondary-button" onClick={(event) => { event.stopPropagation(); download(item); }} disabled={downloading === item.id}><Download size={15} />{downloading === item.id ? 'Đang tải...' : 'Tải PDF'}</button></td></tr>)}</tbody></table></div> : <EmptyPanel title="Chưa có chứng nhận" message="Danh sách chứng nhận sẽ hiển thị khi có dữ liệu." />}{selected && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelected(null); }}><section className="rp-modal rp-certificate-modal" role="dialog" aria-modal="true"><header><div><h2>Chi tiết chứng nhận</h2><p>{selected.studentName || selected.studentId} · {selected.eventName}</p></div><button className="rp-icon-button" onClick={() => setSelected(null)} aria-label="Đóng"><X size={18} /></button></header><div className="rp-detail-grid"><div><small>Mã chứng nhận</small><strong>{selected.id}</strong></div><div><small>Ngày cấp</small><strong>{formatDate(selected.issuedAt)}</strong></div><div><small>Trạng thái</small><strong>{selected.status || 'Đã cấp'}</strong></div></div>{previewLoading ? <LoadingPanel /> : previewUrl ? <iframe className="rp-certificate-preview" src={previewUrl} title={`Chứng nhận ${selected.id}`} /> : <ErrorPanel message="Không thể hiển thị chứng nhận." />}</section></div>}</>;
}

function DataTable({ items, columns }) {
  return <div className="rp-table-wrap"><table className="rp-table"><thead><tr>{columns.map(([label]) => <th key={label}>{label}</th>)}</tr></thead><tbody>{items.map((item, index) => <tr key={item.id || index}>{columns.map(([label, key]) => <td key={key}>{formatCell(item[key])}</td>)}</tr>)}</tbody></table></div>;
}

function formatCell(value) {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'string' && /(?:Time|At|Date)$/i.test(value)) return formatDate(value);
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function sum(items, key) {
  return items.reduce((total, item) => total + (Number(item[key]) || 0), 0);
}

function SearchBox({ value, onChange, placeholder }) {
  return <label className="rp-search"><Search size={17} /><input value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} />{value && <button onClick={() => onChange('')} aria-label="Xóa tìm kiếm"><X size={15} /></button>}</label>;
}

function LoadingPanel() {
  return <div className="rp-state"><span className="rp-spinner" />Đang tải dữ liệu...</div>;
}

function ErrorPanel({ message, onRetry }) {
  return <div className="rp-error"><strong>Không tải được dữ liệu</strong><p>{message}</p>{onRetry && <button className="rp-secondary-button" onClick={onRetry}>Thử lại</button>}</div>;
}

function EmptyPanel({ title, message }) {
  return <div className="rp-empty"><span><ShieldCheck size={24} /></span><strong>{title}</strong><p>{message}</p></div>;
}
