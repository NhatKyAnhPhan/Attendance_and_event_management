const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { test } = require('node:test');
const bcrypt = require('bcryptjs');

const { createPasswordResetHandlers } = require('./password_reset_handler');

test('completes a verified password reset using the canonical user table name', async () => {
  const secret = 'test-password-reset-secret-with-at-least-32-bytes';
  const resetToken = 'a'.repeat(64);
  const userId = 'user-123';
  const resetTokenHash = crypto
    .createHmac('sha256', secret)
    .update(resetToken)
    .digest('hex');
  const executedQueries = [];
  let committed = false;
  let released = false;
  const connection = {
    async beginTransaction() {},
    async execute(sql, parameters) {
      executedQueries.push({ sql, parameters });
      if (sql.includes('SELECT user_id AS userId')) {
        return [[{
          userId,
          resetTokenHash,
          isValid: 1,
        }], []];
      }
      return [{ affectedRows: 1 }, []];
    },
    async commit() {
      committed = true;
    },
    async rollback() {
      assert.fail('A valid reset token should not roll back.');
    },
    release() {
      released = true;
    },
  };
  const handlers = createPasswordResetHandlers({
    pool: { getConnection: async () => connection },
    secret,
    mailConfigured: () => true,
  });
  const response = {
    statusCode: 200,
    body: null,
    status(statusCode) {
      this.statusCode = statusCode;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };

  await handlers.resetPassword({
    ip: 'password-reset-success-test',
    body: {
      email: 'student@example.com',
      resetToken,
      newPassword: 'new-secure-password',
    },
  }, response);

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.message, 'Đặt lại mật khẩu thành công.');
  assert.equal(committed, true);
  assert.equal(released, true);
  assert.match(executedQueries[1].sql, /UPDATE NguoiDung SET Matkhau = \? WHERE Mand = \?/);
  assert.equal(executedQueries[1].parameters[1], userId);
  assert.equal(await bcrypt.compare('new-secure-password', executedQueries[1].parameters[0]), true);
  assert.match(executedQueries[2].sql, /DELETE FROM password_reset_challenges/);
});
