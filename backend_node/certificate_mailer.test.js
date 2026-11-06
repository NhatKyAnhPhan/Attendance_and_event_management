const assert = require('node:assert/strict');
const { afterEach, test } = require('node:test');

const {
  createMailTransport,
  isMailConfigured,
} = require('./certificate_mailer');

const originalEnvironment = {
  MAIL_PROVIDER: process.env.MAIL_PROVIDER,
  MAIL_FROM: process.env.MAIL_FROM,
  SMTP_FROM: process.env.SMTP_FROM,
  RESEND_API_KEY: process.env.RESEND_API_KEY,
  BREVO_API_KEY: process.env.BREVO_API_KEY,
  fetch: global.fetch,
};

function restoreEnvironmentValue(name, value) {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}

afterEach(() => {
  for (const [name, value] of Object.entries(originalEnvironment)) {
    if (name === 'fetch') {
      global.fetch = value;
    } else {
      restoreEnvironmentValue(name, value);
    }
  }
});

test('rejects a bare domain as the Resend sender address', () => {
  process.env.MAIL_PROVIDER = 'resend';
  process.env.RESEND_API_KEY = 'test-key';
  process.env.MAIL_FROM = 'khoaluan.diemdanh.com';
  delete process.env.SMTP_FROM;

  assert.equal(isMailConfigured(), false);
  assert.throws(createMailTransport, /MAIL_FROM phải là địa chỉ email/);
});

test('accepts a sender email with a display name for Resend', async () => {
  process.env.MAIL_PROVIDER = 'resend';
  process.env.RESEND_API_KEY = 'test-key';
  process.env.MAIL_FROM = 'HUIT <chungnhan@example.com>';
  delete process.env.SMTP_FROM;

  assert.equal(isMailConfigured(), true);
  assert.equal(await createMailTransport().verify(), true);
});

test('sends Brevo mail with sender, body, and PDF attachment', async () => {
  process.env.MAIL_PROVIDER = 'brevo';
  process.env.BREVO_API_KEY = 'test-brevo-key';
  process.env.MAIL_FROM = 'HUIT <chungnhan@example.com>';
  delete process.env.SMTP_FROM;
  delete process.env.RESEND_API_KEY;

  let request;
  global.fetch = async (url, options) => {
    request = { url, options };
    return new Response(JSON.stringify({ messageId: '<brevo-message-id>' }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  assert.equal(isMailConfigured(), true);
  const transport = createMailTransport();
  assert.equal(await transport.verify(), true);
  const result = await transport.sendMail({
    to: 'student@example.com',
    subject: 'Chứng nhận',
    text: 'Xin chào\nĐính kèm chứng nhận.',
    attachments: [{
      filename: 'certificate.pdf',
      content: Buffer.from('sample PDF'),
      contentType: 'application/pdf',
    }],
  });

  assert.equal(result.messageId, '<brevo-message-id>');
  assert.equal(request.url, 'https://api.brevo.com/v3/smtp/email');
  assert.equal(request.options.headers['api-key'], 'test-brevo-key');
  const payload = JSON.parse(request.options.body);
  assert.deepEqual(payload.sender, {
    name: 'HUIT',
    email: 'chungnhan@example.com',
  });
  assert.deepEqual(payload.to, [{ email: 'student@example.com' }]);
  assert.equal(payload.textContent, 'Xin chào\nĐính kèm chứng nhận.');
  assert.equal(payload.htmlContent, 'Xin chào<br>Đính kèm chứng nhận.');
  assert.deepEqual(payload.attachment, [{
    name: 'certificate.pdf',
    content: Buffer.from('sample PDF').toString('base64'),
  }]);
});

test('reports Brevo API delivery errors', async () => {
  process.env.MAIL_PROVIDER = 'brevo';
  process.env.BREVO_API_KEY = 'test-brevo-key';
  process.env.MAIL_FROM = 'sender@example.com';
  delete process.env.SMTP_FROM;

  global.fetch = async () => new Response(
    JSON.stringify({ code: 'unauthorized', message: 'Invalid API key' }),
    { status: 401, headers: { 'Content-Type': 'application/json' } },
  );

  await assert.rejects(
    createMailTransport().sendMail({
      to: 'student@example.com',
      subject: 'Test',
      text: 'Test body',
    }),
    (error) => error.code === 'unauthorized' && error.message === 'Invalid API key',
  );
});
