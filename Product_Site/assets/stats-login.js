(() => {
  const form = document.getElementById('login-form');
  form.addEventListener('submit', async event => {
    event.preventDefault();
    const button = document.getElementById('login-button');
    const status = document.getElementById('login-status');
    button.disabled = true; status.textContent = '正在登录…';
    try {
      const response = await fetch('/api/stats/login', { method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: document.getElementById('password').value }),
        signal: AbortSignal.timeout(15000),
      });
      if (response.ok) { location.replace('/stats'); return; }
      status.textContent = response.status === 401 ? '密码不正确，请重试。' : '统计登录暂时不可用，请稍后重试。';
    } catch { status.textContent = '连接失败，请稍后重试。'; }
    finally { button.disabled = false; }
  });
})();
