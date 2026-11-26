import { useRef, useState } from 'react';
import { Download, Upload, X } from 'lucide-react';
import { api } from './api.js';

const HEADERS = {
  units: ['MaDV', 'TenDV', 'MaNhanVienPhuTrach'],
  users: [
    'MaND', 'HoTen', 'Email', 'MatKhau', 'VaiTro', 'TrangThai',
    'SDT', 'DiaChi', 'NgaySinh', 'GioiTinh', 'QueQuan',
    'Lop', 'MaKhoa', 'ChuyenNganh', 'BoMon', 'ChucVu',
  ],
};

const normalizeHeader = (value) => String(value || '')
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .toLowerCase()
  .replace(/[^a-z0-9]/g, '');

const cellText = (value) => {
  if (value instanceof Date && !Number.isNaN(value.valueOf())) {
    return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`;
  }
  return String(value ?? '').trim();
};

function rowToRecord(row, headers, aliases) {
  const record = {};
  for (const [field, candidates] of Object.entries(aliases)) {
    const column = headers.findIndex((header) => candidates.includes(header));
    record[field] = column < 0 ? '' : cellText(row[column]);
  }
  return record;
}

function parseSheet(sheet, kind, warnings) {
  if (!sheet) return [];
  const rows = sheet.data;
  const aliases = kind === 'units' ? {
    id: ['madv', 'maunit', 'unitid', 'unitcode'],
    name: ['tendv', 'tendonvi', 'unitname', 'name'],
    managerId: ['manhanvienphutrach', 'manv', 'managerid', 'employeeid'],
  } : {
    id: ['mand', 'mataikhoan', 'userid', 'usercode'],
    name: ['hoten', 'hovaten', 'fullname', 'name'],
    email: ['email'],
    password: ['matkhau', 'password'],
    role: ['vaitro', 'role'],
    status: ['trangthai', 'trangthaitaikhoan', 'status'],
    phone: ['sdt', 'sodienthoai', 'phone'],
    address: ['diachi', 'address'],
    birthDate: ['ngaysinh', 'birthdate'],
    gender: ['gioitinh', 'gender'],
    hometown: ['quequan', 'hometown'],
    className: ['lop', 'class'],
    cohortCode: ['makhoa', 'cohort', 'cohortcode'],
    major: ['chuyennganh', 'major'],
    subjectDepartment: ['bomon', 'subjectdepartment'],
    position: ['chucvu', 'position'],
  };
  const headerIndex = rows.findIndex((row) => {
    const headers = row.map(normalizeHeader);
    return kind === 'units'
      ? headers.some((header) => aliases.id.includes(header))
        && headers.some((header) => aliases.name.includes(header))
      : headers.some((header) => aliases.id.includes(header))
        && headers.some((header) => aliases.email.includes(header))
        && headers.some((header) => aliases.password.includes(header));
  });
  if (headerIndex < 0) {
    warnings.push(`Sheet ${sheet.sheet}: không tìm thấy hàng tiêu đề hợp lệ.`);
    return [];
  }
  const headers = rows[headerIndex].map(normalizeHeader);
  const records = [];
  const seenIds = new Set();
  const seenEmails = new Set();
  for (const [offset, row] of rows.slice(headerIndex + 1).entries()) {
    if (!row.some((cell) => String(cell ?? '').trim())) continue;
    const record = rowToRecord(row, headers, aliases);
    const line = headerIndex + offset + 2;
    const missing = kind === 'units'
      ? ['id', 'name'].filter((field) => !record[field])
      : ['id', 'name', 'email', 'password', 'role'].filter((field) => !record[field]);
    if (missing.length) {
      warnings.push(`${sheet.sheet} dòng ${line}: thiếu ${missing.join(', ')}; sẽ bỏ qua.`);
      continue;
    }
    const idKey = record.id.toLocaleLowerCase();
    if (seenIds.has(idKey)) {
      warnings.push(`${sheet.sheet} dòng ${line}: mã bị lặp trong file; sẽ bỏ qua.`);
      continue;
    }
    if (kind === 'users') {
      const role = normalizeHeader(record.role);
      const roleLabels = {
        sinhvien: 'Sinh viên',
        student: 'Sinh viên',
        giangvien: 'Giảng viên',
        lecturer: 'Giảng viên',
        canbo: 'Cán bộ',
        nhanvien: 'Cán bộ',
        employee: 'Cán bộ',
      };
      if (!roleLabels[role]) {
        warnings.push(`${sheet.sheet} dòng ${line}: vai trò không hợp lệ (không hỗ trợ Admin); sẽ bỏ qua.`);
        continue;
      }
      record.role = roleLabels[role];
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(record.email) || record.password.length < 8) {
        warnings.push(`${sheet.sheet} dòng ${line}: email không hợp lệ hoặc mật khẩu ngắn hơn 8 ký tự; sẽ bỏ qua.`);
        continue;
      }
      if ((record.role === 'Sinh viên' && (!record.className || !record.major))
        || (record.role === 'Giảng viên' && !record.subjectDepartment)
        || (record.role === 'Cán bộ' && !record.position)) {
        warnings.push(`${sheet.sheet} dòng ${line}: thiếu thông tin hồ sơ bắt buộc theo vai trò; sẽ bỏ qua.`);
        continue;
      }
      if (record.status && !['đang hoạt động', 'đã khóa'].includes(record.status.toLocaleLowerCase())) {
        warnings.push(`${sheet.sheet} dòng ${line}: trạng thái không hợp lệ; sẽ bỏ qua.`);
        continue;
      }
      const emailKey = record.email.toLocaleLowerCase();
      if (seenEmails.has(emailKey)) {
        warnings.push(`${sheet.sheet} dòng ${line}: email bị lặp trong file; sẽ bỏ qua.`);
        continue;
      }
      seenEmails.add(emailKey);
      record.passwordLength = record.password.length;
    }
    seenIds.add(idKey);
    records.push(record);
  }
  return records;
}

async function readMasterWorkbook(file, kind) {
  const { default: readExcelFile } = await import('read-excel-file/universal');
  const sheets = await readExcelFile(file);
  const expectedSheet = kind === 'units' ? 'donvi' : 'nguoidung';
  const sheet = sheets.find((item) => normalizeHeader(item.sheet) === expectedSheet);
  if (!sheet) throw new Error(`File cần có sheet ${kind === 'units' ? 'DonVi' : 'NguoiDung'} theo mẫu của trang này.`);
  const warnings = [];
  const result = {
    units: kind === 'units' ? parseSheet(sheet, 'units', warnings) : [],
    users: kind === 'users' ? parseSheet(sheet, 'users', warnings) : [],
    warnings,
  };
  if (!result.units.length && !result.users.length) {
    throw new Error(warnings.join('\n') || 'Không tìm thấy dữ liệu đơn vị hoặc tài khoản.');
  }
  return result;
}

export default function AdminMasterDataImport({ kind, onImported, showNotice }) {
  const inputRef = useRef(null);
  const [draft, setDraft] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const downloadTemplate = async () => {
    try {
      const { default: writeExcelFile } = await import('write-excel-file/universal');
      const workbook = await writeExcelFile([
        {
          sheet: kind === 'units' ? 'DonVi' : 'NguoiDung',
          data: [HEADERS[kind]],
        },
        {
          sheet: 'HuongDan',
          data: kind === 'units' ? [
            ['Sheet DonVi: MaDV và TenDV bắt buộc; MaNhanVienPhuTrach có thể để trống.'],
            ['Định dạng MaDV và MaNhanVienPhuTrach là Văn bản để giữ số 0 ở đầu.'],
            ['Mã đơn vị phải chưa tồn tại trong hệ thống.'],
          ] : [
            ['Sheet NguoiDung: MaND, HoTen, Email, MatKhau và VaiTro bắt buộc.'],
            ['VaiTro hợp lệ: Sinh viên, Giảng viên, Cán bộ. Không hỗ trợ tạo tài khoản Admin.'],
            ['Sinh viên cần điền Lop và ChuyenNganh; MaKhoa có thể để trống nếu Lop bắt đầu bằng mã khóa (ví dụ 26DHKTPM01). Giảng viên cần điền BoMon; Cán bộ cần điền ChucVu.'],
            ['MatKhau tối thiểu 8 ký tự; mật khẩu được mã hóa trước khi lưu. Trạng thái trống mặc định là Đang hoạt động.'],
            ['Định dạng MaND là Văn bản để giữ số 0 ở đầu. NgaySinh dùng dạng YYYY-MM-DD.'],
            ['Mã tài khoản và email phải chưa tồn tại trong hệ thống.'],
          ],
        },
      ]);
      const url = URL.createObjectURL(await workbook.toBlob());
      const link = document.createElement('a');
      link.href = url;
      link.download = kind === 'units'
        ? 'Mau_import_don_vi.xlsx'
        : 'Mau_import_nguoi_dung.xlsx';
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể tạo file mẫu Excel.');
    }
  };

  const selectWorkbook = async (event) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setBusy(true);
    setError('');
    try {
      setDraft(await readMasterWorkbook(file, kind));
    } catch (exception) {
      showNotice('error', exception instanceof Error ? exception.message : 'Không thể đọc file Excel.');
    } finally {
      setBusy(false);
    }
  };

  const confirmImport = async () => {
    if (!draft) return;
    setBusy(true);
    setError('');
    try {
      const result = await api('/api/admin/master-data/import', {
        method: 'POST',
        body: { units: draft.units, users: draft.users },
      });
      setDraft(null);
      const existingUsers = Array.isArray(result.existingUsers) ? result.existingUsers : [];
      const existingSummary = existingUsers.length
        ? ` Người dùng ${existingUsers.slice(0, 10).map((user) => `${user.name || user.id}${user.email ? ` (${user.email})` : ''}`).join(', ')} đã tồn tại${existingUsers.length > 10 ? ` và ${existingUsers.length - 10} người dùng khác` : ''}.`
        : '';
      showNotice(
        'success',
        kind === 'units'
          ? `Đã thêm ${result.importedUnits} đơn vị.`
          : `Đã thêm ${result.importedUsers} tài khoản.${existingSummary}`,
      );
      await onImported();
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Không thể nhập đơn vị và tài khoản.');
    } finally {
      setBusy(false);
    }
  };

  return <>
    <input ref={inputRef} type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={selectWorkbook} hidden />
    <button className="rp-secondary-button" type="button" onClick={downloadTemplate} disabled={busy}><Download size={16} /> Tải mẫu {kind === 'units' ? 'đơn vị' : 'người dùng'} Excel</button>
    <button className="rp-secondary-button" type="button" onClick={() => inputRef.current?.click()} disabled={busy}><Upload size={16} /> {busy ? 'Đang xử lý...' : `Import ${kind === 'units' ? 'đơn vị' : 'người dùng'} Excel`}</button>
    <small className="rp-import-help">{kind === 'units'
      ? 'Dùng sheet DonVi với các cột MaDV, TenDV và MaNhanVienPhuTrach (không bắt buộc).'
      : 'Dùng sheet NguoiDung. Vai trò hợp lệ: Sinh viên, Giảng viên, Cán bộ; không hỗ trợ tạo Admin. Sinh viên cần lớp/chuyên ngành, Giảng viên cần bộ môn, Cán bộ cần chức vụ.'}</small>
    {draft && <div className="rp-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) setDraft(null); }}>
      <section className="rp-modal rp-form-modal" role="dialog" aria-modal="true">
        <header><div><h2>Xác nhận import {kind === 'units' ? 'đơn vị' : 'người dùng'}</h2><p>{kind === 'units' ? `${draft.units.length} đơn vị hợp lệ sẽ được thêm.` : `${draft.users.length} tài khoản hợp lệ sẽ được thêm.`}</p></div><button type="button" className="rp-icon-button" onClick={() => setDraft(null)} aria-label="Đóng" disabled={busy}><X size={18} /></button></header>
        {kind === 'users' && <p className="rp-modal-muted">Mật khẩu không hiển thị trong bản xem trước và sẽ được mã hóa trước khi lưu. Import tài khoản Admin không được hỗ trợ.</p>}
        {draft.warnings.length > 0 && <div className="rp-import-warning" role="alert"><strong>{draft.warnings.length} dòng sẽ bị bỏ qua</strong>{draft.warnings.map((warning) => <span key={warning}>{warning}</span>)}</div>}
        {draft.units.length > 0 && <div className="rp-import-preview"><strong>Đơn vị tổ chức</strong>{draft.units.map((unit) => <div key={unit.id}><strong>{unit.name}</strong><span>Mã {unit.id} · Nhân viên phụ trách: {unit.managerId || 'Chưa phân công'}</span></div>)}</div>}
        {draft.users.length > 0 && <div className="rp-import-preview"><strong>Tài khoản người dùng</strong>{draft.users.map((user) => <div key={user.id}><strong>{user.name}</strong><span>{user.id} · {user.email} · {user.role}{user.cohortCode ? ` · Khóa ${user.cohortCode}` : ''}</span><span>{'*'.repeat(Math.min(user.passwordLength, 12))} · {user.status || 'Đang hoạt động'}</span></div>)}</div>}
        {error && <div className="rp-detail-error" role="alert">{error}</div>}
        <footer><button type="button" className="rp-secondary-button" onClick={() => setDraft(null)} disabled={busy}>Hủy</button><button type="button" className="rp-secondary-button" onClick={confirmImport} disabled={busy}>{busy ? 'Đang nhập...' : 'Xác nhận import'}</button></footer>
      </section>
    </div>}
  </>;
}
