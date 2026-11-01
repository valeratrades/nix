// registered at document_start, so it runs before every page listener and `onbeforeunload` handler, starving them all
addEventListener("beforeunload", (e) => e.stopImmediatePropagation(), true);
