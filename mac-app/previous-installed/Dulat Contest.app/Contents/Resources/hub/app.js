const groupLink = document.getElementById('group-link');
const compilerLink = document.getElementById('compiler-link');
const status = document.getElementById('status');

async function loadContest() {
  try {
    const [configResponse, sourceResponse] = await Promise.all([
      fetch('/config.json', { cache: 'no-store' }),
      fetch('/starter.cpp', { cache: 'no-store' })
    ]);
    if (!configResponse.ok || !sourceResponse.ok) throw new Error('Не удалось загрузить ресурсы.');
    const config = await configResponse.json();
    const source = await sourceResponse.text();
    const group = new URL(config.groupURL);
    if (group.protocol !== 'https:' || group.hostname !== 'codeforces.com' ||
        !/^\/group\/[A-Za-z0-9_-]+(?:\/|$)/.test(group.pathname)) {
      throw new Error('Ссылка на группу неверна.');
    }
    groupLink.href = group.href;
    compilerLink.href = `https://cpp.sh/?source=${encodeURIComponent(source)}`;
    groupLink.removeAttribute('aria-disabled');
    compilerLink.removeAttribute('aria-disabled');
    status.textContent = '';
  } catch (error) {
    status.textContent = `Ошибка: ${error.message} Попросите организатора перезапустить приложение.`;
  }
}

loadContest();
