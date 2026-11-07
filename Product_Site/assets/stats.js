(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const format = value => new Intl.NumberFormat('zh-CN').format(value);
  const labels = { website: '官网入口下载', update: '应用内更新包', check: '更新检查', direct: '其他直接下载' };
  let days = 30, data = null, controller = null;
  const svgNS = 'http://www.w3.org/2000/svg';
  function node(tag, text, attrs = {}) {
    const el = document.createElement(tag);
    if (text !== undefined) el.textContent = text;
    Object.entries(attrs).forEach(([key, value]) => el.setAttribute(key, value));
    return el;
  }
  function svgNode(tag, attrs, text) {
    const el = document.createElementNS(svgNS, tag);
    Object.entries(attrs).forEach(([key, value]) => el.setAttribute(key, value));
    if (text !== undefined) el.textContent = text;
    return el;
  }
  function tableRow(values) {
    const row = node('tr');
    values.forEach(value => row.append(node('td', value)));
    return row;
  }
  function chart() {
    if (!data) return;
    const kind = $('metric').value, rows = data.daily;
    const maximum = Math.max(...rows.map(row => row[kind]));
    $('chart').replaceChildren();
    $('chart').setAttribute('aria-label', `${data.start} 至 ${data.end}，${labels[kind]}，合计 ${data.totals[kind]} 次；每日数值见下方表格`);
    if (!maximum) {
      const empty = node('div', undefined, { class: 'chart-empty' });
      empty.append(node('strong', '所选时段暂无此类请求'), node('span', '收到请求后，这里会显示每日趋势。'));
      $('chart').append(empty); return;
    }
    const width = Math.max(280, $('chart').clientWidth), height = 220, left = 40, right = width - 8, bottom = 190, top = 12;
    const max = Math.max(1, Math.ceil(maximum / 4) * 4);
    const svg = svgNode('svg', { viewBox: `0 0 ${width} ${height}`, 'aria-hidden': 'true' });
    for (let i = 0; i <= 4; i++) {
      const y = bottom - i * (bottom - top) / 4;
      svg.append(svgNode('line', { x1: left, x2: right, y1: y, y2: y, stroke: '#eceef3', 'stroke-dasharray': '3 4' }));
      svg.append(svgNode('text', { x: left - 8, y: y + 4, 'text-anchor': 'end', fill: '#6e6e73', 'font-size': 10 }, format(max * i / 4)));
    }
    const step = (right - left) / rows.length;
    rows.forEach((row, index) => {
      const barHeight = row[kind] / max * (bottom - top);
      const bar = svgNode('rect', { x: left + index * step + step * .15, y: bottom - barHeight, width: Math.max(1, step * .7), height: barHeight, rx: 2, fill: '#0049f8' });
      bar.append(svgNode('title', {}, `${row.day} · ${format(row[kind])} 次`)); svg.append(bar);
    });
    [0, Math.floor((rows.length - 1) / 2), rows.length - 1].forEach((index, i) => {
      svg.append(svgNode('text', { x: i === 0 ? left : i === 2 ? right : (left + right) / 2, y: 215, 'text-anchor': ['start','middle','end'][i], fill: '#6e6e73', 'font-size': 10 }, rows[index].day.slice(5)));
    });
    $('chart').append(svg);
  }
  function render() {
    Object.keys(labels).forEach(key => { $(key).textContent = format(data.totals[key]); });
    $('delta').textContent = `其中增量包 ${format(data.delta)} 次`;
    $('range').textContent = `${data.start} — ${data.end} · 北京时间`;
    $('daily').replaceChildren(...[...data.daily].reverse().map(row => tableRow([row.day, ...Object.keys(labels).map(key => format(row[key]))])));
    $('versions').replaceChildren(...data.versions.map(row => tableRow([row.version === 'unknown' ? '未识别版本' : `v${row.version}`, format(row.website), format(row.update), format(row.delta), format(row.check), format(row.direct)])));
    if (!data.versions.length) {
      const row = node('tr'); row.append(node('td', '所选时段暂无请求记录', { colspan: '6', class: 'empty' })); $('versions').append(row);
    }
    const date = new Intl.DateTimeFormat('zh-CN', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' });
    $('status').textContent = `统计起点 ${date.format(new Date(data.startedAt))} · 刷新于 ${date.format(new Date(data.generatedAt))}（北京时间）`;
    chart();
  }
  async function load() {
    controller?.abort(); const current = new AbortController(); controller = current;
    const timeout = setTimeout(() => current.abort(), 15000);
    $('refresh').disabled = true; $('results').setAttribute('aria-busy', 'true');
    $('error').hidden = true; $('status').textContent = '正在加载统计…';
    // Never show old totals as though they belong to a newly selected period.
    $('results').hidden = true;
    try {
      const response = await fetch(`/api/stats?days=${days}`, { signal: current.signal, cache: 'no-store' });
      if (response.status === 401) { location.reload(); return; }
      if (!response.ok) throw new Error('unavailable');
      const next = await response.json();
      if (controller !== current) return;
      data = next; $('results').hidden = false; render();
    } catch {
      if (controller !== current) return;
      data = null; $('error').hidden = false; $('status').textContent = '统计服务暂时不可用，未显示计数。';
    } finally {
      clearTimeout(timeout);
      if (controller === current) { $('refresh').disabled = false; $('results').setAttribute('aria-busy', 'false'); }
    }
  }
  document.querySelectorAll('[data-days]').forEach(button => button.addEventListener('click', () => {
    days = Number(button.dataset.days);
    document.querySelectorAll('[data-days]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    load();
  }));
  $('refresh').addEventListener('click', load);
  $('logout').addEventListener('click', async () => {
    try {
      const response = await fetch('/api/stats/logout', { method: 'POST' });
      if (!response.ok) throw new Error('logout_failed');
      location.reload();
    } catch { $('status').textContent = '退出失败，请重试。'; }
  });
  $('metric').addEventListener('change', chart);
  new ResizeObserver(chart).observe($('chart'));
  load();
})();
