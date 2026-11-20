(function () {
  'use strict';

  var root = document.documentElement;
  var body = document.body;

  // 1. Theme toggle
  var themeToggle = document.getElementById('theme-toggle');
  if (themeToggle) {
    themeToggle.addEventListener('click', function () {
      var current = root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
      var next = current === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try {
        localStorage.setItem('ocp-itsg33-theme', next);
      } catch (e) {}
    });
  }

  // 2. Sidebar toggle (desktop collapse + mobile drawer)
  var sidebarToggle = document.getElementById('sidebar-toggle');
  var sidebarBackdrop = document.getElementById('sidebar-backdrop');
  var mqMobile = window.matchMedia('(max-width: 959px)');

  function closeMobileSidebar() {
    body.classList.remove('sidebar-open');
  }

  if (sidebarToggle) {
    sidebarToggle.addEventListener('click', function () {
      if (mqMobile.matches) {
        body.classList.toggle('sidebar-open');
      } else {
        var collapsed = root.classList.toggle('sidebar-collapsed');
        try {
          localStorage.setItem('ocp-itsg33-sidebar', collapsed ? 'collapsed' : 'expanded');
        } catch (e) {}
      }
    });
  }

  if (sidebarBackdrop) {
    sidebarBackdrop.addEventListener('click', closeMobileSidebar);
  }

  // 3. Sidebar navigation quick filter
  var navFilter = document.getElementById('nav-filter');
  var sidebarNav = document.getElementById('sidebar-nav');
  if (navFilter && sidebarNav) {
    var allDetails = Array.prototype.slice.call(sidebarNav.querySelectorAll('details.nav-details'));
    var initialOpen = allDetails.map(function (d) { return d.open; });

    navFilter.addEventListener('input', function () {
      var q = navFilter.value.trim().toLowerCase();
      var links = sidebarNav.querySelectorAll('.nav-item');

      if (!q) {
        links.forEach(function (li) { li.style.display = ''; });
        sidebarNav.querySelectorAll('.nav-group').forEach(function (g) { g.style.display = ''; });
        allDetails.forEach(function (d, i) { d.open = initialOpen[i]; });
        return;
      }

      links.forEach(function (li) {
        var match = li.textContent.toLowerCase().indexOf(q) !== -1;
        li.style.display = match ? '' : 'none';
      });

      // Bottom-up visibility for nested groups
      var groups = Array.prototype.slice.call(sidebarNav.querySelectorAll('.nav-group')).reverse();
      groups.forEach(function (group) {
        var summary = group.querySelector(':scope > details > summary');
        var groupMatch = summary && summary.textContent.toLowerCase().indexOf(q) !== -1;
        if (groupMatch) {
          group.style.display = '';
          group.querySelectorAll('.nav-item, .nav-group').forEach(function (el) { el.style.display = ''; });
          var d = group.querySelector(':scope > details');
          if (d) d.open = true;
          return;
        }
        var visibleChildren = group.querySelectorAll('.nav-item:not([style*="display: none"])').length > 0;
        group.style.display = visibleChildren ? '' : 'none';
        var details = group.querySelector(':scope > details');
        if (details) details.open = visibleChildren;
      });
    });
  }

  // 4. Wrap tables for responsive horizontal scrolling without breaking page width
  var docContent = document.getElementById('doc-content');
  if (docContent) {
    docContent.querySelectorAll('table').forEach(function (table) {
      if (table.parentElement && table.parentElement.classList.contains('table-scroll')) return;
      var wrapper = document.createElement('div');
      wrapper.className = 'table-scroll';
      table.parentNode.insertBefore(wrapper, table);
      wrapper.appendChild(table);
    });

    // 5. Add anchor links to h2, h3, h4
    docContent.querySelectorAll('h2[id], h3[id], h4[id]').forEach(function (heading) {
      if (heading.querySelector('.heading-anchor')) return;
      var anchor = document.createElement('a');
      anchor.className = 'heading-anchor';
      anchor.href = '#' + heading.id;
      anchor.setAttribute('aria-label', 'Link to section');
      anchor.textContent = '#';
      heading.appendChild(anchor);
    });

    // 6. Add Copy button to <pre> blocks
    docContent.querySelectorAll('pre').forEach(function (pre) {
      var code = pre.querySelector('code');
      var target = code || pre;
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'copy-code-btn';
      btn.textContent = 'Copy';
      btn.addEventListener('click', function () {
        var text = target.innerText || target.textContent || '';
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () {
            btn.textContent = 'Copied';
            btn.classList.add('is-copied');
            setTimeout(function () {
              btn.textContent = 'Copy';
              btn.classList.remove('is-copied');
            }, 1600);
          });
        }
      });
      pre.appendChild(btn);
    });

    // 7. Build right-side "On this page" TOC
    var tocAside = document.getElementById('toc-aside');
    var tocNav = document.getElementById('toc-nav');
    if (tocAside && tocNav) {
      var headings = Array.prototype.slice.call(docContent.querySelectorAll('h2[id], h3[id]'));
      if (headings.length >= 2) {
        tocAside.classList.add('has-toc');
        var tocLinks = headings.map(function (h) {
          var a = document.createElement('a');
          a.className = 'toc-link toc-' + h.tagName.toLowerCase();
          a.href = '#' + h.id;
          // Exclude appended '#' anchor text
          var clone = h.cloneNode(true);
          var anc = clone.querySelector('.heading-anchor');
          if (anc) anc.remove();
          a.textContent = clone.textContent.trim();
          tocNav.appendChild(a);
          return { id: h.id, el: h, link: a };
        });

        function updateActiveToc() {
          var scrollY = window.scrollY + 110;
          var active = tocLinks[0];
          for (var i = 0; i < tocLinks.length; i++) {
            if (tocLinks[i].el.offsetTop <= scrollY) {
              active = tocLinks[i];
            }
          }
          tocLinks.forEach(function (item) {
            item.link.classList.toggle('is-active', item === active);
          });
        }

        window.addEventListener('scroll', updateActiveToc, { passive: true });
        updateActiveToc();
      }
    }
  }

  // 8. Search Modal (Ctrl+K / Cmd+K / '/' or button click)
  var searchModal = document.getElementById('search-modal');
  var searchOpen = document.getElementById('search-open');
  var searchClose = document.getElementById('search-close');
  var searchInput = document.getElementById('search-input');
  var searchResults = document.getElementById('search-results');
  var searchIndex = null;
  var selectedIdx = -1;

  function escapeHtml(str) {
    return str.replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function loadSearchIndex() {
    if (searchIndex) return Promise.resolve(searchIndex);
    var url = body.getAttribute('data-search-url') || '/search.json';
    return fetch(url)
      .then(function (r) { return r.json(); })
      .then(function (data) {
        searchIndex = data;
        return data;
      })
      .catch(function () {
        // Fallback to sidebar links if search.json is unavailable
        var fallback = [];
        document.querySelectorAll('#sidebar-nav a.nav-link').forEach(function (a) {
          fallback.push({
            title: a.textContent.trim(),
            url: a.getAttribute('href'),
            content: ''
          });
        });
        searchIndex = fallback;
        return fallback;
      });
  }

  function openSearch() {
    if (!searchModal) return;
    searchModal.hidden = false;
    searchInput.value = '';
    selectedIdx = -1;
    searchResults.innerHTML = '<div class="search-empty">Type to search across all documentation pages.</div>';
    setTimeout(function () { searchInput.focus(); }, 10);
    loadSearchIndex();
  }

  function closeSearch() {
    if (!searchModal) return;
    searchModal.hidden = true;
  }

  function buildSnippet(text, terms) {
    if (!text) return '';
    var lower = text.toLowerCase();
    var pos = -1;
    for (var i = 0; i < terms.length; i++) {
      var idx = lower.indexOf(terms[i]);
      if (idx !== -1) { pos = idx; break; }
    }
    var start = Math.max(0, pos - 60);
    var slice = text.slice(start, start + 180);
    var escaped = escapeHtml((start > 0 ? '…' : '') + slice + (start + 180 < text.length ? '…' : ''));
    terms.forEach(function (t) {
      if (!t) return;
      var re = new RegExp('(' + t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'ig');
      escaped = escaped.replace(re, '<mark>$1</mark>');
    });
    return escaped;
  }

  function renderResults(query) {
    var q = query.trim().toLowerCase();
    if (!q) {
      searchResults.innerHTML = '<div class="search-empty">Type to search across all documentation pages.</div>';
      selectedIdx = -1;
      return;
    }
    var terms = q.split(/\s+/).filter(Boolean);
    var hits = [];
    (searchIndex || []).forEach(function (doc) {
      var titleL = (doc.title || '').toLowerCase();
      var contentL = (doc.content || '').toLowerCase();
      var score = 0;
      var matchedAll = terms.every(function (t) {
        var inTitle = titleL.indexOf(t) !== -1;
        var inContent = contentL.indexOf(t) !== -1;
        if (inTitle) score += 10;
        if (inContent) score += 2;
        return inTitle || inContent;
      });
      if (matchedAll) {
        hits.push({ doc: doc, score: score });
      }
    });

    hits.sort(function (a, b) { return b.score - a.score; });
    hits = hits.slice(0, 15);
    selectedIdx = hits.length > 0 ? 0 : -1;

    if (!hits.length) {
      searchResults.innerHTML = '<div class="search-empty">No matching pages found.</div>';
      return;
    }

    searchResults.innerHTML = hits.map(function (h, i) {
      var snippet = buildSnippet(h.doc.content || '', terms);
      return '<a class="search-hit' + (i === 0 ? ' is-selected' : '') + '" href="' + escapeHtml(h.doc.url) + '">' +
        '<div class="search-hit-title">' + escapeHtml(h.doc.title) + '</div>' +
        (snippet ? '<div class="search-hit-snippet">' + snippet + '</div>' : '') +
        '</a>';
    }).join('');
  }

  if (searchOpen) searchOpen.addEventListener('click', openSearch);
  if (searchClose) searchClose.addEventListener('click', closeSearch);
  if (searchModal) {
    searchModal.addEventListener('click', function (e) {
      if (e.target === searchModal) closeSearch();
    });
  }
  if (searchInput) {
    searchInput.addEventListener('input', function () {
      if (!searchIndex) {
        loadSearchIndex().then(function () { renderResults(searchInput.value); });
      } else {
        renderResults(searchInput.value);
      }
    });
    searchInput.addEventListener('keydown', function (e) {
      var items = searchResults.querySelectorAll('.search-hit');
      if (!items.length) return;
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        selectedIdx = (selectedIdx + 1) % items.length;
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        selectedIdx = (selectedIdx - 1 + items.length) % items.length;
      } else if (e.key === 'Enter' && selectedIdx >= 0) {
        e.preventDefault();
        items[selectedIdx].click();
        return;
      } else {
        return;
      }
      items.forEach(function (el, idx) {
        el.classList.toggle('is-selected', idx === selectedIdx);
      });
      items[selectedIdx].scrollIntoView({ block: 'nearest' });
    });
  }

  document.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      if (searchModal && searchModal.hidden) openSearch();
      else closeSearch();
    } else if (e.key === 'Escape') {
      if (searchModal && !searchModal.hidden) closeSearch();
      closeMobileSidebar();
    } else if (e.key === '/' && document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') {
      e.preventDefault();
      openSearch();
    }
  });
})();
