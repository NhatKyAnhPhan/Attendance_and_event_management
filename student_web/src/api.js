const API_BASE_URL = (
  import.meta.env.VITE_API_BASE_URL ||
  'https://attendance-and-event-management.onrender.com'
).replace(/\/+$/, '');

export class ApiError extends Error {
  constructor(message, status, data) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.data = data;
  }
}

export async function api(path, {
  method = 'GET', body, token, responseType, timeoutMs = 10000,
} = {}) {
  const headers = { Accept: 'application/json' };
  const authToken = token ?? localStorage.getItem('studentWebToken');
  if (authToken) headers.Authorization = `Bearer ${authToken}`;
  const isFormData = typeof FormData !== 'undefined' && body instanceof FormData;
  if (body !== undefined && !isFormData) headers['Content-Type'] = 'application/json';

  let response;
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), timeoutMs);
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : isFormData ? body : JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (error) {
    if (error?.name === 'AbortError') {
      throw new ApiError(`Máy chủ không phản hồi trong ${Math.ceil(timeoutMs / 1000)} giây. Vui lòng thử lại.`, 0);
    }
    throw new ApiError('Không thể kết nối tới máy chủ. Hãy kiểm tra mạng và địa chỉ API.', 0);
  } finally {
    window.clearTimeout(timeout);
  }

  if (responseType === 'blob') {
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new ApiError(data.message || `Máy chủ trả về lỗi HTTP ${response.status}.`, response.status, data);
    }
    return response.blob();
  }

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 401 && !path.includes('/api/auth/login')) {
      localStorage.removeItem('studentWebToken');
      window.dispatchEvent(new Event('student-session-expired'));
    }
    throw new ApiError(data.message || `Máy chủ trả về lỗi HTTP ${response.status}.`, response.status, data);
  }
  return data;
}

export const apiBaseUrl = API_BASE_URL;
