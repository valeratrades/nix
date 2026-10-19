const EXEMPT = []; // replaced at build with TabDiscardingExceptions (os/nixos/desktop/programs/chrome.nix)

const exempt = url => {
  const host = URL.parse(url)?.hostname ?? '';
  return EXEMPT.some(p => host === p || host.endsWith(`.${p}`));
};

chrome.runtime.onStartup.addListener(async () => {
  const tabs = await chrome.tabs.query({ active: false, discarded: false });
  await Promise.all(tabs.filter(t => !exempt(t.pendingUrl ?? t.url)).map(t =>
    chrome.tabs.discard(t.id).catch(e => console.error(`discard ${t.url}: ${e.message}`)), // tab can close or activate between query and discard
  ));
});
