const groupLink = document.getElementById('group-link');
const compilerLink = document.getElementById('compiler-link');
const status = document.getElementById('status');
const retry = document.getElementById('retry');

async function resource(path) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    const response = await fetch(path, { cache: 'no-store', signal: controller.signal });
    if (!response.ok) throw new Error('Ресурс недоступен.');
    return await response.text();
  } finally { clearTimeout(timer); }
}

function enableLink(link, href) {
  link.href = href;
  link.removeAttribute('aria-disabled');
  link.removeAttribute('tabindex');
}

async function loadContest() {
  retry.hidden = true;
  status.hidden = false;
  status.classList.remove('error');
  status.textContent = 'Загрузка…';
  for (const link of [groupLink, compilerLink]) {
    link.removeAttribute('href');
    link.setAttribute('aria-disabled', 'true');
    link.setAttribute('tabindex', '-1');
  }
  const results = await Promise.allSettled([
    (async () => {
      const config = JSON.parse(await resource('/config.json'));
      const group = new URL(config.groupURL);
      if (group.protocol !== 'https:' || !(group.hostname === 'codeforces.com' || /^[a-z][a-z0-9]{2,19}\.contest\.codeforces\.com$/.test(group.hostname)) || group.port ||
          group.username || group.password || group.hash ||
          !/^\/group\/[A-Za-z0-9_-]+\/contest\/[1-9][0-9]*\/?$/.test(group.pathname)) {
        throw new Error('Неверная ссылка на группу.');
      }
      enableLink(groupLink, group.href);
    })(),
    (async () => {
      const source = await resource('/starter.cpp');
      if (!source.trim()) throw new Error('Шаблон C++ пуст.');
      enableLink(compilerLink, "https://www.onlinegdb.com/?new_lang=c%2B%2B20&sidebar=no");
    })()
  ]);
  const labels = ['Группа не загрузилась.', 'Шаблон C++ не загрузился.'];
  const errors = results.flatMap((result, i) => result.status === 'rejected' ? [labels[i]] : []);
  status.textContent = errors.join(' ');
  status.classList.toggle('error', errors.length > 0);
  status.hidden = errors.length === 0;
  retry.hidden = errors.length === 0;
}

retry.addEventListener('click', loadContest);
loadContest();
