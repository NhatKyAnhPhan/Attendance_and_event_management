import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity, ArrowLeft, ArrowRight, Bell, BookOpen,
  CalendarDays, Check, ChevronDown, ChevronLeft, ChevronRight, CircleHelp,
  Clock3, Download, GraduationCap, Home, LogOut, MapPin, Menu, Moon,
  Plus, Search, ShieldCheck, Sparkles, Sun, UserRound, Users, X,
} from 'lucide-react';
import { api, ApiError } from './api.js';
import RolePortal from './RolePortal.jsx';
import { AttendanceBarChart, AttendanceDonutChart } from './StatisticsCharts.jsx';

const NAV_ITEMS = [
  { id: 'home', label: 'Tổng quan', icon: Home },
  { id: 'classes', label: 'Lớp học', icon: BookOpen },
  { id: 'events', label: 'Sự kiện', icon: Sparkles },
  { id: 'calendar', label: 'Lịch của tôi', icon: CalendarDays },
  { id: 'attendance', label: 'Điểm danh', icon: Activity },
  { id: 'notifications', label: 'Thông báo', icon: Bell },
];

const FULL_NAV_ITEMS = [
  ...NAV_ITEMS,
  { id: 'certificates', label: 'Chứng nhận', icon: ShieldCheck },
  { id: 'profile', label: 'Hồ sơ cá nhân', icon: UserRound },
];

const roleIsStudent = (role) => ['student', 'sinh viên'].includes(String(role || '').trim().toLowerCase());
const roleIsLecturer = (role) => ['lecturer', 'teacher', 'giảng viên'].includes(String(role || '').trim().toLowerCase());
const roleIsEmployee = (role) => ['admin', 'administrator', 'quản trị viên', 'organizer', 'event_organizer', 'ban tổ chức', 'cán bộ', 'nhân viên', 'công nhân viên', 'staff', 'employee'].includes(String(role || '').trim().toLowerCase());
const ROLE_OPTIONS = [
  {
    id: 'student',
    label: 'Sinh viên',
    icon: GraduationCap,
    portal: 'STUDENT PORTAL',
    description: 'Theo dõi lớp học, sự kiện và hành trình học tập của bạn.',
    eyebrow: 'KHÔNG GIAN HỌC TẬP CỦA BẠN',
    headline: 'Mỗi ngày đến trường,',
    headlineAccent: 'một bước trưởng thành.',
    loginDescription: 'Đăng nhập bằng tài khoản sinh viên HUIT để tiếp tục.',
    identifierLabel: 'Mã sinh viên hoặc email',
    identifierPlaceholder: 'Ví dụ: 2001230001',
    highlights: [
      { value: '01', label: <>Một tài khoản<br />mọi trải nghiệm</> },
      { value: '24/7', label: <>Thông tin luôn<br />sẵn sàng</> },
      { value: '∞', label: <>Hành trình<br />của riêng bạn</> },
    ],
  },
  {
    id: 'lecturer',
    label: 'Giảng viên',
    icon: BookOpen,
    portal: 'LECTURER PORTAL',
    description: 'Đăng nhập để mở không gian làm việc dành cho giảng viên.',
    eyebrow: 'KẾT NỐI CÔNG TÁC GIẢNG DẠY',
    headline: 'Đồng hành cùng',
    headlineAccent: 'mỗi lớp học HUIT.',
    loginDescription: 'Đăng nhập bằng tài khoản giảng viên của nhà trường.',
    identifierLabel: 'Mã giảng viên hoặc email',
    identifierPlaceholder: 'Nhập mã giảng viên hoặc email',
    highlights: [
      { value: 'GV', label: <>Không gian<br />giảng viên</> },
      { value: 'LỚP', label: <>Quản lý hoạt động<br />giảng dạy</> },
      { value: 'HUIT', label: <>Một tài khoản<br />nhà trường</> },
    ],
  },
  {
    id: 'employee',
    label: 'Nhân viên',
    icon: Users,
    portal: 'STAFF PORTAL',
    description: 'Đăng nhập để mở không gian làm việc dành cho nhân viên và đơn vị tổ chức.',
    eyebrow: 'KẾT NỐI CÁC ĐƠN VỊ HUIT',
    headline: 'Cùng vận hành',
    headlineAccent: 'một HUIT năng động.',
    loginDescription: 'Đăng nhập bằng tài khoản nhân viên hoặc cán bộ HUIT.',
    identifierLabel: 'Mã nhân viên hoặc email',
    identifierPlaceholder: 'Nhập mã nhân viên hoặc email',
    highlights: [
      { value: 'NV', label: <>Không gian<br />nhân viên</> },
      { value: 'ĐV', label: <>Kết nối các<br />đơn vị</> },
      { value: 'HUIT', label: <>Một tài khoản<br />nhà trường</> },
    ],
  },
];
const nameOf = (user) => user?.name || user?.fullName || user?.id || 'Sinh viên';
const initialsOf = (name) => String(name || 'SV').trim().split(/\s+/).slice(-2).map((part) => part[0]).join('').toUpperCase();
const formatDate = (value, options = { day: '2-digit', month: '2-digit', year: 'numeric' }) => {
  const date = value ? new Date(value) : null;
  return date && !Number.isNaN(date.valueOf()) ? new Intl.DateTimeFormat('vi-VN', options).format(date) : 'Chưa cập nhật';
};
const formatTime = (value) => formatDate(value, { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' });
const getApiMessage = (error) => error instanceof Error ? error.message : 'Đã xảy ra lỗi. Vui lòng thử lại.';

export default function App() {
  const [user, setUser] = useState(null);
  const [checkingSession, setCheckingSession] = useState(true);
  const validPages = FULL_NAV_ITEMS.map((item) => item.id);
  const [activePage, setActivePage] = useState(() => {
    const requestedPage = window.location.hash.slice(1);
    return validPages.includes(requestedPage) ? requestedPage : 'home';
  });
  const [notice, setNotice] = useState(null);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [darkMode, setDarkMode] = useState(localStorage.getItem('studentWebDark') === 'true');

  const signOut = useCallback((message) => {
    localStorage.removeItem('studentWebToken');
    setUser(null);
    setActivePage('home');
    if (message) setNotice({ type: 'error', text: message });
  }, []);

  useEffect(() => {
    const handleExpired = () => signOut('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
    window.addEventListener('student-session-expired', handleExpired);
    const restore = async () => {
      const token = localStorage.getItem('studentWebToken');
      if (!token) {
        setCheckingSession(false);
        return;
      }
      try {
        const result = await api('/api/me', { token });
        const role = result.user?.role;
        if (roleIsStudent(role) || roleIsLecturer(role) || roleIsEmployee(role)) {
          setUser(result.user);
        } else {
          signOut('Vai trò tài khoản chưa được hỗ trợ trên cổng web.');
        }
      } catch (error) {
        signOut(error.status === 401 ? null : getApiMessage(error));
      } finally {
        setCheckingSession(false);
      }
    };
    restore();
    return () => window.removeEventListener('student-session-expired', handleExpired);
  }, [signOut]);

  useEffect(() => {
    document.documentElement.dataset.theme = darkMode ? 'dark' : 'light';
    localStorage.setItem('studentWebDark', String(darkMode));
  }, [darkMode]);

  useEffect(() => {
    const syncPage = () => {
      const requestedPage = window.location.hash.slice(1);
      setActivePage(validPages.includes(requestedPage) ? requestedPage : 'home');
    };
    window.addEventListener('hashchange', syncPage);
    window.addEventListener('popstate', syncPage);
    return () => {
      window.removeEventListener('hashchange', syncPage);
      window.removeEventListener('popstate', syncPage);
    };
  }, []);

  const showNotice = (type, text) => {
    setNotice({ type, text });
    window.setTimeout(() => setNotice((current) => current?.text === text ? null : current), 4500);
  };

  if (checkingSession) {
    return <div className="boot-screen"><div className="brand-mark"><GraduationCap size={24} /></div><div className="spinner" /><span>Đang kiểm tra phiên đăng nhập...</span></div>;
  }
  if (!user) {
    return <LoginPage onLogin={setUser} notice={notice} clearNotice={() => setNotice(null)} />;
  }
  if (!roleIsStudent(user.role)) {
    return <RolePortal user={user} onUserChange={setUser} onLogout={() => signOut()} showNotice={showNotice} darkMode={darkMode} setDarkMode={setDarkMode} />;
  }

  const currentNav = FULL_NAV_ITEMS.find((item) => item.id === activePage);
  const goTo = (page) => {
    setActivePage(page);
    if (window.location.hash !== `#${page}`) window.history.pushState(null, '', `#${page}`);
    setMobileMenuOpen(false);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileMenuOpen ? 'sidebar-open' : ''}`}>
        <div className="brand-lockup">
          <div className="brand-mark logo-mark"><img className="huit-logo" src="/huit-logo.jpg" alt="Logo Trường Đại học Công Thương TP.HCM" /></div>
          <div><strong>HUIT</strong><span>CỔNG SINH VIÊN</span></div>
          <button className="icon-button sidebar-close" aria-label="Đóng menu" onClick={() => setMobileMenuOpen(false)}><X size={19} /></button>
        </div>
        <div className="sidebar-caption">KHÔNG GIAN HỌC TẬP</div>
        <nav className="main-nav" aria-label="Điều hướng chính">
          {FULL_NAV_ITEMS.map(({ id, label, icon: Icon }) => (
            <button key={id} className={`nav-link ${activePage === id ? 'active' : ''}`} onClick={() => goTo(id)}>
              <Icon size={19} strokeWidth={1.9} /><span>{label}</span>
              {id === 'attendance' && <span className="nav-live-dot" />}
            </button>
          ))}
        </nav>
        <div className="sidebar-spacer" />
        <div className="attendance-promo">
          <div className="promo-icon"><Activity size={18} /></div>
          <strong>Đang có phiên điểm danh?</strong>
          <p>Quét mã bằng ứng dụng HUIT trên Android.</p>
          <button onClick={() => goTo('attendance')}>Xem hướng dẫn <ArrowRight size={14} /></button>
        </div>
        <div className="sidebar-footer">
          <div className="user-avatar small">{initialsOf(nameOf(user))}</div>
          <div className="sidebar-user"><strong>{nameOf(user)}</strong><span>{user.id || 'Sinh viên'}</span></div>
          <button className="icon-button" title="Đăng xuất" onClick={() => signOut()}><LogOut size={17} /></button>
        </div>
      </aside>
      {mobileMenuOpen && <button className="mobile-backdrop" aria-label="Đóng menu" onClick={() => setMobileMenuOpen(false)} />}
      <main className="main-area">
        <header className="topbar">
          <div className="topbar-left">
            <button className="icon-button mobile-menu-button" aria-label="Mở menu" onClick={() => setMobileMenuOpen(true)}><Menu size={21} /></button>
            <div className="breadcrumb"><span>Không gian sinh viên</span><ChevronRight size={15} /><strong>{currentNav?.label || 'Tổng quan'}</strong></div>
          </div>
          <div className="topbar-actions">
            <div className="connection-pill"><span /> Đang kết nối</div>
            <button className="icon-button theme-toggle" title={darkMode ? 'Giao diện sáng' : 'Giao diện tối'} onClick={() => setDarkMode((value) => !value)}>{darkMode ? <Sun size={18} /> : <Moon size={18} />}</button>
            <button className="header-profile" onClick={() => goTo('profile')}><div className="user-avatar small">{initialsOf(nameOf(user))}</div><ChevronDown size={15} /></button>
          </div>
        </header>
        <section className="page-content">
          {activePage === 'home' && <DashboardPage user={user} goTo={goTo} showNotice={showNotice} />}
          {activePage === 'classes' && <ClassesPage showNotice={showNotice} />}
          {activePage === 'events' && <EventsPage showNotice={showNotice} />}
          {activePage === 'calendar' && <CalendarPage showNotice={showNotice} />}
          {activePage === 'attendance' && <AttendancePage />}
          {activePage === 'notifications' && <NotificationsPage goTo={goTo} />}
          {activePage === 'certificates' && <CertificatesPage showNotice={showNotice} />}
          {activePage === 'profile' && <ProfilePage user={user} onUserChange={setUser} onLogout={() => signOut()} showNotice={showNotice} darkMode={darkMode} setDarkMode={setDarkMode} goTo={goTo} />}
        </section>
      </main>
      {notice && <div role="status" className={`toast ${notice.type}`}><span>{notice.type === 'success' ? <Check size={18} /> : <CircleHelp size={18} />}</span>{notice.text}<button className="icon-button" aria-label="Đóng" onClick={() => setNotice(null)}><X size={16} /></button></div>}
    </div>
  );
}

function LoginPage({ onLogin, notice, clearNotice }) {
  const [step, setStep] = useState('login');
  const [selectedRole, setSelectedRole] = useState('');
  const [identifier, setIdentifier] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [otp, setOtp] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [resetToken, setResetToken] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [resendSeconds, setResendSeconds] = useState(0);

  useEffect(() => {
    if (!resendSeconds) return undefined;
    const timer = window.setTimeout(() => setResendSeconds((seconds) => seconds - 1), 1000);
    return () => window.clearTimeout(timer);
  }, [resendSeconds]);

  const submitLogin = async (event) => {
    event.preventDefault();
    setLoading(true); setError(''); clearNotice();
    try {
      const session = await api('/api/auth/login', { method: 'POST', body: { identifier: identifier.trim(), password } });
      if (!session.token) {
        throw new ApiError('Phản hồi đăng nhập không hợp lệ.', 0);
      }
      const profile = await api('/api/me', { token: session.token });
      const actualRole = profile.user?.role ?? session.user?.role ?? session.role;
      const roleMatches = selectedRole === 'student'
        ? roleIsStudent(actualRole)
        : selectedRole === 'lecturer'
          ? roleIsLecturer(actualRole)
          : roleIsEmployee(actualRole);
      if (!roleMatches) {
        throw new ApiError(`Tài khoản này không thuộc nhóm ${ROLE_OPTIONS.find((role) => role.id === selectedRole)?.label || 'đã chọn'}. Hãy chọn đúng vai trò để tiếp tục.`, 403);
      }
      localStorage.setItem('studentWebToken', session.token);
      onLogin(profile.user);
    } catch (exception) {
      setError(getApiMessage(exception));
    } finally { setLoading(false); }
  };

  const requestReset = async (event) => {
    event.preventDefault();
    setError(''); setLoading(true);
    try {
      await api('/api/auth/password-reset/request', { method: 'POST', body: { email: email.trim() } });
      setStep('otp'); setOtp(''); setResetToken(''); setResendSeconds(60);
    } catch (exception) { setError(getApiMessage(exception)); }
    finally { setLoading(false); }
  };

  const verifyCode = async (event) => {
    event.preventDefault();
    setError('');
    if (!/^\d{6}$/.test(otp)) { setError('Vui lòng nhập đủ 6 chữ số OTP.'); return; }
    setLoading(true);
    try {
      const result = await api('/api/auth/password-reset/verify', { method: 'POST', body: { email: email.trim(), code: otp } });
      if (!result.resetToken) throw new Error('Phản hồi xác nhận mã không hợp lệ.');
      setResetToken(result.resetToken); setStep('new-password');
    } catch (exception) { setError(getApiMessage(exception)); }
    finally { setLoading(false); }
  };

  const finishReset = async (event) => {
    event.preventDefault();
    setError('');
    if (newPassword.length < 8) { setError('Mật khẩu phải có ít nhất 8 ký tự.'); return; }
    if (newPassword !== confirmPassword) { setError('Mật khẩu xác nhận không khớp.'); return; }
    setLoading(true);
    try {
      await api('/api/auth/password-reset/complete', { method: 'POST', body: { email: email.trim(), resetToken, newPassword } });
      setStep('success');
    } catch (exception) { setError(getApiMessage(exception)); }
    finally { setLoading(false); }
  };

  const chooseRole = (role) => {
    setSelectedRole(role);
    setStep('login');
    setError('');
  };
  const selectedRoleInfo = ROLE_OPTIONS.find((role) => role.id === selectedRole);
  const SelectedRoleIcon = selectedRoleInfo?.icon;

  if (!selectedRole) {
    return <RoleSelectionPage onSelect={chooseRole} notice={notice} clearNotice={clearNotice} />;
  }

  return (
    <div className={`login-layout role-${selectedRole}`}>
      <section className={`login-art role-art-${selectedRole}`}>
        <div className="login-brand"><div className="brand-mark logo-mark light"><img className="huit-logo" src="/huit-logo.jpg" alt="Logo Trường Đại học Công Thương TP.HCM" /></div><span>HUIT <small>{selectedRoleInfo.portal}</small></span></div>
        <div className="art-copy">
          <div className="eyebrow"><span /> {selectedRoleInfo.eyebrow}</div>
          <h1>{selectedRoleInfo.headline}<br /><em>{selectedRoleInfo.headlineAccent}</em></h1>
          <p>{selectedRoleInfo.description}</p>
          <div className="art-stats">
            {selectedRoleInfo.highlights.map((highlight) => <div key={highlight.value}><strong>{highlight.value}</strong><span>{highlight.label}</span></div>)}
          </div>
        </div>
        <div className="login-art-footer"><span>© HUIT · Cổng thông tin điện tử</span><span>An toàn · Kết nối · Tận tâm</span></div>
        <div className="art-orb orb-one" /><div className="art-orb orb-two" />
      </section>
      <section className="login-form-side">
        <div className="login-form-wrap">
          <div className="form-mobile-brand"><div className="brand-mark logo-mark"><img className="huit-logo" src="/huit-logo.jpg" alt="Logo Trường Đại học Công Thương TP.HCM" /></div><strong>HUIT</strong><span>{selectedRoleInfo.portal}</span></div>
          {notice && <div className="alert error">{notice.text}<button className="icon-button" onClick={clearNotice}><X size={15} /></button></div>}
          {step === 'login' && <>
            <button className="back-button role-back" onClick={() => { setSelectedRole(''); setError(''); }}><ArrowLeft size={16} /> Chọn vai trò khác</button>
            <div className={`login-role-badge badge-${selectedRole}`}><SelectedRoleIcon size={16} /><span>KHÔNG GIAN {selectedRoleInfo.label.toUpperCase()}</span></div>
            <span className="form-kicker">CHÀO MỪNG BẠN TRỞ LẠI</span>
            <h2>Đăng nhập {selectedRoleInfo.label.toLowerCase()}</h2><p className="form-subtitle">{selectedRoleInfo.loginDescription}</p>
            <form onSubmit={submitLogin} className="auth-form">
              <label>{selectedRoleInfo.identifierLabel}<input autoComplete="username" value={identifier} onChange={(event) => setIdentifier(event.target.value)} placeholder={selectedRoleInfo.identifierPlaceholder} required /></label>
              <label>Mật khẩu<input type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Nhập mật khẩu" required /></label>
              {error && <div className="alert error">{error}</div>}
              <button className="text-button forgot-link" type="button" onClick={() => { setStep('forgot'); setEmail(identifier.includes('@') ? identifier : ''); setError(''); }}>Quên mật khẩu?</button>
              <button className="primary-button full" disabled={loading}>{loading ? <><span className="button-spinner" /> Đang xác thực...</> : <>Đăng nhập <ArrowRight size={17} /></>}</button>
            </form>
            <div className="login-footnote"><ShieldCheck size={16} /> Kết nối bảo mật với tài khoản HUIT của bạn</div>
          </>}
          {step === 'forgot' && <AuthStep title="Khôi phục mật khẩu" subtitle="Nhập email đã đăng ký. Mã xác nhận sẽ được gửi đến hộp thư của bạn." back={() => { setStep('login'); setError(''); }}>
            <form onSubmit={requestReset} className="auth-form"><label>Email tài khoản<input type="email" autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="ban@email.com" required /></label>{error && <div className="alert error">{error}</div>}<button className="primary-button full" disabled={loading}>{loading ? 'Đang gửi...' : <>Gửi mã xác nhận <ArrowRight size={17} /></>}</button></form>
          </AuthStep>}
          {step === 'otp' && <AuthStep title="Kiểm tra email nhé" subtitle={`Nhập mã gồm 6 chữ số đã gửi đến ${email}.`} back={() => { setStep('forgot'); setError(''); }}>
            <form onSubmit={verifyCode} className="auth-form"><label>Mã xác nhận<input inputMode="numeric" maxLength={6} value={otp} onChange={(event) => setOtp(event.target.value.replace(/\D/g, '').slice(0, 6))} placeholder="000000" className="otp-input" required /></label>{error && <div className="alert error">{error}</div>}<button className="primary-button full" disabled={loading}>{loading ? 'Đang xác minh...' : <>Xác minh mã <ArrowRight size={17} /></>}</button><button type="button" className="text-button resend-button" disabled={loading || resendSeconds > 0} onClick={requestReset}>{resendSeconds ? `Gửi lại mã sau ${resendSeconds}s` : 'Gửi lại mã'}</button></form>
          </AuthStep>}
          {step === 'new-password' && <AuthStep title="Tạo mật khẩu mới" subtitle="Mật khẩu mới cần có ít nhất 8 ký tự." back={() => { setStep('otp'); setError(''); }}>
            <form onSubmit={finishReset} className="auth-form"><label>Mật khẩu mới<input type="password" autoComplete="new-password" value={newPassword} onChange={(event) => setNewPassword(event.target.value)} required /></label><label>Nhập lại mật khẩu<input type="password" autoComplete="new-password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} required /></label>{error && <div className="alert error">{error}</div>}<button className="primary-button full" disabled={loading}>{loading ? 'Đang cập nhật...' : 'Đặt mật khẩu mới'}</button></form>
          </AuthStep>}
          {step === 'success' && <div className="success-panel"><div className="success-icon"><Check size={25} /></div><span className="form-kicker">HOÀN TẤT</span><h2>Đổi mật khẩu thành công</h2><p>Bạn có thể dùng mật khẩu mới để đăng nhập vào tài khoản.</p><button className="primary-button full" onClick={() => { setStep('login'); setPassword(''); setError(''); }}>Quay lại đăng nhập <ArrowRight size={17} /></button></div>}
          <div className="login-mobile-footer">© HUIT · Cổng thông tin điện tử</div>
        </div>
      </section>
    </div>
  );
}

function RoleSelectionPage({ onSelect, notice, clearNotice }) {
  return (
    <div className="role-selection-layout">
      <header className="role-selection-header">
        <div className="role-selection-brand">
          <div className="brand-mark logo-mark"><img className="huit-logo" src="/huit-logo.jpg" alt="Logo Trường Đại học Công Thương TP.HCM" /></div>
          <span><strong>HUIT</strong><small>CỔNG THÔNG TIN ĐIỆN TỬ</small></span>
        </div>
        <span className="role-header-secure"><ShieldCheck size={15} /> Đăng nhập bảo mật</span>
      </header>
      <main className="role-selection-main">
        <div className="role-selection-intro">
          <span className="form-kicker">TRƯỜNG ĐẠI HỌC CÔNG THƯƠNG TP. HỒ CHÍ MINH</span>
          <h1>Chào mừng bạn đến với<br /><span>cổng thông tin HUIT</span></h1>
          <p>Chọn không gian phù hợp với vai trò của bạn để tiếp tục.</p>
        </div>
        {notice && <div className="alert error">{notice.text}<button className="icon-button" onClick={clearNotice}><X size={15} /></button></div>}
        <div className="role-choice-grid">
          {ROLE_OPTIONS.map(({ id, label, icon: Icon, description, portal }) => (
            <button className={`role-choice-card choice-${id}`} key={id} onClick={() => onSelect(id)}>
              <span className="role-choice-icon"><Icon size={22} strokeWidth={1.8} /></span>
              <span className="role-choice-copy"><strong>{label}</strong><small>{description}</small></span>
              <span className="role-choice-footer"><span>{portal}</span><ArrowRight size={17} /></span>
            </button>
          ))}
        </div>
        <div className="role-selection-note"><ShieldCheck size={16} /><span>Thông tin đăng nhập được xác thực an toàn qua hệ thống HUIT.</span></div>
      </main>
      <footer className="role-selection-footer"><span>© HUIT · Cổng thông tin điện tử</span><span>Đào tạo · Kết nối · Phát triển</span></footer>
    </div>
  );
}

function AuthStep({ title, subtitle, back, children }) {
  return <><button className="back-button" onClick={back}><ArrowLeft size={16} /> Quay lại</button><span className="form-kicker">HỖ TRỢ TÀI KHOẢN</span><h2>{title}</h2><p className="form-subtitle">{subtitle}</p>{children}</>;
}

function useStudentData() {
  const [data, setData] = useState({ classes: [], events: [], notifications: [], dashboard: {}, calendar: [] });
  const [loading, setLoading] = useState(true);
  const [errors, setErrors] = useState([]);
  const refresh = useCallback(async () => {
    setLoading(true);
    const paths = [
      ['/api/classes', 'classes', 'lớp học'],
      ['/api/events', 'events', 'sự kiện'],
      ['/api/notifications', 'notifications', 'thông báo điểm danh'],
      ['/api/dashboard', 'dashboard', 'thống kê'],
      ['/api/calendar/classes', 'calendar', 'lịch học'],
    ];
    const results = await Promise.allSettled(paths.map(([path]) => api(path)));
    const next = { classes: [], events: [], notifications: [], dashboard: {}, calendar: [] };
    const failures = [];
    results.forEach((result, index) => {
      const [, key, label] = paths[index];
      if (result.status === 'fulfilled') {
        next[key] = key === 'dashboard' ? result.value : (result.value.items || []);
      } else {
        failures.push(`${label}: ${getApiMessage(result.reason)}`);
      }
    });
    setData(next); setErrors(failures); setLoading(false);
  }, []);
  useEffect(() => { refresh(); }, [refresh]);
  return { ...data, loading, errors, refresh };
}

function PageHeading({ eyebrow, title, description, actions }) {
  return <div className="page-heading"><div><div className="page-eyebrow">{eyebrow}</div><h1>{title}</h1>{description && <p>{description}</p>}</div>{actions && <div className="heading-actions">{actions}</div>}</div>;
}

function LoadError({ errors, onRetry }) {
  if (!errors?.length) return null;
  return <div className="alert warning"><div><strong>Một số nội dung chưa tải được</strong><p>{errors.join(' · ')}</p></div>{onRetry && <button className="outline-button compact" onClick={onRetry}>Thử lại</button>}</div>;
}

function DashboardPage({ user, goTo, showNotice }) {
  const { classes, events, notifications, dashboard, loading, errors, refresh } = useStudentData();
  const todayClasses = classes.filter((item) => item.todaySchedule);
  const upcoming = events.filter((event) => {
    const start = new Date(event.startTime);
    return !Number.isNaN(start.valueOf()) && start >= new Date() && event.registrationStatus !== 'notRegistered';
  }).slice(0, 3);
  const stats = [
    { label: 'Lớp đang tham gia', value: classes.length, icon: BookOpen, color: 'blue' },
    { label: 'Sự kiện sắp tới', value: upcoming.length, icon: Sparkles, color: 'violet' },
    { label: 'Có mặt', value: dashboard.present ?? 0, icon: Check, color: 'green' },
    { label: 'Tỉ lệ chuyên cần', value: Number(dashboard.present || 0) + Number(dashboard.late || 0) + Number(dashboard.absent || 0) > 0 ? `${Math.round(100 * Number(dashboard.present || 0) / (Number(dashboard.present || 0) + Number(dashboard.late || 0) + Number(dashboard.absent || 0)))}%` : '—', icon: Activity, color: 'amber' },
  ];
  return <>
    <PageHeading eyebrow="THỨ HẠNG CỦA BẠN, HÀNH TRÌNH CỦA BẠN" title="Tổng quan" description={`${new Intl.DateTimeFormat('vi-VN', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date())} · Chào ${nameOf(user)}, chúc bạn một ngày học tập hiệu quả!`} actions={<button className="outline-button" onClick={refresh}><Activity size={16} /> Làm mới</button>} />
    <LoadError errors={errors} onRetry={refresh} />
    <div className="welcome-banner"><div className="welcome-copy"><span className="welcome-tag"><Sparkles size={14} /> KHÔNG GIAN CỦA BẠN</span><h2>Xin chào, {nameOf(user).split(' ').slice(-1)[0]} <span>✦</span></h2><p>Theo dõi lịch học, khám phá sự kiện và lưu lại từng cột mốc đáng nhớ.</p><button className="banner-button" onClick={() => goTo('calendar')}>Xem lịch của tôi <ArrowRight size={16} /></button></div><div className="welcome-illustration"><div className="illustration-ring ring-a" /><div className="illustration-ring ring-b" /><div className="illustration-cap"><GraduationCap size={75} strokeWidth={1.25} /></div><span className="float-star star-a">✦</span><span className="float-star star-b">✧</span><span className="float-dot dot-a" /><span className="float-dot dot-b" /></div></div>
    <div className="stats-grid">{stats.map(({ label, value, icon: Icon, color }) => <article className="stat-card" key={label}><div className={`stat-icon ${color}`}><Icon size={19} /></div><div><span>{label}</span><strong>{loading ? '—' : value}</strong></div><div className={`stat-spark ${color}`}>↗</div></article>)}</div>
    {!loading && Number(dashboard.present || 0) + Number(dashboard.late || 0) + Number(dashboard.absent || 0) > 0 && <AttendanceDonutChart title="Kết quả điểm danh" data={[{ label: 'Có mặt', value: Number(dashboard.present || 0), color: '#28a76c' }, { label: 'Đi muộn', value: Number(dashboard.late || 0), color: '#e7a639' }, { label: 'Vắng', value: Number(dashboard.absent || 0), color: '#d95d54' }]} />}
    {notifications.length > 0 && <button className="active-session-banner" onClick={() => goTo('attendance')}><span className="pulse-dot" /><span><strong>{notifications.length} phiên điểm danh đang mở</strong><small>Chuyển sang ứng dụng Android để thực hiện điểm danh.</small></span><ArrowRight size={18} /></button>}
    <div className="dashboard-grid">
      <section className="panel-card"><div className="section-title"><div><h2>Lịch học hôm nay</h2><p>Các lớp có lịch trong ngày</p></div><button className="text-button" onClick={() => goTo('classes')}>Tất cả lớp <ArrowRight size={15} /></button></div>
        {loading ? <LoadingLine /> : todayClasses.length ? <div className="schedule-list">{todayClasses.slice(0, 4).map((item, index) => <div className="schedule-item" key={item.id}><div className={`schedule-time tone-${index % 4}`}>{item.todaySchedule.split(' ').slice(-1)[0] || 'Hôm nay'}</div><div className="schedule-detail"><strong>{item.name}</strong><span>{item.lecturer || 'Chưa có giảng viên'} · {item.room || 'Chưa có phòng'}</span></div><span className="status-tag blue-tag">Hôm nay</span></div>)}</div> : <EmptyState icon={CalendarDays} title="Hôm nay chưa có lịch học" text="Bạn có thể xem lịch học của mình trong tuần." action={() => goTo('calendar')} actionLabel="Mở lịch" />}
      </section>
      <section className="panel-card"><div className="section-title"><div><h2>Sự kiện của bạn</h2><p>Những hoạt động sắp diễn ra</p></div><button className="text-button" onClick={() => goTo('events')}>Khám phá <ArrowRight size={15} /></button></div>
        {loading ? <LoadingLine /> : upcoming.length ? <div className="event-mini-list">{upcoming.map((event) => <div className="event-mini" key={event.id}><div className="event-date-tile"><strong>{new Date(event.startTime).getDate()}</strong><span>TH{new Date(event.startTime).getMonth() + 1}</span></div><div className="event-mini-info"><strong>{event.name}</strong><span><Clock3 size={13} /> {formatTime(event.startTime)}</span><span><MapPin size={13} /> {event.location || 'Đang cập nhật địa điểm'}</span></div><span className="status-tag green-tag">Đã đăng ký</span></div>)}</div> : <EmptyState icon={Sparkles} title="Chưa có sự kiện sắp tới" text="Khám phá các hoạt động đang mở đăng ký." action={() => goTo('events')} actionLabel="Xem sự kiện" />}
      </section>
    </div>
    <div className="bottom-hint"><ShieldCheck size={16} /> Mọi thông tin được đồng bộ trực tiếp từ tài khoản sinh viên của bạn.</div>
  </>;
}

function ClassesPage({ showNotice }) {
  const { classes, loading, errors, refresh } = useStudentData();
  const [query, setQuery] = useState('');
  const [joinCode, setJoinCode] = useState('');
  const [joining, setJoining] = useState(false);
  const [selected, setSelected] = useState(null);
  const [detail, setDetail] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [modalError, setModalError] = useState('');
  const filtered = classes.filter((item) => `${item.name} ${item.code} ${item.lecturer}`.toLowerCase().includes(query.toLowerCase()));
  const openClass = async (item) => {
    setSelected(item); setDetail(null); setModalError(''); setDetailLoading(true);
    try { setDetail(await api(`/api/classes/${encodeURIComponent(item.id)}/detail`)); }
    catch (error) { setModalError(getApiMessage(error)); }
    finally { setDetailLoading(false); }
  };
  const joinClass = async (event) => {
    event.preventDefault(); setJoining(true);
    try {
      const result = await api('/api/classes/join', { method: 'POST', body: { classCode: joinCode.trim() } });
      showNotice('success', result.message || 'Tham gia lớp thành công.');
      setJoinCode(''); await refresh();
    } catch (error) { showNotice('error', getApiMessage(error)); }
    finally { setJoining(false); }
  };
  return <>
    <PageHeading eyebrow="HỌC TẬP" title="Lớp học của tôi" description="Quản lý các lớp học phần và theo dõi tình hình học tập." actions={<button className="outline-button" onClick={refresh}><Activity size={16} /> Làm mới</button>} />
    <LoadError errors={errors} onRetry={refresh} />
    <form className="join-class-form" onSubmit={joinClass}><div className="join-icon"><Plus size={19} /></div><div className="join-copy"><strong>Tham gia lớp học</strong><span>Nhập mã lớp do giảng viên cung cấp.</span></div><input value={joinCode} onChange={(event) => setJoinCode(event.target.value)} placeholder="Nhập mã lớp" required aria-label="Mã lớp" /><button className="primary-button" disabled={joining}>{joining ? 'Đang tham gia...' : 'Tham gia lớp'}</button></form>
    <div className="toolbar"><div className="search-box"><Search size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Tìm theo tên lớp hoặc giảng viên..." /></div><span className="result-count">{loading ? 'Đang tải...' : `${filtered.length} lớp học`}</span></div>
    {!loading && filtered.some((item) => Number(item.present || 0) + Number(item.late || 0) + Number(item.absent || 0) > 0) && <AttendanceBarChart title="Kết quả điểm danh theo lớp" categories={filtered.map((item) => item.id || item.code)} series={[{ label: 'Có mặt', color: '#28a76c', values: filtered.map((item) => Number(item.present || 0)) }, { label: 'Đi muộn', color: '#e7a639', values: filtered.map((item) => Number(item.late || 0)) }, { label: 'Vắng', color: '#d95d54', values: filtered.map((item) => Number(item.absent || 0)) }]} />}
    {loading ? <LoadingGrid /> : filtered.length ? <div className="class-grid">{filtered.map((item, index) => <button className="class-card" key={item.id} onClick={() => openClass(item)}><div className={`class-card-art art-${index % 4}`}><span className="class-code">{item.id}</span><BookOpen size={42} strokeWidth={1.2} /><span className="art-label">HỌC PHẦN</span></div><div className="class-card-body"><div className="card-title-row"><h3>{item.name}</h3><ArrowRight size={17} /></div><p><GraduationCap size={14} /> {item.lecturer || 'Chưa cập nhật giảng viên'}</p><p><Clock3 size={14} /> {item.time || 'Chưa có lịch học'}</p><div className="class-card-footer"><span>{item.room ? <><MapPin size={13} /> {item.room}</> : 'Lớp học phần'}</span><span className="progress-caption">{item.rate || 0}% chuyên cần</span></div><div className="progress-track"><span style={{ width: `${Math.min(100, Number(item.rate) || 0)}%` }} /></div></div></button>)}</div> : <EmptyState icon={BookOpen} title={query ? 'Không tìm thấy lớp phù hợp' : 'Bạn chưa tham gia lớp học nào'} text={query ? 'Thử từ khóa khác để tìm lớp học.' : 'Nhập mã lớp ở trên để tham gia lớp học phần của bạn.'} />}
    {selected && <Modal title="Chi tiết lớp học" onClose={() => setSelected(null)}>
      <div className="detail-title">
        <span className="class-code-badge">{selected.id}</span>
        <div><h3>{detail?.class?.name || selected.name}</h3><p>{detail?.class?.lecturerName || selected.lecturer || 'Lớp học phần'}</p></div>
      </div>
      {detailLoading ? <LoadingLine /> : modalError ? <div className="alert error">{modalError}</div> : detail && <>
        <div className="detail-grid">
          <Info label="Học kỳ" value={`${detail.class.semester || '—'} ${detail.class.academicYear || ''}`} />
          <Info label="Số tín chỉ" value={detail.class.credits || '—'} />
          <Info label="Sĩ số" value={`${detail.class.studentCount || 0}${detail.class.capacity ? ` / ${detail.class.capacity}` : ''} sinh viên`} />
          <Info label="Trạng thái" value={detail.class.status || 'Chưa cập nhật'} />
          <Info label="Đơn vị" value={detail.class.departmentName || '—'} />
          <Info label="Môn học" value={detail.class.subjectName || '—'} />
        </div>
        <h4 className="modal-section-title">Lịch học và phòng học</h4>
        {detail.schedules?.length ? detail.schedules.map((schedule) => <div className="modal-list-row" key={schedule.id}><CalendarDays size={16} /><span>Thứ {schedule.weekday} · {schedule.startTime} – {schedule.endTime}</span><span>{schedule.room || 'Chưa xếp phòng'}</span></div>) : <p className="muted-text">Lớp chưa được xếp lịch học.</p>}
        <h4 className="modal-section-title">Kết quả điểm danh từng buổi</h4>
        <div className="attendance-history">
          {detail.attendanceSessions?.length ? detail.attendanceSessions.slice(0, 8).map((session) => <div className="history-row" key={session.id}><span>{session.name || 'Buổi học'} · {session.startTime}</span><span className={`status-tag ${session.status === 'Có mặt' ? 'green-tag' : session.status === 'Vắng mặt' ? 'red-tag' : 'amber-tag'}`}>{session.status}</span></div>) : <p className="muted-text">Chưa có buổi điểm danh nào.</p>}
        </div>
        <p className="modal-footnote"><Activity size={14} /> Muốn điểm danh cho buổi đang mở? Hãy chuyển sang ứng dụng Android.</p>
        <h4 className="modal-section-title">Danh sách sinh viên ({detail.students?.length || 0})</h4>
        <div className="roster-list">
          {detail.students?.length ? detail.students.map((student) => {
            const studentName = student.studentName || student.studentId || '?';
            return <div className="roster-row" key={student.studentId}>
              <span className="roster-avatar">{studentName[0].toUpperCase()}</span>
              <span className="roster-name"><strong>{studentName}</strong><small>{student.studentId}</small></span>
              {student.status && <span className="status-tag blue-tag">{student.status}</span>}
            </div>;
          }) : <p className="muted-text">Lớp chưa có sinh viên.</p>}
        </div>
        <ClassFeedback classId={selected.id} showNotice={showNotice} />
      </>}
    </Modal>}
  </>;
}

function ClassFeedback({ classId, showNotice }) {
  const [summary, setSummary] = useState(null);
  const [mode, setMode] = useState('');
  const [rating, setRating] = useState(0);
  const [comment, setComment] = useState('');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;
    api(`/api/classes/${encodeURIComponent(classId)}/feedback`)
      .then((result) => { if (active) setSummary(result); })
      .catch((exception) => { if (active) setError(getApiMessage(exception)); });
    return () => { active = false; };
  }, [classId]);

  const submit = async (event) => {
    event.preventDefault();
    setError('');
    if (mode === 'rating' && !rating) { setError('Vui lòng chọn số sao.'); return; }
    if (mode === 'feedback' && !comment.trim()) { setError('Vui lòng nhập nội dung phản hồi.'); return; }
    setSaving(true);
    try {
      await api(`/api/classes/${encodeURIComponent(classId)}/feedback`, {
        method: 'POST', body: mode === 'rating' ? { rating, comment: comment.trim() } : { comment: comment.trim() },
      });
      setSummary(await api(`/api/classes/${encodeURIComponent(classId)}/feedback`));
      setMode(''); setComment(''); setRating(0);
      showNotice('success', mode === 'rating' ? 'Đã gửi đánh giá lớp học.' : 'Đã gửi phản hồi lớp học.');
    } catch (exception) {
      setError(getApiMessage(exception));
    } finally {
      setSaving(false);
    }
  };

  return <section className="feedback-panel"><h4 className="modal-section-title">Đánh giá & phản hồi lớp học</h4><p className="feedback-summary">{summary?.ratingCount ? `${Number(summary.averageRating).toFixed(1)} / 5 sao · ${summary.ratingCount} lượt đánh giá` : 'Chưa có lượt đánh giá.'}</p><FeedbackEntryList items={summary?.items || []} />{error && <div className="alert error">{error}</div>}{mode ? <form onSubmit={submit} className="feedback-form">{mode === 'rating' && <div className="rating-stars" role="group" aria-label="Chọn số sao">{[1, 2, 3, 4, 5].map((value) => <button type="button" key={value} className={value <= rating ? 'chosen' : ''} aria-label={`${value} sao`} onClick={() => setRating(value)}>★</button>)}</div>}<label>{mode === 'rating' ? 'Nhận xét thêm' : 'Nội dung phản hồi'}<textarea value={comment} maxLength={2000} onChange={(event) => setComment(event.target.value)} placeholder="Chia sẻ ý kiến của bạn..." required={mode === 'feedback'} /></label><div className="feedback-actions"><button type="button" className="text-button" onClick={() => { setMode(''); setError(''); }}>Hủy</button><button className="primary-button compact" disabled={saving}>{saving ? 'Đang gửi...' : 'Gửi'}</button></div></form> : <div className="feedback-actions"><button className="outline-button compact" onClick={() => setMode('feedback')}>Gửi phản hồi</button><button className="outline-button compact" onClick={() => setMode('rating')}>Đánh giá</button></div>}</section>;
}

function EventsPage({ showNotice }) {
  const { events, loading, errors, refresh } = useStudentData();
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState(null);
  const [details, setDetails] = useState(null);
  const [detailsLoading, setDetailsLoading] = useState(false);
  const [busyId, setBusyId] = useState('');
  const [feedbackVersion, setFeedbackVersion] = useState(0);
  const [filter, setFilter] = useState('all');
  const filtered = useMemo(() => events.filter((event) => {
    const matchesQuery = `${event.name} ${event.organizerName} ${event.location}`.toLowerCase().includes(query.toLowerCase());
    const matchesFilter = filter === 'all' || (filter === 'registered' ? event.registrationStatus !== 'notRegistered' : event.registrationStatus === 'notRegistered');
    return matchesQuery && matchesFilter;
  }), [events, query, filter]);
  const openEvent = async (event) => {
    setSelected(event); setDetails(null); setDetailsLoading(true);
    try { setDetails(await api(`/api/events/${encodeURIComponent(event.id)}`)); }
    catch (error) { showNotice('error', getApiMessage(error)); }
    finally { setDetailsLoading(false); }
  };
  const register = async (event, allowClassConflict = false) => {
    setBusyId(event.id);
    try {
      const result = await api(`/api/events/${encodeURIComponent(event.id)}/register`, { method: 'POST', body: { allowClassConflict } });
      showNotice('success', result.message || 'Đăng ký sự kiện thành công.');
      await refresh();
      if (selected?.id === event.id) setSelected(null);
    } catch (error) {
      if (error.data?.type === 'class_schedule_conflict' && window.confirm(`${error.message}\n\nBạn có chắc chắn muốn vẫn đăng ký?`)) {
        await register(event, true);
        return;
      }
      showNotice('error', getApiMessage(error));
    } finally { setBusyId(''); }
  };
  const cancel = async (event) => {
    if (!window.confirm('Bạn muốn hủy đăng ký sự kiện này?')) return;
    setBusyId(event.id);
    try {
      const result = await api(`/api/events/${encodeURIComponent(event.id)}/register`, { method: 'DELETE' });
      showNotice('success', result.message || 'Đã hủy đăng ký sự kiện.');
      await refresh(); setSelected(null);
    } catch (error) { showNotice('error', getApiMessage(error)); }
    finally { setBusyId(''); }
  };
  return <>
    <PageHeading eyebrow="HOẠT ĐỘNG SINH VIÊN" title="Sự kiện & hoạt động" description="Khám phá hoạt động trong trường và đăng ký tham gia." actions={<button className="outline-button" onClick={refresh}><Activity size={16} /> Làm mới</button>} />
    <LoadError errors={errors} onRetry={refresh} />
    <div className="toolbar event-toolbar"><div className="search-box"><Search size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Tìm sự kiện, địa điểm..." /></div><div className="filter-tabs"><button className={filter === 'all' ? 'selected' : ''} onClick={() => setFilter('all')}>Tất cả</button><button className={filter === 'registered' ? 'selected' : ''} onClick={() => setFilter('registered')}>Đã đăng ký</button><button className={filter === 'open' ? 'selected' : ''} onClick={() => setFilter('open')}>Có thể đăng ký</button></div></div>
    {loading ? <LoadingGrid /> : filtered.length ? <div className="event-grid">{filtered.map((event, index) => {
      const registered = event.registrationStatus !== 'notRegistered';
      const ended = event.status === 'Đã đóng' || (event.endTime && new Date(event.endTime) < new Date());
      return <article className="event-card" key={event.id}><button className={`event-cover cover-${index % 4}${event.imageUrl ? ' has-image' : ''}`} aria-label={`Xem chi tiết: ${event.name}`} onClick={() => openEvent(event)}>{event.imageUrl && <img className="event-cover-image" src={event.imageUrl} alt="" loading="lazy" onError={(error) => { error.currentTarget.hidden = true; }} />}{event.imageUrl && <span className="event-cover-shade" />}<span className="event-cover-kicker">HUIT · HOẠT ĐỘNG SINH VIÊN</span>{!event.imageUrl && <Sparkles size={43} strokeWidth={1.1} />}<span className="event-date-label">{formatDate(event.startTime)}</span></button><div className="event-card-content"><div className="event-title-line"><h3>{event.name}</h3>{registered && <span className="status-tag green-tag">Đã đăng ký</span>}</div><p className="event-organizer">{event.organizerName || 'Đơn vị tổ chức HUIT'}</p><div className="event-meta"><span><Clock3 size={14} /> {formatTime(event.startTime)}</span><span><MapPin size={14} /> {event.location || 'Đang cập nhật địa điểm'}</span></div><div className="event-card-actions"><button className="text-button" onClick={() => openEvent(event)}>Xem chi tiết</button>{registered ? <button className="outline-button compact" onClick={() => cancel(event)} disabled={busyId === event.id || ended}>{busyId === event.id ? 'Đang xử lý...' : 'Hủy đăng ký'}</button> : <button className="primary-button compact" onClick={() => register(event)} disabled={busyId === event.id || ended}>{busyId === event.id ? 'Đang đăng ký...' : ended ? 'Đã kết thúc' : 'Đăng ký'}</button>}</div></div></article>;
    })}</div> : <EmptyState icon={Sparkles} title="Chưa có sự kiện phù hợp" text={query ? 'Thử điều chỉnh bộ lọc hoặc từ khóa.' : 'Các sự kiện mới sẽ xuất hiện tại đây.'} />}
    {selected && <Modal title="Thông tin sự kiện" onClose={() => setSelected(null)}><div className={`event-detail-cover${selected.imageUrl ? ' has-image' : ''}`}>{selected.imageUrl && <img className="event-detail-image" src={selected.imageUrl} alt="" onError={(error) => { error.currentTarget.hidden = true; }} />}{selected.imageUrl && <span className="event-detail-shade" />}{!selected.imageUrl && <Sparkles size={37} />}<span>{selected.id}</span></div>{detailsLoading ? <LoadingLine /> : details ? <><div className="event-detail-heading"><h3>{details.name || selected.name}</h3><span className={`status-tag ${selected.registrationStatus !== 'notRegistered' ? 'green-tag' : 'blue-tag'}`}>{selected.registrationStatus !== 'notRegistered' ? 'Đã đăng ký' : 'Chưa đăng ký'}</span></div><p className="event-description">{details.description || 'Chưa có mô tả cho sự kiện này.'}</p><div className="detail-grid"><Info label="Đơn vị tổ chức" value={details.organizerName || selected.organizerName || '—'} /><Info label="Thời gian" value={`${formatTime(details.startTime)} – ${formatDate(details.endTime, { hour: '2-digit', minute: '2-digit' })}`} /><Info label="Địa điểm" value={details.location || 'Chưa cập nhật'} /><Info label="Số lượng đăng ký" value={`${details.registeredCount || 0}${details.capacity ? ` / ${details.capacity}` : ''}`} /></div>{details.benefits?.length > 0 && <><h4 className="modal-section-title">Quyền lợi</h4>{details.benefits.map((benefit, index) => <div className="modal-list-row" key={index}><Check size={16} />{benefit.content || benefit.type}</div>)}</>}{details.rules?.length > 0 && <><h4 className="modal-section-title">Nội quy</h4>{details.rules.map((rule, index) => <div className="modal-list-row" key={index}><span className="rule-number">{index + 1}</span>{rule.text || rule.content}</div>)}</>}{selected.registrationStatus !== 'notRegistered' && <p className="modal-footnote"><Activity size={14} /> Điểm danh sự kiện chỉ thực hiện trên ứng dụng Android.</p>}{selected.registrationStatus !== 'notRegistered' && (selected.status === 'Đã đóng' || (selected.endTime && new Date(selected.endTime) <= new Date())) && <EventFeedback key={`${selected.id}-${feedbackVersion}`} eventId={selected.id} showNotice={showNotice} onSaved={() => setFeedbackVersion((version) => version + 1)} />}<div className="modal-actions">{selected.registrationStatus !== 'notRegistered' ? <button className="outline-button" onClick={() => cancel(selected)} disabled={busyId === selected.id || (selected.endTime && new Date(selected.endTime) <= new Date())}>{busyId === selected.id ? 'Đang xử lý...' : 'Hủy đăng ký'}</button> : <button className="primary-button" onClick={() => register(selected)} disabled={busyId === selected.id || (selected.endTime && new Date(selected.endTime) <= new Date())}>{busyId === selected.id ? 'Đang xử lý...' : (selected.endTime && new Date(selected.endTime) <= new Date()) ? 'Đã kết thúc' : 'Đăng ký sự kiện'}</button>}</div></> : <div className="muted-text">Không thể tải thông tin sự kiện.</div>}</Modal>}
  </>;
}

function EventFeedback({ eventId, showNotice, onSaved }) {
  const [summary, setSummary] = useState(null);
  const [mode, setMode] = useState('');
  const [rating, setRating] = useState(0);
  const [comment, setComment] = useState('');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    api(`/api/events/${encodeURIComponent(eventId)}/feedback`)
      .then((result) => { if (active) setSummary(result); })
      .catch((exception) => { if (active) setError(getApiMessage(exception)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [eventId]);

  const submit = async (event) => {
    event.preventDefault();
    setError('');
    if (mode === 'rating' && !rating) { setError('Vui lòng chọn số sao.'); return; }
    if (mode === 'feedback' && !comment.trim()) { setError('Vui lòng nhập nội dung phản hồi.'); return; }
    setSaving(true);
    try {
      await api(`/api/events/${encodeURIComponent(eventId)}/feedback`, {
        method: 'POST',
        body: mode === 'rating' ? { rating, comment: comment.trim() } : { comment: comment.trim() },
      });
      const updated = await api(`/api/events/${encodeURIComponent(eventId)}/feedback`);
      setSummary(updated); setMode(''); setComment(''); setRating(0); onSaved();
      showNotice('success', mode === 'rating' ? 'Đã gửi đánh giá.' : 'Đã gửi phản hồi.');
    } catch (exception) { setError(getApiMessage(exception)); }
    finally { setSaving(false); }
  };

  return <section className="feedback-panel">
    <h4 className="modal-section-title">Đánh giá & phản hồi</h4>
    {!loading && summary && <><p className="feedback-summary">{summary.ratingCount ? `${Number(summary.averageRating).toFixed(1)} / 5 sao · ${summary.ratingCount} lượt đánh giá` : 'Chưa có lượt đánh giá.'}</p><FeedbackEntryList items={summary.items || []} /></>}
    {error && <div className="alert error">{error}</div>}
    {mode ? <form onSubmit={submit} className="feedback-form">
      {mode === 'rating' && <div className="rating-stars" role="group" aria-label="Chọn số sao">{[1, 2, 3, 4, 5].map((value) => <button type="button" key={value} className={value <= rating ? 'chosen' : ''} aria-label={`${value} sao`} onClick={() => setRating(value)}>★</button>)}</div>}
      <label>{mode === 'rating' ? 'Nhận xét thêm (không bắt buộc)' : 'Nội dung phản hồi'}<textarea value={comment} maxLength={2000} onChange={(event) => setComment(event.target.value)} placeholder="Chia sẻ cảm nhận của bạn..." required={mode === 'feedback'} /></label>
      <div className="feedback-actions"><button type="button" className="text-button" onClick={() => { setMode(''); setError(''); }}>Hủy</button><button className="primary-button compact" disabled={saving}>{saving ? 'Đang gửi...' : 'Gửi'}</button></div>
    </form> : <div className="feedback-actions"><button className="outline-button compact" onClick={() => setMode('feedback')}>Gửi phản hồi</button><button className="outline-button compact" onClick={() => setMode('rating')}>★ Đánh giá</button></div>}
  </section>;
}

function FeedbackEntryList({ items }) {
  const [selected, setSelected] = useState(null);
  if (!items.length) return null;
  return <><div className="feedback-entry-list">{items.slice(0, 5).map((item, index) => <button className="feedback-entry" key={item.id || index} onClick={() => setSelected(item)}><span>{item.rating ? `${'★'.repeat(Math.max(0, Math.min(5, Number(item.rating))) )} ` : ''}{item.comment || item.content || 'Đã gửi phản hồi'}</span><small>{item.createdAt ? formatDate(item.createdAt) : ''}</small></button>)}</div>{selected && <Modal title={selected.rating ? 'Chi tiết đánh giá' : 'Chi tiết phản hồi'} onClose={() => setSelected(null)}><div className="detail-grid">{selected.rating && <Info label="Đánh giá" value={`${selected.rating} / 5 sao`} />}<Info label="Thời gian" value={formatDate(selected.createdAt)} /></div><p className="feedback-entry-detail">{selected.comment || selected.content || 'Không có nội dung.'}</p></Modal>}</>;
}

function CalendarPage() {
  const { calendar, events, loading, errors, refresh } = useStudentData();
  const [weekOffset, setWeekOffset] = useState(0);
  const [mode, setMode] = useState('week');
  const start = new Date();
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7) + weekOffset * 7);
  start.setHours(0, 0, 0, 0);
  const weekDays = Array.from({ length: 7 }, (_, index) => {
    const day = new Date(start); day.setDate(start.getDate() + index); return day;
  });
  const classEvents = calendar.flatMap((item) => (item.schedules || []).map((schedule) => ({ type: 'class', name: item.name, subject: item.subjectName, lecturer: item.lecturerName, ...schedule })));
  const itemsForDay = (day) => {
    const weekday = ((day.getDay() + 6) % 7) + 1;
    const classesForDay = classEvents.filter((item) => item.weekday === weekday && (!item.startsOn || new Date(item.startsOn) <= day) && (!item.endsOn || new Date(item.endsOn) >= day));
    const eventsForDay = events.filter((event) => {
      if (event.registrationStatus === 'notRegistered') return false;
      const date = new Date(event.startTime);
      return !Number.isNaN(date.valueOf()) && date.toDateString() === day.toDateString();
    }).map((event) => ({ type: 'event', name: event.name, startTime: new Date(event.startTime).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' }), room: event.location }));
    return [...classesForDay, ...eventsForDay];
  };
  const rangeLabel = `${formatDate(weekDays[0])} – ${formatDate(weekDays[6])}`;
  const agendaItems = weekDays.flatMap((day) => itemsForDay(day).map((item, index) => ({
    ...item,
    day,
    key: `${day.toISOString()}-${index}`,
  })));
  const weekContent = (
    <div className="week-grid">
      {weekDays.map((day) => {
        const dayItems = itemsForDay(day);
        const isToday = day.toDateString() === new Date().toDateString();
        return (
          <div className={`week-day ${isToday ? 'is-today' : ''}`} key={day.toISOString()}>
            <div className="week-day-heading">
              <span>{new Intl.DateTimeFormat('vi-VN', { weekday: 'short' }).format(day)}</span>
              <strong>{day.getDate()}</strong>
            </div>
            <div className="week-day-items">
              {dayItems.map((item, index) => (
                <div className={`calendar-event ${item.type}`} key={`${item.name}-${index}`}>
                  <strong>{item.name}</strong>
                  <span>{item.startTime}</span>
                  {item.room && <small>{item.room}</small>}
                </div>
              ))}
              {!dayItems.length && <span className="empty-day">—</span>}
            </div>
          </div>
        );
      })}
    </div>
  );
  const agendaContent = (
    <div className="agenda-list">
      {agendaItems.map((item) => (
        <div className="agenda-item" key={item.key}>
          <div className="agenda-date">
            <strong>{item.day.getDate()}</strong>
            <span>{new Intl.DateTimeFormat('vi-VN', { weekday: 'short', month: 'short' }).format(item.day)}</span>
          </div>
          <div className={`agenda-icon ${item.type}`}><CalendarDays size={17} /></div>
          <div className="agenda-info">
            <strong>{item.name}</strong>
            <span>{item.subject || item.location || item.room || 'Lịch học'}</span>
          </div>
          <span className="agenda-time">{item.startTime || 'Cả ngày'}</span>
        </div>
      ))}
      {!agendaItems.length && <EmptyState icon={CalendarDays} title="Tuần này chưa có lịch" text="Lịch học và sự kiện của bạn sẽ hiển thị tại đây." />}
    </div>
  );
  return <>
    <PageHeading eyebrow="KẾ HOẠCH HỌC TẬP" title="Lịch của tôi" description="Lịch học phần và các hoạt động đã đăng ký." actions={<button className="outline-button" onClick={refresh}><Activity size={16} /> Làm mới</button>} />
    <LoadError errors={errors} onRetry={refresh} />
    <section className="panel-card calendar-panel">
      <div className="calendar-toolbar">
        <div className="calendar-switch">
          <button className="icon-button" onClick={() => setWeekOffset((offset) => offset - 1)} aria-label="Tuần trước"><ChevronLeft size={18} /></button>
          <button className="icon-button" onClick={() => setWeekOffset((offset) => offset + 1)} aria-label="Tuần sau"><ChevronRight size={18} /></button>
          <strong>{rangeLabel}</strong>
          <button className="text-button today-button" onClick={() => setWeekOffset(0)}>Hôm nay</button>
        </div>
        <div className="filter-tabs">
          <button className={mode === 'week' ? 'selected' : ''} onClick={() => setMode('week')}>Tuần</button>
          <button className={mode === 'agenda' ? 'selected' : ''} onClick={() => setMode('agenda')}>Danh sách</button>
        </div>
      </div>
      {loading ? <LoadingLine /> : mode === 'week' ? weekContent : agendaContent}
      <div className="calendar-legend"><span><i className="legend-dot class" /> Lịch học</span><span><i className="legend-dot event" /> Sự kiện</span></div>
    </section>
  </>;
}

function AttendancePage() {
  const [sessions, setSessions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const load = useCallback(async () => {
    setLoading(true); setError('');
    try { const result = await api('/api/notifications'); setSessions(result.items || []); }
    catch (exception) { setError(getApiMessage(exception)); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { load(); }, [load]);
  return <>
    <PageHeading eyebrow="ĐIỂM DANH AN TOÀN" title="Điểm danh trên Android" description="Để xác thực chính xác bằng QR, vị trí hoặc khuôn mặt, vui lòng dùng ứng dụng HUIT trên điện thoại Android." actions={<button className="outline-button" onClick={load}><Activity size={16} /> Kiểm tra phiên</button>} />
    <div className="android-hero"><div className="android-visual"><div className="phone-frame"><div className="phone-notch" /><div className="phone-screen"><div className="phone-logo"><img className="huit-logo" src="/huit-logo.jpg" alt="Logo HUIT" /></div><span>HUIT STUDENT</span><div className="phone-scan"><div className="scan-corner top-left" /><div className="scan-corner top-right" /><div className="scan-corner bottom-left" /><div className="scan-corner bottom-right" /><div className="scan-line" /></div><small>Đưa mã QR vào khung hình</small></div></div><div className="phone-orbit orbit-left" /><div className="phone-orbit orbit-right" /></div><div className="android-copy"><span className="welcome-tag"><ShieldCheck size={14} /> BẢO MẬT TRÊN THIẾT BỊ</span><h2>Điểm danh cần camera và vị trí của điện thoại</h2><p>Phiên bản web không kích hoạt quét QR, nhận diện khuôn mặt hoặc gửi yêu cầu điểm danh. Mở ứng dụng Android để sử dụng các chức năng này.</p><div className="android-steps"><div><span>01</span><p>Mở ứng dụng <strong>HUIT</strong> trên điện thoại Android.</p></div><div><span>02</span><p>Chọn lớp học hoặc sự kiện cần điểm danh.</p></div><div><span>03</span><p>Quét mã QR hoặc chọn phương thức được yêu cầu.</p></div></div></div></div>
    <section className="panel-card active-attendance-panel"><div className="section-title"><div><h2>Phiên điểm danh đang mở</h2><p>Thông tin phiên hiện tại dành cho tài khoản của bạn</p></div><span className="live-label"><i /> TRỰC TIẾP</span></div>{error && <div className="alert error">{error}</div>}{loading ? <LoadingLine /> : sessions.length ? <div className="active-session-list">{sessions.map((session) => <div className="active-session-row" key={session.sessionId}><span className="active-session-icon"><Activity size={18} /></span><div><strong>{session.className || `Lớp ${session.classId}`}</strong><p>{session.content || 'Phiên điểm danh'} · {session.method || 'QR'}{session.closesAt ? ` · Đóng lúc ${formatTime(session.closesAt)}` : ''}</p></div><span className="status-tag green-tag">Đang mở</span></div>)}</div> : <EmptyState icon={Check} title="Hiện không có phiên đang mở" text="Khi giảng viên mở phiên, thông tin sẽ xuất hiện tại đây." />}</section>
  </>;
}

function NotificationsPage({ goTo }) {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filter, setFilter] = useState('all');
  const [selected, setSelected] = useState(null);
  const [readIds, setReadIds] = useState(() => {
    try { return new Set(JSON.parse(localStorage.getItem('studentWebReadNotifications') || '[]')); }
    catch { return new Set(); }
  });
  const refresh = useCallback(async () => {
    setError('');
    try {
      const result = await api('/api/notifications');
      setItems(result.items || []);
    } catch (exception) {
      setError(getApiMessage(exception));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
    const timer = window.setInterval(refresh, 15000);
    return () => window.clearInterval(timer);
  }, [refresh]);

  useEffect(() => {
    localStorage.setItem('studentWebReadNotifications', JSON.stringify([...readIds]));
  }, [readIds]);

  const markRead = (id) => setReadIds((current) => new Set(current).add(id));
  const visible = items.filter((item) => filter !== 'unread' || !readIds.has(item.sessionId));

  return <>
    <PageHeading eyebrow="CẬP NHẬT TÀI KHOẢN" title="Thông báo" description="Các phiên điểm danh đang mở cho lớp bạn tham gia." actions={<button className="outline-button" onClick={refresh}><Activity size={16} /> Làm mới</button>} />
    <div className="filter-tabs"><button className={filter === 'all' ? 'selected' : ''} onClick={() => setFilter('all')}>Tất cả</button><button className={filter === 'unread' ? 'selected' : ''} onClick={() => setFilter('unread')}>Chưa đọc</button><button className={filter === 'important' ? 'selected' : ''} onClick={() => setFilter('important')}>Quan trọng</button></div>
    {items.some((item) => !readIds.has(item.sessionId)) && <button className="text-button" onClick={() => setReadIds(new Set(items.map((item) => item.sessionId)))}>Đánh dấu tất cả đã đọc</button>}
    {error && <div className="alert error">{error}</div>}
    {loading ? <LoadingLine /> : visible.length ? <div className="notification-list">{visible.map((item) => <button className={`notification-item ${readIds.has(item.sessionId) ? 'read' : ''}`} key={item.sessionId} onClick={() => { setSelected(item); markRead(item.sessionId); }}><span className="notification-icon"><Bell size={18} /></span><span className="notification-copy"><strong>Điểm danh lớp {item.classId} đã mở</strong><small>{item.content || 'Phiên điểm danh'} · {item.method || 'QR'} · {formatTime(item.createdAt)}</small></span><span className="status-tag amber-tag">Quan trọng</span></button>)}</div> : <EmptyState icon={Bell} title="Không có thông báo nào" text="Khi giảng viên mở phiên điểm danh, thông tin sẽ xuất hiện tại đây." />}
    {selected && <Modal title={`Điểm danh lớp ${selected.classId}`} onClose={() => setSelected(null)}><p>{selected.content || 'Phiên điểm danh'} đang mở bằng {selected.method || 'QR'}.</p><p className="modal-footnote">{selected.closesAt ? `Đóng lúc ${formatTime(selected.closesAt)}.` : ''} Điểm danh cần camera/vị trí trên thiết bị di động.</p><button className="primary-button" onClick={() => { setSelected(null); goTo('attendance'); }}>Xem hướng dẫn điểm danh <ArrowRight size={16} /></button></Modal>}
  </>;
}

function CertificatesPage({ showNotice }) {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [downloading, setDownloading] = useState('');
  const [selected, setSelected] = useState(null);
  const [previewUrl, setPreviewUrl] = useState('');
  const [previewLoading, setPreviewLoading] = useState(false);
  const openCertificate = async (item) => {
    setSelected(item); setPreviewUrl(''); setPreviewLoading(true);
    try {
      const blob = await api(`/api/student/certificates/${encodeURIComponent(item.id)}/pdf`, { responseType: 'blob' });
      setPreviewUrl(URL.createObjectURL(blob));
    } catch (exception) { showNotice('error', `Không thể mở chứng nhận: ${getApiMessage(exception)}`); }
    finally { setPreviewLoading(false); }
  };
  useEffect(() => () => { if (previewUrl) URL.revokeObjectURL(previewUrl); }, [previewUrl]);
  const load = useCallback(async () => {
    setLoading(true); setError('');
    try { const result = await api('/api/student/certificates'); setItems(result.items || []); }
    catch (exception) { setError(getApiMessage(exception)); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { load(); }, [load]);
  const download = async (item) => {
    setDownloading(item.id);
    try {
      const blob = await api(`/api/student/certificates/${encodeURIComponent(item.id)}/pdf`, { responseType: 'blob' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a'); link.href = url; link.download = `${String(item.id).replace(/[^A-Za-z0-9._-]/g, '_')}.pdf`; link.click(); URL.revokeObjectURL(url);
      showNotice('success', 'Chứng nhận đã được tải xuống.');
    } catch (exception) { showNotice('error', `Không thể tải chứng nhận: ${getApiMessage(exception)}`); }
    finally { setDownloading(''); }
  };
  return <>
    <PageHeading eyebrow="DẤU ẤN CỦA BẠN" title="Chứng nhận của tôi" description="Xem và tải về chứng nhận đã được cấp cho tài khoản của bạn." actions={<button className="outline-button" onClick={load}><Activity size={16} /> Làm mới</button>} />
    {error && <div className="alert error">{error}</div>}
    {loading ? <LoadingGrid /> : items.length ? <div className="certificate-grid">{items.map((item) => <article className="certificate-card certificate-card-open" key={item.id} role="button" tabIndex={0} onClick={() => openCertificate(item)} onKeyDown={(event) => event.key === 'Enter' && openCertificate(item)}><div className="certificate-art"><div className="certificate-seal"><ShieldCheck size={31} /></div><div className="certificate-lines"><span /><span /><span /></div><span className="certificate-caption">CERTIFICATE OF PARTICIPATION</span></div><div className="certificate-info"><span className="status-tag green-tag">Đã cấp</span><h3>{item.eventName || 'Chứng nhận sự kiện'}</h3><p>Mã chứng nhận: <strong>{item.id}</strong></p><p>Ngày cấp: {formatDate(item.issuedAt)}</p><button className="primary-button compact" onClick={(event) => { event.stopPropagation(); download(item); }} disabled={downloading === item.id}>{downloading === item.id ? <><span className="button-spinner" /> Đang tải...</> : <><Download size={15} /> Tải PDF</>}</button></div></article>)}</div> : <div className="panel-card"><EmptyState icon={ShieldCheck} title="Chưa có chứng nhận được cấp" text="Chứng nhận sự kiện sẽ được hiển thị tại đây sau khi ban tổ chức cấp." />{!loading && <button className="text-button centered-action" onClick={load}>Tải lại danh sách <ArrowRight size={15} /></button>}</div>}
    {selected && <Modal title="Chi tiết chứng nhận" onClose={() => { setSelected(null); setPreviewUrl(''); }}><div className="detail-grid"><Info label="Sự kiện" value={selected.eventName || 'Chứng nhận sự kiện'} /><Info label="Mã chứng nhận" value={selected.id} /><Info label="Ngày cấp" value={formatDate(selected.issuedAt)} /></div>{previewLoading ? <LoadingLine /> : previewUrl ? <iframe className="certificate-preview-frame" src={previewUrl} title={`Chứng nhận ${selected.id}`} /> : <div className="alert error">Không thể hiển thị ảnh chứng nhận.</div>}</Modal>}
  </>;
}

function ProfilePage({ user, onUserChange, onLogout, showNotice, darkMode, setDarkMode, goTo }) {
  const [form, setForm] = useState({
    email: user.email || '', phone: user.phone || '', address: user.address || '',
    birthDate: user.birthDate ? String(user.birthDate).slice(0, 10) : '',
    gender: user.gender || '', hometown: user.hometown || '',
  });
  const [saving, setSaving] = useState(false);
  const [changingPassword, setChangingPassword] = useState(false);
  const [password, setPassword] = useState({ currentPassword: '', newPassword: '', confirm: '' });
  const [profileError, setProfileError] = useState('');
  const [passwordError, setPasswordError] = useState('');
  const initials = initialsOf(nameOf(user));
  const updateForm = (field) => (event) => setForm((value) => ({ ...value, [field]: event.target.value }));
  const saveProfile = async (event) => {
    event.preventDefault(); setSaving(true); setProfileError('');
    try {
      const result = await api('/api/me', { method: 'PUT', body: form });
      if (!result.user) throw new Error('Máy chủ không trả về thông tin hồ sơ mới.');
      onUserChange(result.user); showNotice('success', 'Thông tin hồ sơ đã được cập nhật.');
    } catch (exception) { setProfileError(getApiMessage(exception)); }
    finally { setSaving(false); }
  };
  const savePassword = async (event) => {
    event.preventDefault(); setPasswordError('');
    if (password.newPassword.length < 8) { setPasswordError('Mật khẩu mới cần có ít nhất 8 ký tự.'); return; }
    if (password.newPassword !== password.confirm) { setPasswordError('Mật khẩu xác nhận không khớp.'); return; }
    setChangingPassword(true);
    try {
      const result = await api('/api/me?action=password', { method: 'PUT', body: { currentPassword: password.currentPassword, newPassword: password.newPassword } });
      setPassword({ currentPassword: '', newPassword: '', confirm: '' }); showNotice('success', result.message || 'Đổi mật khẩu thành công.');
    } catch (exception) { setPasswordError(getApiMessage(exception)); }
    finally { setChangingPassword(false); }
  };
  return <>
    <PageHeading eyebrow="TÀI KHOẢN" title="Hồ sơ cá nhân" description="Quản lý thông tin liên hệ và cài đặt tài khoản." />
    <div className="profile-layout"><div className="profile-main">
      <section className="panel-card profile-card"><div className="profile-banner"><div className="profile-avatar">{initials}</div><div><span className="welcome-tag"><ShieldCheck size={13} /> TÀI KHOẢN SINH VIÊN</span><h2>{nameOf(user)}</h2><p>{user.id || 'Mã sinh viên chưa cập nhật'} · {user.major || 'Sinh viên HUIT'}</p></div></div>
        <form className="profile-form" onSubmit={saveProfile}><div className="section-title"><div><h2>Thông tin liên hệ</h2><p>Các trường bên dưới có thể được cập nhật.</p></div></div>{profileError && <div className="alert error">{profileError}</div>}<div className="form-grid"><label>Email<input type="email" value={form.email} onChange={updateForm('email')} required /></label><label>Số điện thoại<input type="tel" value={form.phone} onChange={updateForm('phone')} placeholder="Chưa cập nhật" /></label><label>Ngày sinh<input type="date" value={form.birthDate} onChange={updateForm('birthDate')} /></label><label>Giới tính<select value={form.gender} onChange={updateForm('gender')}><option value="">Chưa cập nhật</option><option>Nam</option><option>Nữ</option><option>Khác</option></select></label><label>Quê quán<input value={form.hometown} onChange={updateForm('hometown')} placeholder="Nhập quê quán" /></label><label>Địa chỉ hiện tại<input value={form.address} onChange={updateForm('address')} placeholder="Nhập địa chỉ" /></label></div><button className="primary-button" disabled={saving}>{saving ? 'Đang lưu...' : <>Lưu thay đổi <Check size={16} /></>}</button></form>
      </section>
      <section className="panel-card"><div className="section-title"><div><h2>Thông tin học tập</h2><p>Thông tin do nhà trường quản lý.</p></div></div><div className="detail-grid profile-study"><Info label="Mã sinh viên" value={user.id || '—'} /><Info label="Lớp" value={user.className || '—'} /><Info label="Chuyên ngành" value={user.major || '—'} /><Info label="Khoa / Trường" value={user.department || user.unit || 'HUIT'} /></div></section>
    </div><aside className="profile-side">
      <section className="panel-card account-card"><div className="side-card-icon"><ShieldCheck size={20} /></div><h3>Bảo mật tài khoản</h3><p>Thay đổi mật khẩu định kỳ để bảo vệ tài khoản của bạn.</p><form className="password-form" onSubmit={savePassword}>{passwordError && <div className="alert error">{passwordError}</div>}<label>Mật khẩu hiện tại<input type="password" autoComplete="current-password" value={password.currentPassword} onChange={(event) => setPassword((value) => ({ ...value, currentPassword: event.target.value }))} required /></label><label>Mật khẩu mới<input type="password" autoComplete="new-password" value={password.newPassword} onChange={(event) => setPassword((value) => ({ ...value, newPassword: event.target.value }))} required /></label><label>Nhập lại mật khẩu<input type="password" autoComplete="new-password" value={password.confirm} onChange={(event) => setPassword((value) => ({ ...value, confirm: event.target.value }))} required /></label><button className="outline-button full" disabled={changingPassword}>{changingPassword ? 'Đang cập nhật...' : 'Đổi mật khẩu'}</button></form></section>
      <section className="panel-card preferences-card"><h3>Tùy chỉnh</h3><button className="preference-row" onClick={() => setDarkMode((value) => !value)}><span className="pref-icon">{darkMode ? <Sun size={17} /> : <Moon size={17} />}</span><span><strong>Giao diện tối</strong><small>{darkMode ? 'Đang bật' : 'Đang tắt'}</small></span><span className={`toggle ${darkMode ? 'on' : ''}`} /></button><button className="preference-row" onClick={() => goTo('certificates')}><span className="pref-icon"><ShieldCheck size={17} /></span><span><strong>Chứng nhận của tôi</strong><small>Xem các chứng nhận đã cấp</small></span><ChevronRight size={17} /></button></section>
      <button className="logout-button" onClick={onLogout}><LogOut size={17} /> Đăng xuất tài khoản</button>
    </aside></div>
  </>;
}

function Modal({ title, onClose, children }) {
  useEffect(() => {
    const onKey = (event) => { if (event.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="modal-card" role="dialog" aria-modal="true" aria-label={title}><header className="modal-header"><h2>{title}</h2><button className="icon-button" onClick={onClose} aria-label="Đóng"><X size={19} /></button></header><div className="modal-content">{children}</div></section></div>;
}

function Info({ label, value }) {
  return <div className="info-cell"><span>{label}</span><strong>{value || '—'}</strong></div>;
}

function EmptyState({ icon: Icon, title, text, action, actionLabel }) {
  return <div className="empty-state"><div className="empty-icon"><Icon size={22} /></div><strong>{title}</strong><p>{text}</p>{action && <button className="text-button" onClick={action}>{actionLabel} <ArrowRight size={14} /></button>}</div>;
}

function LoadingLine() {
  return <div className="loading-state"><span className="spinner" /> Đang tải dữ liệu...</div>;
}

function LoadingGrid() {
  return <div className="loading-grid">{[1, 2, 3].map((item) => <div className="skeleton-card" key={item}><span /><span /><span /></div>)}</div>;
}
