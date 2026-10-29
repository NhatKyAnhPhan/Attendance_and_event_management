export function parseStudentIds(value) {
  return [...new Set(String(value || '').split(/[\s,;]+/).map((id) => id.trim()).filter(Boolean))];
}
