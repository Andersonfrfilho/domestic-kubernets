const { execSync } = require('child_process');

function request(baseUrl, path, method = 'GET', body = null) {
  const url = `${baseUrl}${path}`;

  let cmd = `curl -s -X ${method}`;
  cmd += ` -H 'Content-Type: application/json'`;
  cmd += ` -H 'Host: gateway.domestic.local'`;
  cmd += ` -w '\n%{http_code}'`;

  if (body && (method === 'POST' || method === 'PUT' || method === 'PATCH')) {
    cmd += ` -d '${JSON.stringify(body).replace(/'/g, "'\\''")}'`;
  }

  cmd += ` '${url}'`;

  const output = execSync(cmd, { encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 });
  const lines = output.trim().split('\n');
  const statusStr = lines[lines.length - 1];
  const status = parseInt(statusStr, 10);
  const raw = lines.slice(0, -1).join('\n');

  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    data = raw;
  }

  return Promise.resolve({ status, ok: status >= 200 && status < 300, data });
}

module.exports = { request };
