import { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import {
  Activity, Award, BarChart3, Bell, BookOpen, Building2, CalendarDays, Download, Eye,
  ChevronLeft, ChevronRight, ClipboardCheck, Home, LogOut,
  Menu, MessageSquare, Moon, Pencil, Plus, RefreshCw, RotateCcw, Save, Search, Settings, ShieldCheck,
  QrCode, Sun, Trash2, Upload, Users, X,
} from 'lucide-react';
import { api } from './api.js';
import { QRCodeSVG } from 'qrcode.react';
import { AttendanceDonutChart } from './StatisticsCharts.jsx';
import { semesterForDate } from './semester.js';
import AdminMasterDataImport from './AdminMasterDataImport.jsx';
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
const isEmployeeRole = (role) => ['organizer', 'event_organizer', 'ban tổ chức', 'cán bộ', 'nhân viên', 'công nhân viên', 'staff', 'employee'].includes(String(role || '').trim().toLowerCase());
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
  const [certificateTemplateOpen, setCertificateTemplateOpen] = useState(false);

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
  const canImportAdminMasterData = isAdminRole(role) && ['users', 'orgUnits'].includes(page);
  const certificateTemplateAction = page === 'certificates'
    ? <button className="rp-secondary-button" onClick={() => setCertificateTemplateOpen(true)}><Eye size={16} /> Xem mẫu</button>
    : null;
  return (
    <>
      <PageTitle
        title={titles[page] || 'Dashboard'}
        subtitle="Dữ liệu được tải trực tiếp từ hệ thống HUIT."
        onRefresh={load}
        loading={loading}
        action={canImportAdminMasterData
          ? <AdminMasterDataImport kind={page === 'orgUnits' ? 'units' : 'users'} onImported={load} showNotice={showNotice} />
          : certificateTemplateAction}
      />
      {page !== 'notifications' && <SearchBox value={query} onChange={setQuery} placeholder={`Tìm trong ${(titles[page] || '').toLowerCase()}...`} />}
      {error ? <ErrorPanel message={error} onRetry={load} /> : loading ? <LoadingPanel /> : (
        page === 'events' ? <EventsView items={rows} />
          : page === 'notifications' ? <EmptyPanel title="Không có thông báo" message="Hiện chưa có thông báo dành cho vai trò này." />
            : page === 'certificates' ? <StaffCertificateTable items={rows} showNotice={showNotice} />
            : <GenericTable page={page} items={rows} />
      )}
      {certificateTemplateOpen && <CertificateSignatureDialog onClose={() => setCertificateTemplateOpen(false)} showNotice={showNotice} />}
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
  const [selectedSemester, setSelectedSemester] = useState(() =>
    semesterForDate(new Date()),
  );
  const [semesterAttendance, setSemesterAttendance] = useState(null);
  const [semesterAttendanceLoading, setSemesterAttendanceLoading] = useState(false);
  const [semesterAttendanceError, setSemesterAttendanceError] = useState('');
  const [semesterReload, setSemesterReload] = useState(0);
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
  const refreshDashboard = () => {
    onRefresh?.();
    setSemesterReload((value) => value + 1);
  };
  useEffect(() => {
    if (!canViewAttendanceReport) return undefined;
    let active = true;
    setSemesterAttendanceLoading(true);
    setSemesterAttendanceError('');
    setSemesterAttendance(null);
    api(`/api/dashboard?semester=${encodeURIComponent(selectedSemester)}`)
      .then((result) => {
        if (active) setSemesterAttendance(result.attendanceBreakdown || null);
      })
      .catch((exception) => {
        if (active) {
          setSemesterAttendanceError(
            exception instanceof Error ? exception.message : 'Không thể tải thống kê học kỳ.',
          );
        }
      })
      .finally(() => {
        if (active) setSemesterAttendanceLoading(false);
      });
    return () => { active = false; };
  }, [canViewAttendanceReport, selectedSemester, semesterReload]);
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
      : canViewAttendanceReport
        ? semesterAttendance
        : data?.attendanceBreakdown || attendanceReport?.summary || aggregateEventBreakdown;
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
      <PageTitle title="Trang chủ" subtitle={`Số liệu hiện tại · ${isAdminRole(role) ? 'Quản trị viên' : isLecturerRole(role) ? 'Giảng viên' : 'Công nhân viên'}`} onRefresh={refreshDashboard} loading={loading} />
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
          {canViewAttendanceReport && !isClassSelected && !isEventSelected && <div className="rp-semester-filter">
            <label htmlFor="role-dashboard-semester">Học kỳ thống kê</label>
            <select id="role-dashboard-semester" value={selectedSemester} onChange={(event) => setSelectedSemester(event.target.value)}>
              <option value="HK1">Học kỳ 1</option>
              <option value="HK2">Học kỳ 2</option>
              <option value="HK3">Học kỳ 3</option>
            </select>
          </div>}
          {canViewAttendanceReport && !isClassSelected && !isEventSelected && semesterAttendanceLoading && <LoadingPanel />}
          {canViewAttendanceReport && !isClassSelected && !isEventSelected && semesterAttendanceError && <ErrorPanel message={semesterAttendanceError} onRetry={() => setSemesterReload((value) => value + 1)} />}
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
  const allClasses = itemsOf(data);
  const classes = allClasses.filter((item) => JSON.stringify(item).toLowerCase().includes(query.trim().toLowerCase()));
  const canManage = isAdminRole(role);
  const [importingWorkbook, setImportingWorkbook] = useState(false);
  const workbookInput = useRef(null);
  const [classWorkbookDraft, setClassWorkbookDraft] = useState(null);
  const [classWorkbookError, setClassWorkbookError] = useState('');
  const selectedClass = classes.find((item) => String(item.id) === String(selectedId));

  const prepareClassWorkbook = async (event) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setClassWorkbookError('');
    try {
      const groups = await readStudentRosterGroupsFromWorkbook(file, {
        targetIdHeaders: ['MaLop', 'Mã lớp', 'classId', 'classCode'],
        targetNameHeaders: ['TenLop', 'Tên lớp', 'className'],
      });
      const prepared = groups.map((group) => {
        const matches = allClasses.filter((item) =>
          String(item.id || item.code).trim().toLowerCase() === group.targetId.toLowerCase());
        const item = matches.length === 1 ? matches[0] : null;
        const start = item?.startTime ? new Date(item.startTime) : null;
        const archived = item && (item.status === 'Đã đóng'
          || (start && !Number.isNaN(start.valueOf()) && start < new Date(Date.now() - 365 * 86400000)));
        const issue = group.studentIds.length > 2000
          ? 'Vượt giới hạn 2.000 sinh viên.'
          : matches.length !== 1
            ? matches.length ? 'Mã lớp bị trùng.' : 'Không tìm thấy mã lớp.'
            : archived ? 'Lớp đã đóng hoặc lưu trữ.' : '';
        return { ...group, item, issue };
      });
      setClassWorkbookDraft(prepared);
    } catch (exception) {
      const message = exception instanceof Error ? exception.message : 'Không thể đọc file Excel.';
      setClassWorkbookError(message);
      showNotice('error', `Không thể chuẩn bị nhập lớp: ${message}`);
    }
  };

  const importClassWorkbook = async (event) => {
    event.preventDefault();
    if (!classWorkbookDraft) return;
    setImportingWorkbook(true);
    let imported = 0;
    let alreadyMember = 0;
    let unknown = 0;
    let duplicates = 0;
    const skipped = classWorkbookDraft.filter((group) => group.issue)
      .map((group) => `${group.targetName || group.targetId}: ${group.issue}`);
    try {
      for (const group of classWorkbookDraft) {
        if (group.issue) continue;
        try {
          const result = await api(`/api/admin/classes/${encodeURIComponent(group.item.id)}/students/import`, {
            method: 'POST',
            body: { studentIds: group.studentIds },
          });
          imported += Number(result.importedCount || 0);
          alreadyMember += Number(result.alreadyMemberCount || 0);
          unknown += result.unknownStudentIds?.length || 0;
          duplicates += group.duplicateRows;
        } catch (exception) {
          skipped.push(`${group.item.name || group.item.id}: ${exception instanceof Error ? exception.message : 'không thể nhập.'}`);
        }
      }
      await onRefresh();
      const summary = `Đã thêm ${imported} sinh viên; ${alreadyMember} sinh viên đã có trong lớp.`
        + (unknown ? ` Không tìm thấy ${unknown} mã sinh viên.` : '')
        + (duplicates ? ` Có ${duplicates} dòng mã trùng trong file.` : '')
        + (skipped.length ? ` Không nhập được ${skipped.length} lớp: ${skipped.slice(0, 5).join(' | ')}${skipped.length > 5 ? ' | ...' : ''}` : '');
      showNotice(skipped.length ? 'error' : 'success', summary);
      setClassWorkbookDraft(null);
    } catch (exception) {
      const message = exception instanceof Error ? exception.message : 'Không thể tải lại danh sách lớp.';
      setClassWorkbookError(message);
      showNotice('error', `Đã nhập nhưng không thể xác nhận dữ liệu mới: ${message}`);
    } finally {
      setImportingWorkbook(false);
    }
  };

  return (
    <>
      <PageTitle title="Quản lý lớp học" subtitle="Lớp được phân quyền theo tài khoản đang đăng nhập." onRefresh={onRefresh} loading={loading} action={canManage && <>
        <input ref={workbookInput} type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={prepareClassWorkbook} hidden />
        <button className="rp-secondary-button" onClick={() => workbookInput.current?.click()} disabled={importingWorkbook}>
          <Upload size={16} /> {importingWorkbook ? 'Đang nhập...' : 'Thêm lớp Excel'}
        </button>
        <ClassAdminActions createOnly onRefresh={onRefresh} showNotice={showNotice} />
      </>} />
      {classWorkbookDraft && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !importingWorkbook) setClassWorkbookDraft(null); }}>
        <form className="rp-modal rp-form-modal" role="dialog" aria-modal="true" onSubmit={importClassWorkbook}>
          <header><div><h2>Xác nhận nhập sinh viên vào lớp</h2><p>{classWorkbookDraft.length} mã lớp, {classWorkbookDraft.reduce((total, group) => total + group.studentIds.length, 0)} mã sinh viên được đọc từ file.</p></div><button type="button" className="rp-icon-button" onClick={() => setClassWorkbookDraft(null)} aria-label="Đóng" disabled={importingWorkbook}><X size={18} /></button></header>
          {!classWorkbookDraft.some((group) => !group.issue) && <div className="rp-import-warning" role="alert"><strong>Chưa thể nhập sinh viên</strong><span>Không có mã lớp nào khớp với lớp hiện có. Hãy tạo lớp trước, rồi mới import danh sách sinh viên.</span></div>}
          {classWorkbookError && <ErrorPanel message={classWorkbookError} />}
          <div className="rp-import-preview">{classWorkbookDraft.map((group) => <div key={group.targetId}><strong>{group.item?.name || group.targetName || group.targetId} · {group.targetId}</strong><span>{group.studentIds.length} sinh viên{group.duplicateRows ? `, ${group.duplicateRows} dòng trùng` : ''}{group.issue ? ` · Bỏ qua: ${group.issue}` : ''}</span><code>{group.studentIds.join(', ')}</code></div>)}</div>
          <footer><button type="button" className="rp-secondary-button" onClick={() => setClassWorkbookDraft(null)} disabled={importingWorkbook}>Hủy</button><button className="rp-secondary-button" disabled={importingWorkbook || !classWorkbookDraft.some((group) => !group.issue)}>{importingWorkbook ? 'Đang nhập...' : 'Xác nhận nhập'}</button></footer>
        </form>
      </div>}
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
  const [pendingStudentImport, setPendingStudentImport] = useState(null);

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
    if (!ids.length) {
      setError('Không tìm thấy mã sinh viên hợp lệ để nhập.');
      return;
    }
    if (ids.length > 2000) {
      setError('Mỗi lần chỉ có thể nhập tối đa 2.000 sinh viên.');
      return;
    }
    setPendingStudentImport(ids);
  };

  const confirmStudentImport = async () => {
    if (!pendingStudentImport) return;
    setBusy(true);
    setError('');
    try {
      const result = await api(`/api/admin/classes/${encodeURIComponent(item.id)}/students/import`, {
        method: 'POST', body: { studentIds: pendingStudentImport },
      });
      const unknown = result.unknownStudentIds?.length ? ` Mã không tồn tại: ${result.unknownStudentIds.join(', ')}.` : '';
      showNotice('success', `Đã thêm ${result.importedCount || 0} sinh viên; ${result.alreadyMemberCount || 0} sinh viên đã có trong lớp.${unknown}`);
      setPendingStudentImport(null);
      setForm(null);
      await onRefresh();
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể nhập sinh viên.');
      setPendingStudentImport(null);
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể nhập sinh viên.');
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
      {pendingStudentImport && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) setPendingStudentImport(null); }}>
        <section className="rp-modal rp-form-modal" role="dialog" aria-modal="true">
          <header><div><h2>Xác nhận import sinh viên</h2><p>{item.name || item.id} · {pendingStudentImport.length} mã sinh viên.</p></div><button type="button" className="rp-icon-button" onClick={() => setPendingStudentImport(null)} aria-label="Đóng" disabled={busy}><X size={18} /></button></header>
          {error && <ErrorPanel message={error} />}
          <div className="rp-import-preview"><div><strong>Danh sách mã sinh viên</strong><code>{pendingStudentImport.join(', ')}</code></div></div>
          <footer><button type="button" className="rp-secondary-button" onClick={() => setPendingStudentImport(null)} disabled={busy}>Hủy</button><button type="button" className="rp-secondary-button" onClick={confirmStudentImport} disabled={busy}>{busy ? 'Đang nhập...' : 'Xác nhận import'}</button></footer>
        </section>
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

function normalizeWorkbookHeader(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

async function readWorkbookRows(file) {
  const { default: readExcelFile } = await import('read-excel-file/universal');
  const workbook = await readExcelFile(file);
  const rows = Array.isArray(workbook[0]) ? workbook : workbook[0]?.data;
  if (!Array.isArray(rows) || !rows.length) throw new Error('Không tìm thấy dữ liệu trong file Excel.');
  return rows;
}

async function readStudentRosterGroupsFromWorkbook(file, { targetIdHeaders, targetNameHeaders }) {
  const rows = await readWorkbookRows(file);
  const studentHeaders = new Set(['mssv', 'masv', 'masinhvien', 'studentid', 'studentcode']);
  const targetHeaders = new Set(targetIdHeaders.map(normalizeWorkbookHeader));
  const headerIndex = rows.findIndex((row) => {
    const headers = row.map(normalizeWorkbookHeader);
    return headers.some((header) => studentHeaders.has(header))
      && headers.some((header) => targetHeaders.has(header));
  });
  if (headerIndex < 0) throw new Error('File cần có cột MSSV và mã sự kiện/lớp.');
  const headers = rows[headerIndex].map(normalizeWorkbookHeader);
  const studentIndex = headers.findIndex((header) => studentHeaders.has(header));
  const targetIndex = headers.findIndex((header) => targetHeaders.has(header));
  const targetNameSet = new Set(targetNameHeaders.map(normalizeWorkbookHeader));
  const targetNameIndex = headers.findIndex((header) => targetNameSet.has(header));
  const groups = new Map();
  for (const [offset, row] of rows.slice(headerIndex + 1).entries()) {
    const studentId = String(row[studentIndex] ?? '').trim();
    if (!studentId) continue;
    const targetId = String(row[targetIndex] ?? '').trim();
    if (!targetId) throw new Error(`Thiếu mã sự kiện/lớp ở dòng ${headerIndex + offset + 2}.`);
    const key = targetId.toLocaleLowerCase();
    const group = groups.get(key) || {
      targetId,
      targetName: targetNameIndex < 0 ? '' : String(row[targetNameIndex] ?? '').trim(),
      studentIds: [],
      seen: new Set(),
      duplicateRows: 0,
    };
    const studentKey = studentId.toLocaleUpperCase();
    if (group.seen.has(studentKey)) group.duplicateRows += 1;
    else {
      group.seen.add(studentKey);
      group.studentIds.push(studentId);
    }
    groups.set(key, group);
  }
  if (!groups.size) throw new Error('Không tìm thấy sinh viên có mã sự kiện/lớp trong file Excel.');
  return [...groups.values()];
}

function excelTimeMinutes(value) {
  if (value instanceof Date) return value.getHours() * 60 + value.getMinutes();
  if (typeof value === 'number' && value >= 0 && value < 1) return Math.round(value * 1440);
  const match = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(String(value ?? '').trim());
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  return hours < 24 && minutes < 60 ? hours * 60 + minutes : null;
}

function excelDateString(value) {
  if (value instanceof Date && !Number.isNaN(value.valueOf())) {
    return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`;
  }
  const text = String(value ?? '').trim();
  const isoDate = /^(\d{4})-(\d{2})-(\d{2})/.exec(text);
  if (isoDate) return `${isoDate[1]}-${isoDate[2]}-${isoDate[3]}`;
  const date = new Date(text);
  if (Number.isNaN(date.valueOf())) return '';
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

async function readEventsFromWorkbook(file) {
  const rows = await readWorkbookRows(file);
  const headersWanted = {
    id: new Set(['masukien']),
    name: new Set(['tensukien']),
    organizer: new Set(['donvitochuc']),
    location: new Set(['diadiem']),
    date: new Set(['ngaytochuc']),
    start: new Set(['giobatdau']),
    end: new Set(['gioketthuc']),
    description: new Set(['mota']),
  };
  const headerIndex = rows.findIndex((row) => {
    const headers = row.map(normalizeWorkbookHeader);
    return headers.some((header) => headersWanted.id.has(header))
      && headers.some((header) => headersWanted.name.has(header));
  });
  if (headerIndex < 0) throw new Error('File cần có cột MaSuKien và TenSuKien.');
  const headers = rows[headerIndex].map(normalizeWorkbookHeader);
  const column = (key) => headers.findIndex((header) => headersWanted[key].has(header));
  const events = [];
  const warnings = [];
  for (const [offset, row] of rows.slice(headerIndex + 1).entries()) {
    const name = String(row[column('name')] ?? '').trim();
    const sourceId = String(row[column('id')] ?? '').trim();
    if (!name && !sourceId) continue;
    const rowNumber = headerIndex + offset + 2;
    if (!name || !sourceId) {
      warnings.push(`Dòng ${rowNumber}: thiếu ${!sourceId ? 'mã sự kiện' : 'tên sự kiện'}, sẽ bỏ qua.`);
      continue;
    }
    const eventDate = excelDateString(row[column('date')]);
    const organizerName = String(row[column('organizer')] ?? '').trim();
    const location = String(row[column('location')] ?? '').trim();
    const missingFields = [
      !eventDate && 'ngày tổ chức',
      !organizerName && 'đơn vị tổ chức',
      !location && 'địa điểm',
    ].filter(Boolean);
    if (missingFields.length) {
      warnings.push(`Dòng ${rowNumber} (${name}): thiếu ${missingFields.join(', ')}, sẽ bỏ qua.`);
      continue;
    }
    events.push({
      sourceId,
      name,
      organizerName,
      location,
      eventDate,
      startMinutes: excelTimeMinutes(row[column('start')]),
      endMinutes: excelTimeMinutes(row[column('end')]),
      description: String(row[column('description')] ?? '').trim(),
    });
  }
  if (!events.length) {
    throw new Error(warnings.length
      ? `Không có sự kiện hợp lệ để nhập. ${warnings.join(' ')}`
      : 'Không tìm thấy sự kiện nào trong file Excel.');
  }
  return { events, warnings };
}

function normalizeMatchText(value) {
  return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().replace(/\s+/g, ' ');
}

function EventRegistrationFormField({ form, setForm }) {
  const [container, setContainer] = useState(null);

  useEffect(() => {
    setContainer(form
      ? document.querySelector('form.rp-modal.rp-form-modal .rp-form-grid')
      : null);
  }, [Boolean(form), form?.id]);

  if (!form || !container) return null;
  return createPortal(
    <label className="rp-form-wide">
      Đơn đăng ký có mộc (PDF)
      <input
        type="file"
        accept="application/pdf,.pdf"
        onChange={(event) => {
          const registrationFormFile = event.target.files?.[0] || null;
          setForm((current) => current && ({
            ...current,
            registrationFormFile,
          }));
        }}
      />
      <small className="rp-image-help">
        Tệp PDF tối đa 10 MB. Không bắt buộc.
      </small>
      {form.registrationFormFile && (
        <small>{form.registrationFormFile.name}</small>
      )}
      {form.registrationFormUrl
        ? <a className="rp-registration-form-link" href={form.registrationFormUrl} target="_blank" rel="noreferrer">Xem đơn đăng ký hiện tại</a>
        : !form.registrationFormFile && <small>Chưa có đơn đăng ký PDF.</small>}
    </label>,
    container,
  );
}

function eventAttendanceThresholdOptions(periodCount) {
  return periodCount > 0
    ? Array.from({ length: periodCount }, (_, index) => Math.floor(((index + 1) * 100) / periodCount))
    : [100];
}

function EventRegistrationDetails({ eventId, registrationFormUrl }) {
  const [container, setContainer] = useState(null);

  useEffect(() => {
    if (!eventId) {
      setContainer(null);
      return;
    }
    const target = [...document.querySelectorAll('.rp-modal-backdrop .rp-modal')]
      .find((modal) => !modal.querySelector('form') && modal.textContent.includes(eventId));
    setContainer(target || null);
  }, [eventId]);

  if (!eventId || !container) return null;
  return createPortal(
    <section className="rp-registration-form-details">
      <h3 className="rp-modal-section-title">Đơn đăng ký</h3>
      {registrationFormUrl
        ? <a className="rp-secondary-button" href={registrationFormUrl} target="_blank" rel="noreferrer">Xem đơn đăng ký</a>
        : <p className="rp-modal-muted">Không có đơn đăng ký.</p>}
    </section>,
    container,
  );
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
  const [manualImportPreview, setManualImportPreview] = useState(null);
  const [eventWorkbookDraft, setEventWorkbookDraft] = useState(null);
  const [eventUnitMappings, setEventUnitMappings] = useState({});
  const [eventWorkbookBusy, setEventWorkbookBusy] = useState(false);
  const [studentWorkbookDraft, setStudentWorkbookDraft] = useState(null);
  const [studentWorkbookBusy, setStudentWorkbookBusy] = useState(false);
  const eventWorkbookInput = useRef(null);
  const studentWorkbookInput = useRef(null);
  const [busyAction, setBusyAction] = useState('');
  const [certificateTarget, setCertificateTarget] = useState(null);
  const [certificateStudents, setCertificateStudents] = useState([]);
  const [selectedCertificateStudents, setSelectedCertificateStudents] = useState(new Set());
  const [certificateLoading, setCertificateLoading] = useState(false);
  const [certificateBusy, setCertificateBusy] = useState('');
  const [certificateError, setCertificateError] = useState('');
  const [showClosedEvents, setShowClosedEvents] = useState(false);
  const [selectedClosedEventIds, setSelectedClosedEventIds] = useState(new Set());
  const [imagePreview, setImagePreview] = useState('');
  const [imageInputVersion, setImageInputVersion] = useState(0);
  const allEvents = itemsOf(data).map((item) => {
    const closed = item.status === 'Đã đóng';
    const now = Date.now();
    const start = item.startTime ? new Date(item.startTime).getTime() : NaN;
    const end = item.endTime ? new Date(item.endTime).getTime() : NaN;
    const status = closed ? 'Đã đóng' : Number.isFinite(end) && end <= now ? 'Đã kết thúc' : Number.isFinite(start) && start > now ? 'Sắp diễn ra' : 'Đang diễn ra';
    return { ...item, displayStatus: status };
  });
  const events = allEvents
    .filter((item) => (item.displayStatus === 'Đã đóng') === showClosedEvents)
    .filter((item) => JSON.stringify(item).toLowerCase().includes(query.trim().toLowerCase()))
    .sort((a, b) => {
      const rank = (item) => item.displayStatus === 'Sắp diễn ra' ? 0 : item.displayStatus === 'Đang diễn ra' ? 1 : item.displayStatus === 'Đã kết thúc' ? 2 : 3;
      return rank(a) - rank(b) || new Date(a.startTime || 0) - new Date(b.startTime || 0);
    });
  const canManage = !isLecturerRole(role);
  const canImportExcel = isAdminRole(role) || isEmployeeRole(role);
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
      const attendanceThresholdOptions = eventAttendanceThresholdOptions(periods.length);
      const storedAttendanceThreshold = Number(current.attendanceThresholdPercent);
      setUnits(itemsOf(unitResult));
      setForm({
        id: item?.id || '', name: current.name || item?.name || '', organizerId: current.organizerId || item?.organizerId || '',
        startTime: toDateTimeInput(current.startTime || item?.startTime || new Date()),
        endTime: toDateTimeInput(current.endTime || item?.endTime || new Date(Date.now() + 7200000)),
        location: current.location || item?.location || '', capacity: String(current.capacity || item?.capacity || 100),
        certificateEnabled: current.certificateEnabled === true || Number(current.certificateEnabled) === 1,
        imageUrl: current.imageUrl || item?.imageUrl || '',
        registrationFormUrl: current.registrationFormUrl || '',
        registrationFormFile: null,
        description: current.description || '', benefits, rules, periods,
        attendanceThresholdPercent: attendanceThresholdOptions.includes(storedAttendanceThreshold)
          ? storedAttendanceThreshold
          : 100,
      });
    } catch (exception) {
      setFormError(exception instanceof Error ? exception.message : 'Không thể tải dữ liệu sự kiện.');
      setForm({ id: item?.id || '', name: item?.name || '', organizerId: item?.organizerId || '', startTime: '', endTime: '', location: item?.location || '', capacity: String(item?.capacity || 100), certificateEnabled: item?.certificateEnabled === true || Number(item?.certificateEnabled) === 1, attendanceThresholdPercent: 100, imageUrl: item?.imageUrl || '', registrationFormUrl: '', registrationFormFile: null, description: '', benefits: [], rules: '', periods: [] });
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
      attendanceThresholdPercent: eventAttendanceThresholdOptions(parsePeriods.length)
        .includes(Number(form.attendanceThresholdPercent))
        ? Number(form.attendanceThresholdPercent)
        : 100,
    };
    try {
      if (form.registrationFormFile) {
        const uploadBody = new FormData();
        uploadBody.append('registrationForm', form.registrationFormFile);
        const uploadedForm = await api('/api/organizer/event-registration-forms', {
          method: 'POST',
          body: uploadBody,
          timeoutMs: 30000,
        });
        body.registrationFormUrl = uploadedForm.registrationFormUrl;
      } else {
        body.registrationFormUrl = form.registrationFormUrl || '';
      }
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

  const refreshCertificateStudents = async (item) => {
    const result = await api(`/api/organizer/events/${encodeURIComponent(item.id)}/students`);
    const attendees = itemsOf(result);
    setCertificateStudents(attendees.filter((student) => (
      student.certificateStatus !== 'Đã cấp' || student.emailStatus !== 'Đã gửi'
    )));
    return attendees;
  };

  const openCertificateManager = async (item) => {
    setCertificateTarget(item);
    setCertificateStudents([]);
    setSelectedCertificateStudents(new Set());
    setCertificateError('');
    setCertificateLoading(true);
    try {
      await refreshCertificateStudents(item);
    } catch (exception) {
      setCertificateError(exception instanceof Error ? exception.message : 'Không tải được danh sách cấp chứng nhận.');
    } finally {
      setCertificateLoading(false);
    }
  };

  const issueSelectedCertificates = async (channel) => {
    if (!certificateTarget || selectedCertificateStudents.size === 0) return;
    const selectedIds = [...selectedCertificateStudents].filter((studentId) => {
      const student = certificateStudents.find((item) => item.studentId === studentId);
      if (!student) return false;
      return channel === 'app'
        ? student.certificateStatus !== 'Đã cấp'
        : student.emailStatus !== 'Đã gửi' && student.emailStatus !== 'Đang gửi';
    });
    if (selectedIds.length === 0) return;
    const channelLabel = channel === 'app' ? 'cấp trong app' : 'gửi qua Gmail';
    if (!window.confirm(`Thực hiện ${channelLabel} cho ${selectedIds.length} sinh viên đã chọn?`)) return;
    setCertificateBusy(channel + '-selected');
    setCertificateError('');
    let completed = 0;
    const failures = [];
    const endpointAction = channel === 'app' ? 'issue' : 'send';
    const resultField = channel === 'app' ? 'issued' : 'sent';
    try {
      for (const studentId of selectedIds) {
        try {
          const result = await api(`/api/organizer/events/${encodeURIComponent(certificateTarget.id)}/certificates/${endpointAction}`, {
            method: 'POST', body: { studentId },
          });
          completed += Number(result[resultField] || 0);
          for (const failure of result.failures || []) failures.push(failure.message || studentId);
        } catch (exception) {
          failures.push(`${studentId}: ${exception instanceof Error ? exception.message : 'Action failed.'}`);
        }
      }
      await refreshCertificateStudents(certificateTarget);
      setSelectedCertificateStudents(new Set());
      showNotice(failures.length ? 'error' : 'success', `Đã ${channelLabel} ${completed}/${selectedIds.length} chứng nhận.${failures.length ? ' Lỗi: ' + failures.join('; ') : ''}`);
    } catch (exception) {
      setCertificateError(exception instanceof Error ? exception.message : 'Không tải lại được danh sách chứng nhận.');
    } finally {
      setCertificateBusy('');
    }
  };

  const issueAllCertificates = async (channel) => {
    if (!certificateTarget) return;
    const channelLabel = channel === 'app' ? 'cấp trong app' : 'gửi qua Gmail';
    if (!window.confirm(`Thực hiện ${channelLabel} cho toàn bộ sinh viên đủ điều kiện của sự kiện "${certificateTarget.name}"?`)) return;
    setCertificateBusy(channel + '-all');
    setCertificateError('');
    try {
      const endpointAction = channel === 'app' ? 'issue' : 'send';
      const result = await api(`/api/organizer/events/${encodeURIComponent(certificateTarget.id)}/certificates/${endpointAction}`, { method: 'POST' });
      const completed = Number(result[channel === 'app' ? 'issued' : 'sent'] || 0);
      const failures = (result.failures || []).map((failure) => failure.message || failure.studentId);
      await refreshCertificateStudents(certificateTarget);
      setSelectedCertificateStudents(new Set());
      showNotice(failures.length ? 'error' : 'success', `Đã ${channelLabel} ${completed} chứng nhận${result.skipped ? ', bỏ qua ' + result.skipped : ''}.${failures.length ? ' Lỗi: ' + failures.join('; ') : result.message ? ' ' + result.message : ''}`);
    } catch (exception) {
      setCertificateError(exception instanceof Error ? exception.message : 'Không cấp được chứng nhận.');
    } finally {
      setCertificateBusy('');
    }
  };

  const runEventAction = async (item, action) => {
    if (action === 'certificates') {
      await openCertificateManager(item);
      return;
    }
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

  const deleteSelectedClosedEvents = async () => {
    const ids = [...selectedClosedEventIds];
    if (!ids.length || !window.confirm(`Xóa ${ids.length} sự kiện đã đóng đã chọn? Thao tác này không thể hoàn tác.`)) return;
    setBusyAction('delete-selected');
    try {
      for (const id of ids) await api(`/api/organizer/events/${encodeURIComponent(id)}`, { method: 'DELETE' });
      setSelectedClosedEventIds(new Set());
      showNotice('success', `Đã xóa ${ids.length} sự kiện.`);
      await onRefresh();
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể xóa các sự kiện đã chọn.');
      await onRefresh();
    } finally {
      setBusyAction('');
    }
  };

  const importStudents = async (event) => {
    event.preventDefault();
    const ids = parseStudentIds(studentIds);
    if (!ids.length) {
      showNotice('error', 'Không tìm thấy mã sinh viên hợp lệ để nhập.');
      return;
    }
    if (ids.length > 2000) {
      showNotice('error', 'Mỗi lần chỉ có thể nhập tối đa 2.000 sinh viên.');
      return;
    }
    setManualImportPreview(ids);
  };

  const confirmManualImport = async () => {
    if (!importTarget || !manualImportPreview) return;
    setBusyAction('import');
    try {
      const result = await api(`/api/organizer/events/${encodeURIComponent(importTarget.id)}/students/import`, { method: 'POST', body: { studentIds: manualImportPreview } });
      const unknown = result.unknownStudentIds?.length ? ` Mã không tồn tại: ${result.unknownStudentIds.join(', ')}.` : '';
      showNotice('success', `Đã thêm ${result.importedCount || 0} sinh viên đăng ký; ${result.alreadyRegisteredCount || 0} sinh viên đã đăng ký trước đó.${unknown}`);
      setManualImportPreview(null);
      setImportTarget(null);
      setStudentIds('');
      await onRefresh();
    } catch (exception) {
      const message = exception instanceof Error ? exception.message : 'Không thể nhập sinh viên.';
      showNotice('error', message);
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

  const prepareEventWorkbook = async (event) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setBusyAction('reading-events');
    try {
      const { events: importedEvents, warnings } = await readEventsFromWorkbook(file);
      const unitResult = await api('/api/organizer/units');
      const availableUnits = itemsOf(unitResult);
      if (!availableUnits.length) throw new Error('Không có đơn vị tổ chức được phân công cho tài khoản này.');
      const mappings = {};
      const unitWarnings = [];
      for (const organizerName of new Set(importedEvents.map((item) => item.organizerName))) {
        const matches = availableUnits.filter((unit) =>
          normalizeMatchText(unit.name) === normalizeMatchText(organizerName));
        mappings[organizerName] = matches.length === 1 ? String(matches[0].id) : '';
        if (matches.length !== 1) {
          unitWarnings.push(matches.length
            ? `Đơn vị "${organizerName}" trùng với nhiều đơn vị trong hệ thống; sự kiện của đơn vị này sẽ bị bỏ qua.`
            : `Không tìm thấy đơn vị "${organizerName}" trong các đơn vị hiện có; sự kiện của đơn vị này sẽ bị bỏ qua.`);
        }
      }
      setEventUnitMappings(mappings);
      setEventWorkbookDraft({ events: importedEvents, warnings, unitWarnings, units: availableUnits });
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể đọc file sự kiện.');
    } finally {
      setBusyAction('');
    }
  };

  const importEventWorkbook = async (event) => {
    event.preventDefault();
    if (!eventWorkbookDraft) return;
    setEventWorkbookBusy(true);
    let imported = 0;
    let alreadyExists = 0;
    const failures = [];
    const existingNames = new Set(itemsOf(data).map((item) => normalizeMatchText(item.name)));
    try {
      for (const item of eventWorkbookDraft.events) {
        if (!eventUnitMappings[item.organizerName]) {
          failures.push(`${item.name}: không tìm thấy đơn vị "${item.organizerName}" trong hệ thống.`);
          continue;
        }
        const nameKey = normalizeMatchText(item.name);
        if (existingNames.has(nameKey)) {
          alreadyExists += 1;
          continue;
        }
        try {
          const startMinutes = item.startMinutes ?? 9 * 60;
          const start = new Date(`${item.eventDate}T${String(Math.floor(startMinutes / 60)).padStart(2, '0')}:${String(startMinutes % 60).padStart(2, '0')}:00`);
          let durationMinutes = (item.endMinutes ?? startMinutes + 120) - startMinutes;
          if (durationMinutes <= 0) durationMinutes += 1440;
          const end = new Date(start.getTime() + durationMinutes * 60000);
          const result = await api('/api/organizer/events', {
            method: 'POST',
            body: {
              sourceId: item.sourceId,
              name: item.name,
              organizerId: eventUnitMappings[item.organizerName],
              startTime: start.toISOString(),
              endTime: end.toISOString(),
              location: item.location,
              capacity: 2000,
              certificateEnabled: false,
              description: item.description,
              benefits: [],
              rules: [],
              attendancePeriods: [],
              allowHistoricalImport: true,
            },
          });
          imported += 1;
          existingNames.add(nameKey);
          if (result?.message) existingNames.add(nameKey);
        } catch (exception) {
          failures.push(`${item.name}: ${exception instanceof Error ? exception.message : 'không thể tạo sự kiện.'}`);
        }
      }
      setEventWorkbookDraft(null);
      await onRefresh();
      const summary = `Đã thêm ${imported} sự kiện.${alreadyExists ? ` Đã có sẵn: ${alreadyExists}.` : ''}`
        + (failures.length ? ` Không nhập được ${failures.length}: ${failures.slice(0, 5).join(' | ')}${failures.length > 5 ? ' | ...' : ''}` : '')
        + ' Giờ mặc định 09:00, thời lượng 2 giờ nếu thiếu, sức chứa 2.000.';
      showNotice(failures.length ? 'error' : 'success', summary);
    } finally {
      setEventWorkbookBusy(false);
    }
  };

  const prepareStudentWorkbook = async (event) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    try {
      const groups = await readStudentRosterGroupsFromWorkbook(file, {
        targetIdHeaders: ['MaSuKien', 'Mã sự kiện', 'eventId', 'eventCode'],
        targetNameHeaders: ['TenSuKien', 'Tên sự kiện', 'eventName'],
      });
      const allEvents = itemsOf(data);
      const prepared = groups.map((group) => {
        let matches = allEvents.filter((item) =>
          String(item.id || '').trim().toLowerCase() === group.targetId.toLowerCase());
        if (!matches.length && group.targetName) {
          const targetName = normalizeMatchText(group.targetName);
          matches = allEvents.filter((item) => {
            const existingName = normalizeMatchText(item.name);
            return existingName === targetName;
          });
        }
        const issue = group.studentIds.length > 2000
          ? 'Vượt giới hạn 2.000 sinh viên.'
          : matches.length !== 1
            ? matches.length ? 'Có nhiều sự kiện trùng mã/tên.' : 'Chưa có sự kiện tương ứng.'
            : '';
        return { ...group, item: matches.length === 1 ? matches[0] : null, issue };
      });
      setStudentWorkbookDraft(prepared);
    } catch (exception) {
      showNotice('error', `Không thể chuẩn bị import sinh viên: ${exception instanceof Error ? exception.message : 'Không thể đọc file Excel.'}`);
    }
  };

  const importStudentWorkbook = async (event) => {
    event.preventDefault();
    if (!studentWorkbookDraft) return;
    setStudentWorkbookBusy(true);
    let imported = 0;
    let alreadyRegistered = 0;
    let unknown = 0;
    let duplicates = 0;
    const skipped = studentWorkbookDraft.filter((group) => group.issue)
      .map((group) => `${group.targetName || group.targetId}: ${group.issue}`);
    try {
      for (const group of studentWorkbookDraft) {
        if (group.issue) continue;
        try {
          const result = await api(`/api/organizer/events/${encodeURIComponent(group.item.id)}/students/import`, {
            method: 'POST',
            body: { studentIds: group.studentIds, allowHistoricalImport: true },
          });
          imported += Number(result.importedCount || 0);
          alreadyRegistered += Number(result.alreadyRegisteredCount || 0);
          unknown += result.unknownStudentIds?.length || 0;
          duplicates += group.duplicateRows;
        } catch (exception) {
          skipped.push(`${group.item.name}: ${exception instanceof Error ? exception.message : 'không thể nhập.'}`);
        }
      }
      await onRefresh();
      const summary = `Đã thêm ${imported} sinh viên; ${alreadyRegistered} đã đăng ký trước đó.`
        + (unknown ? ` Không tìm thấy ${unknown} mã sinh viên.` : '')
        + (duplicates ? ` Có ${duplicates} dòng trùng trong file.` : '')
        + (skipped.length ? ` Không nhập được ${skipped.length} danh sách: ${skipped.slice(0, 5).join(' | ')}${skipped.length > 5 ? ' | ...' : ''}` : '');
      showNotice(skipped.length ? 'error' : 'success', summary);
      setStudentWorkbookDraft(null);
    } catch (exception) {
      showNotice('error', `Không thể xác nhận dữ liệu sau khi import: ${exception instanceof Error ? exception.message : 'Không thể tải lại sự kiện.'}`);
    } finally {
      setStudentWorkbookBusy(false);
    }
  };

  const certificateEventEnded = certificateTarget && (
    certificateTarget.status === 'Đã đóng'
    || certificateTarget.status === 'Đã kết thúc'
    || new Date(certificateTarget.endTime) <= new Date()
  );
  const appPendingCertificateStudents = certificateStudents.filter((student) => student.attendanceEligible && student.certificateStatus !== 'Đã cấp');
  const emailPendingCertificateStudents = certificateStudents.filter((student) => student.attendanceEligible && student.emailStatus !== 'Đã gửi' && student.emailStatus !== 'Đang gửi');

  return <>
    <EventRegistrationFormField form={form} setForm={setForm} />
    <EventRegistrationDetails
      eventId={selected?.id}
      registrationFormUrl={details?.registrationFormUrl}
    />
    {certificateTarget && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !certificateBusy) setCertificateTarget(null); }}>
      <section className="rp-modal rp-form-modal" role="dialog" aria-modal="true">
        <header><div><h2>{'Ch\u1ee9ng nh\u1eadn s\u1ef1 ki\u1ec7n'}</h2><p>{certificateTarget.name}</p></div><button className="rp-icon-button" onClick={() => setCertificateTarget(null)} aria-label={'\u0110\u00f3ng'} disabled={Boolean(certificateBusy)}><X size={18} /></button></header>
        {certificateError && <ErrorPanel message={certificateError} />}
        {!certificateEventEnded && <div className="rp-detail-error" role="status">{'Ch\u1ec9 c\u00f3 th\u1ec3 c\u1ea5p ho\u1eb7c g\u1eedi ch\u1ee9ng nh\u1eadn sau khi s\u1ef1 ki\u1ec7n k\u1ebft th\u00fac ho\u1eb7c \u0111\u00e3 \u0111\u00f3ng.'}</div>}
        {certificateLoading ? <LoadingPanel /> : certificateStudents.length ? <>
          <p className="rp-modal-muted">{'Ch\u1ecdn sinh vi\u00ean \u0111\u00e3 \u0111i\u1ec3m danh. C\u1ea5p qua app v\u00e0 g\u1eedi qua Gmail \u0111\u01b0\u1ee3c theo d\u00f5i ri\u00eang.'}</p>
          <div className="rp-table-wrap"><table className="rp-table"><thead><tr><th>{'Ch\u1ecdn'}</th><th>{'M\u00e3 sinh vi\u00ean'}</th><th>{'H\u1ecd t\u00ean'}</th><th>{'Điểm danh'}</th><th>{'Tr\u1ea1ng th\u00e1i app'}</th><th>{'Tr\u1ea1ng th\u00e1i Gmail'}</th></tr></thead><tbody>
            {certificateStudents.map((student) => {
              const appDone = student.certificateStatus === '\u0110\u00e3 c\u1ea5p';
              const emailDone = student.emailStatus === '\u0110\u00e3 g\u1eedi';
              const emailPending = student.emailStatus === '\u0110ang g\u1eedi';
              const canSelect = certificateEventEnded && student.attendanceEligible && (!appDone || (!emailDone && !emailPending));
              const attendanceLabel = student.totalAttendanceSessions > 0 ? `${student.attendedSessions}/${student.totalAttendanceSessions} buổi · cần ${student.requiredAttendanceSessions}, vắng tối đa ${student.maxAttendanceAbsences} · ${student.attendancePercent}%` : student.attendanceEligible ? 'Đạt (dữ liệu cũ)' : 'Chưa điểm danh';
              return <tr key={student.studentId}><td><input type="checkbox" aria-label={'Ch\u1ecdn ' + student.studentName} checked={selectedCertificateStudents.has(student.studentId)} disabled={!canSelect || Boolean(certificateBusy)} onChange={(event) => setSelectedCertificateStudents((current) => { const next = new Set(current); if (event.target.checked) next.add(student.studentId); else next.delete(student.studentId); return next; })} /></td><td>{student.studentId}</td><td>{student.studentName}</td><td>{attendanceLabel} · {student.attendanceEligible ? 'Đạt' : 'Chưa đạt'}</td><td>{student.certificateStatus || 'Ch\u01b0a c\u1ea5p'}</td><td>{student.emailStatus || 'Ch\u01b0a g\u1eedi'}</td></tr>;
            })}
          </tbody></table></div>
        </> : !certificateError && <EmptyPanel title={'Ch\u01b0a c\u00f3 sinh vi\u00ean c\u1ea7n x\u1eed l\u00fd'} message={'Ch\u1ec9 sinh vi\u00ean \u0111\u00e3 \u0111i\u1ec3m danh s\u1ef1 ki\u1ec7n m\u1edbi \u0111\u1ee7 \u0111i\u1ec1u ki\u1ec7n.'} />}
        <footer>
          <button type="button" className="rp-secondary-button" onClick={() => setCertificateTarget(null)} disabled={Boolean(certificateBusy)}>{'\u0110\u00f3ng'}</button>
          <button type="button" className="rp-secondary-button" onClick={() => issueSelectedCertificates('app')} disabled={!certificateEventEnded || Boolean(certificateBusy) || selectedCertificateStudents.size === 0}>{certificateBusy === 'app-selected' ? '...': 'C\u1ea5p \u0111\u00e3 ch\u1ecdn qua app'}</button>
          <button type="button" className="rp-secondary-button" onClick={() => issueAllCertificates('app')} disabled={!certificateEventEnded || Boolean(certificateBusy) || appPendingCertificateStudents.length === 0}>{certificateBusy === 'app-all' ? '...': 'C\u1ea5p h\u1ebft qua app (' + appPendingCertificateStudents.length + ')'}</button>
          <button type="button" className="rp-secondary-button" onClick={() => issueSelectedCertificates('gmail')} disabled={!certificateEventEnded || Boolean(certificateBusy) || selectedCertificateStudents.size === 0}>{certificateBusy === 'gmail-selected' ? '...': 'G\u1eedi \u0111\u00e3 ch\u1ecdn qua Gmail'}</button>
          <button type="button" className="rp-secondary-button" onClick={() => issueAllCertificates('gmail')} disabled={!certificateEventEnded || Boolean(certificateBusy) || emailPendingCertificateStudents.length === 0}>{certificateBusy === 'gmail-all' ? '...': 'G\u1eedi h\u1ebft qua Gmail (' + emailPendingCertificateStudents.length + ')'}</button>
        </footer>
      </section>
    </div>}
    <PageTitle title="Quản lý sự kiện" subtitle="Sự kiện và đăng ký được đồng bộ trực tiếp từ hệ thống HUIT." onRefresh={onRefresh} loading={loading} action={<>
      {canImportExcel && <>
        <input ref={eventWorkbookInput} type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={prepareEventWorkbook} hidden />
        <input ref={studentWorkbookInput} type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={prepareStudentWorkbook} hidden />
        <button className="rp-secondary-button" onClick={() => eventWorkbookInput.current?.click()} disabled={busyAction === 'reading-events' || eventWorkbookBusy}>
          <Upload size={16} /> Thêm sự kiện Excel
        </button>
        <button className="rp-secondary-button" onClick={() => studentWorkbookInput.current?.click()} disabled={studentWorkbookBusy}>
          <Upload size={16} /> {studentWorkbookBusy ? 'Đang nhập sinh viên...' : 'Import sinh viên Excel'}
        </button>
      </>}
      {canManage && <button className="rp-secondary-button" onClick={() => openForm()}><Plus size={16} /> Tạo sự kiện</button>}
    </>} />
    {eventWorkbookDraft && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !eventWorkbookBusy) setEventWorkbookDraft(null); }}>
      <form className="rp-modal rp-form-modal" role="dialog" aria-modal="true" onSubmit={importEventWorkbook}>
        <header><div><h2>Xác nhận thêm sự kiện từ Excel</h2><p>{eventWorkbookDraft.events.filter((item) => eventUnitMappings[item.organizerName]).length} sự kiện có đơn vị khớp sẽ được thêm; {eventWorkbookDraft.events.length - eventWorkbookDraft.events.filter((item) => eventUnitMappings[item.organizerName]).length} sự kiện không khớp sẽ bị bỏ qua.</p></div><button type="button" className="rp-icon-button" onClick={() => setEventWorkbookDraft(null)} aria-label="Đóng" disabled={eventWorkbookBusy}><X size={18} /></button></header>
        {(eventWorkbookDraft.warnings.length > 0 || eventWorkbookDraft.unitWarnings.length > 0) && <div className="rp-import-warning" role="alert"><strong>{eventWorkbookDraft.warnings.length + eventWorkbookDraft.unitWarnings.length} mục sẽ bị bỏ qua</strong>{[...eventWorkbookDraft.warnings, ...eventWorkbookDraft.unitWarnings].map((warning) => <span key={warning}>{warning}</span>)}</div>}
        <div className="rp-import-preview">{eventWorkbookDraft.events.map((item) => {
          const unitId = eventUnitMappings[item.organizerName];
          const unit = eventWorkbookDraft.units?.find((candidate) => String(candidate.id) === unitId);
          return <div key={item.sourceId}><strong>{item.name}</strong><span>Mã {item.sourceId} · {item.eventDate}{item.startMinutes !== null ? ` · ${String(Math.floor(item.startMinutes / 60)).padStart(2, '0')}:${String(item.startMinutes % 60).padStart(2, '0')}` : ''} · {item.location}</span><span>{unit ? `Đơn vị trong hệ thống: ${unit.name}` : `Đơn vị từ file: ${item.organizerName} · sẽ bỏ qua vì chưa khớp`}</span></div>;
        })}</div>
        <footer><button type="button" className="rp-secondary-button" onClick={() => setEventWorkbookDraft(null)} disabled={eventWorkbookBusy}>Hủy</button><button className="rp-secondary-button" disabled={eventWorkbookBusy || !eventWorkbookDraft.events.some((item) => eventUnitMappings[item.organizerName])}>{eventWorkbookBusy ? 'Đang nhập...' : 'Xác nhận thêm sự kiện'}</button></footer>
      </form>
    </div>}
    {studentWorkbookDraft && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !studentWorkbookBusy) setStudentWorkbookDraft(null); }}>
      <form className="rp-modal rp-form-modal" role="dialog" aria-modal="true" onSubmit={importStudentWorkbook}>
        <header><div><h2>Xác nhận import sinh viên</h2><p>{studentWorkbookDraft.length} danh sách · {studentWorkbookDraft.reduce((total, group) => total + group.studentIds.length, 0)} mã sinh viên được đọc từ file.</p></div><button type="button" className="rp-icon-button" onClick={() => setStudentWorkbookDraft(null)} aria-label="Đóng" disabled={studentWorkbookBusy}><X size={18} /></button></header>
        {!studentWorkbookDraft.some((group) => !group.issue) && <div className="rp-import-warning" role="alert"><strong>Chưa thể nhập sinh viên</strong><span>Không có danh sách nào khớp với sự kiện hiện có. Hãy nhập sự kiện trước hoặc kiểm tra mã sự kiện trong file.</span></div>}
        <div className="rp-import-preview">{studentWorkbookDraft.map((group) => <div key={group.targetId}><strong>{group.item?.name || group.targetName || group.targetId} · {group.targetId}</strong><span>{group.studentIds.length} sinh viên{group.duplicateRows ? `, ${group.duplicateRows} dòng trùng` : ''}{group.issue ? ` · Bỏ qua: ${group.issue}` : ''}</span><code>{group.studentIds.join(', ')}</code></div>)}</div>
        <footer><button type="button" className="rp-secondary-button" onClick={() => setStudentWorkbookDraft(null)} disabled={studentWorkbookBusy}>Hủy</button><button className="rp-secondary-button" disabled={studentWorkbookBusy || !studentWorkbookDraft.some((group) => !group.issue)}>{studentWorkbookBusy ? 'Đang import...' : 'Xác nhận import'}</button></footer>
      </form>
    </div>}
    <div className="rp-event-tabs" role="group" aria-label="Lọc sự kiện">
      <button type="button" className={!showClosedEvents ? 'active' : ''} onClick={() => { setShowClosedEvents(false); setSelectedClosedEventIds(new Set()); }}>Sự kiện đang mở</button>
      <button type="button" className={showClosedEvents ? 'active' : ''} onClick={() => { setShowClosedEvents(true); setSelectedClosedEventIds(new Set()); }}>Sự kiện đã đóng</button>
    </div>
    {showClosedEvents && canManage && events.length > 0 && <div className="rp-event-bulk-actions">
      <button type="button" className="rp-secondary-button" onClick={() => setSelectedClosedEventIds(selectedClosedEventIds.size === events.length ? new Set() : new Set(events.map((item) => String(item.id))))}>{selectedClosedEventIds.size === events.length ? 'Bỏ chọn tất cả' : 'Chọn tất cả'}</button>
      <button type="button" className="rp-secondary-button" onClick={deleteSelectedClosedEvents} disabled={!selectedClosedEventIds.size || busyAction === 'delete-selected'}><Trash2 size={15} /> {busyAction === 'delete-selected' ? 'Đang xóa...' : `Xóa đã chọn (${selectedClosedEventIds.size})`}</button>
    </div>}
    <SearchBox value={query} onChange={setQuery} placeholder="Tìm tên sự kiện, địa điểm, trạng thái..." />
    {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : events.length ? <div className="rp-event-grid">{events.map((item) => {
      const eventEnded = item.displayStatus === 'Đã đóng' || item.displayStatus === 'Đã kết thúc';
      const statusClass = item.displayStatus === 'Sắp diễn ra' ? 'rp-event-status-new' : item.displayStatus === 'Đang diễn ra' ? 'rp-event-status-live' : 'rp-event-status-ended';
      return <article className="rp-card rp-event-card" key={item.id}>
        {showClosedEvents && canManage && <label className="rp-event-select"><input type="checkbox" checked={selectedClosedEventIds.has(String(item.id))} onChange={(event) => setSelectedClosedEventIds((current) => { const next = new Set(current); event.target.checked ? next.add(String(item.id)) : next.delete(String(item.id)); return next; })} /> Chọn</label>}
        <button className="rp-event-open" onClick={() => openDetails(item)}><div className="rp-event-top"><span className={`rp-tag ${statusClass}`}>{item.displayStatus}</span><span className="rp-event-id">{item.id}</span></div><h2>{item.name || 'Sự kiện HUIT'}</h2><div className="rp-event-detail"><Award size={15} />{Number(item.certificateEnabled) === 1 || item.certificateEnabled === true ? 'Có cấp chứng nhận' : 'Không cấp chứng nhận'}</div><div className="rp-event-detail"><CalendarDays size={15} />{formatDate(item.startTime)}</div><div className="rp-event-detail"><Building2 size={15} />{item.location || 'Chưa cập nhật địa điểm'}</div><div className="rp-event-progress"><span>Đăng ký</span><strong>{item.registeredCount ?? 0}{item.capacity ? ` / ${item.capacity}` : ''}</strong></div><div className="rp-progress-track"><i style={{ width: `${item.capacity ? Math.min(100, Number(item.registeredCount || 0) * 100 / item.capacity) : 0}%` }} /></div>        </button>{canManage && <div className="rp-inline-actions">{!eventEnded && <button className="rp-secondary-button" onClick={() => openForm(item)} disabled={Number(item.registeredCount) > 0} title={Number(item.registeredCount) > 0 ? 'Không thể chỉnh sửa vì đã có sinh viên đăng ký.' : 'Chỉnh sửa sự kiện'}><Pencil size={15} /> Chỉnh sửa</button>}{canImportExcel && <button className="rp-secondary-button" onClick={() => { setImportTarget(item); setStudentIds(''); }} disabled={eventEnded} title={eventEnded ? 'Không thể nhập sinh viên vào sự kiện đã đóng hoặc kết thúc.' : 'Nhập danh sách sinh viên đăng ký'}><Upload size={15} /> Nhập SV</button>}{(Number(item.certificateEnabled) === 1 || item.certificateEnabled === true) && <button className="rp-secondary-button" onClick={() => runEventAction(item, 'certificates')} disabled={busyAction === `${item.id}:certificates`}><Award size={15} /> Chứng nhận</button>}{!showClosedEvents && item.displayStatus !== 'Đã đóng' && <button className="rp-secondary-button" onClick={() => runEventAction(item, 'close')}><ShieldCheck size={15} /> Đóng</button>}{showClosedEvents && <button className="rp-icon-button" aria-label="Xóa sự kiện" title="Xóa sự kiện" onClick={() => runEventAction(item, 'delete')}><Trash2 size={15} /></button>}</div>}</article>;
    })}</div> : <EmptyPanel title={showClosedEvents ? 'Chưa có sự kiện đã đóng' : 'Chưa có sự kiện'} message="Không tìm thấy sự kiện phù hợp." />}
    {form && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !saving) setForm(null); }}>
      <form className="rp-modal rp-form-modal" role="dialog" aria-modal="true" onSubmit={saveEvent}>
        <header><div><h2>{form.id ? 'Chỉnh sửa sự kiện' : 'Tạo sự kiện'}</h2><p>{form.id || 'Nhập thông tin hoạt động.'}</p></div><button type="button" className="rp-icon-button" onClick={() => setForm(null)} aria-label="Đóng"><X size={18} /></button></header>
        {formError && <ErrorPanel message={formError} />}
        <div className="rp-form-grid">
          <label>Tên sự kiện<input required value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} /></label>
          <label>Đơn vị tổ chức<select required value={form.organizerId} onChange={(event) => setForm({ ...form, organizerId: event.target.value })}><option value="">Chọn đơn vị</option>{units.map((unit) => <option key={unit.id} value={unit.id}>{unit.name}</option>)}</select></label>
          <label>Bắt đầu<input type="datetime-local" required value={form.startTime} onChange={(event) => setForm({ ...form, startTime: event.target.value })} /></label>
          <label>Kết thúc<input type="datetime-local" required value={form.endTime} onChange={(event) => setForm({ ...form, endTime: event.target.value })} /></label>
          <label>Địa điểm<input required value={form.location} onChange={(event) => setForm({ ...form, location: event.target.value })} /></label>
          <label>Sức chứa<input type="number" min="1" required value={form.capacity} onChange={(event) => setForm({ ...form, capacity: event.target.value })} /></label>
          <label className="rp-form-wide rp-checkbox-field"><input type="checkbox" checked={form.certificateEnabled === true} onChange={(event) => setForm({ ...form, certificateEnabled: event.target.checked })} /><span>Cấp chứng nhận cho người tham dự</span><small>Chỉ bật nếu sự kiện này sẽ phát hành giấy chứng nhận.</small></label>
          {form.certificateEnabled && <label className="rp-form-wide">Điều kiện điểm danh để đạt chứng nhận
            <select
              value={eventAttendanceThresholdOptions(form.periods.length).includes(Number(form.attendanceThresholdPercent))
                ? Number(form.attendanceThresholdPercent)
                : 100}
              onChange={(event) => setForm({ ...form, attendanceThresholdPercent: Number(event.target.value) })}
            >
              {eventAttendanceThresholdOptions(form.periods.length).map((threshold) => <option key={threshold} value={threshold}>{threshold}%</option>)}
            </select>
            <small>Các mức được tính theo số khung điểm danh đã tạo.</small>
          </label>}
          <label className="rp-form-wide">Chọn ảnh từ máy<input key={imageInputVersion} type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => { const imageFile = event.target.files?.[0] || null; setForm({ ...form, imageFile, ...(imageFile ? { imageUrl: '' } : {}) }); }} /><small className="rp-image-help">JPEG, PNG hoặc WebP, tối đa 5 MB. Ảnh sẽ tải lên khi lưu sự kiện.</small></label>
          <label className="rp-form-wide">Hoặc dùng URL ảnh<input type="url" maxLength="1000" value={form.imageUrl} onChange={(event) => { if (form.imageFile) setImageInputVersion((version) => version + 1); setForm({ ...form, imageUrl: event.target.value, imageFile: null }); }} placeholder="https://..." /><small className="rp-image-help">Để trống cả hai trường để tự chọn ảnh theo chủ đề sự kiện.</small>{(imagePreview || form.imageUrl) && <img key={imagePreview || form.imageUrl} className="rp-event-image-preview" src={imagePreview || form.imageUrl} alt="Xem trước ảnh sự kiện" onError={(event) => { event.currentTarget.hidden = true; }} />}</label>
          <label className="rp-form-wide">Mô tả<textarea rows="3" value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })} /></label>
          <section className="rp-form-wide rp-editor-section">
            <div className="rp-editor-heading"><strong>Quyền lợi</strong><button type="button" className="rp-secondary-button" onClick={() => setForm({ ...form, benefits: [...form.benefits, { type: 'Khác', points: '0', content: '' }] })} disabled={form.benefits.length >= 20}><Plus size={15} /> Thêm quyền lợi</button></div>
            {form.benefits.map((benefit, index) => <div className="rp-editor-row rp-benefit-row" key={`benefit-${index}`}><select aria-label={`Loại quyền lợi ${index + 1}`} value={benefit.type} onChange={(event) => setForm({ ...form, benefits: form.benefits.map((item, itemIndex) => itemIndex === index ? { ...item, type: event.target.value } : item) })}>{['Điểm rèn luyện', 'Điểm công tác xã hội', 'Chứng nhận', 'Khác'].map((type) => <option key={type} value={type}>{type}</option>)}</select><input aria-label={`Số điểm quyền lợi ${index + 1}`} type="number" min="0" step="1" required value={benefit.points} onChange={(event) => setForm({ ...form, benefits: form.benefits.map((item, itemIndex) => itemIndex === index ? { ...item, points: event.target.value } : item) })} placeholder="Số điểm" /><input aria-label={`Nội dung quyền lợi ${index + 1}`} maxLength="500" required value={benefit.content} onChange={(event) => setForm({ ...form, benefits: form.benefits.map((item, itemIndex) => itemIndex === index ? { ...item, content: event.target.value } : item) })} placeholder="Nội dung quyền lợi" /><button type="button" className="rp-icon-button" aria-label={`Xóa quyền lợi ${index + 1}`} onClick={() => setForm({ ...form, benefits: form.benefits.filter((_, itemIndex) => itemIndex !== index) })}><Trash2 size={15} /></button></div>)}
          </section>
          <label className="rp-form-wide">Nội quy<textarea rows="3" value={form.rules} onChange={(event) => setForm({ ...form, rules: event.target.value })} placeholder="Mỗi dòng một nội quy" /></label>
          <section className="rp-form-wide rp-editor-section">
            <div className="rp-editor-heading"><strong>Khung giờ điểm danh</strong><button type="button" className="rp-secondary-button" onClick={() => setForm({ ...form, periods: [...form.periods, { name: `Đợt ${form.periods.length + 1}`, startTime: form.startTime, endTime: form.endTime }], attendanceThresholdPercent: 100 })} disabled={form.periods.length >= 12}><Plus size={15} /> Thêm khung giờ</button></div>
            <small>Chọn ngày giờ trên lịch; để trống danh sách nếu điểm danh trong toàn bộ thời gian sự kiện.</small>
            {form.periods.map((period, index) => <div className="rp-editor-row rp-period-row" key={`period-${index}`}><input aria-label={`Tên khung điểm danh ${index + 1}`} required maxLength="60" value={period.name} onChange={(event) => setForm({ ...form, periods: form.periods.map((item, itemIndex) => itemIndex === index ? { ...item, name: event.target.value } : item) })} placeholder="Tên khung, ví dụ: Đợt 1" /><label>Bắt đầu<input aria-label={`Bắt đầu khung ${index + 1}`} type="datetime-local" required value={period.startTime} onChange={(event) => setForm({ ...form, periods: form.periods.map((item, itemIndex) => itemIndex === index ? { ...item, startTime: event.target.value } : item) })} /></label><label>Kết thúc<input aria-label={`Kết thúc khung ${index + 1}`} type="datetime-local" required value={period.endTime} onChange={(event) => setForm({ ...form, periods: form.periods.map((item, itemIndex) => itemIndex === index ? { ...item, endTime: event.target.value } : item) })} /></label><button type="button" className="rp-icon-button" aria-label={`Xóa khung điểm danh ${index + 1}`} onClick={() => setForm({ ...form, periods: form.periods.filter((_, itemIndex) => itemIndex !== index), attendanceThresholdPercent: 100 })}><Trash2 size={15} /></button></div>)}
          </section>
        </div>
        <footer><button type="button" className="rp-secondary-button" onClick={() => setForm(null)} disabled={saving}>Hủy</button><button className="rp-secondary-button" disabled={saving}>{saving ? 'Đang lưu...' : form.id ? 'Lưu thay đổi' : 'Tạo sự kiện'}</button></footer>
      </form>
    </div>}
    {importTarget && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !busyAction) setImportTarget(null); }}><form className="rp-modal rp-form-modal" role="dialog" aria-modal="true" onSubmit={importStudents}><header><div><h2>Nhập sinh viên đăng ký</h2><p>{importTarget.name}</p></div><button type="button" className="rp-icon-button" onClick={() => setImportTarget(null)} aria-label="Đóng"><X size={18} /></button></header><label>Chọn file Excel (.xlsx)<input type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={readEventStudentWorkbook} disabled={Boolean(busyAction)} />{busyAction === 'reading-import' && <small role="status">Đang đọc file Excel...</small>}</label><label>Mã sinh viên<textarea rows="7" required value={studentIds} onChange={(event) => setStudentIds(event.target.value)} placeholder="Mỗi dòng một mã sinh viên; có thể phân tách bằng dấu phẩy hoặc dấu chấm phẩy." /></label><footer><button type="button" className="rp-secondary-button" onClick={() => setImportTarget(null)} disabled={busyAction === 'import'}>Hủy</button><button className="rp-secondary-button" disabled={busyAction === 'import'}>{busyAction === 'import' ? 'Đang nhập...' : 'Nhập sinh viên'}</button></footer></form></div>}
    {importTarget && manualImportPreview && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && busyAction !== 'import') setManualImportPreview(null); }}><section className="rp-modal rp-form-modal" role="dialog" aria-modal="true"><header><div><h2>Xác nhận import sinh viên</h2><p>{importTarget.name} · {manualImportPreview.length} mã sinh viên.</p></div><button type="button" className="rp-icon-button" onClick={() => setManualImportPreview(null)} aria-label="Đóng" disabled={busyAction === 'import'}><X size={18} /></button></header><div className="rp-import-preview"><div><strong>Danh sách mã sinh viên</strong><code>{manualImportPreview.join(', ')}</code></div></div><footer><button type="button" className="rp-secondary-button" onClick={() => setManualImportPreview(null)} disabled={busyAction === 'import'}>Hủy</button><button type="button" className="rp-secondary-button" onClick={confirmManualImport} disabled={busyAction === 'import'}>{busyAction === 'import' ? 'Đang nhập...' : 'Xác nhận import'}</button></footer></section></div>}
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
  const [selectedSubjectId, setSelectedSubjectId] = useState('');
  const [manualAttendancePage, setManualAttendancePage] = useState(false);
  const [attendanceExportMode, setAttendanceExportMode] = useState(false);
  const [exportingSessionId, setExportingSessionId] = useState('');
  const [roster, setRoster] = useState(null);
  const [rosterLoading, setRosterLoading] = useState(false);
  const [rosterError, setRosterError] = useState('');
  const [pendingAttendanceStatuses, setPendingAttendanceStatuses] = useState(new Map());
  const [bulkSaving, setBulkSaving] = useState(false);
  const lecturerOrAdmin = isLecturerRole(role) || isAdminRole(role);
  const items = itemsOf(data).map((item) => ({
    ...item,
    classLabel: item.className
      ? `${item.className} · ${item.classId}`
      : item.classId || '',
  })).filter((item) => JSON.stringify(item).toLowerCase().includes(query.trim().toLowerCase()));
  const subjectKeyOf = (item) => String(item.subjectId || item.classId || 'unknown');
  const subjects = [...new Map(items.map((item) => [subjectKeyOf(item), {
    id: subjectKeyOf(item),
    name: item.subjectName || item.className || item.classId || 'Môn học',
    code: item.subjectId || item.classId || '',
    className: item.className || '',
    sessions: items.filter((candidate) => subjectKeyOf(candidate) === subjectKeyOf(item)),
  }])).values()];
  const subjectSessions = items.filter((item) => subjectKeyOf(item) === selectedSubjectId);
  const stats = lecturerOrAdmin
    ? [['Có mặt', sum(items, 'present')], ['Đi trễ', sum(items, 'late')], ['Vắng mặt', sum(items, 'absent')]]
    : [['Đăng ký', sum(items, 'registeredCount')], ['Đã tham dự', sum(items, 'checkedInCount')], ['Vắng mặt', sum(items, 'absentCount')]];

  const openRoster = async (session) => {
    setPendingAttendanceStatuses(new Map());
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

  const applyBulkAttendanceStatus = async () => {
    const records = [...pendingAttendanceStatuses].map(([studentId, status]) => ({ studentId, status }));
    if (!selected || !roster?.session?.canEdit || !records.length || bulkSaving) return;
    setBulkSaving(true);
    setRosterError('');
    try {
      const bulkEndpoint = `/api/admin/attendance/sessions/${encodeURIComponent(selected.id)}/students/bulk-update`;
      try {
        await api(bulkEndpoint, { method: 'POST', body: { records } });
      } catch (exception) {
        // Older deployed backends route "bulk-update" through :studentId. Fall back
        // to the existing single-student API until the bulk route is deployed there.
        const bulkRouteUnavailable = exception?.status === 400
          && exception.message === 'Trạng thái điểm danh không hợp lệ.';
        if (!bulkRouteUnavailable) throw exception;
        const studentEndpoint = `/api/admin/attendance/sessions/${encodeURIComponent(selected.id)}/students`;
        for (let offset = 0; offset < records.length; offset += 10) {
          const chunk = records.slice(offset, offset + 10);
          await Promise.all(chunk.map(({ studentId, status }) => api(
            `${studentEndpoint}/${encodeURIComponent(studentId)}`,
            { method: 'POST', body: { status } },
          )));
        }
      }
      setPendingAttendanceStatuses(new Map());
      await openRoster(selected);
      onRefresh();
    } catch (exception) {
      setRosterError(exception instanceof Error ? exception.message : 'Không thể cập nhật điểm danh cho các sinh viên đã chọn.');
    } finally {
      setBulkSaving(false);
    }
  };

  const exportAttendanceSession = async (session) => {
    if (exportingSessionId) return;
    setExportingSessionId(String(session.id));
    setRosterError('');
    try {
      const rosterData = await api(`/api/admin/attendance/sessions/${encodeURIComponent(session.id)}/students`);
      const rosterStudents = itemsOf(rosterData);
      const cell = (value, style = {}) => ({ value, ...style });
      const titleStyle = { fontWeight: 'bold', fontSize: 17, textColor: '#FFFFFF', backgroundColor: '#174B8A', align: 'center', height: 30 };
      const metaStyle = { backgroundColor: '#EAF2FB', textColor: '#36536F' };
      const headerStyle = { fontWeight: 'bold', textColor: '#FFFFFF', backgroundColor: '#2467A6', align: 'center', wrap: true, height: 26 };
      const rows = [
        [cell('DANH SÁCH ĐIỂM DANH', { ...titleStyle, columnSpan: 7 })],
        [cell('MÔN HỌC', { ...metaStyle, fontWeight: 'bold' }), cell(session.subjectName || '—', { ...metaStyle, columnSpan: 6 })],
        [cell('LỚP HỌC PHẦN', { ...metaStyle, fontWeight: 'bold' }), cell(session.classLabel || session.classId || '—', { ...metaStyle, columnSpan: 6 })],
        [cell('BUỔI HỌC', { ...metaStyle, fontWeight: 'bold' }), cell(session.sessionName || 'Buổi học', { ...metaStyle, columnSpan: 6 })],
        [],
        ['STT', 'Mã sinh viên', 'Họ và tên', 'Trạng thái', 'Có phép', 'Không phép', 'Cập nhật lúc'].map((value) => cell(value, headerStyle)),
        ...rosterStudents.map((student, index) => {
          const status = student.attendanceStatus || 'Chưa ghi nhận';
          const stripe = index % 2 ? '#F4F8FC' : '#FFFFFF';
          return [
            cell(index + 1, { backgroundColor: stripe, align: 'center' }),
            cell(student.studentId || '', { backgroundColor: stripe }),
            cell(student.studentName || '', { backgroundColor: stripe }),
            cell(status, { backgroundColor: stripe }),
            cell(status === 'Vắng có phép' ? '✓' : '', { backgroundColor: status === 'Vắng có phép' ? '#EAF0FF' : stripe, align: 'center' }),
            cell(status === 'Vắng mặt' ? '✓' : '', { backgroundColor: status === 'Vắng mặt' ? '#FCE8E7' : stripe, align: 'center' }),
            cell(student.checkedInAt ? formatDate(student.checkedInAt) : '', { backgroundColor: stripe }),
          ];
        }),
      ];
      const { default: writeExcelFile } = await import('write-excel-file/universal');
      const workbook = await writeExcelFile(rows, {
        sheet: 'Điểm danh',
        columns: [{ width: 8 }, { width: 20 }, { width: 30 }, { width: 20 }, { width: 14 }, { width: 16 }, { width: 22 }],
      });
      const url = URL.createObjectURL(await workbook.toBlob());
      const link = document.createElement('a');
      link.href = url;
      const safeName = (value) => String(value || '').replace(/[^A-Za-z0-9._-]+/g, '_');
      link.download = `diem_danh_${safeName(session.subjectId || session.subjectName)}_${safeName(session.classId)}_${safeName(session.sessionName || session.id)}.xlsx`;
      link.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (exception) {
      setRosterError(exception instanceof Error ? exception.message : 'Không thể tải file Excel điểm danh.');
    } finally {
      setExportingSessionId('');
    }
  };

  if (manualAttendancePage || attendanceExportMode) {
    const manualOptions = [
      ['present', 'Có mặt'],
      ['late', 'Đi muộn'],
      ['excused', 'Có phép'],
      ['absent', 'Không phép'],
    ];
    const students = itemsOf(roster);
    return <main className="rp-manual-attendance-page">
      <div className="rp-manual-page-heading">
        <button type="button" className="rp-secondary-button" onClick={() => {
          if (selected) { setSelected(null); setRoster(null); setRosterError(''); }
          else if (selectedSubjectId) setSelectedSubjectId('');
          else { setManualAttendancePage(false); setAttendanceExportMode(false); setRosterError(''); }
        }}><ChevronLeft size={17} /> {selected ? 'Chọn buổi khác' : selectedSubjectId ? 'Chọn môn khác' : 'Quay lại điểm danh'}</button>
        <div><span className="rp-detail-eyebrow">GIẢNG VIÊN · ĐIỂM DANH</span><h1>{attendanceExportMode ? selectedSubjectId ? 'Chọn buổi để tải Excel' : 'Tải Excel điểm danh' : selected ? 'Điểm danh sinh viên' : selectedSubjectId ? 'Chọn buổi học' : 'Điểm danh thủ công'}</h1><p>{attendanceExportMode ? selectedSubjectId ? `Môn học: ${subjects.find((subject) => subject.id === selectedSubjectId)?.name || 'Môn học'} · Chọn buổi học để tải danh sách điểm danh.` : 'Chọn môn học trước, sau đó chọn buổi cần tải danh sách điểm danh.' : selected ? `${selected.classLabel || selected.className || selected.classId} · ${selected.sessionName || 'Buổi học'}` : selectedSubjectId ? `Môn học: ${subjects.find((subject) => subject.id === selectedSubjectId)?.name || 'Môn học'} · Chọn buổi cần điểm danh.` : 'Chọn môn học trước, sau đó chọn buổi cần ghi nhận trạng thái tham dự.'}</p></div>
        {selected && <button type="button" className="rp-secondary-button" onClick={() => openRoster(selected)} disabled={rosterLoading}><RefreshCw size={16} /> Làm mới</button>}
      </div>
      {!selected ? !selectedSubjectId ? <>
        {error && <ErrorPanel message={error} onRetry={onRefresh} />}
        {attendanceExportMode && rosterError && <ErrorPanel message={rosterError} />}
        {loading ? <LoadingPanel /> : subjects.length ? <div className="rp-manual-session-grid">{subjects.map((subject) => <button key={subject.id} className="rp-manual-session-card rp-manual-subject-card" onClick={() => setSelectedSubjectId(subject.id)}><span className="rp-attendance-session-icon"><BookOpen size={20} /></span><span className="rp-manual-session-copy"><strong>{subject.name}</strong><small>{subject.code}{subject.className && subject.className !== subject.name ? ` · ${subject.className}` : ''}</small><small>{subject.sessions.length} buổi học có phiên điểm danh</small></span><ChevronRight size={18} /></button>)}</div> : <EmptyPanel title="Chưa có môn học" message="Chưa có môn học nào có phiên điểm danh để quản lý." />}
      </> : <>
        {attendanceExportMode && rosterError && <ErrorPanel message={rosterError} />}
        {subjectSessions.length ? <div className="rp-manual-session-grid">{subjectSessions.map((item) => <button key={item.id} className="rp-manual-session-card" onClick={() => attendanceExportMode ? exportAttendanceSession(item) : openRoster(item)} disabled={attendanceExportMode && Boolean(exportingSessionId)}><span className="rp-attendance-session-icon">{attendanceExportMode && exportingSessionId === String(item.id) ? <RefreshCw size={20} className="rp-spin" /> : attendanceExportMode ? <Download size={20} /> : <ClipboardCheck size={20} />}</span><span className="rp-manual-session-copy"><strong>{item.sessionName || 'Buổi học'}</strong><small>{item.classLabel}</small><small>{item.openedAt ? `Mở lúc ${formatDate(item.openedAt)}` : ''}{item.closedAt ? ` · Đóng lúc ${formatDate(item.closedAt)}` : ''}</small></span><span className="rp-manual-session-cta">{attendanceExportMode ? exportingSessionId === String(item.id) ? 'Đang tải…' : 'Tải Excel' : ''}<ChevronRight size={18} /></span></button>)}</div> : <EmptyPanel title="Chưa có buổi học" message="Môn học này chưa có phiên điểm danh." />}
      </> : <>
        {rosterError && <ErrorPanel message={rosterError} onRetry={() => openRoster(selected)} />}
        {rosterLoading ? <LoadingPanel /> : roster && <>
          <div className={`rp-manual-session-state ${roster.session?.canEdit ? 'is-open' : 'is-closed'}`}><span className="rp-state-dot" /><div><strong>{roster.session?.canEdit ? 'Đang mở · Có thể cập nhật điểm danh' : 'Phiên đã đóng · Chỉ xem kết quả'}</strong><small>{roster.session?.canEdit ? 'Tích trạng thái cho từng sinh viên, sau đó bấm Áp dụng điểm danh để lưu.' : 'Các trạng thái được khóa theo cấu hình của phiên điểm danh.'}</small></div><span className="rp-manual-student-count">{students.length} sinh viên</span></div>
          <div className="rp-manual-bulk-toolbar">
            <span className="rp-manual-selected-count">Đã đánh dấu <strong>{pendingAttendanceStatuses.size}</strong> / {students.length} sinh viên</span>
            <button type="button" className="rp-attendance-manual-button" onClick={applyBulkAttendanceStatus} disabled={!roster.session?.canEdit || !pendingAttendanceStatuses.size || bulkSaving}>{bulkSaving ? 'Đang lưu…' : `Áp dụng điểm danh (${pendingAttendanceStatuses.size})`}</button>
          </div>
          <div className="rp-manual-table-wrap"><table className="rp-manual-table"><thead><tr><th>STT</th><th>Mã sinh viên</th><th>Họ tên</th>{manualOptions.map(([value, label]) => <th className="rp-manual-status-check-column" key={value}>{label}</th>)}<th>Cập nhật lúc</th></tr></thead><tbody>{students.map((student, index) => {
            const currentStatus = statusValue(student.attendanceStatus);
            const studentId = String(student.studentId);
            const displayedStatus = pendingAttendanceStatuses.get(studentId) ?? currentStatus;
            return <tr key={student.studentId} className={pendingAttendanceStatuses.has(studentId) ? 'is-selected' : ''}>
              <td className="rp-manual-row-number">{index + 1}</td><td className="rp-manual-student-code">{student.studentId}</td><td className="rp-manual-student-name">{student.studentName || 'Sinh viên'}</td>
              {manualOptions.map(([value, label]) => <td className={`rp-manual-status-check-column is-${value}`} key={value}><input type="checkbox" aria-label={`${label}: ${student.studentName}`} checked={displayedStatus === value} disabled={!roster.session?.canEdit || bulkSaving} onChange={(event) => setPendingAttendanceStatuses((current) => {
                const next = new Map(current);
                const nextStatus = event.target.checked ? value : 'present';
                if (nextStatus === currentStatus) next.delete(studentId);
                else next.set(studentId, nextStatus);
                return next;
              })} /></td>)}
              <td className="rp-manual-student-time">{student.checkedInAt ? formatDate(student.checkedInAt) : '—'}</td>
            </tr>;
          })}</tbody></table></div>
          {!students.length && <EmptyPanel title="Chưa có sinh viên" message="Buổi học này chưa có sinh viên trong danh sách." />}
        </>}
      </>}
    </main>;
  }
  return (
    <>
      <PageTitle title="Điểm danh" subtitle={lecturerOrAdmin ? 'Phiên học và kết quả tham dự từ cơ sở dữ liệu.' : 'Tổng hợp điểm danh các sự kiện thuộc đơn vị.'} onRefresh={onRefresh} loading={loading} action={lecturerOrAdmin && <div className="rp-attendance-top-actions"><button type="button" className="rp-attendance-manual-button" onClick={() => { setSelected(null); setRoster(null); setQuery(''); setAttendanceExportMode(false); setManualAttendancePage(true); }}><ClipboardCheck size={16} /> Điểm danh thủ công</button><button type="button" className="rp-secondary-button" onClick={() => { setSelected(null); setRoster(null); setQuery(''); setSelectedSubjectId(''); setRosterError(''); setManualAttendancePage(false); setAttendanceExportMode(true); }}><Download size={16} /> Tải Excel điểm danh</button><ClassQrGenerator onCreated={onRefresh} /></div>} />
      <div className="rp-metrics-grid rp-metrics-compact">{stats.map(([label, value]) => <article className="rp-metric-card" key={label}><span className="rp-metric-icon"><ClipboardCheck size={19} /></span><div><span>{label}</span><strong>{value}</strong></div></article>)}</div>
      <SearchBox value={query} onChange={setQuery} placeholder="Tìm mã lớp, sự kiện, trạng thái..." />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : lecturerOrAdmin
        ? <DataTable items={items} columns={[[ 'Lớp', 'classLabel'], ['Buổi học', 'sessionName'], ['Mở lúc', 'openedAt'], ['Đóng lúc', 'closedAt'], ['Phương thức', 'method'], ['Có mặt', 'present'], ['Đi trễ', 'late'], ['Vắng', 'absent']]} />
        : <EventAttendanceView items={items} />}
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
      <EventRegistrationDetails
        eventId={selected?.id}
        registrationFormUrl={details?.registrationFormUrl}
      />
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
  const [allowEarlyAttendance, setAllowEarlyAttendance] = useState(false);
  const [sessionId, setSessionId] = useState('');
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
        setAllowEarlyAttendance(Boolean(result.allowEarlyAttendance));
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
        setAllowEarlyAttendance(Boolean(result.allowEarlyAttendance));
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
      setAllowEarlyAttendance(Boolean(result.allowEarlyAttendance));
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
    const selectedSession = sessions.find((session) => session.classSessionId === sessionId);
    if (selectedSession?.startTime
      && new Date(selectedSession.startTime).getTime() > Date.now()
      && !allowEarlyAttendance) {
      setError('Chưa đến giờ bắt đầu. Quản trị viên chưa cho phép mở điểm danh sớm.');
      return;
    }
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

  const selectedSession = sessions.find((session) => session.classSessionId === sessionId);
  const startsInFuture = selectedSession?.startTime
    && new Date(selectedSession.startTime).getTime() > Date.now();
  const activeSessionId = selectedSession?.activeSessionId;
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
          {loading && !sessions.length ? <LoadingPanel /> : <div className="rp-form-grid"><label className="rp-form-wide">Buổi học<select required value={sessionId} onChange={(event) => setSessionId(event.target.value)}><option value="">Chọn buổi học</option>{sessions.map((session) => <option key={session.classSessionId} value={session.classSessionId}>{session.className || session.classId} · {session.classId} · Buổi {session.classSessionId} · {formatDate(session.startTime)}{session.activeSessionId ? ' · Đang có QR' : ''}</option>)}</select></label><p className="rp-form-hint">QR có hiệu lực {sessions.find((session) => session.classSessionId === sessionId)?.qrDurationMinutes || 15} phút; phạm vi GPS {sessions.find((session) => session.classSessionId === sessionId)?.gpsRadiusMeters || 100} m theo cài đặt. Trình duyệt cần quyền vị trí và trang phải chạy qua HTTPS hoặc localhost.</p>{startsInFuture && !allowEarlyAttendance && <p className="rp-form-hint">Chưa đến giờ bắt đầu. Quản trị viên chưa cho phép mở điểm danh sớm.</p>}{activeSessionId && <><p className="rp-form-hint">Buổi học đã có mã QR hoạt động. Tắt mã đó trước khi tạo mã mới.</p><button type="button" className="rp-secondary-button" onClick={() => stopQr(activeSessionId)} disabled={loading}>Tắt mã QR đang hoạt động</button></>}</div>}
            <footer><button type="button" className="rp-secondary-button" onClick={() => setOpen(false)} disabled={loading}>Hủy</button><button className="rp-secondary-button" disabled={loading || !sessionId || Boolean(activeSessionId) || Boolean(startsInFuture && !allowEarlyAttendance)}>{loading ? 'Đang tạo...' : 'Lấy vị trí và tạo QR'}</button></footer>
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
          {report && !report.error && <><div className="rp-metrics-grid rp-metrics-compact">{totals.map(([label, value]) => <article className="rp-metric-card" key={label}><span className="rp-metric-icon"><BarChart3 size={19} /></span><div><span>{label}</span><strong>{value}</strong></div></article>)}</div><AttendanceDonutChart title="Phân bổ kết quả điểm danh" data={[{ label: 'Có mặt', value: sum(summary, 'present'), color: '#28a76c' }, { label: 'Đi muộn', value: sum(summary, 'late'), color: '#e7a639' }, { label: 'Vắng mặt', value: sum(summary, 'absent'), color: '#d95d54' }, { label: 'Vắng có phép', value: sum(summary, 'excused'), color: '#4770d8' }]} /><DataTable items={summary} columns={[['Mã sinh viên', 'studentId'], ['Họ tên', 'studentName'], ['Tổng buổi', 'totalSessions'], ['Có mặt', 'present'], ['Đi trễ', 'late'], ['Vắng', 'absent'], ['Có phép', 'excused'], ['Tỷ lệ đi học (%)', 'attendancePercent'], ['Kết quả', 'attendanceResult']]} /></>}
          {!classes.length && <EmptyPanel title="Chưa có lớp" message="Tài khoản chưa được phân công lớp học." />}
        </>
      )}
    </>
  );
}

function SearchableOptionField({ label, options, value, onChange }) {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const selected = options.find((item) => String(item.id) === String(value));
  const optionLabel = (item) => `${item.name}${item.subjectName ? ` · ${item.subjectName}` : ''}${item.startTime ? ` · ${formatDate(item.startTime)}` : ''}`;
  useEffect(() => { setQuery(selected ? optionLabel(selected) : ''); }, [value, options]);
  const normalizedQuery = query.trim().toLocaleLowerCase();
  const filtered = options.filter((item) => `${item.id} ${optionLabel(item)}`.toLocaleLowerCase().includes(normalizedQuery));

  return <label className="rp-searchable-field">{label}
    <div className="rp-searchable-select">
      <input type="search" role="combobox" aria-label={label} aria-expanded={open} aria-controls="rp-settings-options" autoComplete="off" placeholder="Tìm theo tên hoặc mã..." value={query} onFocus={() => setOpen(true)} onBlur={() => setOpen(false)} onChange={(event) => { setQuery(event.target.value); setOpen(true); if (value) onChange(''); }} />
      {open && <div className="rp-searchable-options" id="rp-settings-options" role="listbox">
        {filtered.length ? filtered.slice(0, 100).map((item) => <button type="button" role="option" aria-selected={String(item.id) === String(value)} key={item.id} onMouseDown={(event) => event.preventDefault()} onClick={() => { onChange(String(item.id)); setQuery(optionLabel(item)); setOpen(false); }}>{optionLabel(item)}</button>) : <p>Không tìm thấy kết quả.</p>}
        {filtered.length > 100 && <p>Nhập thêm từ khóa để thu hẹp {filtered.length} kết quả.</p>}
      </div>}
    </div>
  </label>;
}

function SettingsView({ darkMode, setDarkMode }) {
  const [scopeType, setScopeType] = useState('global');
  const [scopeId, setScopeId] = useState('');
  const [classes, setClasses] = useState([]);
  const [events, setEvents] = useState([]);
  const [allowEarlyAttendance, setAllowEarlyAttendance] = useState(false);
  const [parameters, setParameters] = useState({ gpsRadiusMeters: '100', eventRegistrationLockHours: '0', qrDurationMinutes: '15' });
  const [inherit, setInherit] = useState({ gpsRadiusMeters: false, eventRegistrationLockHours: false, qrDurationMinutes: false });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [savingEarlyAttendance, setSavingEarlyAttendance] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const isSpecificScope = (type) => type === 'class' || type === 'event';
  const isClassScope = (type) => type === 'class' || type === 'all_classes';

  const loadParameters = async (type = scopeType, id = scopeId) => {
    if (isSpecificScope(type) && !id) {
      setLoading(false);
      return;
    }
    setLoading(true);
    setError('');
    try {
      const query = isSpecificScope(type)
        ? `?scopeType=${type}&scopeId=${encodeURIComponent(id)}`
        : `?scopeType=${type}`;
      const result = await api(`/api/admin/settings/parameters${query}`);
      setAllowEarlyAttendance(Boolean(result.global?.allowEarlyAttendance));
      const keys = ['gpsRadiusMeters', 'eventRegistrationLockHours', 'qrDurationMinutes'];
      const nextParameters = {};
      const nextInherit = {};
      keys.forEach((key) => {
        const inherited = type !== 'global' && result.overrides?.[key] == null;
        nextInherit[key] = inherited;
        nextParameters[key] = String(result.overrides?.[key] ?? result.effective?.[key] ?? '');
      });
      setParameters(nextParameters);
      setInherit(nextInherit);
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể tải tham số.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    let active = true;
    setLoading(true);
    api('/api/admin/settings/parameters/options').then((result) => {
      if (!active) return;
      setClasses(itemsOf({ items: result.classes }));
      setEvents(itemsOf({ items: result.events }));
      return loadParameters('global', '');
    }).catch((exception) => {
      if (active) {
        setError(exception instanceof Error ? exception.message : 'Không thể tải danh sách lớp và sự kiện.');
        setLoading(false);
      }
    });
    return () => { active = false; };
  }, []);

  const changeScopeType = (event) => {
    const nextType = event.target.value;
    const options = nextType === 'class' ? classes : nextType === 'event' ? events : [];
    const nextId = isSpecificScope(nextType) ? String(options[0]?.id || '') : '';
    setScopeType(nextType);
    setScopeId(nextId);
    loadParameters(nextType, nextId);
  };

  const saveParameters = async () => {
    setSaving(true);
    setError('');
    setNotice('');
    try {
      const asNumber = (key) => parameters[key].trim() === '' ? null : Number(parameters[key]);
      await api('/api/admin/settings/parameters', {
        method: 'PUT',
        body: {
          scopeType,
          ...(isSpecificScope(scopeType) ? { scopeId } : {}),
          gpsRadiusMeters: scopeType !== 'global' && inherit.gpsRadiusMeters ? null : asNumber('gpsRadiusMeters'),
          eventRegistrationLockHours: isClassScope(scopeType)
            ? null
            : scopeType !== 'global' && inherit.eventRegistrationLockHours
              ? null
              : asNumber('eventRegistrationLockHours'),
          qrDurationMinutes: scopeType !== 'global' && inherit.qrDurationMinutes ? null : asNumber('qrDurationMinutes'),
        },
      });
      await loadParameters(scopeType, scopeId);
      setNotice('Đã lưu tham số cấu hình.');
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể lưu tham số.');
    } finally {
      setSaving(false);
    }
  };

  const updateEarlyAttendance = async (enabled) => {
    setSavingEarlyAttendance(true);
    setError('');
    setNotice('');
    try {
      const result = await api('/api/admin/settings/early-attendance', {
        method: 'PUT',
        body: { allowEarlyAttendance: enabled },
      });
      setAllowEarlyAttendance(Boolean(result.allowEarlyAttendance));
      setNotice(enabled
        ? 'Đã cho phép mở phiên và điểm danh sự kiện trước giờ bắt đầu trên toàn hệ thống.'
        : 'Đã tắt quyền mở phiên và điểm danh sự kiện trước giờ bắt đầu.');
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể lưu cài đặt mở điểm danh sớm.');
    } finally {
      setSavingEarlyAttendance(false);
    }
  };

  const updateParameter = (key, value) => setParameters((current) => ({ ...current, [key]: value }));
  const toggleInheritance = (key, value) => setInherit((current) => ({ ...current, [key]: value }));
  const parameterField = (key, label, unit, min, max) => (
    <div className="rp-parameter-field" key={key}>
      <label htmlFor={`rp-parameter-${key}`}>{label}</label>
      <div><input id={`rp-parameter-${key}`} type="number" min={min} max={max} step="1" value={parameters[key]} disabled={scopeType !== 'global' && inherit[key]} onChange={(event) => updateParameter(key, event.target.value)} /><small>{unit}</small></div>
      {scopeType !== 'global' && <label className="rp-parameter-inherit"><input type="checkbox" checked={Boolean(inherit[key])} onChange={(event) => toggleInheritance(key, event.target.checked)} /> Dùng tham số từ phạm vi rộng hơn</label>}
      <small className="rp-parameter-range">Giới hạn: {min}–{max} {unit}</small>
    </div>
  );
  const selectedOptions = scopeType === 'class' ? classes : scopeType === 'event' ? events : [];

  return <>
    <PageTitle title="Cài đặt" subtitle="Tùy chỉnh giao diện và các tham số vận hành." />
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
    <section className="rp-card rp-parameter-card">
      <header><div><h2>Tham số hệ thống</h2><p>Cấu hình toàn hệ thống, cho toàn bộ lớp/sự kiện hoặc ghi đè riêng cho một đối tượng.</p></div><Settings size={19} /></header>
      {error && <ErrorPanel message={error} />}
      {notice && <p className="rp-parameter-notice">{notice}</p>}
      <div className="rp-form-grid">
        <label>Phạm vi cài đặt<select value={scopeType} onChange={changeScopeType}><option value="global">Toàn hệ thống</option><option value="all_classes">Toàn bộ lớp học phần</option><option value="class">Một lớp học phần</option><option value="all_events">Toàn bộ sự kiện</option><option value="event">Một sự kiện</option></select></label>
        {isSpecificScope(scopeType) && <SearchableOptionField label={scopeType === 'class' ? 'Lớp học phần' : 'Sự kiện'} options={selectedOptions} value={scopeId} onChange={(id) => { setScopeId(id); loadParameters(scopeType, id); }} />}
      </div>
      {loading ? <LoadingPanel /> : <>
        <div className="rp-form-grid">
          <label className="rp-form-wide rp-checkbox-field">
            <input
              type="checkbox"
              checked={allowEarlyAttendance}
              disabled={savingEarlyAttendance}
              onChange={(event) => updateEarlyAttendance(event.target.checked)}
            />
            <span>Cho phép mở phiên và điểm danh sự kiện trước giờ bắt đầu</span>
            <small>Cho phép ban tổ chức mở phiên sớm và sinh viên điểm danh sự kiện trước giờ bắt đầu. Áp dụng toàn hệ thống; phù hợp khi demo.{savingEarlyAttendance ? ' Đang lưu...' : ''}</small>
          </label>
        </div>
        <div className="rp-parameter-grid">
          {parameterField('gpsRadiusMeters', 'GPS điểm danh', 'mét', 10, 5000)}
          {!isClassScope(scopeType) && parameterField('eventRegistrationLockHours', 'Khóa đăng ký trước khi sự kiện bắt đầu', 'giờ', 0, 720)}
          {parameterField('qrDurationMinutes', 'Thời gian QR có hiệu lực', 'phút', 1, 180)}
        </div>
        <p className="rp-parameter-help">Có mặt và đi trễ được tính là tham dự; buổi vắng có phép vẫn tính là vắng.</p>
        <div className="rp-parameter-footer"><span>Tham số riêng có thể kế thừa giá trị từ phạm vi rộng hơn.</span><button className="rp-secondary-button" onClick={saveParameters} disabled={saving || (isSpecificScope(scopeType) && !scopeId)}>{saving ? 'Đang lưu...' : 'Lưu tham số'}</button></div>
      </>}
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

function CertificateSignatureDialog({ onClose, showNotice }) {
  const [signatures, setSignatures] = useState({
    dean: { imageData: '', name: '' },
    organizer: { imageData: '', name: '' },
  });
  const [savedSignatures, setSavedSignatures] = useState({
    dean: { imageData: '', name: '' },
    organizer: { imageData: '', name: '' },
  });
  const [previewUrl, setPreviewUrl] = useState('');
  const [previewError, setPreviewError] = useState('');
  const [loading, setLoading] = useState(true);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const previewUrlRef = useRef('');

  const replacePreview = (blob) => {
    const nextUrl = URL.createObjectURL(blob);
    if (previewUrlRef.current) URL.revokeObjectURL(previewUrlRef.current);
    previewUrlRef.current = nextUrl;
    setPreviewUrl(nextUrl);
  };

  const refreshPreview = async () => {
    setPreviewLoading(true);
    setPreviewError('');
    try {
      const blob = await api('/api/staff/certificates/template/preview', { responseType: 'blob' });
      replacePreview(blob);
    } catch (exception) {
      const message = exception instanceof Error ? exception.message : 'Không thể xem mẫu chứng nhận.';
      setPreviewError(message);
      showNotice('error', message);
    } finally {
      setPreviewLoading(false);
    }
  };

  useEffect(() => {
    let active = true;
    const load = async () => {
      try {
        const [settings, blob] = await Promise.all([
          api('/api/staff/certificate-signature'),
          api('/api/staff/certificates/template/preview', { responseType: 'blob' }),
        ]);
        if (!active) return;
        const saved = {
          dean: {
            imageData: settings.signatureData || '',
            name: settings.signatureName || '',
          },
          organizer: {
            imageData: settings.organizerSignatureData || '',
            name: settings.organizerSignatureName || '',
          },
        };
        setSavedSignatures(saved);
        setSignatures(saved);
        replacePreview(blob);
      } catch (exception) {
        if (active) {
          setPreviewError(exception instanceof Error ? exception.message : 'Không thể tải mẫu chứng nhận.');
        }
      } finally {
        if (active) setLoading(false);
      }
    };
    void load();
    return () => {
      active = false;
      if (previewUrlRef.current) URL.revokeObjectURL(previewUrlRef.current);
    };
  }, []);

  const saveSignature = async () => {
    setSaving(true);
    try {
      await api('/api/staff/certificate-signature', {
        method: 'PUT',
        body: signatures,
      });
      setSavedSignatures(signatures);
      await refreshPreview();
      showNotice('success', 'Đã lưu chữ ký và tên người ký cho chứng nhận mới.');
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể lưu chữ ký mẫu.');
    } finally {
      setSaving(false);
    }
  };

  const hasSavedSignature = Object.values(savedSignatures).some(
    (signer) => signer.imageData || signer.name,
  );
  const resetSignature = async () => {
    if (!hasSavedSignature || !window.confirm('Đặt lại chữ ký và tên của cả hai bên?')) return;
    setSaving(true);
    try {
      await api('/api/staff/certificate-signature', { method: 'DELETE' });
      const empty = {
        dean: { imageData: '', name: '' },
        organizer: { imageData: '', name: '' },
      };
      setSignatures(empty);
      setSavedSignatures(empty);
      await refreshPreview();
      showNotice('success', 'Đã đặt lại chữ ký và tên của cả hai bên.');
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể đặt lại chữ ký mẫu.');
    } finally {
      setSaving(false);
    }
  };

  return <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <section className="rp-modal rp-template-modal" role="dialog" aria-modal="true" aria-labelledby="certificate-template-title">
      <header>
        <div><h2 id="certificate-template-title">Mẫu chứng nhận</h2><p>Thiết lập chữ ký và tên Ban tổ chức, Trưởng khoa cho các lần cấp sau.</p></div>
        <button className="rp-icon-button" onClick={onClose} aria-label="Đóng"><X size={18} /></button>
      </header>
      {previewLoading || loading ? <LoadingPanel /> : previewError ? <ErrorPanel message={previewError} onRetry={refreshPreview} /> : previewUrl && <iframe className="rp-certificate-preview rp-template-preview" src={previewUrl} title="Mẫu chứng nhận" />}
      <section className="rp-signature-editor">
        <SignerSignatureEditor
          title="Ban tổ chức"
          value={signatures.organizer}
          savedValue={savedSignatures.organizer}
          onChange={(value) => setSignatures((current) => ({ ...current, organizer: value }))}
          disabled={saving}
          showNotice={showNotice}
        />
        <SignerSignatureEditor
          title="Trưởng khoa"
          value={signatures.dean}
          savedValue={savedSignatures.dean}
          onChange={(value) => setSignatures((current) => ({ ...current, dean: value }))}
          disabled={saving}
          showNotice={showNotice}
        />
        <footer className="rp-signature-footer">
          <button className="rp-secondary-button" onClick={resetSignature} disabled={!hasSavedSignature || saving}><RotateCcw size={15} /> Đặt lại cả hai</button>
          <button className="rp-secondary-button rp-signature-save" onClick={saveSignature} disabled={saving}><Save size={15} />{saving ? 'Đang lưu...' : 'Xác nhận dùng làm mẫu'}</button>
        </footer>
      </section>
    </section>
  </div>;
}

function SignerSignatureEditor({ title, value, savedValue, onChange, disabled, showNotice }) {
  const canvasRef = useRef(null);
  const fileRef = useRef(null);
  const drawingRef = useRef(false);
  const drawingHasStrokesRef = useRef(false);
  const [signatureColor, setSignatureColor] = useState('#173c6b');

  const pointOnCanvas = (event) => {
    const canvas = canvasRef.current;
    const bounds = canvas.getBoundingClientRect();
    return {
      x: (event.clientX - bounds.left) * (canvas.width / bounds.width),
      y: (event.clientY - bounds.top) * (canvas.height / bounds.height),
    };
  };

  const uploadSignature = (event) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    if (!['image/png', 'image/jpeg'].includes(file.type)) {
      showNotice('error', 'Vui lòng chọn ảnh PNG hoặc JPEG.');
      return;
    }
    if (file.size > 1024 * 1024) {
      showNotice('error', 'Ảnh chữ ký không được vượt quá 1 MB.');
      return;
    }
    const reader = new FileReader();
    reader.onerror = () => showNotice('error', 'Không thể đọc tệp ảnh chữ ký.');
    reader.onload = () => {
      if (typeof reader.result === 'string') {
        const canvas = canvasRef.current;
        if (canvas) canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
        drawingHasStrokesRef.current = false;
        onChange({ ...value, imageData: reader.result });
      }
    };
    reader.readAsDataURL(file);
  };

  const startDrawing = (event) => {
    const canvas = canvasRef.current;
    if (!canvas || disabled) return;
    event.preventDefault();
    canvas.setPointerCapture(event.pointerId);
    const context = canvas.getContext('2d');
    const point = pointOnCanvas(event);
    if (!drawingHasStrokesRef.current) {
      context.clearRect(0, 0, canvas.width, canvas.height);
      drawingHasStrokesRef.current = true;
    }
    context.beginPath();
    context.strokeStyle = signatureColor;
    context.lineWidth = 4;
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.fillStyle = signatureColor;
    context.fillRect(point.x - 2, point.y - 2, 4, 4);
    context.beginPath();
    context.moveTo(point.x, point.y);
    drawingRef.current = true;
    onChange({ ...value, imageData: '' });
  };

  const drawSignature = (event) => {
    if (!drawingRef.current) return;
    const context = canvasRef.current?.getContext('2d');
    if (!context) return;
    const point = pointOnCanvas(event);
    context.lineTo(point.x, point.y);
    context.stroke();
  };

  const finishDrawing = () => {
    if (!drawingRef.current) return;
    drawingRef.current = false;
    const canvas = canvasRef.current;
    canvas?.getContext('2d')?.beginPath();
    if (canvas) onChange({ ...value, imageData: canvas.toDataURL('image/png') });
  };

  const clearSignature = () => {
    const canvas = canvasRef.current;
    if (canvas) canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
    drawingHasStrokesRef.current = false;
    onChange({ ...value, imageData: '' });
  };

  useEffect(() => {
    if (!value.imageData && !drawingRef.current) {
      const canvas = canvasRef.current;
      if (canvas) canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
    }
  }, [value.imageData]);

  return <section className="rp-signer-editor">
    <div className="rp-signature-heading">
      <div>
        <h3>Chữ ký {title}</h3>
        <p>{savedValue.imageData || savedValue.name ? 'Đã có mẫu. Có thể thay chữ ký hoặc tên trước khi lưu.' : 'Chưa thiết lập chữ ký và tên.'}</p>
      </div>
      {value.imageData && <img className="rp-signature-current" src={value.imageData} alt={`Chữ ký ${title} đang chọn`} />}
    </div>
    <label className="rp-signature-name">
      <span>Tên hiển thị dưới chữ ký</span>
      <input
        value={value.name}
        maxLength={120}
        onChange={(event) => onChange({ ...value, name: event.target.value })}
        placeholder={`Nhập tên ${title.toLowerCase()}`}
        disabled={disabled}
      />
    </label>
    <div className="rp-signature-actions">
      <input ref={fileRef} type="file" accept="image/png,image/jpeg" hidden onChange={uploadSignature} />
      <button className="rp-secondary-button" onClick={() => fileRef.current?.click()} disabled={disabled}><Upload size={15} /> Tải ảnh chữ ký</button>
      <button className="rp-secondary-button" onClick={clearSignature} disabled={disabled}><RotateCcw size={15} /> Xóa chữ ký</button>
      <label className="rp-signature-color">
        <span>Màu nét</span>
        <input type="color" value={signatureColor} onChange={(event) => setSignatureColor(event.target.value)} aria-label={`Chọn màu chữ ký ${title}`} disabled={disabled} />
      </label>
    </div>
    <canvas
      ref={canvasRef}
      className="rp-signature-canvas"
      width={680}
      height={120}
      aria-label={`Vùng vẽ chữ ký ${title}`}
      onPointerDown={startDrawing}
      onPointerMove={drawSignature}
      onPointerUp={finishDrawing}
      onPointerCancel={finishDrawing}
    />
    <p className="rp-signature-help">Vẽ chữ ký trong khung hoặc tải ảnh PNG/JPEG (tối đa 1 MB).</p>
  </section>;
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
