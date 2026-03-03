"use strict";

var RELEASES_URL = "https://github.com/rooneyj9005/Thunder/releases";
var RELEASE_API_URL = "https://api.github.com/repos/rooneyj9005/Thunder/releases/latest";
var MAIN_PACK_TOML_URL = "https://raw.githubusercontent.com/rooneyj9005/Thunder/main/pack.toml";

var latestReleasePromise = null;

function fetchLatestThunderRelease() {
  if (latestReleasePromise) {
    return latestReleasePromise;
  }

  latestReleasePromise = fetch(RELEASE_API_URL, {
    headers: {
      Accept: "application/vnd.github+json",
    },
    cache: "no-store",
  }).then(function (response) {
    if (!response.ok) {
      throw new Error(String(response.status));
    }
    return response.json();
  });

  return latestReleasePromise;
}

function fetchMainPackToml() {
  return fetch(MAIN_PACK_TOML_URL, {
    cache: "no-store",
  }).then(function (response) {
    if (!response.ok) {
      throw new Error(String(response.status));
    }
    return response.text();
  });
}

function parsePackVersionFromToml(packTomlText) {
  if (typeof packTomlText !== "string") {
    return null;
  }

  var match = packTomlText.match(/^version\s*=\s*"([^"]+)"/m);
  return match ? match[1] : null;
}

function normalizeVersionTag(versionText) {
  if (!versionText) {
    return null;
  }
  return String(versionText).replace(/^v/i, "").trim();
}

function findMrpackAsset(releaseData) {
  if (!releaseData || !Array.isArray(releaseData.assets)) {
    return null;
  }

  return (
    releaseData.assets.find(function (asset) {
      return typeof asset.name === "string" && asset.name.endsWith(".mrpack");
    }) || null
  );
}

function updateDownloadButtonFromLatestRelease() {
  var downloadButton = document.getElementById("download-btn");
  var downloadVersion = document.getElementById("download-version");

  if (!downloadButton) {
    return Promise.resolve(null);
  }

  return fetchLatestThunderRelease()
    .then(function (releaseData) {
      var mrpackAsset = findMrpackAsset(releaseData);

      if (mrpackAsset && mrpackAsset.browser_download_url) {
        downloadButton.href = mrpackAsset.browser_download_url;
        if (mrpackAsset.name) {
          downloadButton.setAttribute("download", mrpackAsset.name);
        }
      } else {
        downloadButton.href = RELEASES_URL;
        downloadButton.removeAttribute("download");
      }

      if (downloadVersion && releaseData.tag_name) {
        downloadVersion.textContent = releaseData.tag_name;
      }

      return releaseData;
    })
    .catch(function () {
      downloadButton.href = RELEASES_URL;
      downloadButton.removeAttribute("download");
      if (downloadVersion) {
        downloadVersion.textContent = "See all releases";
      }
      return null;
    });
}

function updateHeaderVersionStatus() {
  var headerStatusElement = document.getElementById("header-version-status");

  if (!headerStatusElement) {
    return Promise.resolve(null);
  }

  function renderStatus(iconClassName, state, textValue, titleValue) {
    headerStatusElement.innerHTML = "";
    headerStatusElement.setAttribute("data-state", state);
    headerStatusElement.setAttribute("title", titleValue);

    var iconElement = document.createElement("i");
    iconElement.className = "bi " + iconClassName;
    iconElement.setAttribute("aria-hidden", "true");

    var textElement = document.createElement("span");
    textElement.textContent = textValue;

    headerStatusElement.appendChild(iconElement);
    headerStatusElement.appendChild(textElement);
  }

  return Promise.all([
    fetchLatestThunderRelease().catch(function () {
      return null;
    }),
    fetchMainPackToml().catch(function () {
      return null;
    }),
  ]).then(function (results) {
    var releaseData = results[0];
    var mainPackToml = results[1];

    var releaseVersion = releaseData && releaseData.tag_name ? normalizeVersionTag(releaseData.tag_name) : null;
    var mainVersion = parsePackVersionFromToml(mainPackToml);

    if (!releaseVersion && !mainVersion) {
      renderStatus(
        "bi-exclamation-triangle",
        "unavailable",
        "Version status unavailable",
        "Could not read release tag or main pack version."
      );
      return null;
    }

    if (!releaseVersion || !mainVersion) {
      renderStatus(
        "bi-info-circle",
        "partial",
        "Version data partial",
        "One of release or main version could not be resolved."
      );
      return {
        releaseVersion: releaseVersion,
        mainVersion: mainVersion,
      };
    }

    if (releaseVersion === mainVersion) {
      renderStatus(
        "bi-check-circle",
        "in-sync",
        "Release " + releaseVersion + " | Main " + mainVersion,
        "Main and latest release are in sync."
      );
    } else {
      renderStatus(
        "bi-arrow-left-right",
        "out-of-sync",
        "Release " + releaseVersion + " | Main " + mainVersion,
        "Main differs from latest release."
      );
    }

    return {
      releaseVersion: releaseVersion,
      mainVersion: mainVersion,
    };
  });
}

function initializeThunderPage() {
  return Promise.all([
    updateDownloadButtonFromLatestRelease(),
    updateHeaderVersionStatus(),
  ]);
}

window.updateDownloadButtonFromLatestRelease = updateDownloadButtonFromLatestRelease;
window.updateHeaderVersionStatus = updateHeaderVersionStatus;
window.initializeThunderPage = initializeThunderPage;
