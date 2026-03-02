(function () {
  "use strict";

  var REPO = "rooneyj9005/Thunder";
  var API_URL = "https://api.github.com/repos/" + REPO + "/releases/latest";
  var RELEASES_URL = "https://github.com/" + REPO + "/releases";

  var btn = document.getElementById("download-btn");
  var versionEl = document.getElementById("download-version");

  if (!btn) return;

  fetch(API_URL)
    .then(function (res) {
      if (!res.ok) throw new Error(res.status);
      return res.json();
    })
    .then(function (data) {
      var asset =
        data.assets &&
        data.assets.find(function (a) {
          return a.name.endsWith(".mrpack");
        });

      if (asset) {
        btn.href = asset.browser_download_url;
        btn.setAttribute("download", asset.name);
      } else {
        btn.href = RELEASES_URL;
      }

      if (versionEl && data.tag_name) {
        versionEl.textContent = data.tag_name;
      }
    })
    .catch(function () {
      btn.href = RELEASES_URL;
      if (versionEl) {
        versionEl.textContent = "See all releases";
      }
    });
})();
