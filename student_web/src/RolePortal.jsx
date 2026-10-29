import { useCallback, useEffect, useState } from 'react';
import {
  Activity, Award, BarChart3, Bell, BookOpen, Building2, CalendarDays,
  ChevronLeft, ChevronRight, ClipboardCheck, Home, LogOut,
  Menu, MessageSquare, Moon, RefreshCw, Search, Settings, ShieldCheck, Sun,
  Users, X,
} from 'lucide-react';
import { api } from './api.js';
import './role-portal.css';

const ADMIN_ITEMS = [
  ['dashboard', 'Dashboard', Home], ['users', 'Quản lý người dùng', Users],
  ['orgUnits', 'Đơn vị tổ chức', Building2], ['classes', 'Quản lý lớp học', BookOpen],
  ['events', 'Quản lý sự kiện', CalendarDays], ['attendance', 'Điểm danh', ClipboardCheck],
  ['reports', 'Báo cáo & Thống kê', BarChart3], ['feedback', 'Phản hồi', MessageSquare],
  ['certificates', 'Chứng chỉ', Award], ['settings', 'Cài đặt', Settings],
];
const LECTURER_ITEMS = [
  ['dashboard', 'Dashboard', Home], ['calendar', 'Lịch của tôi', CalendarDays],
  ['classes', 'Quản lý lớp học', BookOpen], ['attendance', 'Điểm danh', ClipboardCheck],
  ['reports', 'Báo cáo & Thống kê', BarChart3], ['notifications', 'Thông báo', Bell],
];
const EMPLOYEE_ITEMS = [
  ['dashboard', 'Dashboard', Home], ['calendar', 'Lịch của tôi', CalendarDays],
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
  if (page === 'settings') return { endpoint: '/health', kind: 'health' };
  return null;
}

export default function RolePortal({ user, onLogout, showNotice, darkMode, setDarkMode }) {
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
          <div className="rp-breadcrumb"><span>Trang chủ</span><ChevronRight size={15} /><strong>{PAGE_TITLES[activePage] || 'Dashboard'}</strong></div>
          <div className="rp-header-actions">
            <span className="rp-connected"><i /> Đang kết nối</span>
            <button className="rp-icon-button" aria-label={darkMode ? 'Giao diện sáng' : 'Giao diện tối'} onClick={() => setDarkMode((value) => !value)}>
              {darkMode ? <Sun size={18} /> : <Moon size={18} />}
            </button>
            <button className="rp-header-avatar" title={`${nameOf(user)} · ${roleLabel}`} onClick={() => goTo('profile')}>{initialsOf(nameOf(user))}</button>
          </div>
        </header>
        <section className="rp-content">
          <RolePortalPage page={activePage} role={user.role} user={user} onNavigate={goTo} showNotice={showNotice} />
        </section>
      </main>
    </div>
  );
}

function RolePortalPage({ page, role, user, onNavigate, showNotice }) {
  const config = resourceFor(page, role);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(Boolean(config));
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');
  const [selectedId, setSelectedId] = useState('');
  const [detail, setDetail] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [health, setHealth] = useState(null);
  const [selectedDate, setSelectedDate] = useState(() => new Date());

  const load = useCallback(async () => {
    if (!config) return;
    setLoading(true);
    setError('');
    try {
      const result = await api(config.endpoint);
      setData(result);
      if (config.kind === 'health') setHealth(result);
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
    void load();
  }, [load]);

  const loadDetail = async (item) => {
    if (!item?.id) return;
    setSelectedId(String(item.id));
    setDetailLoading(true);
    try {
      const result = await api(`/api/admin/classes/${encodeURIComponent(item.id)}/students`);
      setDetail(itemsOf(result));
    } catch (exception) {
      setDetail([]);
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể tải danh sách sinh viên.');
    } finally {
      setDetailLoading(false);
    }
  };

  if (page === 'dashboard') return <Dashboard data={data} loading={loading} error={error} onRefresh={load} role={role} onNavigate={onNavigate} />;
  if (page === 'calendar') return <CalendarView data={data} loading={loading} error={error} onRefresh={load} selectedDate={selectedDate} setSelectedDate={setSelectedDate} role={role} />;
  if (page === 'classes') return <ClassesView data={data} loading={loading} error={error} query={query} setQuery={setQuery} onRefresh={load} onSelect={loadDetail} selectedId={selectedId} detail={detail} detailLoading={detailLoading} onCloseDetail={() => { setSelectedId(''); setDetail(null); }} />;
  if (page === 'attendance') return <AttendanceView data={data} loading={loading} error={error} query={query} setQuery={setQuery} onRefresh={load} role={role} />;
  if (page === 'reports') return <ReportsView data={data} loading={loading} error={error} onRefresh={load} role={role} />;
  if (page === 'profile') return <ProfileView data={data?.user || user} loading={loading} error={error} onRefresh={load} role={role} />;
  if (page === 'settings') return <SettingsView health={health} loading={loading} error={error} onRefresh={load} />;

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
            : <GenericTable page={page} items={rows} />
      )}
    </>
  );
}

function ProfileView({ data, loading, error, onRefresh, role }) {
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
  return (
    <>
      <PageTitle title="Hồ sơ cá nhân" subtitle="Thông tin tài khoản được xác thực bởi hệ thống HUIT." onRefresh={onRefresh} loading={loading} />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : (
        <section className="rp-profile-layout">
          <article className="rp-card rp-profile-summary"><span className="rp-profile-avatar">{initialsOf(data?.name || data?.fullName || data?.id)}</span><h2>{data?.name || data?.fullName || 'Người dùng HUIT'}</h2><code>{data?.id || 'Chưa cập nhật mã'}</code><span className="rp-tag">{roleLabel}</span></article>
          <article className="rp-card rp-profile-details"><h2>Thông tin tài khoản</h2><div className="rp-profile-grid">{details.map(([label, value]) => <div key={label}><span>{label}</span><strong>{value || 'Chưa cập nhật'}</strong></div>)}</div></article>
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
  const numericMetrics = metrics.filter((metric) => Number.isFinite(Number(metric.value)));
  return (
    <>
      <PageTitle title="Tổng quan" subtitle={`Số liệu hiện tại · ${isAdminRole(role) ? 'Quản trị viên' : isLecturerRole(role) ? 'Giảng viên' : 'Công nhân viên'}`} onRefresh={onRefresh} loading={loading} />
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
          {!!numericMetrics.length && <section className="rp-card rp-chart-card">
            <h2>Số lượng theo chỉ số</h2>
            <div className="rp-bars">
              {numericMetrics.map((metric, index) => {
                const max = Math.max(...numericMetrics.map((entry) => Number(entry.value)), 1);
                return <div className="rp-bar-row" key={metric.label}><span>{metric.label}</span><div><i style={{ width: `${Math.max(4, Number(metric.value) / max * 100)}%` }} /></div><strong>{metric.value}</strong></div>;
              })}
            </div>
          </section>}
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
  const classes = itemsOf(data);
  const organizer = !isLecturerRole(role);
  const entries = organizer
    ? classes.map((event) => ({ id: event.id, title: event.name, date: event.startTime, place: event.location, detail: event.status, type: 'Sự kiện' }))
    : classes.flatMap((item) => (item.schedules || []).map((schedule) => ({
      id: `${item.id}-${schedule.weekday}-${schedule.startTime}`,
      title: item.name,
      date: schedule.startTime,
      place: schedule.room,
      detail: `${item.subjectName || ''} · ${weekdayName(schedule.weekday)}`,
      weekday: Number(schedule.weekday),
      time: `${schedule.startTime || ''}–${schedule.endTime || ''}`,
      type: 'Lớp học',
    })));
  const filtered = organizer ? entries : entries.filter((entry) => entry.weekday === selectedDate.getDay() || (selectedDate.getDay() === 0 && entry.weekday === 7));
  return (
    <>
      <PageTitle title="Lịch của tôi" subtitle="Lịch học và lịch sự kiện của bạn." onRefresh={onRefresh} loading={loading} />
      <div className="rp-calendar-controls">
        <div className="rp-calendar-period"><button className="rp-icon-button" aria-label="Tuần trước" onClick={() => setSelectedDate((date) => new Date(date.getTime() - (view === 'day' ? 1 : 7) * 86400000))}><ChevronLeft size={18} /></button><strong>{new Intl.DateTimeFormat('vi-VN', { month: 'long', year: 'numeric' }).format(selectedDate)}</strong><button className="rp-icon-button" aria-label="Tuần sau" onClick={() => setSelectedDate((date) => new Date(date.getTime() + (view === 'day' ? 1 : 7) * 86400000))}><ChevronRight size={18} /></button></div>
        <div className="rp-segmented">{['day', 'week', 'month'].map((value) => <button key={value} className={view === value ? 'selected' : ''} onClick={() => setView(value)}>{value === 'day' ? 'Ngày' : value === 'week' ? 'Tuần' : 'Tháng'}</button>)}</div>
      </div>
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : (
        <section className="rp-card rp-list-card">
          <h2>{organizer ? 'Sự kiện phụ trách' : `Lịch ${view === 'day' ? 'trong ngày' : 'theo thứ trong tuần'}`}</h2>
          {filtered.length ? filtered.map((entry) => <div className="rp-list-row" key={entry.id}><span className="rp-list-icon"><CalendarDays size={18} /></span><span className="rp-list-main"><strong>{entry.title}</strong><small>{entry.detail || entry.type} · {entry.place || 'Chưa cập nhật địa điểm'}</small></span><span className="rp-list-time">{entry.time || formatDate(entry.date)}</span></div>) : <EmptyPanel title="Không có lịch" message="Không có lịch học hoặc sự kiện trong khoảng thời gian này." />}
        </section>
      )}
    </>
  );
}

function weekdayName(value) {
  const day = Number(value);
  return ({ 1: 'Thứ 2', 2: 'Thứ 3', 3: 'Thứ 4', 4: 'Thứ 5', 5: 'Thứ 6', 6: 'Thứ 7', 7: 'Chủ nhật' })[day] || 'Chưa xếp lịch';
}

function ClassesView({ data, loading, error, query, setQuery, onRefresh, onSelect, selectedId, detail, detailLoading, onCloseDetail }) {
  const classes = itemsOf(data).filter((item) => JSON.stringify(item).toLowerCase().includes(query.trim().toLowerCase()));
  return (
    <>
      <PageTitle title="Quản lý lớp học" subtitle="Lớp được phân quyền theo tài khoản đang đăng nhập." onRefresh={onRefresh} loading={loading} />
      <SearchBox value={query} onChange={setQuery} placeholder="Tìm tên lớp, mã lớp, giảng viên..." />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : classes.length ? (
        <div className="rp-class-grid">{classes.map((item) => <button className="rp-card rp-class-card" key={item.id} onClick={() => onSelect(item)}><span className="rp-class-code">{item.code || item.id}</span><h2>{item.name || 'Lớp học phần'}</h2><p>{item.subjectName || item.subjectCode || 'Môn học'} · {item.lecturerName || 'Giảng viên'}</p><div className="rp-class-meta"><span><Users size={15} /> {item.studentCount ?? 0} sinh viên</span><span>{item.status || item.semester || 'Đang mở'}</span></div></button>)}</div>
      ) : <EmptyPanel title="Chưa có lớp học" message="Không tìm thấy lớp học phù hợp." />}
      {selectedId && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onCloseDetail(); }}><section className="rp-modal" role="dialog" aria-modal="true"><header><div><h2>Danh sách sinh viên</h2><p>Lớp {selectedId}</p></div><button className="rp-icon-button" onClick={onCloseDetail} aria-label="Đóng"><X size={18} /></button></header>{detailLoading ? <LoadingPanel /> : detail?.length ? <DataTable items={detail} columns={[['Mã sinh viên', 'studentId'], ['Họ tên', 'studentName'], ['Email', 'email'], ['Trạng thái', 'status']]} /> : <EmptyPanel title="Chưa có sinh viên" message="Lớp chưa có sinh viên hoặc không tải được danh sách." />}</section></div>}
    </>
  );
}

function EventsView({ items }) {
  return items.length ? <div className="rp-event-grid">{items.map((item) => <article className="rp-card rp-event-card" key={item.id}><div className="rp-event-top"><span className="rp-tag">{item.status || 'Sự kiện'}</span><span className="rp-event-id">{item.id}</span></div><h2>{item.name || 'Sự kiện HUIT'}</h2><div className="rp-event-detail"><CalendarDays size={15} />{formatDate(item.startTime)}</div><div className="rp-event-detail"><Building2 size={15} />{item.location || 'Chưa cập nhật địa điểm'}</div><div className="rp-event-progress"><span>Đăng ký</span><strong>{item.registeredCount ?? 0}{item.capacity ? ` / ${item.capacity}` : ''}</strong></div><div className="rp-progress-track"><i style={{ width: `${item.capacity ? Math.min(100, Number(item.registeredCount || 0) * 100 / item.capacity) : 0}%` }} /></div></article>)}</div> : <EmptyPanel title="Chưa có sự kiện" message="Đơn vị của bạn chưa có sự kiện hoặc không tìm thấy kết quả." />;
}

function AttendanceView({ data, loading, error, query, setQuery, onRefresh, role }) {
  const lecturerOrAdmin = isLecturerRole(role) || isAdminRole(role);
  const items = itemsOf(data).filter((item) => JSON.stringify(item).toLowerCase().includes(query.trim().toLowerCase()));
  const stats = lecturerOrAdmin
    ? [['Có mặt', sum(items, 'present')], ['Đi trễ', sum(items, 'late')], ['Vắng mặt', sum(items, 'absent')]]
    : [['Đăng ký', sum(items, 'registeredCount')], ['Đã tham dự', sum(items, 'checkedInCount')], ['Vắng mặt', sum(items, 'absentCount')]];
  return (
    <>
      <PageTitle title="Điểm danh" subtitle={lecturerOrAdmin ? 'Phiên học và kết quả tham dự từ cơ sở dữ liệu.' : 'Tổng hợp điểm danh các sự kiện thuộc đơn vị.'} onRefresh={onRefresh} loading={loading} />
      <div className="rp-metrics-grid rp-metrics-compact">{stats.map(([label, value]) => <article className="rp-metric-card" key={label}><span className="rp-metric-icon"><ClipboardCheck size={19} /></span><div><span>{label}</span><strong>{value}</strong></div></article>)}</div>
      <SearchBox value={query} onChange={setQuery} placeholder="Tìm mã lớp, sự kiện, trạng thái..." />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : lecturerOrAdmin
        ? <DataTable items={items} columns={[['Lớp', 'className'], ['Buổi học', 'sessionName'], ['Mở lúc', 'openedAt'], ['Đóng lúc', 'closedAt'], ['Phương thức', 'method'], ['Có mặt', 'present'], ['Đi trễ', 'late'], ['Vắng', 'absent']]} />
        : <EventsView items={items} />}
    </>
  );
}

function ReportsView({ data, loading, error, onRefresh, role }) {
  const [selectedClassId, setSelectedClassId] = useState('');
  const [report, setReport] = useState(null);
  const [reportLoading, setReportLoading] = useState(false);
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
  return (
    <>
      <PageTitle title="Báo cáo & thống kê" subtitle="Báo cáo điểm danh theo lớp học." onRefresh={onRefresh} loading={loading} />
      {error ? <ErrorPanel message={error} onRetry={onRefresh} /> : loading ? <LoadingPanel /> : (
        <>
          <section className="rp-card rp-report-select"><label htmlFor="rp-report-class">Chọn lớp học</label><select id="rp-report-class" value={selectedClassId} onChange={selectClass}><option value="">Chọn lớp để xem báo cáo</option>{classes.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.studentCount ?? 0} sinh viên</option>)}</select></section>
          {reportLoading && <LoadingPanel />}
          {report?.error && <ErrorPanel message={report.error} />}
          {report && !report.error && <><div className="rp-metrics-grid rp-metrics-compact">{totals.map(([label, value]) => <article className="rp-metric-card" key={label}><span className="rp-metric-icon"><BarChart3 size={19} /></span><div><span>{label}</span><strong>{value}</strong></div></article>)}</div><DataTable items={summary} columns={[['Mã sinh viên', 'studentId'], ['Họ tên', 'studentName'], ['Tổng buổi', 'totalSessions'], ['Có mặt', 'present'], ['Đi trễ', 'late'], ['Vắng', 'absent'], ['Có phép', 'excused']]} /></>}
          {!classes.length && <EmptyPanel title="Chưa có lớp" message="Tài khoản chưa được phân công lớp học." />}
        </>
      )}
    </>
  );
}

function SettingsView({ health, loading, error, onRefresh }) {
  return <><PageTitle title="Cài đặt" subtitle="Tùy chỉnh giao diện và kiểm tra kết nối hệ thống." onRefresh={onRefresh} loading={loading} /><section className="rp-card rp-settings-card"><span className={`rp-health-dot ${health?.database === 'connected' ? 'ok' : ''}`} /><div><h2>Kết nối máy chủ</h2><p>{error || (health?.database === 'connected' ? 'Máy chủ và cơ sở dữ liệu đang hoạt động.' : loading ? 'Đang kiểm tra kết nối...' : 'Máy chủ phản hồi nhưng chưa xác nhận được cơ sở dữ liệu.')}</p></div><button className="rp-secondary-button" onClick={onRefresh} disabled={loading}><RefreshCw size={16} /> Kiểm tra lại</button></section></>;
}

function GenericTable({ page, items }) {
  const columns = page === 'users' ? [['Mã', 'id'], ['Họ tên', 'name'], ['Email', 'email'], ['Vai trò', 'role'], ['Trạng thái', 'status']]
    : page === 'orgUnits' ? [['Mã đơn vị', 'id'], ['Tên đơn vị', 'name']]
      : page === 'certificates' ? [['Mã chứng chỉ', 'id'], ['Sinh viên', 'studentName'], ['Sự kiện', 'eventName'], ['Ngày cấp', 'issuedAt'], ['Trạng thái', 'status']]
        : page === 'feedback' ? [['Loại', 'sourceType'], ['Sinh viên', 'studentName'], ['Nội dung', 'content'], ['Sự kiện / lớp', 'eventName'], ['Thời gian', 'sentAt']]
          : [['Mã', 'id'], ['Nội dung', 'title'], ['Thời gian', 'createdAt']];
  return items.length ? <DataTable items={items} columns={columns} /> : <EmptyPanel title="Chưa có dữ liệu" message="Danh sách sẽ hiển thị khi hệ thống có bản ghi." />;
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
